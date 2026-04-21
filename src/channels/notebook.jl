# channels/notebook.jl — Notebook WebSocket channel handlers
#
# Replaces the notebook section of web_server.jl using Therapy's
# first-class channel API. Handles: cell execution, CRUD, save,
# tab management, formatting, bonds, interrupt, external changes.

using Therapy
using UUIDs
import ExpressionExplorer

# ═══════════════════════════════════════════════════════════════
# Types
# ═══════════════════════════════════════════════════════════════

"""A single tab in the web UI — either a notebook or a plain file."""
mutable struct WebTab
    id::UUID
    tab_type::Symbol              # :notebook or :file
    nb::Union{Notebook, Nothing}
    worker::Union{NotebookWorker, Nothing}
    label::String
    path::String
    file_content::String
    watcher::Union{DebouncedWatcher, Nothing}
    # Last `Notebook` we either loaded or wrote to disk. The watcher does
    # a 3-way merge `(snapshot → disk) ⇒ in-memory` so external edits
    # apply without clobbering cells the user is editing locally.
    snapshot::Ref{Notebook}
    # Hash of the file bytes we last wrote. The watcher uses this to
    # recognize its own writes (disk byte-for-byte == hash → skip), so a
    # save followed by more typing in CodeMirror cannot lose the new
    # keystrokes via a stale-disk diff.
    last_written_hash::Ref{UInt64}
end

function _initial_disk_hash(path)
    isfile(path) ? hash(read(path)) : zero(UInt64)
end

"""Cheap notebook snapshot — copies only the fields the watcher diff
reads (cell_order + per-cell {id, code, folded, disabled}). `deepcopy`
on a Notebook can fail when an errored cell holds a CapturedException
whose backtrace points at a Module (Julia's deepcopy refuses Modules);
a snapshot for diff purposes never needs the output/error/result
fields anyway."""
function _snapshot_notebook(nb::Notebook)
    snap = Notebook(; path=nb.path)
    snap.cell_order = copy(nb.cell_order)
    for (id, c) in nb.cells
        snap.cells[id] = Cell(; id=c.id, code=c.code,
                                folded=c.folded, disabled=c.disabled,
                                show_logs=c.show_logs)
    end
    snap
end

WebTab(id, nb::Notebook, worker, label, path) =
    WebTab(id, :notebook, nb, worker, label, path, "", nothing,
           Ref(_snapshot_notebook(nb)), Ref(_initial_disk_hash(path)))
WebTab(id, label, path, content::String) =
    WebTab(id, :file, nothing, nothing, label, path, content, nothing,
           Ref(Notebook(; path)), Ref(_initial_disk_hash(path)))

"""Server-side notebook state for the web UI (multi-tab)."""
mutable struct WebNotebookState
    tabs::Vector{WebTab}
    active_tab_idx::Int
    executing::Bool
    interrupted::Bool
end

function active_tab(state::WebNotebookState)
    idx = state.active_tab_idx
    (idx < 1 || idx > length(state.tabs)) && return nothing
    state.tabs[idx]
end

function active_nb(state::WebNotebookState)
    tab = active_tab(state)
    tab === nothing ? nothing : tab.nb
end

function active_worker(state::WebNotebookState)
    tab = active_tab(state)
    tab === nothing ? nothing : tab.worker
end

# Make sure the active tab's worker is alive before we hand it to a
# `remote_execute_cell!` call. `Malt.interrupt(...)` sometimes terminates
# the underlying worker process (especially on macOS — the SIGINT can
# unwind through `_jl_mutex_unlock` in the scheduler and crash the
# process instead of raising InterruptException). Once the process is
# dead every subsequent execution throws Malt.TerminatedWorkerException.
# Auto-reboot here so the user can re-run after pressing Stop.
function ensure_active_worker_alive!(state::WebNotebookState)
    worker = active_worker(state)
    worker === nothing && return nothing
    is_worker_alive(worker) && return worker
    @info "[notebook] Worker died — rebooting"
    try
        restart_worker!(worker)
    catch e
        @warn "[notebook] Worker reboot failed" exception=e
    end
    worker
end

function is_notebook_tab(state::WebNotebookState)
    tab = active_tab(state)
    tab !== nothing && tab.tab_type == :notebook
end

# ═══════════════════════════════════════════════════════════════
# Broadcast helpers
# ═══════════════════════════════════════════════════════════════

function _nb_broadcast!(msg::Dict)
    msg["channel"] = "notebook"
    try; Therapy.broadcast_all(msg); catch; end
end

function _nb_send!(conn, msg::Dict)
    msg["channel"] = "notebook"
    try; Therapy.send_ws_message(conn, msg); catch; end
end

# Apply a client-supplied code update to `cell` with stale-client detection.
# Returns `(applied::Bool, server_code::String)` — when `applied` is false the
# caller should push `server_code` back so the client's CodeMirror catches up
# to whatever overwrote `cell.code` (typically a watcher merge of an external
# edit). The check: if the client's incoming code matches the last-executed
# hash *and* the server has since diverged from that hash, the client is
# echoing pre-merge state and we keep the server version.
#
# Edge case: never-run cells have empty `produced_by_hash`, so this falls
# open and the client always wins. That's acceptable — there's no "last
# executed" baseline to detect staleness against.
function _apply_client_code!(cell::Cell, client_code::String)
    server_code = cell.code
    client_code == server_code && return (true, server_code)
    if !isempty(cell.produced_by_hash)
        client_hash = string(hash(strip(client_code)), base=16)
        server_hash = source_hash(cell)
        if client_hash == cell.produced_by_hash && server_hash != cell.produced_by_hash
            return (false, server_code)
        end
    end
    cell.code = client_code
    return (true, client_code)
end

# Broadcast a cell_code_updated event so every client's CodeMirror catches up.
# The client-side handler diff-checks against the current buffer (Notebook.jl
# `if (data.code !== cur)`), so if the user's editor already matches the
# server, no dispatch fires and the cursor stays put.
function _broadcast_cell_code!(cell_id::AbstractString, code::AbstractString)
    _nb_broadcast!(Dict(
        "event" => "cell_code_updated",
        "cell_id" => String(cell_id),
        "code" => String(code)
    ))
end

function _update_cell_signal!(cell::Cell)
    try
        Therapy.broadcast_all(Dict{String,Any}(
            "type" => "cell_state",
            "cell_id" => string(cell.id),
            "state" => string(cell.state)
        ))
    catch; end
end

# Stub — cell state updates are pushed via broadcast in handlers
function create_cell_signals!(state::WebNotebookState) end

# ═══════════════════════════════════════════════════════════════
# State serialization
# ═══════════════════════════════════════════════════════════════

function _serialize_logs(logs::Vector{LogRecord})
    [Dict("level" => Int(r.level), "message" => r.message, "line" => r.line,
          "kwargs" => [Dict("k" => k, "v" => v) for (k, v) in r.kwargs])
     for r in logs]
end

function _rootassignee(cell::Cell)::String
    isempty(strip(cell.code)) && return ""
    try
        expr = Meta.parse("begin\n$(cell.code)\nend")
        ra = ExpressionExplorer.get_rootassignee(expr)
        ra === nothing ? "" : string(ra)
    catch
        ""
    end
end

function _cell_to_dict(cell::Cell)
    output_html = render_output_html(cell)
    Dict(
        "cell_id" => string(cell.id),
        "code" => cell.code,
        "state" => string(cell.state),
        "output_html" => output_html,
        "runtime_ns" => cell.output.runtime_ns,
        "stdout" => cell.output.stdout,
        "rootassignee" => _rootassignee(cell),
        "folded" => cell.folded,
        "disabled" => cell.disabled,
        "stale" => is_stale(cell),
        "logs" => _serialize_logs(cell.output.logs)
    )
end

function serialize_cells_json(state::WebNotebookState)::String
    tab = active_tab(state)
    tab === nothing && return "[]"
    tab.tab_type != :notebook && return "[]"
    nb = active_nb(state)
    cells_data = [_cell_to_dict(cell) for cell in ordered_cells(nb)]
    try
        io = IOBuffer()
        print(io, "[")
        for (i, cell) in enumerate(cells_data)
            i > 1 && print(io, ",")
            print(io, "{")
            first = true
            for (k, v) in cell
                first || print(io, ",")
                first = false
                print(io, "\"", k, "\":")
                if v isa String
                    print(io, "\"", replace(replace(replace(replace(v,
                        "\\" => "\\\\"), "\"" => "\\\""), "\n" => "\\n"), "\r" => "\\r"), "\"")
                elseif v isa Bool
                    print(io, v ? "true" : "false")
                elseif v isa Number
                    print(io, v)
                elseif v === nothing
                    print(io, "null")
                else
                    print(io, "\"", string(v), "\"")
                end
            end
            print(io, "}")
        end
        print(io, "]")
        return String(take!(io))
    catch e
        @warn "serialize_cells_json failed" exception=e
        return "[]"
    end
end

# ═══════════════════════════════════════════════════════════════
# Full state sync (on WebSocket connect)
# ═══════════════════════════════════════════════════════════════

function send_full_state!(state::WebNotebookState, conn)
    tab = active_tab(state)
    if tab.tab_type == :file
        _nb_send!(conn, Dict(
            "event" => "full_state",
            "tab_type" => "file",
            "file_path" => tab.path,
            "file_content" => tab.file_content,
            "active_is_file" => 1,
            "active_can_format" => endswith(lowercase(tab.path), ".jl") ? 1 : 0
        ))
        return
    end
    nb = active_nb(state)
    cells_data = [_cell_to_dict(cell) for cell in ordered_cells(nb)]

    _nb_send!(conn, Dict(
        "event" => "full_state",
        "notebook_path" => nb.path,
        "cells" => cells_data,
        "cell_order" => [string(id) for id in nb.cell_order],
        "executing" => state.executing,
        "active_is_file" => 0,
        "active_can_format" => 1
    ))
end

# ═══════════════════════════════════════════════════════════════
# Channel registration
# ═══════════════════════════════════════════════════════════════

function setup_notebook_channel!(state::WebNotebookState)
    Therapy.on_channel_message() do channel, conn, msg
        channel == "notebook" || return
        action = get(msg, "action", "")
        try
            if action == "execute"
                _handle_execute_cell!(state, conn, msg)
            elseif action == "run_all"
                _handle_run_all!(state, conn, msg)
            elseif action == "add_cell"
                _handle_add_cell!(state, conn, msg)
            elseif action == "delete_cell"
                _handle_delete_cell!(state, conn, msg)
            elseif action == "move_cell"
                _handle_move_cell!(state, conn, msg)
            elseif action == "reorder_cell"
                _handle_reorder_cell!(state, conn, msg)
            elseif action == "reorder_cells"
                _handle_reorder_cells!(state, conn, msg)
            elseif action == "update_code"
                _handle_update_code!(state, conn, msg)
            elseif action == "toggle_fold"
                _handle_toggle_fold!(state, conn, msg)
            elseif action == "toggle_disable"
                _handle_toggle_disable!(state, conn, msg)
            elseif action == "toggle_show_logs"
                _handle_toggle_show_logs!(state, conn, msg)
            elseif action == "save"
                _handle_save!(state, conn, msg)
            elseif action == "run_stale"
                _handle_run_stale!(state, conn, msg)
            elseif action == "open_notebook"
                _handle_open_notebook!(state, conn, msg)
            elseif action == "switch_tab"
                _handle_switch_tab!(state, conn, msg)
            elseif action == "close_tab"
                _handle_close_tab!(state, conn, msg)
            elseif action == "set_bond"
                _handle_set_bond!(state, conn, msg)
            elseif action == "save_file"
                _handle_save_file!(state, conn, msg)
            elseif action == "interrupt"
                _handle_interrupt!(state, conn, msg)
            elseif action == "format_cell"
                _handle_format_cell!(state, conn, msg)
            elseif action == "format_all"
                _handle_format_all!(state, conn, msg)
            elseif action == "format_file"
                _handle_format_file!(state, conn, msg)
            elseif action == "format_active"
                # Format whatever the active tab is — file or notebook.
                tab = active_tab(state)
                if tab !== nothing && tab.tab_type == :file
                    _handle_format_file!(state, conn, msg)
                else
                    _handle_format_all!(state, conn, msg)
                end
            else
                @warn "[notebook] Unknown action" action=action
            end
        catch e
            @warn "[notebook] Handler error" action=action exception=(e, catch_backtrace())
        end
    end
end

# ═══════════════════════════════════════════════════════════════
# Execution handlers
# ═══════════════════════════════════════════════════════════════

function _handle_execute_cell!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    isempty(cell_id_str) && return

    cell_id = UUID(cell_id_str)
    cell = get_cell(active_nb(state), cell_id)
    cell === nothing && return

    new_code = get(data, "code", nothing)
    if new_code !== nothing
        cell.code = new_code
    end

    @async begin
        state.executing = true
        state.interrupted = false
        try
            _execute_cells!(state, [cell])
        finally
            state.executing = false
        end
    end
end

function _handle_run_all!(state::WebNotebookState, conn, data)
    @async begin
        state.executing = true
        state.interrupted = false
        try
            nb = active_nb(state)
            update_topology!(nb)
            order = execution_order(nb)
            # _run_order! handles save_session! + _broadcast_stale! in
            # its own finally block — no need to call them again here.
            _run_order!(state, order)
        finally
            state.executing = false
        end
    end
end

function _execute_cells!(state::WebNotebookState, changed_cells::Vector{Cell})
    nb = active_nb(state)
    update_topology!(nb, changed_cells)
    order = execution_order(nb, changed_cells)
    _run_order!(state, order)
end

function _run_order!(state::WebNotebookState, order)
    nb = active_nb(state)
    # If a previous Stop killed the worker process, reboot before we
    # try to execute anything. Otherwise every cell instantly errors
    # with Malt.TerminatedWorkerException and the user is locked out.
    ensure_active_worker_alive!(state)
    # The cleanup broadcast at the end of this function MUST fire even
    # if a cell raises during execution — otherwise the toolbar is left
    # showing "Stop / N / 0" forever (is_executing=1, run_progress
    # half-reset). Wrap the whole body in try/finally so the reset is
    # the last thing the client sees regardless of how the loop exited.
    try

    for (cell, err) in order.errable
        cell.state = cell_idle
        cell.produced_by_hash = source_hash(cell)
        cell.output = CellOutput()
        is_self_disabled = cell.disabled
        msg = is_self_disabled ? "Cell is disabled" : "Skipped — depends on a disabled cell"
        cell.output.text_representation = msg
        _nb_broadcast!(Dict(
            "event" => "cell_output",
            "cell_id" => string(cell.id),
            "output_html" => is_self_disabled ? "" : """<div class="cell-skipped-msg">$(msg)</div>""",
            "runtime_ns" => UInt64(0),
            "stdout" => "",
            "rootassignee" => "",
            "logs" => Any[],
            "state" => "cell_skipped"
        ))
    end

    for c in order.runnable
        c.state = cell_queued
        _update_cell_signal!(c)
        _nb_broadcast!(Dict(
            "event" => "cell_state",
            "cell_id" => string(c.id),
            "state" => "cell_queued"
        ))
    end

    n_total = length(order.runnable)
    for (i, c) in enumerate(order.runnable)
        state.interrupted && break

        c.state = cell_running
        _update_cell_signal!(c)
        _nb_broadcast!(Dict(
            "event" => "cell_state",
            "cell_id" => string(c.id),
            "state" => "cell_running"
        ))
        _nb_broadcast!(Dict(
            "event" => "run_progress",
            "running_index" => i,
            "total" => n_total,
            "cell_id" => string(c.id)
        ))

        remote_execute_cell!(active_worker(state), c; log_callback=rec -> begin
            try _nb_broadcast!(Dict(
                "event" => "cell_log",
                "cell_id" => string(c.id),
                "log" => Dict("level" => Int(rec.level), "message" => rec.message,
                             "kwargs" => [Dict("k" => k, "v" => v) for (k, v) in rec.kwargs])
            )) catch; end
        end)
        _update_cell_signal!(c)

        _nb_broadcast!(Dict(
            "event" => "cell_output",
            "cell_id" => string(c.id),
            "output_html" => render_output_html(c),
            "runtime_ns" => c.output.runtime_ns,
            "stdout" => c.output.stdout,
            "rootassignee" => _rootassignee(c),
            "logs" => _serialize_logs(c.output.logs),
            "state" => string(c.state)
        ))
    end

    finally
        _nb_broadcast!(Dict(
            "event" => "run_progress",
            "running_index" => 0,
            "total" => 0
        ))
        # save_session! + _broadcast_stale! MUST run in finally too —
        # otherwise an exception during the execute loop (Malt hiccup,
        # JSON serialize error, etc.) skips the post-run stale-clear
        # broadcast, leaving every just-ran cell visually stuck on the
        # stale class until the user manually saves. Both helpers have
        # their own try/catch internally so they can't re-throw here.
        try save_session!(nb) catch; end
        try _broadcast_stale!(state) catch; end
    end
end

function _broadcast_stale!(state::WebNotebookState)
    active_tab(state).tab_type == :notebook || return
    nb = active_nb(state)
    nb === nothing && return
    sc = stale_cells(nb)
    stale_ids = [string(c.id) for c in sc]
    _nb_broadcast!(Dict(
        "event" => "stale_update",
        "count" => length(sc),
        "stale_ids" => stale_ids,
        "total_cells" => length(ordered_cells(nb))
    ))
end

# ═══════════════════════════════════════════════════════════════
# Cell CRUD handlers
# ═══════════════════════════════════════════════════════════════

function _handle_add_cell!(state::WebNotebookState, conn, data)
    nb = active_nb(state)
    after_cell_id_str = get(data, "after_cell_id", "")
    restore_code = get(data, "code", "")
    mutation_id = get(data, "mutation_id", nothing)
    temp_id = get(data, "temp_id", nothing)
    new_cell = Cell(; code=restore_code)

    try
        if isempty(after_cell_id_str)
            insert_cell!(nb, 1, new_cell)
        else
            after_id = UUID(after_cell_id_str)
            idx = findfirst(==(after_id), nb.cell_order)
            if idx !== nothing
                insert_cell!(nb, idx + 1, new_cell)
            else
                add_cell!(nb, new_cell)
            end
        end

        _update_cell_signal!(new_cell)

        cell_html = try
            cell_vnode = render_cell(new_cell; mode=:live, index=0)
            gap_vnode = CellGap(; after_cell_id=string(new_cell.id))
            cell_str = cell_vnode !== nothing ? Therapy.render_to_string(cell_vnode) : ""
            gap_str = Therapy.render_to_string(gap_vnode)
            cell_str * gap_str
        catch e
            @warn "[notebook] Failed to render new cell" exception=(e, catch_backtrace())
            ""
        end

        msg = Dict(
            "event" => "cell_added",
            "cell_id" => string(new_cell.id),
            "after_cell_id" => after_cell_id_str,
            "cell_html" => cell_html
        )
        mutation_id !== nothing && (msg["ack_mutation"] = mutation_id)
        temp_id !== nothing && (msg["temp_id"] = temp_id)
        _nb_broadcast!(msg)
    catch e
        @warn "[notebook] Add cell failed" exception=(e, catch_backtrace())
        if mutation_id !== nothing
            _nb_send!(conn, Dict(
                "event" => "mutation_error",
                "ack_mutation" => mutation_id,
                "reason" => string(e)
            ))
        end
    end
end

function _handle_delete_cell!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    isempty(cell_id_str) && return
    mutation_id = get(data, "mutation_id", nothing)

    nb = active_nb(state)
    cell_id = UUID(cell_id_str)

    cell = get_cell(nb, cell_id)
    deleted_code = cell !== nothing ? cell.code : ""
    deleted_index = findfirst(==(cell_id), nb.cell_order)
    prev_cell_id = if deleted_index !== nothing && deleted_index > 1
        string(nb.cell_order[deleted_index - 1])
    else
        ""
    end

    removed = remove_cell!(nb, cell_id)
    if removed === nothing
        if mutation_id !== nothing
            _nb_send!(conn, Dict(
                "event" => "mutation_error",
                "ack_mutation" => mutation_id,
                "reason" => "Cell not found"
            ))
        end
        return
    end

    msg = Dict(
        "event" => "cell_deleted",
        "cell_id" => cell_id_str,
        "code" => deleted_code,
        "index" => deleted_index !== nothing ? deleted_index : 0,
        "prev_cell_id" => prev_cell_id
    )
    mutation_id !== nothing && (msg["ack_mutation"] = mutation_id)
    _nb_broadcast!(msg)
end

function _handle_move_cell!(state::WebNotebookState, conn, data)
    nb = active_nb(state)
    cell_id_str = get(data, "cell_id", "")
    direction = get(data, "direction", "")
    mutation_id = get(data, "mutation_id", nothing)
    isempty(cell_id_str) && return

    cell_id = UUID(cell_id_str)
    idx = findfirst(==(cell_id), nb.cell_order)
    idx === nothing && return

    swapped = if direction == "up"
        swap_cell_up!(nb, idx)
    elseif direction == "down"
        swap_cell_down!(nb, idx)
    else
        false
    end

    if !swapped
        if mutation_id !== nothing
            _nb_send!(conn, Dict(
                "event" => "mutation_error",
                "ack_mutation" => mutation_id,
                "reason" => "Cannot move cell $(direction)"
            ))
        end
        return
    end

    msg = Dict(
        "event" => "cell_moved",
        "cell_id" => cell_id_str,
        "direction" => direction
    )
    mutation_id !== nothing && (msg["ack_mutation"] = mutation_id)
    _nb_broadcast!(msg)
end

function _handle_reorder_cell!(state::WebNotebookState, conn, data)
    nb = active_nb(state)
    cell_id_str = get(data, "cell_id", "")
    target_idx = get(data, "index", -1)
    mutation_id = get(data, "mutation_id", nothing)
    isempty(cell_id_str) && return

    moved = reorder_cell!(nb, UUID(cell_id_str), Int(target_idx))

    if !moved
        if mutation_id !== nothing
            _nb_send!(conn, Dict(
                "event" => "mutation_error",
                "ack_mutation" => mutation_id,
                "reason" => "Cannot reorder cell"
            ))
        end
        return
    end

    msg = Dict(
        "event" => "cell_reordered",
        "cell_id" => cell_id_str,
        "cell_order" => [string(id) for id in nb.cell_order]
    )
    mutation_id !== nothing && (msg["ack_mutation"] = mutation_id)
    _nb_broadcast!(msg)
end

function _handle_reorder_cells!(state::WebNotebookState, conn, data)
    nb = active_nb(state)
    cell_id_strs = get(data, "cell_ids", String[])
    target_idx = get(data, "index", -1)
    mutation_id = get(data, "mutation_id", nothing)
    isempty(cell_id_strs) && return

    cell_ids = [UUID(String(s)) for s in cell_id_strs]
    filter!(id -> id ∉ cell_ids, nb.cell_order)
    insert_at = clamp(Int(target_idx), 1, length(nb.cell_order) + 1)
    for (i, id) in enumerate(cell_ids)
        insert!(nb.cell_order, insert_at + i - 1, id)
    end

    msg = Dict(
        "event" => "cell_reordered",
        "cell_order" => [string(id) for id in nb.cell_order]
    )
    mutation_id !== nothing && (msg["ack_mutation"] = mutation_id)
    _nb_broadcast!(msg)
end

# ═══════════════════════════════════════════════════════════════
# Property toggle handlers
# ═══════════════════════════════════════════════════════════════

function _handle_toggle_fold!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    isempty(cell_id_str) && return
    cell = get_cell(active_nb(state), UUID(cell_id_str))
    cell === nothing && return
    cell.folded = get(data, "folded", false)
end

function _handle_toggle_disable!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    isempty(cell_id_str) && return
    nb = active_nb(state)
    cell = get_cell(nb, UUID(cell_id_str))
    cell === nothing && return
    cell.disabled = get(data, "disabled", false)
    nb.topology = nothing
    nb._cached_topological_order = nothing
    _nb_broadcast!(Dict(
        "event" => "cell_disabled",
        "cell_id" => cell_id_str,
        "disabled" => cell.disabled
    ))
end

function _handle_toggle_show_logs!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    isempty(cell_id_str) && return
    cell = get_cell(active_nb(state), UUID(cell_id_str))
    cell === nothing && return
    cell.show_logs = get(data, "show_logs", true)
end

function _handle_update_code!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    new_code = get(data, "code", "")
    isempty(cell_id_str) && return

    cell = get_cell(active_nb(state), UUID(cell_id_str))
    cell === nothing && return

    applied, server_code = _apply_client_code!(cell, String(new_code))
    if !applied
        # Server has a newer external edit (likely from the watcher merging
        # an agent change). Echo it back so the client's CodeMirror replaces
        # its stale buffer instead of having silently-rejected typing.
        _broadcast_cell_code!(cell_id_str, server_code)
    end

    _broadcast_stale!(state)
end

# ═══════════════════════════════════════════════════════════════
# Save handlers
# ═══════════════════════════════════════════════════════════════

function _handle_save!(state::WebNotebookState, conn, data)
    mutation_id = get(data, "mutation_id", nothing)
    tab = active_tab(state)

    if tab.tab_type == :file
        content = get(data, "content", nothing)
        if content !== nothing
            tab.file_content = String(content)
            write(tab.path, tab.file_content)
            tab.last_written_hash[] = hash(codeunits(tab.file_content))
            msg = Dict("event" => "saved", "notebook_path" => tab.path)
            mutation_id !== nothing && (msg["ack_mutation"] = mutation_id)
            _nb_broadcast!(msg)
        end
        return
    end

    nb = active_nb(state)
    codes = get(data, "codes", nothing)
    rejected = Tuple{String,String}[]  # cell_id, server_code — pushed back below
    if codes !== nothing
        for (cid, code) in codes
            cell = get_cell(nb, UUID(String(cid)))
            cell === nothing && continue
            applied, server_code = _apply_client_code!(cell, String(code))
            applied || push!(rejected, (String(cid), server_code))
        end
    end

    serialized = serialize_notebook(nb)
    write(nb.path, serialized)
    tab.last_written_hash[] = hash(codeunits(serialized))
    tab.snapshot[] = _snapshot_notebook(nb)
    save_session!(nb)

    # Push the authoritative code back for any cell where the client's buffer
    # was stale relative to a server-side merge. Done after the disk write so
    # what we tell the client matches what's now on disk.
    for (cid, server_code) in rejected
        _broadcast_cell_code!(cid, server_code)
    end

    msg = Dict("event" => "saved", "notebook_path" => nb.path)
    mutation_id !== nothing && (msg["ack_mutation"] = mutation_id)
    _nb_broadcast!(msg)
    # Re-broadcast stale state so the toolbar pill and per-cell .stale class
    # re-sync from the single server source of truth.
    _broadcast_stale!(state)
end

function _handle_save_file!(state::WebNotebookState, conn, data)
    tab = active_tab(state)
    tab.tab_type == :file || return
    content = get(data, "content", nothing)
    content === nothing && return
    tab.file_content = String(content)
    write(tab.path, tab.file_content)
    tab.last_written_hash[] = hash(codeunits(tab.file_content))
    _nb_broadcast!(Dict(
        "event" => "saved",
        "notebook_path" => tab.path
    ))
end

# ═══════════════════════════════════════════════════════════════
# Run stale + interrupt
# ═══════════════════════════════════════════════════════════════

function _handle_run_stale!(state::WebNotebookState, conn, data)
    nb = active_nb(state)
    codes = get(data, "codes", nothing)
    rejected = Tuple{String,String}[]
    if codes !== nothing
        for (cid, code) in codes
            cell = get_cell(nb, UUID(String(cid)))
            cell === nothing && continue
            applied, server_code = _apply_client_code!(cell, String(code))
            applied || push!(rejected, (String(cid), server_code))
        end
    end
    for (cid, server_code) in rejected
        _broadcast_cell_code!(cid, server_code)
    end

    @async begin
        state.executing = true
        try
            sc = stale_cells(nb)
            if isempty(sc)
                _nb_broadcast!(Dict(
                    "event" => "info",
                    "message" => "No stale cells"
                ))
                return
            end
            _execute_cells!(state, sc)
        finally
            state.executing = false
        end
    end
end

function _handle_interrupt!(state::WebNotebookState, conn, data)
    state.executing || return

    state.interrupted = true
    state.executing = false

    worker = active_worker(state)
    if worker !== nothing
        try
            Malt.interrupt(worker.worker)
        catch e
            @warn "[notebook] Interrupt failed" exception=e
        end
    end

    nb = active_nb(state)
    if nb !== nothing
        for cell in ordered_cells(nb)
            if cell.state == cell_queued || cell.state == cell_running
                cell.state = cell_idle
                _update_cell_signal!(cell)
                _nb_broadcast!(Dict(
                    "event" => "cell_state",
                    "cell_id" => string(cell.id),
                    "state" => "cell_idle"
                ))
            end
        end
    end

    _nb_broadcast!(Dict("event" => "run_progress", "running_index" => 0, "total" => 0))
    _nb_broadcast!(Dict("event" => "interrupted"))
end

# ═══════════════════════════════════════════════════════════════
# Format handlers
# ═══════════════════════════════════════════════════════════════

function _handle_format_cell!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    isempty(cell_id_str) && return

    _nb_broadcast!(Dict("event" => "format_started"))

    nb = active_nb(state)
    cell = get_cell(nb, UUID(cell_id_str))
    if cell !== nothing
        original = cell.code
        formatted = format_code(original)
        if formatted != original
            cell.code = formatted
            update_topology!(nb)
            _nb_broadcast!(Dict(
                "event" => "cell_formatted",
                "cell_id" => cell_id_str,
                "code" => formatted
            ))
            _broadcast_stale!(state)
        end
    end

    _nb_broadcast!(Dict("event" => "format_done"))
end

function _handle_format_all!(state::WebNotebookState, conn, data)
    _nb_broadcast!(Dict("event" => "format_started"))

    nb = active_nb(state)
    cells = ordered_cells(nb)
    changed = 0

    for cell in cells
        original = cell.code
        formatted = format_code(original)
        if formatted != original
            cell.code = formatted
            changed += 1
            _nb_broadcast!(Dict(
                "event" => "cell_formatted",
                "cell_id" => string(cell.id),
                "code" => formatted
            ))
        end
    end

    if changed > 0
        update_topology!(nb)
        _broadcast_stale!(state)
    end
    _nb_broadcast!(Dict("event" => "format_done"))
end

function _handle_format_file!(state::WebNotebookState, conn, data)
    tab = active_tab(state)
    tab === nothing && return
    tab.tab_type == :file || return
    endswith(tab.path, ".jl") || return

    _nb_broadcast!(Dict("event" => "format_started"))

    original = tab.file_content
    formatted = format_code(original)
    if formatted != original
        tab.file_content = formatted
        _nb_broadcast!(Dict(
            "event" => "cell_code_updated",
            "cell_id" => "__file__",
            "code" => formatted
        ))
    end
    _nb_broadcast!(Dict("event" => "format_done"))
end

# ═══════════════════════════════════════════════════════════════
# Bond handler
# ═══════════════════════════════════════════════════════════════

function _handle_set_bond!(state::WebNotebookState, conn, data)
    bond_name = get(data, "name", "")
    isempty(bond_name) && return
    raw_value = get(data, "value", nothing)
    raw_value === nothing && return

    nb = active_nb(state)
    worker = active_worker(state)
    worker === nothing && return
    name_sym = Symbol(bond_name)

    @async begin
        state.executing = true
        try
            cell_id, ok = try
                Malt.remote_eval_fetch(worker.worker,
                    :(Sessions.SessionsUI.apply_bond_update!(_workspace.mod,
                        $(QuoteNode(name_sym)), $(QuoteNode(raw_value)))))
            catch e
                @warn "[bond] worker call failed" name=bond_name exception=(e, catch_backtrace())
                return
            end

            ok || return
            cell_id === nothing && return

            bond_cell = get(nb.cells, cell_id, nothing)
            if bond_cell === nothing
                @warn "[bond] cell_id from registry not found in notebook" name=bond_name cell_id=cell_id
                return
            end

            deps = try
                downstream_dependents(nb, [bond_cell])
            catch e
                @warn "[bond] downstream_dependents failed" exception=e
                Cell[]
            end
            isempty(deps) || _execute_cells!(state, deps)
        catch e
            @warn "[bond] outer error" exception=(e, catch_backtrace())
        finally
            state.executing = false
        end
    end
end

# ═══════════════════════════════════════════════════════════════
# Tab management handlers
# ═══════════════════════════════════════════════════════════════

function _handle_open_notebook!(state::WebNotebookState, conn, data)
    raw_path = get(data, "path", "")
    isempty(raw_path) && return

    full_path = if isabspath(raw_path)
        abspath(raw_path)
    else
        _active_dir = let t = active_tab(state)
            dirname(abspath(t.path))
        end
        abspath(joinpath(_active_dir, raw_path))
    end

    !isfile(full_path) && return

    binary_exts = Set([".png", ".jpg", ".jpeg", ".gif", ".bmp", ".ico", ".webp", ".svg",
                       ".pdf", ".zip", ".gz", ".tar", ".7z", ".rar",
                       ".mp3", ".mp4", ".wav", ".avi", ".mov", ".mkv", ".webm",
                       ".exe", ".dll", ".so", ".dylib", ".o", ".a",
                       ".wasm", ".class", ".pyc", ".pyo",
                       ".db", ".sqlite", ".sqlite3",
                       ".ttf", ".otf", ".woff", ".woff2", ".eot",
                       ".DS_Store"])
    ext = lowercase(splitext(full_path)[2])
    if ext in binary_exts
        _nb_broadcast!(Dict(
            "event" => "info",
            "message" => "Cannot open binary file: $(basename(full_path))"
        ))
        return
    end

    for (i, tab) in enumerate(state.tabs)
        if tab.path == full_path
            state.active_tab_idx = i
            if tab.tab_type == :notebook
                create_cell_signals!(state)
            end
            _broadcast_nb_html!(state)
            _broadcast_tab_active!(state)
            return
        end
    end

    is_nb = endswith(full_path, ".jl") && is_notebook_file(full_path)

    if is_nb
        nb = load_notebook(full_path)
        session_data = load_session(session_path(nb.path))
        if session_data !== nothing
            apply_session!(nb, session_data)
        end
        worker = NotebookWorker(; notebook_path=nb.path)
        tab = WebTab(uuid4(), nb, worker, basename(full_path), full_path)
        push!(state.tabs, tab)
        state.active_tab_idx = length(state.tabs)
        _start_tab_watcher!(state, tab)
        create_cell_signals!(state)
    else
        content = try
            read(full_path, String)
        catch
            _nb_broadcast!(Dict("event" => "info", "message" => "Cannot open: $(basename(full_path))"))
            return
        end
        tab = WebTab(uuid4(), basename(full_path), full_path, content)
        push!(state.tabs, tab)
        state.active_tab_idx = length(state.tabs)
    end

    _broadcast_nb_html!(state)
    _broadcast_tab_active!(state)
end

# Broadcast the active-tab type so NotebookToolbar's active_is_file /
# active_can_format effects flip correctly. MUST be called whenever the
# active tab changes (switch / open / close).
function _broadcast_tab_active!(state::WebNotebookState)
    tab = active_tab(state)
    tab === nothing && return
    is_file = tab.tab_type == :file
    can_format = !is_file || endswith(lowercase(tab.path), ".jl")
    try
        _nb_broadcast!(Dict(
            "event" => "tab_active_changed",
            "active_is_file"    => is_file ? 1 : 0,
            "active_can_format" => can_format ? 1 : 0
        ))
    catch; end
    try
        Therapy.broadcast_all(Dict{String,Any}(
            "channel" => "file_explorer",
            "event" => "active_file_changed",
            "path" => tab.path
        ))
    catch; end
end

function _handle_switch_tab!(state::WebNotebookState, conn, data)
    tab_idx = get(data, "tab_idx", 0)
    (tab_idx isa Number) || return
    tab_idx = Int(tab_idx)
    (tab_idx < 1 || tab_idx > length(state.tabs)) && return
    tab_idx == state.active_tab_idx && return

    state.active_tab_idx = tab_idx
    create_cell_signals!(state)
    _broadcast_nb_html!(state)
    _broadcast_tab_active!(state)
end

function _broadcast_nb_html!(state::WebNotebookState)
    nb_html = try
        # Wrap binding access in invokelatest for Julia 1.12 world-age safety:
        # Main.TherapyApp and NotebookPanel are defined in a later world than
        # this channel module, so a bare getfield emits a 1.12 deprecation.
        host = Base.invokelatest(() -> isdefined(Main, :TherapyApp) ? getfield(Main, :TherapyApp) : Main)
        _NP = Base.invokelatest(getfield, host, :NotebookPanel)
        vnode = Base.invokelatest(_NP, state)
        vnode !== nothing ? Therapy.render_to_string(vnode) : ""
    catch e
        @warn "[notebook] Failed to render notebook panel" exception=e
        ""
    end

    tab = active_tab(state)
    total = if tab !== nothing && tab.tab_type == :notebook && active_nb(state) !== nothing
        length(ordered_cells(active_nb(state)))
    else
        0
    end
    _nb_broadcast!(Dict(
        "event" => "nb_replaced",
        "nb_html" => nb_html,
        "total_cells" => total
    ))
end

function _handle_close_tab!(state::WebNotebookState, conn, data)
    tab_idx = get(data, "tab_idx", 0)
    (tab_idx isa Number) || return
    tab_idx = Int(tab_idx)
    (tab_idx < 1 || tab_idx > length(state.tabs)) && return

    closed_tab = state.tabs[tab_idx]
    if closed_tab.worker !== nothing
        try stop_worker!(closed_tab.worker) catch; end
    end
    if closed_tab.watcher !== nothing
        try stop_watching!(closed_tab.watcher) catch; end
    end
    deleteat!(state.tabs, tab_idx)

    if isempty(state.tabs)
        state.active_tab_idx = 0
    elseif tab_idx <= state.active_tab_idx
        state.active_tab_idx = max(1, state.active_tab_idx - 1)
    end
    if !isempty(state.tabs)
        state.active_tab_idx = clamp(state.active_tab_idx, 1, length(state.tabs))
    end

    create_cell_signals!(state)
    _broadcast_nb_html!(state)
    _broadcast_tab_active!(state)
end

# ═══════════════════════════════════════════════════════════════
# File watcher — detect external changes (agent edits, git, IDE)
# ═══════════════════════════════════════════════════════════════

function start_web_watchers!(state::WebNotebookState)
    for tab in state.tabs
        _start_tab_watcher!(state, tab)
    end
end

function _start_tab_watcher!(state::WebNotebookState, tab::WebTab)
    tab.watcher !== nothing && stop_watching!(tab.watcher)
    (!isfile(tab.path) || isempty(tab.path)) && return

    tab.watcher = DebouncedWatcher(tab.nb, _ -> _on_web_external_change!(state, tab);
                                    delay=0.5, poll_interval=0.5)
    start_watching!(tab.watcher)
end

function _on_web_external_change!(state::WebNotebookState, tab::WebTab)
    try
        # Snapshot which cells are mid-flight before we touch anything. Agent
        # edits to those cells are deferred — applying them now would race with
        # the worker (the cell would re-emit output for code that's no longer
        # the source). We restore busy cells' code AND rewind their snapshot
        # entry below so the next watcher poll re-merges them once they idle.
        busy_codes = Dict{UUID, String}()
        if state.executing
            for (id, c) in tab.nb.cells
                if c.state == cell_running || c.state == cell_queued
                    busy_codes[id] = c.code
                end
            end
        end

        old_order = copy(tab.nb.cell_order)
        # merge_external_changes hashes the disk bytes and compares against
        # the hash recorded after our last save. If they match, the watcher
        # is seeing its own write echo back and skips the diff entirely —
        # so typing that lands in CodeMirror between save and the watcher
        # poll cycle cannot be reverted by a stale-disk apply.
        diff = merge_external_changes!(tab.nb, tab.snapshot, tab.last_written_hash)

        # Restore busy cells in BOTH the notebook and the snapshot. Rewinding
        # the snapshot entry is critical: merge updated snapshot[] = disk_nb
        # wholesale, so without rewinding, the next poll's diff would be empty
        # for that cell and the deferred agent edit would be lost forever.
        if !isempty(busy_codes)
            snap = tab.snapshot[]
            for (id, original_code) in busy_codes
                haskey(tab.nb.cells, id)  && (tab.nb.cells[id].code  = original_code)
                haskey(snap.cells,    id) && (snap.cells[id].code   = original_code)
            end
        end

        reordered = diff.new_order != old_order
        # Filter the broadcast list — busy cells haven't actually changed
        # in-memory yet, so emitting cell_code_updated for them would push
        # the agent's version to CodeMirror prematurely.
        changed = isempty(busy_codes) ? diff.changed :
                  [(id, code) for (id, code) in diff.changed if !haskey(busy_codes, id)]
        n_changes = length(diff.added) + length(changed) + length(diff.removed) + length(diff.metadata_changed)
        n_changes == 0 && !reordered && return

        create_cell_signals!(state)
        _broadcast_stale!(state)

        if !isempty(diff.added) || !isempty(diff.removed) || reordered
            _broadcast_nb_html!(state)
        else
            for (id, new_code) in changed
                haskey(tab.nb.cells, id) || continue
                _nb_broadcast!(Dict(
                    "event" => "cell_code_updated",
                    "cell_id" => string(id),
                    "code" => new_code
                ))
            end
            for (id, new_folded, new_disabled) in diff.metadata_changed
                haskey(tab.nb.cells, id) || continue
                _nb_broadcast!(Dict(
                    "event" => "cell_code_updated",
                    "cell_id" => string(id),
                    "folded" => new_folded,
                    "disabled" => new_disabled
                ))
            end
        end
    catch e
        @warn "[notebook] External change handler error" exception=(e, catch_backtrace())
    end
end
