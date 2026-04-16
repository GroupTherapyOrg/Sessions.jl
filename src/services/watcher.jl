# Layer 3: File watcher — watches notebook file for external changes

using FileWatching

# --- Hot reload: diff and apply ---

"""Result of diffing two notebooks."""
struct NotebookDiff
    added::Vector{Cell}          # New cells (in order they appear in new notebook)
    removed::Vector{UUID}        # UUIDs of removed cells
    changed::Vector{Tuple{UUID, String}}  # (cell_id, new_code) for cells with changed source
    metadata_changed::Vector{Tuple{UUID, Bool, Bool}}  # (cell_id, new_folded, new_disabled) — code same, metadata differs
    unchanged::Vector{UUID}      # UUIDs of cells unchanged
    new_order::Vector{UUID}      # Full cell order from the new notebook
end

"""Diff two notebooks to identify added/removed/changed cells."""
function diff_notebooks(old::Notebook, new::Notebook)
    old_ids = Set(old.cell_order)
    new_ids = Set(new.cell_order)

    # New cells: present in new but not old
    added_ids = setdiff(new_ids, old_ids)
    added = [new.cells[id] for id in new.cell_order if id in added_ids]

    # Removed cells: present in old but not new
    removed = UUID[id for id in old.cell_order if !(id in new_ids)]

    # Changed & unchanged: cells present in both
    changed = Tuple{UUID, String}[]
    metadata_changed = Tuple{UUID, Bool, Bool}[]
    unchanged = UUID[]
    for id in new.cell_order
        id in old_ids || continue
        old_cell = old.cells[id]
        new_cell = new.cells[id]
        if old_cell.code != new_cell.code
            push!(changed, (id, new_cell.code))
        elseif old_cell.folded != new_cell.folded || old_cell.disabled != new_cell.disabled
            push!(metadata_changed, (id, new_cell.folded, new_cell.disabled))
        else
            push!(unchanged, id)
        end
    end

    NotebookDiff(added, removed, changed, metadata_changed, unchanged, new.cell_order)
end

"""Apply a diff to update a notebook in place. Returns the diff for inspection."""
function apply_diff!(nb::Notebook, diff::NotebookDiff)
    # Remove deleted cells
    for id in diff.removed
        delete!(nb.cells, id)
    end

    # Add new cells (just add to cells dict; order is set below)
    for cell in diff.added
        nb.cells[cell.id] = cell
    end

    # Update changed cells: update code, mark stale (preserve output)
    for (id, new_code) in diff.changed
        cell = nb.cells[id]
        cell.code = new_code
        # Cell is now stale if it was previously executed
    end

    # Update metadata-only changes (folded/disabled)
    for (id, new_folded, new_disabled) in diff.metadata_changed
        cell = nb.cells[id]
        cell.folded = new_folded
        cell.disabled = new_disabled
    end

    # Update cell order to match new notebook
    nb.cell_order = copy(diff.new_order)

    diff
end

"""Reload a notebook from disk: re-parse, diff, apply changes.
Returns the diff (empty diff if no changes)."""
function reload_notebook!(nb::Notebook)
    isfile(nb.path) || error("File not found: $(nb.path)")
    new_nb = load_notebook(nb.path)
    diff = diff_notebooks(nb, new_nb)
    apply_diff!(nb, diff)
    diff
end

"""Smart merge: diff disk against the in-memory notebook directly.

If they match, the change came from us (our own save echoing back through
the watcher) — `diff` is empty and we apply nothing. If they differ, it's
a TRUE external edit (agent file write, git pull, manual editor save) and
we apply the disk version to in-memory `nb`.

Comparing against `nb` itself (rather than a separately-tracked snapshot)
removes a class of bookkeeping bugs where post-save the watcher's snapshot
was stale, causing it to mis-classify our own writes as external and
broadcast cell_code_updated for every cell — silently overwriting any
typing the user had done since save."""
function merge_external_changes!(nb::Notebook, _ignored=nothing)
    isfile(nb.path) || error("File not found: $(nb.path)")
    disk_nb = load_notebook(nb.path)

    # Diff: what does disk say that in-memory doesn't?
    diff = diff_notebooks(nb, disk_nb)

    # Apply only disk-originated changes to in-memory notebook:
    # 1. Remove cells deleted on disk
    for id in diff.removed
        delete!(nb.cells, id)
    end

    # 2. Add cells added on disk
    for cell in diff.added
        nb.cells[cell.id] = cell
    end

    # 3. Update cells changed on disk (overwrite code, preserve output)
    for (id, new_code) in diff.changed
        haskey(nb.cells, id) || continue
        nb.cells[id].code = new_code
    end

    # 3b. Update metadata-only changes (folded/disabled)
    for (id, new_folded, new_disabled) in diff.metadata_changed
        haskey(nb.cells, id) || continue
        nb.cells[id].folded = new_folded
        nb.cells[id].disabled = new_disabled
    end

    # 4. Update cell order to match disk
    nb.cell_order = copy(diff.new_order)

    diff
end

# --- File watcher ---

"""
Watch a notebook file for external changes and reload when modified.
Uses polling to allow clean cancellation. Returns a WatcherHandle.
"""
mutable struct WatcherHandle
    task::Task
    running::Threads.Atomic{Bool}
end

function watch_notebook(nb::Notebook, on_change::Function;
                        poll_interval::Float64=1.0)
    path = nb.path
    isfile(path) || error("File not found: $path")

    running = Threads.Atomic{Bool}(true)

    task = @async begin
        last_mtime = mtime(path)
        while running[]
            sleep(poll_interval)
            running[] || break

            current_mtime = mtime(path)
            if current_mtime > last_mtime
                last_mtime = current_mtime
                try
                    on_change(path)
                catch e
                    @warn "Watcher callback error" exception=e
                end
            end
        end
    end

    WatcherHandle(task, running)
end

"""Stop a file watcher."""
function stop_watcher(handle::WatcherHandle)
    handle.running[] = false
    # Wait briefly for the task to finish
    for _ in 1:20
        istaskdone(handle.task) && return
        sleep(0.05)
    end
end

# --- Debounced watcher ---

"""Watcher with debounce: waits for `delay` seconds of quiet before firing callback."""
mutable struct DebouncedWatcher
    handle::Union{WatcherHandle, Nothing}
    nb::Notebook
    on_change::Function
    delay::Float64          # seconds (default 0.2)
    poll_interval::Float64  # seconds (default 0.5)
    timer::Union{Timer, Nothing}
    pending::Threads.Atomic{Bool}
end

function DebouncedWatcher(nb::Notebook, on_change::Function;
                          delay::Float64=0.2, poll_interval::Float64=0.5)
    DebouncedWatcher(nothing, nb, on_change, delay, poll_interval, nothing,
                     Threads.Atomic{Bool}(false))
end

"""Start the debounced watcher."""
function start_watching!(dw::DebouncedWatcher)
    dw.handle !== nothing && return dw  # already running

    dw.handle = watch_notebook(dw.nb, _ -> _debounce_trigger!(dw);
                               poll_interval=dw.poll_interval)
    dw
end

"""Stop the debounced watcher and cancel any pending timer."""
function stop_watching!(dw::DebouncedWatcher)
    if dw.timer !== nothing
        close(dw.timer)
        dw.timer = nothing
    end
    dw.pending[] = false
    if dw.handle !== nothing
        stop_watcher(dw.handle)
        dw.handle = nothing
    end
end

"""Internal: called when file change detected. Resets debounce timer."""
function _debounce_trigger!(dw::DebouncedWatcher)
    dw.pending[] = true
    # Cancel existing timer
    if dw.timer !== nothing
        close(dw.timer)
        dw.timer = nothing
    end
    # Start new timer
    dw.timer = Timer(dw.delay) do _
        if dw.pending[]
            dw.pending[] = false
            try
                dw.on_change(dw.nb.path)
            catch e
                @warn "DebouncedWatcher callback error" exception=e
            end
        end
    end
end
