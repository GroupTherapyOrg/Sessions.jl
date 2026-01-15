# Signals.jl - Server signals for real-time state synchronization
#
# Uses Therapy.jl's reactive WebSocket system for automatic state propagation.
# Server signals automatically broadcast to subscribed clients.
# DOM elements with data-server-signal attributes auto-update.

using Therapy

# =============================================================================
# Server Signals (Automatically broadcast via WebSocket)
# =============================================================================

# Cell states: {cell_id => "IDLE"|"RUNNING"|"QUEUED"|"ERROR"}
# Auto-broadcasts to all connected clients when updated
const CELL_STATES_SIGNAL = Ref{Any}(nothing)

# Cell outputs: {cell_id => {html: "...", runtime_ms: 123}}
# Auto-broadcasts to all connected clients when updated
const CELL_OUTPUTS_SIGNAL = Ref{Any}(nothing)

# Notebook info: {id, path, cell_count, modified}
const NOTEBOOK_INFO_SIGNAL = Ref{Any}(nothing)

# Connected users for collaboration
const USERS_SIGNAL = Ref{Any}(nothing)

"""
Initialize Therapy.jl server signals.
These automatically broadcast to subscribed clients via WebSocket.
"""
function setup_signals!()
    # Cell states - clients subscribe via data-server-signal="cell_states"
    CELL_STATES_SIGNAL[] = create_server_signal("cell_states", Dict{String, String}())

    # Cell outputs - clients subscribe via data-server-signal="cell_outputs"
    CELL_OUTPUTS_SIGNAL[] = create_server_signal("cell_outputs", Dict{String, Any}())

    # Notebook info
    NOTEBOOK_INFO_SIGNAL[] = create_server_signal("notebook_info", Dict{String, Any}())

    # Connected users
    USERS_SIGNAL[] = create_server_signal("users", Dict{String, Any}[])
end

# =============================================================================
# Signal Update Functions (Auto-broadcast to clients)
# =============================================================================

"""
Update a single cell's state. Automatically broadcasts to all clients.
"""
function set_cell_state!(cell_id::UUID, state::CellState)
    sig = CELL_STATES_SIGNAL[]
    sig === nothing && return

    update_server_signal!(sig, states -> begin
        states[string(cell_id)] = string(state)
        return states
    end)
end

"""
Update a cell's output. Automatically broadcasts to all clients.
"""
function set_cell_output!(cell_id::UUID, output::Union{Nothing, CellOutput}, runtime_ms::Union{Nothing, Float64})
    sig = CELL_OUTPUTS_SIGNAL[]
    sig === nothing && return

    output_data = if output === nothing
        Dict{String, Any}("html" => "", "logs" => "", "runtime_ms" => runtime_ms)
    else
        Dict{String, Any}(
            "html" => output.html,
            "logs" => output.logs,
            "error_logs" => output.error_logs,
            "runtime_ms" => runtime_ms
        )
    end

    update_server_signal!(sig, outputs -> begin
        outputs[string(cell_id)] = output_data
        return outputs
    end)
end

"""
Update notebook info. Automatically broadcasts to all clients.
"""
function set_notebook_info!(notebook::Notebook)
    sig = NOTEBOOK_INFO_SIGNAL[]
    sig === nothing && return

    set_server_signal!(sig, Dict{String, Any}(
        "id" => string(notebook.id),
        "path" => notebook.path,
        "modified" => notebook.modified,
        "cell_count" => length(notebook.cells)
    ))
end

"""
Broadcast all cell states for a notebook.
"""
function broadcast_all_cell_states!(notebook::Notebook)
    sig = CELL_STATES_SIGNAL[]
    sig === nothing && return

    update_server_signal!(sig, states -> begin
        for (id, cell) in notebook.cells
            states[string(id)] = string(cell.state)
        end
        return states
    end)
end

# =============================================================================
# Connection Lifecycle (Using Therapy.jl hooks)
# =============================================================================

"""
Set up WebSocket connection lifecycle hooks.
"""
function setup_lifecycle!()
    on_ws_connect() do conn
        println("[Sessions] Client connected: $(conn.id)")

        # Add to users signal
        sig = USERS_SIGNAL[]
        if sig !== nothing
            update_server_signal!(sig, users -> begin
                push!(users, Dict{String,Any}("id" => conn.id[1:8], "connected_at" => time()))
                return users
            end)
        end
    end

    on_ws_disconnect() do conn
        println("[Sessions] Client disconnected: $(conn.id)")

        # Remove from users signal
        sig = USERS_SIGNAL[]
        if sig !== nothing
            update_server_signal!(sig, users -> begin
                filter!(u -> u["id"] != conn.id[1:8], users)
                return users
            end)
        end

        # Clean up notebook association
        delete!(CONN_NOTEBOOK, conn.id)
    end
end
