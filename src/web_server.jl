# web_server.jl — Server state + channel handlers for Sessions.jl Web UI
#
# Bridges the notebook engine to Therapy.jl WebSocket channels.
# Handles: cell execution, add/delete/move cells, save, run all.
# All heavy lifting (execution, reactivity, analysis) stays server-side.

using Therapy
# Note: Markdown is already imported by web.jl (included earlier in the module)

"""Server-side notebook state for the web UI."""
mutable struct WebNotebookState
    nb::Notebook
    workspace::Workspace
    executing::Bool
end

"""
    setup_web_notebook!(state::WebNotebookState)

Set up WebSocket channel handlers for notebook communication.
Creates the "notebook" channel and registers message handlers.
"""
function setup_web_notebook!(state::WebNotebookState)
    # Create channel (safe for HMR reloads)
    if !haskey(Therapy.MESSAGE_CHANNELS, "notebook")
        create_channel("notebook")
    end

    on_channel_message("notebook") do conn, data
        action = get(data, "action", "")
        try
            if action == "execute"
                handle_execute_cell!(state, conn, data)
            elseif action == "run_all"
                handle_run_all!(state, conn, data)
            elseif action == "add_cell"
                handle_add_cell!(state, conn, data)
            elseif action == "delete_cell"
                handle_delete_cell!(state, conn, data)
            elseif action == "move_cell"
                handle_move_cell!(state, conn, data)
            elseif action == "update_code"
                handle_update_code!(state, conn, data)
            elseif action == "save"
                handle_save!(state, conn, data)
            else
                @warn "[WebNotebook] Unknown action" action=action
            end
        catch e
            @warn "[WebNotebook] Handler error" action=action exception=(e, catch_backtrace())
        end
    end
end

# =============================================================================
# Full state sync (on WebSocket connect)
# =============================================================================

"""Send complete notebook state to a newly connected client."""
function send_full_state!(state::WebNotebookState, conn)
    cells_data = []
    for cell in ordered_cells(state.nb)
        push!(cells_data, _cell_to_dict(cell))
    end

    send_channel!("notebook", conn, Dict(
        "event" => "full_state",
        "notebook_path" => state.nb.path,
        "cells" => cells_data,
        "cell_order" => [string(id) for id in state.nb.cell_order]
    ))
end

"""Convert a Cell to a serializable Dict for the client."""
function _cell_to_dict(cell::Cell)
    output_html = _web_render_output_html(cell)
    Dict(
        "cell_id" => string(cell.id),
        "code" => cell.code,
        "state" => string(cell.state),
        "output_html" => output_html,
        "runtime_ns" => cell.output.runtime_ns,
        "stdout" => cell.output.stdout,
        "folded" => cell.folded,
        "disabled" => cell.disabled,
        "stale" => is_stale(cell)
    )
end

"""Render cell output to HTML string via Sessions._render_output + Therapy.render_to_string."""
function _web_render_output_html(cell::Cell)
    # Markdown cells: render prose directly
    if _is_markdown_cell(strip(cell.code)) && cell.output.output_type == :markdown
        return sprint(io -> Markdown.html(io, cell.output.result))
    end
    vnode = _render_output(cell)
    vnode === nothing && return ""
    Therapy.render_to_string(vnode)
end

# =============================================================================
# Cell execution handlers
# =============================================================================

"""Handle a single cell execution request."""
function handle_execute_cell!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    isempty(cell_id_str) && return

    cell_id = UUID(cell_id_str)
    cell = get_cell(state.nb, cell_id)
    cell === nothing && return

    # Update code if provided
    new_code = get(data, "code", nothing)
    if new_code !== nothing
        cell.code = new_code
    end

    @async begin
        state.executing = true
        try
            _execute_cells!(state, [cell])
        finally
            state.executing = false
        end
    end
end

"""Handle run-all request."""
function handle_run_all!(state::WebNotebookState, conn, data)
    @async begin
        state.executing = true
        try
            update_topology!(state.nb)
            order = execution_order(state.nb)

            # Mark all as queued
            for c in order.runnable
                c.state = cell_queued
                broadcast_channel!("notebook", Dict(
                    "event" => "cell_state",
                    "cell_id" => string(c.id),
                    "state" => "cell_queued"
                ))
            end

            # Execute in topological order
            for c in order.runnable
                c.state = cell_running
                broadcast_channel!("notebook", Dict(
                    "event" => "cell_state",
                    "cell_id" => string(c.id),
                    "state" => "cell_running"
                ))

                execute_cell!(state.workspace, c)

                broadcast_channel!("notebook", Dict(
                    "event" => "cell_output",
                    "cell_id" => string(c.id),
                    "output_html" => _web_render_output_html(c),
                    "runtime_ns" => c.output.runtime_ns,
                    "stdout" => c.output.stdout,
                    "state" => string(c.state)
                ))
            end

            save_session!(state.nb)
        finally
            state.executing = false
        end
    end
end

"""Execute cells with reactive dependencies: topology → queued → running → done."""
function _execute_cells!(state::WebNotebookState, changed_cells::Vector{Cell})
    update_topology!(state.nb, changed_cells)
    order = execution_order(state.nb, changed_cells)

    # Mark all runnable as queued
    for c in order.runnable
        c.state = cell_queued
        broadcast_channel!("notebook", Dict(
            "event" => "cell_state",
            "cell_id" => string(c.id),
            "state" => "cell_queued"
        ))
    end

    # Execute in topological order
    for c in order.runnable
        c.state = cell_running
        broadcast_channel!("notebook", Dict(
            "event" => "cell_state",
            "cell_id" => string(c.id),
            "state" => "cell_running"
        ))

        execute_cell!(state.workspace, c)

        broadcast_channel!("notebook", Dict(
            "event" => "cell_output",
            "cell_id" => string(c.id),
            "output_html" => _web_render_output_html(c),
            "runtime_ns" => c.output.runtime_ns,
            "stdout" => c.output.stdout,
            "state" => string(c.state)
        ))
    end

    # Broadcast errors
    for (c, _err) in order.errable
        c.state = cell_errored
        broadcast_channel!("notebook", Dict(
            "event" => "cell_state",
            "cell_id" => string(c.id),
            "state" => "cell_errored"
        ))
    end

    save_session!(state.nb)
end

# =============================================================================
# Cell CRUD handlers
# =============================================================================

"""Handle add-cell request."""
function handle_add_cell!(state::WebNotebookState, conn, data)
    after_cell_id_str = get(data, "after_cell_id", "")
    new_cell = Cell(; code="")

    if isempty(after_cell_id_str)
        # Insert at beginning
        insert_cell!(state.nb, 1, new_cell)
    else
        after_id = UUID(after_cell_id_str)
        idx = findfirst(==(after_id), state.nb.cell_order)
        if idx !== nothing
            insert_cell!(state.nb, idx + 1, new_cell)
        else
            add_cell!(state.nb, new_cell)
        end
    end

    broadcast_channel!("notebook", Dict(
        "event" => "cell_added",
        "cell" => _cell_to_dict(new_cell),
        "after_cell_id" => after_cell_id_str,
        "cell_order" => [string(id) for id in state.nb.cell_order]
    ))
end

"""Handle delete-cell request."""
function handle_delete_cell!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    isempty(cell_id_str) && return

    cell_id = UUID(cell_id_str)
    removed = remove_cell!(state.nb, cell_id)
    removed === nothing && return

    broadcast_channel!("notebook", Dict(
        "event" => "cell_deleted",
        "cell_id" => cell_id_str,
        "cell_order" => [string(id) for id in state.nb.cell_order]
    ))
end

"""Handle move-cell request."""
function handle_move_cell!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    direction = get(data, "direction", "")
    isempty(cell_id_str) && return

    cell_id = UUID(cell_id_str)
    idx = findfirst(==(cell_id), state.nb.cell_order)
    idx === nothing && return

    swapped = if direction == "up"
        swap_cell_up!(state.nb, idx)
    elseif direction == "down"
        swap_cell_down!(state.nb, idx)
    else
        false
    end

    swapped || return

    broadcast_channel!("notebook", Dict(
        "event" => "cell_order",
        "cell_order" => [string(id) for id in state.nb.cell_order]
    ))
end

"""Handle code update (without execution)."""
function handle_update_code!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    new_code = get(data, "code", "")
    isempty(cell_id_str) && return

    cell = get_cell(state.nb, UUID(cell_id_str))
    cell === nothing && return
    cell.code = new_code
end

"""Handle save request."""
function handle_save!(state::WebNotebookState, conn, data)
    save_notebook(state.nb)
    save_session!(state.nb)
    broadcast_channel!("notebook", Dict(
        "event" => "saved",
        "notebook_path" => state.nb.path
    ))
    println("[WebNotebook] Saved: $(state.nb.path)")
end
