# server.jl - Comprehensive Server Module for Sessions.jl
#
# This file consolidates all server-side functionality for Sessions.jl, combining:
# 1. Pluto org package integration (ExpressionExplorer, PlutoDependencyExplorer, Malt)
# 2. Therapy.jl WebSocket signal handlers
# 3. Cell execution logic
# 4. Notebook state management
#
# Gold Standard: Pluto.jl (https://github.com/fonsp/Pluto.jl)
# Framework: Therapy.jl (Leptos.rs-inspired reactive web framework)
#
# Note: This file re-exports functionality from Engine/ files for comprehensive
# server-side access while adding Therapy.jl WebSocket integration.

# =============================================================================
# SECTION 1: GLOBAL STATE MANAGEMENT
# =============================================================================
#
# Central state for all notebooks, connections, and signal registries.
# Sessions.jl notebooks are designed to be embeddable Therapy.jl components,
# so state management must support multiple notebooks and connections.

"""
Active notebooks indexed by UUID.
Each notebook has its own Malt worker for sandboxed execution.
"""
const NOTEBOOKS = Dict{UUID, Notebook}()

# =============================================================================
# BOND INFRASTRUCTURE (for @bind macro)
# =============================================================================
#
# Registry tracking which cells define which bonds, and the widget elements.
# This enables reactive execution when bond values change from the frontend.

"""
Registry: cell_id -> set of bond symbol names defined in that cell
"""
const CELL_BOND_NAMES = Dict{UUID, Set{Symbol}}()

"""
Registry: symbol -> widget element (for transform_value lookup)
"""
const BOND_ELEMENTS = Dict{Symbol, Any}()

"""
Struct wrapping a bound element for HTML rendering.
When displayed, wraps the widget in a <bond def="name"> tag.
"""
struct SessionsBond
    element::Any      # HTML-showable widget
    defines::Symbol   # Variable name being bound
    cell_id::UUID     # Owning cell
end

# Bond interface - default implementations (widgets can override)
"""
Default value before any user interaction. Override for custom widgets.
"""
initial_value(x) = missing

"""
Transform JavaScript value to Julia type. Override for custom widgets.
"""
transform_value(x, val) = val

"""
Enumerate possible values (for validation). Override for custom widgets.
"""
possible_values(x) = nothing

"""
Validate value from browser (security). Override for custom widgets.
"""
validate_value(x, val) = true

"""
Register a bond element for a cell.
"""
function create_bond(element, defines::Symbol, cell_id::UUID)
    # Register in cell's bond set
    if !haskey(CELL_BOND_NAMES, cell_id)
        CELL_BOND_NAMES[cell_id] = Set{Symbol}()
    end
    push!(CELL_BOND_NAMES[cell_id], defines)

    # Store element for transform_value lookup
    BOND_ELEMENTS[defines] = element

    # Return bond struct for display
    SessionsBond(element, defines, cell_id)
end

"""
Clear bonds for a cell (called when cell is re-executed or deleted).
"""
function clear_cell_bonds!(cell_id::UUID)
    if haskey(CELL_BOND_NAMES, cell_id)
        for sym in CELL_BOND_NAMES[cell_id]
            delete!(BOND_ELEMENTS, sym)
        end
        delete!(CELL_BOND_NAMES, cell_id)
    end
end

# HTML rendering for SessionsBond
function Base.show(io::IO, ::MIME"text/html", bond::SessionsBond)
    print(io, """<bond def="$(bond.defines)">""")
    show(io, MIME"text/html"(), bond.element)
    print(io, "</bond>")
end

"""
    @bind name element

Create a bidirectional binding between a widget and a Julia variable.
When the user interacts with the widget in the browser, the variable
is updated and all cells referencing it are re-executed.

# Example
```julia
@bind x html"<input type='range' min='1' max='10'>"
# x will update when the slider moves

y = x * 2  # This cell re-runs automatically when x changes
```

The macro:
1. Sets the variable to the widget's initial_value
2. Renders the widget wrapped in a <bond def="name"> tag
3. When the browser sends updates, transform_value converts the JS value
4. Dependent cells are automatically re-executed
"""
macro bind(def, element)
    if !(def isa Symbol)
        error("@bind requires a symbol as the first argument, got: $(repr(def))")
    end

    quote
        local el = $(esc(element))
        # Set initial value using the interface (defaults to missing)
        local init_val = Sessions.initial_value(el)
        # Define the variable globally in the notebook's workspace
        global $(esc(def)) = init_val
        # Note: cell_id is provided by the execution context
        # For now, we use a placeholder; the actual cell_id tracking
        # happens through ExpressionExplorer detecting the definition
        local cell_id = UUIDs.uuid4()  # Placeholder - actual tracking via reactivity
        Sessions.create_bond(el, $(QuoteNode(def)), cell_id)
    end
end

"""
Connection to notebook mapping.
Tracks which WebSocket connections are associated with which notebooks.
"""
const CONN_NOTEBOOK = Dict{String, UUID}()

"""
Registry of per-cell signals that have been created.
Used to avoid duplicate signal creation and track cleanup.
"""
const CELL_SIGNAL_REGISTRY = Set{String}()

"""
Global server signal references for Therapy.jl integration.
"""
const NOTEBOOK_INFO_SIGNAL = Ref{Any}(nothing)
const USERS_SIGNAL = Ref{Any}(nothing)
const CELLS_LIST_SIGNAL = Ref{Any}(nothing)

# =============================================================================
# SECTION 2: PLUTO ORG PACKAGES - EXPRESSIONEXPLORER INTEGRATION
# =============================================================================
#
# ExpressionExplorer analyzes Julia code to find:
# - References: Variables that a cell reads
# - Definitions: Variables that a cell defines
# - Function definitions: Functions defined in a cell
#
# This enables reactive execution where downstream cells automatically
# re-run when upstream cells change.
#
# Note: analyze_cell! and analyze_code are defined in Engine/Reactivity.jl
# The module includes these functions for comprehensive server access.

# =============================================================================
# SECTION 3: PLUTO ORG PACKAGES - PLUTODEPENDENCYEXPLORER INTEGRATION
# =============================================================================
#
# PlutoDependencyExplorer builds a dependency graph between cells and
# computes the execution order. It determines which cells need to re-run
# when a cell's code changes.
#
# Note: PDECell, compute_topology, get_execution_order, get_all_execution_order,
# get_downstream_cells, and has_cycle are defined in Engine/Reactivity.jl

# =============================================================================
# SECTION 4: PLUTO ORG PACKAGES - MALT WORKER EXECUTION
# =============================================================================
#
# Malt.jl provides sandboxed execution in a separate Julia process.
# Each notebook gets its own worker for isolation and interruptibility.
# Supports rich MIME output (HTML, SVG, images) for Therapy.jl rendering.
#
# Note: ExecutionResult, execute_code, execute_cell!, render_rich_output,
# execute_reactive!, and run_all! are defined in Engine/Worker.jl
# Worker management (ensure_worker!, shutdown_worker!, interrupt_worker!)
# is defined in Engine/Notebook.jl

# =============================================================================
# SECTION 5: THERAPY.JL SERVER SIGNALS
# =============================================================================
#
# Server signals enable real-time state synchronization using Therapy.jl's
# reactive WebSocket system. Updates are broadcast as JSON patches (RFC 6902)
# for efficiency.
#
# Signal naming convention:
# - cell_state_{cell_id}   -> "CELL_IDLE"|"CELL_RUNNING"|"CELL_QUEUED"|"CELL_ERROR"
# - cell_output_{cell_id}  -> HTML string of cell output
# - cell_runtime_{cell_id} -> Runtime in ms (number as string)

"""
Initialize global Therapy.jl server signals.
Per-cell signals are created dynamically when cells are added.
"""
function setup_signals!()
    NOTEBOOK_INFO_SIGNAL[] = create_server_signal("notebook_info", Dict{String, Any}())
    USERS_SIGNAL[] = create_server_signal("users", Dict{String, Any}[])
    CELLS_LIST_SIGNAL[] = create_server_signal("cells_list", Dict{String, Any}[])
end

"""
Register server signals for a new cell.
Creates: cell_state_{id}, cell_output_{id}, cell_runtime_{id}
"""
function register_cell_signals!(cell::Cell)
    cell_id = string(cell.id)

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
    update_cells_list_signal!(notebook)
end

"""
Update a cell's state signal. Automatically broadcasts to all clients.
"""
function set_cell_state!(cell_id::UUID, state::CellState)
    id_str = string(cell_id)
    signal_name = "cell_state_$(id_str)"

    if !(signal_name in CELL_SIGNAL_REGISTRY)
        create_server_signal(signal_name, string(state))
        push!(CELL_SIGNAL_REGISTRY, signal_name)
    end

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

    output_html = output !== nothing ? output.html : ""
    output_sig = get_server_signal_by_name(output_signal_name)
    if output_sig !== nothing
        set_server_signal!(output_sig, output_html)
    end

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
# SECTION 6: THERAPY.JL WEBSOCKET CHANNEL HANDLERS
# =============================================================================
#
# Channels handle discrete messages (events) from clients.
# Each channel has a specific purpose and message format.
#
# Request channels: execute, add_cell, delete_cell, move_cell, update_code,
#                   paste_content, interrupt, run_all, restart, save, load
# Response channels: cell_state, cell_output, cell_added, cell_deleted,
#                    cell_moved, paste_complete, interrupted, restarted,
#                    saved, loaded, error

"""
Signal Updates (Using Therapy.jl Server Signals)
These functions update server signals which automatically broadcast
to all subscribed clients via Therapy.jl's WebSocket infrastructure.
"""
function update_cell_state_signal(cell::Cell)
    set_cell_state!(cell.id, cell.state)
end

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

        if code !== nothing
            cell.code = code
            analyze_cell!(cell)
        end

        println("[Sessions] Executing cell: $(cell_id)")
        println("[Sessions] Cell defines: $(cell.definitions)")
        println("[Sessions] Cell references: $(cell.references)")

        broadcast_cell_state(notebook_id, cell)

        try
            cells_to_run = get_execution_order(notebook, [cell_id])
            println("[Sessions] Cells to run ($(length(cells_to_run))): $(map(c -> string(c.id)[1:8], cells_to_run))")
            for c in cells_to_run
                println("[Sessions]   - $(string(c.id)[1:8]): defs=$(c.definitions), refs=$(c.references)")
            end

            results = execute_reactive!(notebook, cell_id)

            for c in cells_to_run
                broadcast_cell_state(notebook_id, c)
                broadcast_cell_output(notebook_id, c)
            end
        catch e
            println("[Sessions] ERROR: $(sprint(showerror, e))")
            send_channel!("error", conn.id, Dict(
                "message" => "Execution failed: $(sprint(showerror, e))"
            ))
        end
    end
end

"""
Handle adding new cells.
Message: {notebook_id, after_cell_id?, code?}
"""
function setup_add_cell_channel!()
    on_channel_message("add_cell") do conn, data
        notebook_id = UUID(data["notebook_id"])

        notebook = get(NOTEBOOKS, notebook_id, nothing)
        if notebook === nothing
            send_channel!("error", conn.id, Dict("message" => "Notebook not found"))
            return
        end

        after_cell_str = get(data, "after_cell_id", nothing)
        after = (after_cell_str !== nothing && after_cell_str != "null" && !isempty(string(after_cell_str))) ? UUID(after_cell_str) : nothing
        code = get(data, "code", "")

        cell = add_cell!(notebook; code=code, after=after)
        register_cell_signals!(cell)
        update_cells_list_signal!(notebook)

        cell_html = render_to_string(CellView(cell))

        broadcast_channel!("cell_added", Dict(
            "notebook_id" => string(notebook_id),
            "cell_id" => string(cell.id),
            "cell_html" => cell_html,
            "after_cell_id" => after === nothing ? nothing : string(after)
        ))
    end
end

"""
Handle deleting cells.
Message: {notebook_id, cell_id}
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
            unregister_cell_signals!(cell_id)
            update_cells_list_signal!(notebook)

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
        end
    end
end

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

        run_all!(notebook)

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

        shutdown_worker!(notebook)
        ensure_worker!(notebook)

        for cell in values(notebook.cells)
            cell.output = nothing
            cell.state = CELL_IDLE
            cell.runtime_ms = nothing
        end

        broadcast_channel!("restarted", Dict(
            "notebook_id" => string(notebook_id)
        ))

        for cell in values(notebook.cells)
            broadcast_cell_state(notebook_id, cell)
        end
    end
end

"""
Handle pasted content (Pluto notebook or raw code).
Message: {notebook_id, content, after_cell_id?}
"""
function setup_paste_content_channel!()
    on_channel_message("paste_content") do conn, data
        notebook_id = UUID(data["notebook_id"])
        content = get(data, "content", "")

        notebook = get(NOTEBOOKS, notebook_id, nothing)
        if notebook === nothing
            send_channel!("error", conn.id, Dict("message" => "Notebook not found"))
            return
        end

        parsed_cells = parse_pluto_content(content)

        if isempty(parsed_cells)
            return
        end

        after_cell_str = get(data, "after_cell_id", nothing)
        after = (after_cell_str !== nothing && after_cell_str != "null" && !isempty(string(after_cell_str))) ? UUID(after_cell_str) : nothing

        created_cells = Cell[]
        prev_cell_id = after

        for (uuid_str, code) in parsed_cells
            cell = add_cell!(notebook; code=code, after=prev_cell_id)
            register_cell_signals!(cell)
            push!(created_cells, cell)
            prev_cell_id = cell.id
        end

        update_cells_list_signal!(notebook)

        for (i, cell) in enumerate(created_cells)
            cell_html = render_to_string(CellView(cell))
            insert_after = i == 1 ? after : created_cells[i-1].id

            broadcast_channel!("cell_added", Dict(
                "notebook_id" => string(notebook_id),
                "cell_id" => string(cell.id),
                "cell_html" => cell_html,
                "after_cell_id" => insert_after === nothing ? nothing : string(insert_after)
            ))
        end

        broadcast_channel!("paste_complete", Dict(
            "notebook_id" => string(notebook_id),
            "cells_created" => length(created_cells),
            "is_pluto_format" => is_pluto_content(content)
        ))
    end
end

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
"""
function setup_load_channel!()
    on_channel_message("load") do conn, data
        path = data["path"]

        try
            notebook = load_notebook(path)
            NOTEBOOKS[notebook.id] = notebook
            CONN_NOTEBOOK[conn.id] = notebook.id
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
# SECTION 6b: BOND VALUE HANDLING
# =============================================================================
#
# When a bond value changes in the browser, we need to:
# 1. Transform the JS value to the proper Julia type
# 2. Set the variable in the worker's workspace
# 3. Find and re-execute all cells that reference this variable

"""
    set_bond_and_run!(notebook::Notebook, name::Symbol, value)

Set a bound variable's value and re-execute dependent cells.
This is the core reactive mechanism for @bind.

1. Sets the variable in the worker's workspace
2. Finds all cells that reference this variable
3. Executes them in topological order
"""
function set_bond_and_run!(notebook::Notebook, name::Symbol, value)
    # Ensure worker exists
    worker = ensure_worker!(notebook)

    # Set the variable in the worker's Main module
    try
        Malt.remote_eval_wait(worker, quote
            global $name = $value
        end)
        println("[Sessions] Bond set: $name = $(repr(value))")
    catch e
        println("[Sessions] ERROR setting bond $name: $(sprint(showerror, e))")
        return
    end

    # Find cells that reference this variable
    affected_cells = UUID[]
    for cell in values(notebook.cells)
        if name in cell.references
            push!(affected_cells, cell.id)
        end
    end

    if isempty(affected_cells)
        println("[Sessions] No cells reference :$name, skipping execution")
        return
    end

    println("[Sessions] Bond :$name affects $(length(affected_cells)) cell(s)")

    # Get full execution order (includes downstream dependencies)
    cells_to_run = get_execution_order(notebook, affected_cells)

    # Mark all as queued
    for cell in cells_to_run
        cell.state = CELL_QUEUED
        broadcast_cell_state(notebook.id, cell)
    end

    # Execute in order
    for cell in cells_to_run
        result = execute_cell!(notebook, cell)
        broadcast_cell_state(notebook.id, cell)
        broadcast_cell_output(notebook.id, cell)

        # Stop on error
        if !result.success
            println("[Sessions] Cell execution failed, stopping bond propagation")
            break
        end
    end
end

"""
Handle bond value changes from browser.
Message: {notebook_id, name, value}
"""
function setup_set_bond_channel!()
    on_channel_message("set_bond") do conn, data
        notebook_id = UUID(data["notebook_id"])
        name = Symbol(data["name"])
        raw_value = data["value"]

        notebook = get(NOTEBOOKS, notebook_id, nothing)
        if notebook === nothing
            send_channel!("error", conn.id, Dict("message" => "Notebook not found"))
            return
        end

        # Transform value using widget's transform_value if available
        widget = get(BOND_ELEMENTS, name, nothing)
        julia_value = transform_value(widget, raw_value)

        println("[Sessions] set_bond: :$name raw=$(repr(raw_value)) transformed=$(repr(julia_value))")

        # Set value and run dependent cells
        set_bond_and_run!(notebook, name, julia_value)
    end
end

"""
Create all message channels.
Must be called before registering handlers.
"""
function create_channels!()
    # Request channels
    create_channel("execute")
    create_channel("add_cell")
    create_channel("delete_cell")
    create_channel("move_cell")
    create_channel("update_code")
    create_channel("paste_content")
    create_channel("interrupt")
    create_channel("run_all")
    create_channel("restart")
    create_channel("save")
    create_channel("load")
    create_channel("set_bond")  # Bond value updates from browser

    # Response channels
    create_channel("cell_state")
    create_channel("cell_output")
    create_channel("cell_added")
    create_channel("cell_deleted")
    create_channel("cell_moved")
    create_channel("paste_complete")
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
    create_channels!()

    setup_execute_channel!()
    setup_add_cell_channel!()
    setup_delete_cell_channel!()
    setup_move_cell_channel!()
    setup_update_code_channel!()
    setup_paste_content_channel!()
    setup_interrupt_channel!()
    setup_run_all_channel!()
    setup_restart_channel!()
    setup_save_channel!()
    setup_load_channel!()
    setup_set_bond_channel!()  # @bind support
end

# =============================================================================
# SECTION 7: WEBSOCKET CONNECTION LIFECYCLE
# =============================================================================
#
# Hooks for WebSocket connection and disconnection events.
# Used to track connected users and clean up resources.

"""
Set up WebSocket connection lifecycle hooks.
"""
function setup_lifecycle!()
    on_ws_connect() do conn
        println("[Sessions] Client connected: $(conn.id)")

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

        sig = USERS_SIGNAL[]
        if sig !== nothing
            update_server_signal!(sig, users -> begin
                filter!(u -> u["id"] != conn.id[1:8], users)
                return users
            end)
        end

        delete!(CONN_NOTEBOOK, conn.id)
    end
end

# =============================================================================
# SECTION 8: NOTEBOOK STATE MANAGEMENT UTILITIES
# =============================================================================
#
# Helper functions for managing notebook state and coordinating between
# the different components.
#
# Note: Worker management functions (ensure_worker!, shutdown_worker!,
# interrupt_worker!) are defined in Engine/Notebook.jl

"""
    create_default_notebook!()

Create a default notebook with welcome cells.
Returns the created notebook.
"""
function create_default_notebook!()
    notebook = Notebook()
    add_cell!(notebook; code="# Welcome to Sessions.jl\n# A reactive Julia notebook powered by Therapy.jl")
    add_cell!(notebook; code="1 + 1")
    add_cell!(notebook; code="x = 42")
    add_cell!(notebook; code="x * 2")
    NOTEBOOKS[notebook.id] = notebook
    register_all_cell_signals!(notebook)
    return notebook
end

"""
    get_or_create_default_notebook!()

Get the first notebook or create a default one if none exists.
"""
function get_or_create_default_notebook!()
    if !isempty(NOTEBOOKS)
        return first(values(NOTEBOOKS))
    else
        return create_default_notebook!()
    end
end

# =============================================================================
# SECTION 9: SERVER INITIALIZATION
# =============================================================================
#
# Functions to initialize all server components.
# Called by the main serve() function in App.jl.

"""
    initialize_server!()

Initialize all server components: signals, channels, lifecycle hooks.
Must be called before starting the HTTP server.
"""
function initialize_server!()
    setup_signals!()
    setup_channels!()
    setup_lifecycle!()
end
