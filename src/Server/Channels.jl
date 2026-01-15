# Channels.jl - WebSocket channel handlers using Therapy.jl
#
# Defines the WebSocket protocol for client-server communication.

using Therapy
using UUIDs
using JSON3

# =============================================================================
# Global State
# =============================================================================

# Active notebooks (notebook_id => Notebook)
const NOTEBOOKS = Dict{UUID, Notebook}()

# Connection to notebook mapping
const CONN_NOTEBOOK = Dict{String, UUID}()

# =============================================================================
# Channel: Execute Cell
# =============================================================================

"""
Handle cell execution requests.
Message: {notebook_id, cell_id, code}
"""
function setup_execute_channel!()
    on_channel_message("execute") do conn, data
        notebook_id = UUID(data["notebook_id"])
        cell_id = UUID(data["cell_id"])
        code = get(data, "code", nothing)

        notebook = get(NOTEBOOKS, notebook_id, nothing)
        if notebook === nothing
            send_channel!("error", conn.id, Dict("message" => "Notebook not found"))
            return
        end

        cell = get_cell(notebook, cell_id)
        if cell === nothing
            send_channel!("error", conn.id, Dict("message" => "Cell not found"))
            return
        end

        # Update code if provided
        if code !== nothing
            cell.code = code
            analyze_cell!(cell)
        end

        # Broadcast that cell is running
        broadcast_cell_state(notebook_id, cell)

        # Execute reactively (cell + downstream dependencies)
        try
            results = execute_reactive!(notebook, cell_id)

            # Broadcast updates for each executed cell
            for cell in get_execution_order(notebook, [cell_id])
                broadcast_cell_state(notebook_id, cell)
                broadcast_cell_output(notebook_id, cell)
            end
        catch e
            send_channel!("error", conn.id, Dict(
                "message" => "Execution failed: $(sprint(showerror, e))"
            ))
        end
    end
end

# =============================================================================
# Channel: Cell Operations
# =============================================================================

"""
Handle adding new cells.
Message: {notebook_id, after_cell_id?, code?}

After adding, registers per-cell signals and updates cells_list signal
so clients can add the new cell to DOM without page refresh.
"""
function setup_add_cell_channel!()
    on_channel_message("add_cell") do conn, data
        notebook_id = UUID(data["notebook_id"])

        notebook = get(NOTEBOOKS, notebook_id, nothing)
        if notebook === nothing
            send_channel!("error", conn.id, Dict("message" => "Notebook not found"))
            return
        end

        # Handle null/nothing after_cell_id (for "Add Cell" at end of notebook)
        after_cell_str = get(data, "after_cell_id", nothing)
        after = (after_cell_str !== nothing && after_cell_str != "null" && !isempty(string(after_cell_str))) ? UUID(after_cell_str) : nothing
        code = get(data, "code", "")

        cell = add_cell!(notebook; code=code, after=after)

        # Register per-cell signals for the new cell
        register_cell_signals!(cell)

        # Update cells_list signal (triggers client to add new cell to DOM)
        update_cells_list_signal!(notebook)

        # Also broadcast via channel for backwards compatibility
        broadcast_channel!("cell_added", Dict(
            "notebook_id" => string(notebook_id),
            "cell" => cell_to_dict(cell),
            "after_cell_id" => after === nothing ? nothing : string(after)
        ))
    end
end

"""
Handle deleting cells.
Message: {notebook_id, cell_id}

After deleting, unregisters per-cell signals and updates cells_list signal.
"""
function setup_delete_cell_channel!()
    on_channel_message("delete_cell") do conn, data
        notebook_id = UUID(data["notebook_id"])
        cell_id = UUID(data["cell_id"])

        notebook = get(NOTEBOOKS, notebook_id, nothing)
        if notebook === nothing
            return
        end

        if delete_cell!(notebook, cell_id)
            # Unregister per-cell signals
            unregister_cell_signals!(cell_id)

            # Update cells_list signal
            update_cells_list_signal!(notebook)

            # Also broadcast via channel for backwards compatibility
            broadcast_channel!("cell_deleted", Dict(
                "notebook_id" => string(notebook_id),
                "cell_id" => string(cell_id)
            ))
        end
    end
end

"""
Handle moving cells.
Message: {notebook_id, cell_id, new_index}
"""
function setup_move_cell_channel!()
    on_channel_message("move_cell") do conn, data
        notebook_id = UUID(data["notebook_id"])
        cell_id = UUID(data["cell_id"])
        new_index = data["new_index"]

        notebook = get(NOTEBOOKS, notebook_id, nothing)
        if notebook === nothing
            return
        end

        if move_cell!(notebook, cell_id, new_index)
            broadcast_channel!("cell_moved", Dict(
                "notebook_id" => string(notebook_id),
                "cell_id" => string(cell_id),
                "new_index" => new_index
            ))
        end
    end
end

"""
Handle code updates (without execution).
Message: {notebook_id, cell_id, code}
"""
function setup_update_code_channel!()
    on_channel_message("update_code") do conn, data
        notebook_id = UUID(data["notebook_id"])
        cell_id = UUID(data["cell_id"])
        code = data["code"]

        notebook = get(NOTEBOOKS, notebook_id, nothing)
        if notebook === nothing
            return
        end

        cell = get_cell(notebook, cell_id)
        if cell !== nothing
            cell.code = code
            analyze_cell!(cell)
            # Don't broadcast - just update locally
            # Client already has the code since they sent it
        end
    end
end

# =============================================================================
# Channel: Notebook Operations
# =============================================================================

"""
Handle interrupt requests.
Message: {notebook_id}
"""
function setup_interrupt_channel!()
    on_channel_message("interrupt") do conn, data
        notebook_id = UUID(data["notebook_id"])

        notebook = get(NOTEBOOKS, notebook_id, nothing)
        if notebook === nothing
            return
        end

        interrupt_worker!(notebook)

        broadcast_channel!("interrupted", Dict(
            "notebook_id" => string(notebook_id)
        ))
    end
end

"""
Handle run all request.
Message: {notebook_id}
"""
function setup_run_all_channel!()
    on_channel_message("run_all") do conn, data
        notebook_id = UUID(data["notebook_id"])

        notebook = get(NOTEBOOKS, notebook_id, nothing)
        if notebook === nothing
            return
        end

        # Run all cells
        run_all!(notebook)

        # Broadcast all cell states
        for cell in values(notebook.cells)
            broadcast_cell_state(notebook_id, cell)
            broadcast_cell_output(notebook_id, cell)
        end
    end
end

"""
Handle restart request (restart worker, clear outputs).
Message: {notebook_id}
"""
function setup_restart_channel!()
    on_channel_message("restart") do conn, data
        notebook_id = UUID(data["notebook_id"])

        notebook = get(NOTEBOOKS, notebook_id, nothing)
        if notebook === nothing
            return
        end

        # Shutdown and restart worker
        shutdown_worker!(notebook)
        ensure_worker!(notebook)

        # Clear all cell outputs and reset states
        for cell in values(notebook.cells)
            cell.output = nothing
            cell.state = CELL_IDLE
            cell.runtime_ms = nothing
        end

        broadcast_channel!("restarted", Dict(
            "notebook_id" => string(notebook_id)
        ))

        # Broadcast all cell states
        for cell in values(notebook.cells)
            broadcast_cell_state(notebook_id, cell)
        end
    end
end

# =============================================================================
# Channel: File Operations
# =============================================================================

"""
Handle save requests.
Message: {notebook_id, path?}
"""
function setup_save_channel!()
    on_channel_message("save") do conn, data
        notebook_id = UUID(data["notebook_id"])
        path = get(data, "path", nothing)

        notebook = get(NOTEBOOKS, notebook_id, nothing)
        if notebook === nothing
            send_channel!("error", conn.id, Dict("message" => "Notebook not found"))
            return
        end

        # Use provided path or existing path
        save_path = path !== nothing ? path : notebook.path
        if save_path === nothing
            send_channel!("error", conn.id, Dict("message" => "No path specified"))
            return
        end

        try
            save_notebook(notebook, save_path)
            notebook.path = save_path
            notebook.modified = false

            broadcast_channel!("saved", Dict(
                "notebook_id" => string(notebook_id),
                "path" => save_path
            ))
        catch e
            send_channel!("error", conn.id, Dict(
                "message" => "Save failed: $(sprint(showerror, e))"
            ))
        end
    end
end

"""
Handle load requests.
Message: {path}

After loading, registers per-cell signals for all cells.
"""
function setup_load_channel!()
    on_channel_message("load") do conn, data
        path = data["path"]

        try
            notebook = load_notebook(path)
            NOTEBOOKS[notebook.id] = notebook

            # Associate connection with notebook
            CONN_NOTEBOOK[conn.id] = notebook.id

            # Register per-cell signals for all cells
            register_all_cell_signals!(notebook)

            broadcast_channel!("loaded", Dict(
                "notebook" => notebook_to_dict(notebook)
            ))
        catch e
            send_channel!("error", conn.id, Dict(
                "message" => "Load failed: $(sprint(showerror, e))"
            ))
        end
    end
end

# =============================================================================
# Signal Updates (Using Therapy.jl Server Signals)
# =============================================================================

# These functions update server signals which automatically broadcast
# to all subscribed clients via Therapy.jl's WebSocket infrastructure.

"""
Update cell state via server signal (auto-broadcasts).
"""
function update_cell_state_signal(cell::Cell)
    set_cell_state!(cell.id, cell.state)
end

"""
Update cell output via server signal (auto-broadcasts).
"""
function update_cell_output_signal(cell::Cell)
    set_cell_output!(cell.id, cell.output, cell.runtime_ms)
end

# Legacy broadcast functions (for backwards compatibility)
function broadcast_cell_state(notebook_id::UUID, cell::Cell)
    update_cell_state_signal(cell)
end

function broadcast_cell_output(notebook_id::UUID, cell::Cell)
    update_cell_output_signal(cell)
end

# =============================================================================
# Setup All Channels
# =============================================================================

"""
Create all message channels.
Must be called before registering handlers.
"""
function create_channels!()
    # Cell operations
    create_channel("execute")
    create_channel("add_cell")
    create_channel("delete_cell")
    create_channel("move_cell")
    create_channel("update_code")

    # Notebook operations
    create_channel("interrupt")
    create_channel("run_all")
    create_channel("restart")
    create_channel("save")
    create_channel("load")

    # Response channels (for broadcasting to clients)
    create_channel("cell_state")
    create_channel("cell_output")
    create_channel("cell_added")
    create_channel("cell_deleted")
    create_channel("cell_moved")
    create_channel("interrupted")
    create_channel("restarted")
    create_channel("saved")
    create_channel("loaded")
    create_channel("error")
end

"""
Register all WebSocket channel handlers.
"""
function setup_channels!()
    # First create all channels
    create_channels!()

    # Then register handlers
    setup_execute_channel!()
    setup_add_cell_channel!()
    setup_delete_cell_channel!()
    setup_move_cell_channel!()
    setup_update_code_channel!()
    setup_interrupt_channel!()
    setup_run_all_channel!()
    setup_restart_channel!()
    setup_save_channel!()
    setup_load_channel!()
end
