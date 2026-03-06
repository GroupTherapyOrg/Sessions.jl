# Layer 3: File watcher — watches notebook file for external changes

using FileWatching

# --- Hot reload: diff and apply ---

"""Result of diffing two notebooks."""
struct NotebookDiff
    added::Vector{Cell}          # New cells (in order they appear in new notebook)
    removed::Vector{UUID}        # UUIDs of removed cells
    changed::Vector{Tuple{UUID, String}}  # (cell_id, new_code) for cells with changed source
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
    unchanged = UUID[]
    for id in new.cell_order
        id in old_ids || continue
        old_code = old.cells[id].code
        new_code = new.cells[id].code
        if old_code != new_code
            push!(changed, (id, new_code))
        else
            push!(unchanged, id)
        end
    end

    NotebookDiff(added, removed, changed, unchanged, new.cell_order)
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
