# Signals.jl - Server signals for real-time state synchronization
#
# Uses Therapy.jl's reactive WebSocket system for automatic state propagation.
#
# Architecture: Per-Cell Server Signals
# =====================================
# Instead of Dict-based signals (cell_states = {cell_id => state}), we use
# individual signals per cell. This enables:
#
# 1. Fine-grained subscriptions (clients only get what they need)
# 2. Simpler client-side handling (one signal = one cell)
# 3. Better use of data-server-signal attributes where applicable
#
# Signal naming convention:
# - cell_state_{cell_id}   -> "CELL_IDLE"|"CELL_RUNNING"|"CELL_QUEUED"|"CELL_ERROR"
# - cell_output_{cell_id}  -> HTML string of cell output
# - cell_runtime_{cell_id} -> Runtime in ms (number as string)

using Therapy

# =============================================================================
# Signal Registry (Track per-cell signals)
# =============================================================================

# Track which cell signals have been created
const CELL_SIGNAL_REGISTRY = Set{String}()

# Global notebook info signal
const NOTEBOOK_INFO_SIGNAL = Ref{Any}(nothing)

# Connected users for collaboration
const USERS_SIGNAL = Ref{Any}(nothing)

# Cells list signal for dynamic cell management (add/delete without refresh)
const CELLS_LIST_SIGNAL = Ref{Any}(nothing)

# Notebook tabs signal - tracks all open notebooks for tab UI
const NOTEBOOK_TABS_SIGNAL = Ref{Any}(nothing)

# Active notebook signal - which notebook is currently displayed
const ACTIVE_NOTEBOOK_SIGNAL = Ref{Any}(nothing)

"""
Initialize global Therapy.jl server signals.
Per-cell signals are created dynamically when cells are added.
"""
function setup_signals!()
    # Notebook info (global)
    NOTEBOOK_INFO_SIGNAL[] = create_server_signal("notebook_info", Dict{String, Any}())

    # Connected users (global)
    USERS_SIGNAL[] = create_server_signal("users", Dict{String, Any}[])

    # Cells list - tracks which cells exist and their order
    # Client subscribes to this to know when to add/remove cell DOM elements
    CELLS_LIST_SIGNAL[] = create_server_signal("cells_list", Dict{String, Any}[])

    # Notebook tabs - list of open notebooks for tab bar
    # Each entry: {id, title, modified, created_at}
    NOTEBOOK_TABS_SIGNAL[] = create_server_signal("notebook_tabs", Dict{String, Any}[])

    # Active notebook - which notebook is currently displayed
    ACTIVE_NOTEBOOK_SIGNAL[] = create_server_signal("active_notebook", "")
end

# =============================================================================
# Per-Cell Signal Management
# =============================================================================

"""
Register server signals for a new cell.
Creates: cell_state_{id}, cell_output_{id}, cell_runtime_{id}
"""
function register_cell_signals!(cell::Cell)
    cell_id = string(cell.id)

    # Create per-cell signals (only if not already created)
    state_key = "cell_state_$(cell_id)"
    output_key = "cell_output_$(cell_id)"
    runtime_key = "cell_runtime_$(cell_id)"

    if !(state_key in CELL_SIGNAL_REGISTRY)
        create_server_signal(state_key, string(cell.state))
        push!(CELL_SIGNAL_REGISTRY, state_key)
    end

    if !(output_key in CELL_SIGNAL_REGISTRY)
        output_html = cell.output !== nothing ? cell.output.html : ""
        create_server_signal(output_key, output_html)
        push!(CELL_SIGNAL_REGISTRY, output_key)
    end

    if !(runtime_key in CELL_SIGNAL_REGISTRY)
        runtime_str = cell.runtime_ms !== nothing ? string(round(cell.runtime_ms, digits=1)) : ""
        create_server_signal(runtime_key, runtime_str)
        push!(CELL_SIGNAL_REGISTRY, runtime_key)
    end
end

"""
Unregister signals for a deleted cell.
"""
function unregister_cell_signals!(cell_id::UUID)
    id_str = string(cell_id)

    # Remove from registry (signals themselves can be reused if cell recreated)
    delete!(CELL_SIGNAL_REGISTRY, "cell_state_$(id_str)")
    delete!(CELL_SIGNAL_REGISTRY, "cell_output_$(id_str)")
    delete!(CELL_SIGNAL_REGISTRY, "cell_runtime_$(id_str)")
end

"""
Register signals for all cells in a notebook.
Called when notebook is loaded or server starts.
"""
function register_all_cell_signals!(notebook::Notebook)
    for cell in values(notebook.cells)
        register_cell_signals!(cell)
    end

    # Update cells list signal
    update_cells_list_signal!(notebook)
end

# =============================================================================
# Signal Update Functions (Per-Cell)
# =============================================================================

"""
Update a cell's state signal. Automatically broadcasts to all clients.
"""
function set_cell_state!(cell_id::UUID, state::CellState)
    id_str = string(cell_id)
    signal_name = "cell_state_$(id_str)"

    # Ensure signal exists
    if !(signal_name in CELL_SIGNAL_REGISTRY)
        create_server_signal(signal_name, string(state))
        push!(CELL_SIGNAL_REGISTRY, signal_name)
    end

    # Get signal by name and update it
    sig = get_server_signal_by_name(signal_name)
    if sig !== nothing
        set_server_signal!(sig, string(state))
    end
end

"""
Update a cell's output signal. Automatically broadcasts to all clients.
"""
function set_cell_output!(cell_id::UUID, output::Union{Nothing, CellOutput}, runtime_ms::Union{Nothing, Float64})
    id_str = string(cell_id)
    output_signal_name = "cell_output_$(id_str)"
    runtime_signal_name = "cell_runtime_$(id_str)"

    # Update output HTML
    output_html = output !== nothing ? output.html : ""
    output_sig = get_server_signal_by_name(output_signal_name)
    if output_sig !== nothing
        set_server_signal!(output_sig, output_html)
    end

    # Update runtime
    runtime_str = runtime_ms !== nothing ? string(round(runtime_ms, digits=1)) : ""
    runtime_sig = get_server_signal_by_name(runtime_signal_name)
    if runtime_sig !== nothing
        set_server_signal!(runtime_sig, runtime_str)
    end
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
Update the cells list signal (used for add/delete without refresh).
"""
function update_cells_list_signal!(notebook::Notebook)
    sig = CELLS_LIST_SIGNAL[]
    sig === nothing && return

    cells_data = [
        Dict{String, Any}(
            "id" => string(cell.id),
            "code" => cell.code
        )
        for cell in cells_in_order(notebook)
    ]

    set_server_signal!(sig, cells_data)
end

"""
Broadcast all cell states for a notebook (updates all per-cell signals).
"""
function broadcast_all_cell_states!(notebook::Notebook)
    for (id, cell) in notebook.cells
        set_cell_state!(id, cell.state)
    end
end

# =============================================================================
# Notebook Tabs Signals (Multi-notebook support)
# =============================================================================

"""
Update the notebook tabs signal with all open notebooks.
Called when notebooks are opened, closed, or modified.
"""
function update_notebook_tabs_signal!()
    sig = NOTEBOOK_TABS_SIGNAL[]
    sig === nothing && return

    # Build list of all open notebooks
    tabs_data = [
        Dict{String, Any}(
            "id" => string(nb.id),
            "title" => nb.path !== nothing ? basename(nb.path) : "Untitled",
            "modified" => nb.modified,
            "path" => nb.path
        )
        for nb in values(NOTEBOOKS)
    ]

    set_server_signal!(sig, tabs_data)
end

"""
Set the active notebook ID. Broadcasts to all clients.
"""
function set_active_notebook!(notebook_id::Union{UUID, String})
    sig = ACTIVE_NOTEBOOK_SIGNAL[]
    sig === nothing && return

    id_str = notebook_id isa UUID ? string(notebook_id) : notebook_id
    set_server_signal!(sig, id_str)
end

"""
Get the active notebook ID for a connection, or the default.
"""
function get_active_notebook_id(conn_id::String)::Union{UUID, Nothing}
    if haskey(CONN_NOTEBOOK, conn_id)
        return CONN_NOTEBOOK[conn_id]
    elseif !isempty(NOTEBOOKS)
        return first(keys(NOTEBOOKS))
    end
    return nothing
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
