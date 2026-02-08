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
# FILE BROWSER STATE
# =============================================================================

"""
File browser state for each connection.
Tracks current directory and workspace root.
"""
const FILEBROWSER_STATE = Dict{String, Dict{String, Any}}()

"""
Global file browser signal reference.
"""
const FILEBROWSER_LISTING_SIGNAL = Ref{Any}(nothing)

"""
File entry struct for browser listings.
"""
struct FileEntry
    name::String
    is_directory::Bool
    size::Int64
    modified::Float64  # Unix timestamp
    path::String       # Full path for actions
end

"""
Convert FileEntry to Dict for JSON serialization.
"""
function file_entry_to_dict(entry::FileEntry)
    Dict{String,Any}(
        "name" => entry.name,
        "is_directory" => entry.is_directory,
        "size" => entry.size,
        "modified" => entry.modified,
        "path" => entry.path
    )
end

"""
List directory contents, returning FileEntry objects.
Excludes hidden files by default.
"""
function list_directory(path::String; show_hidden::Bool = false)
    entries = FileEntry[]

    if !isdir(path)
        return entries
    end

    try
        for name in readdir(path)
            # Skip hidden files unless requested
            if !show_hidden && startswith(name, ".")
                continue
            end

            full_path = joinpath(path, name)
            try
                info = stat(full_path)
                push!(entries, FileEntry(
                    name,
                    isdir(full_path),
                    Int64(info.size),
                    Float64(info.mtime),
                    full_path
                ))
            catch
                # Skip files we can't stat (permissions, etc.)
            end
        end
    catch e
        @warn "Failed to list directory" path exception=e
    end

    # Sort: directories first, then alphabetically
    sort!(entries, by = e -> (!e.is_directory, lowercase(e.name)))

    return entries
end

"""
Format file size for display.
"""
function format_file_size(bytes::Int64)
    if bytes < 1024
        return "$(bytes) B"
    elseif bytes < 1024 * 1024
        return "$(round(bytes / 1024, digits=1)) KB"
    elseif bytes < 1024 * 1024 * 1024
        return "$(round(bytes / (1024 * 1024), digits=1)) MB"
    else
        return "$(round(bytes / (1024 * 1024 * 1024), digits=1)) GB"
    end
end

"""
Validate that a path is within the allowed workspace.
Returns normalized path if valid, nothing if invalid.
"""
function validate_path(path::String, root::String)
    # Normalize both paths
    norm_path = normpath(abspath(path))
    norm_root = normpath(abspath(root))

    # Check that path is within root (prevent directory traversal)
    if startswith(norm_path, norm_root)
        return norm_path
    else
        return nothing
    end
end

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
    FILEBROWSER_LISTING_SIGNAL[] = create_server_signal("filebrowser_listing", Dict{String, Any}[])
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
    println("[Sessions] set_cell_output! $(id_str[1:8]): html=$(length(output_html)) chars")

    output_sig = get_server_signal_by_name(output_signal_name)
    if output_sig !== nothing
        set_server_signal!(output_sig, output_html)
    else
        @warn "[Sessions] Signal not found: $output_signal_name — output dropped"
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

        # Mark as running and broadcast immediately
        cell.state = CELL_RUNNING
        broadcast_cell_state(notebook_id, cell)

        # Run execution async so WS handler returns immediately,
        # allowing signal updates to reach the client
        @async try
            cells_to_run = get_execution_order(notebook, [cell_id])
            println("[Sessions] Cells to run ($(length(cells_to_run))): $(map(c -> string(c.id)[1:8], cells_to_run))")

            results = execute_reactive!(notebook, cell_id)

            for c in cells_to_run
                broadcast_cell_state(notebook_id, c)
                broadcast_cell_output(notebook_id, c)
            end
            println("[Sessions] Execution complete for cell $(string(cell_id)[1:8])")
        catch e
            println("[Sessions] ERROR: $(sprint(showerror, e))")
            cell.state = CELL_ERROR
            broadcast_cell_state(notebook_id, cell)
            broadcast_channel!("error", Dict(
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

        cell_html = render_to_string(IDECellCard(cell))

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
        notebook = get(NOTEBOOKS, notebook_id, nothing)
        if notebook === nothing
            return
        end

        # Support both direction-based (from toolbar) and index-based moves
        new_index = if haskey(data, "direction")
            current_idx = findfirst(id -> id == cell_id, notebook.cell_order)
            if current_idx === nothing
                return
            end
            if data["direction"] == "up"
                max(1, current_idx - 1)
            else
                min(length(notebook.cell_order), current_idx + 1)
            end
        else
            data["new_index"]
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
Handle toggle fold. Toggles cell.folded and broadcasts.
Message: {notebook_id, cell_id}
"""
function setup_toggle_fold_channel!()
    on_channel_message("toggle_fold") do conn, data
        notebook_id = UUID(data["notebook_id"])
        cell_id = UUID(data["cell_id"])
        notebook = get(NOTEBOOKS, notebook_id, nothing)
        if notebook === nothing
            return
        end

        cell = get_cell(notebook, cell_id)
        if cell === nothing
            return
        end

        cell.folded = !cell.folded
        broadcast_channel!("cell_folded", Dict(
            "notebook_id" => string(notebook_id),
            "cell_id" => string(cell_id),
            "folded" => cell.folded
        ))
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

        # Mark all cells as queued immediately
        for cell in values(notebook.cells)
            cell.state = CELL_QUEUED
            broadcast_cell_state(notebook_id, cell)
        end

        # Run async so WS handler returns immediately
        @async try
            run_all!(notebook)

            for cell in values(notebook.cells)
                broadcast_cell_state(notebook_id, cell)
                broadcast_cell_output(notebook_id, cell)
            end
            println("[Sessions] Run all complete")
        catch e
            println("[Sessions] Run all ERROR: $(sprint(showerror, e))")
            broadcast_channel!("error", Dict(
                "message" => "Run all failed: $(sprint(showerror, e))"
            ))
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
            cell_html = render_to_string(IDECellCard(cell))
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

"""
Handle export_notebook channel messages.
Message: {notebook_id, format}
Formats: "html", "script", "pluto"
Returns exported content via export_result channel.
"""
function setup_export_channel!()
    on_channel_message("export_notebook") do conn, data
        notebook_id_str = get(data, "notebook_id", "")
        format = get(data, "format", "html")

        if isempty(notebook_id_str)
            send_channel!("error", conn.id, Dict("message" => "Missing notebook_id"))
            return
        end

        notebook_id = UUID(notebook_id_str)
        notebook = get(NOTEBOOKS, notebook_id, nothing)
        if notebook === nothing
            send_channel!("error", conn.id, Dict("message" => "Notebook not found"))
            return
        end

        try
            title = notebook.path !== nothing ? replace(basename(notebook.path), ".jl" => "") : "notebook"

            if format == "html"
                content = export_to_html(notebook)
                send_channel!("export_result", conn.id, Dict(
                    "content" => content,
                    "filename" => "$(title).html",
                    "mime" => "text/html"
                ))
            elseif format == "script"
                content = export_to_script(notebook)
                send_channel!("export_result", conn.id, Dict(
                    "content" => content,
                    "filename" => "$(title).jl",
                    "mime" => "text/x-julia"
                ))
            elseif format == "pluto"
                # Save to temp file and read back (save_notebook sets path)
                original_path = notebook.path
                tmp = tempname() * ".jl"
                save_notebook(notebook, tmp)
                content = read(tmp, String)
                rm(tmp; force=true)
                # Restore original path
                notebook.path = original_path
                send_channel!("export_result", conn.id, Dict(
                    "content" => content,
                    "filename" => "$(title).jl",
                    "mime" => "text/x-julia"
                ))
            else
                send_channel!("error", conn.id, Dict("message" => "Unknown format: $format"))
            end

            println("[Sessions] Exported notebook as $format: $title")
        catch e
            send_channel!("error", conn.id, Dict("message" => "Export failed: $(sprint(showerror, e))"))
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

# =============================================================================
# SECTION 6B: FILE BROWSER CHANNEL HANDLERS
# =============================================================================

"""
Update file browser listing signal with current directory contents.
"""
function update_filebrowser_listing!(path::String)
    entries = list_directory(path)
    listing = [file_entry_to_dict(e) for e in entries]

    sig = FILEBROWSER_LISTING_SIGNAL[]
    if sig !== nothing
        set_server_signal!(sig, listing)
    end
end

"""
Get file browser state for a connection, initializing if needed.
"""
function get_filebrowser_state(conn_id::String; root::String = pwd())
    if !haskey(FILEBROWSER_STATE, conn_id)
        FILEBROWSER_STATE[conn_id] = Dict{String, Any}(
            "root" => root,
            "current" => root
        )
    end
    return FILEBROWSER_STATE[conn_id]
end

"""
Handle navigate_directory channel messages.
Message: {path} or {path, root}
"""
function setup_navigate_directory_channel!()
    on_channel_message("navigate_directory") do conn, data
        state = get_filebrowser_state(conn.id)
        root = get(data, "root", state["root"])
        path = get(data, "path", state["current"])

        # Validate path is within root
        validated = validate_path(path, root)
        if validated === nothing
            println("[Sessions] Path traversal attempt blocked: $path")
            send_channel!("error", conn.id, Dict("message" => "Invalid path"))
            return
        end

        # Update state
        state["root"] = root
        state["current"] = validated

        # Update listing
        update_filebrowser_listing!(validated)

        println("[Sessions] Navigate to: $validated")
    end
end

"""
Handle refresh_filebrowser channel messages.
"""
function setup_refresh_filebrowser_channel!()
    on_channel_message("refresh_filebrowser") do conn, data
        state = get_filebrowser_state(conn.id)
        update_filebrowser_listing!(state["current"])
        println("[Sessions] Refresh file browser")
    end
end

"""
Handle create_file channel messages.
Message: {path, name}
"""
function setup_create_file_channel!()
    on_channel_message("create_file") do conn, data
        state = get_filebrowser_state(conn.id)
        dir = get(data, "path", state["current"])
        name = get(data, "name", "untitled.jl")

        # Validate path
        validated = validate_path(dir, state["root"])
        if validated === nothing
            send_channel!("error", conn.id, Dict("message" => "Invalid path"))
            return
        end

        # Create file
        file_path = joinpath(validated, name)
        if !isfile(file_path)
            try
                write(file_path, "# New file\n")
                update_filebrowser_listing!(validated)
                println("[Sessions] Created file: $file_path")
            catch e
                send_channel!("error", conn.id, Dict("message" => "Failed to create file: $e"))
            end
        else
            send_channel!("error", conn.id, Dict("message" => "File already exists"))
        end
    end
end

"""
Handle create_folder channel messages.
Message: {path, name}
"""
function setup_create_folder_channel!()
    on_channel_message("create_folder") do conn, data
        state = get_filebrowser_state(conn.id)
        dir = get(data, "path", state["current"])
        name = get(data, "name", "New Folder")

        # Validate path
        validated = validate_path(dir, state["root"])
        if validated === nothing
            send_channel!("error", conn.id, Dict("message" => "Invalid path"))
            return
        end

        # Create folder
        folder_path = joinpath(validated, name)
        if !isdir(folder_path)
            try
                mkdir(folder_path)
                update_filebrowser_listing!(validated)
                println("[Sessions] Created folder: $folder_path")
            catch e
                send_channel!("error", conn.id, Dict("message" => "Failed to create folder: $e"))
            end
        else
            send_channel!("error", conn.id, Dict("message" => "Folder already exists"))
        end
    end
end

"""
Handle create_notebook channel messages.
Creates a new .jl file with Pluto notebook header, then opens it.
Message: {name}
"""
function setup_create_notebook_channel!()
    on_channel_message("create_notebook") do conn, data
        state = get_filebrowser_state(conn.id)
        name = get(data, "name", "notebook.jl")

        # Ensure .jl extension
        if !endswith(name, ".jl")
            name = name * ".jl"
        end

        # Validate path
        dir = state["current"]
        validated = validate_path(dir, state["root"])
        if validated === nothing
            send_channel!("error", conn.id, Dict("message" => "Invalid path"))
            return
        end

        file_path = joinpath(validated, name)
        if isfile(file_path)
            send_channel!("error", conn.id, Dict("message" => "File already exists: $name"))
            return
        end

        try
            # Create a new Pluto-format notebook
            notebook = Notebook()
            notebook.path = file_path
            add_cell!(notebook; code="# $(replace(name, ".jl" => ""))")
            add_cell!(notebook; code="")
            save_notebook(notebook)

            # Register and open the notebook
            NOTEBOOKS[notebook.id] = notebook
            register_all_cell_signals!(notebook)
            CONN_NOTEBOOK[conn.id] = notebook.id

            # Update file listing
            update_filebrowser_listing!(validated)

            # Notify client
            send_channel!("loaded", conn.id, Dict(
                "notebook_id" => string(notebook.id),
                "path" => file_path,
                "cell_count" => length(notebook.cells)
            ))
            println("[Sessions] Created notebook: $file_path")
        catch e
            send_channel!("error", conn.id, Dict("message" => "Failed to create notebook: $e"))
        end
    end
end

"""
Handle delete_item channel messages.
Message: {path}
"""
function setup_delete_item_channel!()
    on_channel_message("delete_item") do conn, data
        state = get_filebrowser_state(conn.id)
        path = get(data, "path", "")

        # Validate path
        validated = validate_path(path, state["root"])
        if validated === nothing
            send_channel!("error", conn.id, Dict("message" => "Invalid path"))
            return
        end

        # Don't allow deleting root
        if validated == normpath(abspath(state["root"]))
            send_channel!("error", conn.id, Dict("message" => "Cannot delete workspace root"))
            return
        end

        try
            if isdir(validated)
                rm(validated; recursive=true)
            else
                rm(validated)
            end
            update_filebrowser_listing!(state["current"])
            println("[Sessions] Deleted: $validated")
        catch e
            send_channel!("error", conn.id, Dict("message" => "Failed to delete: $e"))
        end
    end
end

"""
Handle rename_item channel messages.
Message: {old_path, new_name}
"""
function setup_rename_item_channel!()
    on_channel_message("rename_item") do conn, data
        state = get_filebrowser_state(conn.id)
        old_path = get(data, "old_path", "")
        new_name = get(data, "new_name", "")

        # Validate old path
        validated_old = validate_path(old_path, state["root"])
        if validated_old === nothing
            send_channel!("error", conn.id, Dict("message" => "Invalid path"))
            return
        end

        # Build new path
        dir = dirname(validated_old)
        new_path = joinpath(dir, new_name)

        # Validate new path
        validated_new = validate_path(new_path, state["root"])
        if validated_new === nothing
            send_channel!("error", conn.id, Dict("message" => "Invalid destination path"))
            return
        end

        try
            mv(validated_old, validated_new)
            update_filebrowser_listing!(state["current"])
            println("[Sessions] Renamed: $validated_old -> $validated_new")
        catch e
            send_channel!("error", conn.id, Dict("message" => "Failed to rename: $e"))
        end
    end
end

"""
Handle open_file channel messages.
Message: {path}
For .jl files, opens as notebook. For others, sends file content.
"""
function setup_open_file_channel!()
    on_channel_message("open_file") do conn, data
        state = get_filebrowser_state(conn.id)
        path = get(data, "path", "")

        # Validate path
        validated = validate_path(path, state["root"])
        if validated === nothing
            send_channel!("error", conn.id, Dict("message" => "Invalid path"))
            return
        end

        if !isfile(validated)
            send_channel!("error", conn.id, Dict("message" => "File not found"))
            return
        end

        # For .jl files, check if it's a Pluto notebook and open as such
        if endswith(lowercase(validated), ".jl")
            try
                # Try to load as notebook (will work for Pluto format)
                notebook = load_notebook(validated)
                NOTEBOOKS[notebook.id] = notebook
                register_all_cell_signals!(notebook)
                CONN_NOTEBOOK[conn.id] = notebook.id

                # Send notebook info via channel
                send_channel!("loaded", conn.id, Dict(
                    "notebook_id" => string(notebook.id),
                    "path" => validated,
                    "cell_count" => length(notebook.cells)
                ))
                println("[Sessions] Opened notebook: $validated")
            catch e
                # Not a valid Pluto notebook, just inform client
                send_channel!("error", conn.id, Dict(
                    "message" => "Failed to open as notebook: $e"
                ))
            end
        else
            # For other files, could send content for viewing
            # This is a placeholder - full implementation in SESSIONS-2101
            send_channel!("error", conn.id, Dict(
                "message" => "Only .jl files can be opened"
            ))
        end
    end
end

# =============================================================================
# SECTION 6B1b: MULTI-NOTEBOOK CHANNEL HANDLERS (SESSIONS-3701)
# =============================================================================
#
# Channels for switching between, closing, and managing multiple open notebooks.
# Each notebook has its own Malt worker and per-cell signals.

"""
Handle switch_notebook channel messages.
Message: {notebook_id}
Switches the connection's active notebook and triggers page reload.
"""
function setup_switch_notebook_channel!()
    on_channel_message("switch_notebook") do conn, data
        notebook_id_str = get(data, "notebook_id", "")
        if isempty(notebook_id_str)
            send_channel!("error", conn.id, Dict("message" => "Missing notebook_id"))
            return
        end

        notebook_id = UUID(notebook_id_str)
        if !haskey(NOTEBOOKS, notebook_id)
            send_channel!("error", conn.id, Dict("message" => "Notebook not found"))
            return
        end

        # Update connection's active notebook
        CONN_NOTEBOOK[conn.id] = notebook_id
        notebook = NOTEBOOKS[notebook_id]

        # Register signals for the switched-to notebook's cells
        register_all_cell_signals!(notebook)

        # Broadcast switch event to trigger client reload
        broadcast_channel!("notebook_switched", Dict(
            "notebook_id" => string(notebook_id),
            "title" => notebook.path !== nothing ? basename(notebook.path) : "Untitled"
        ))
        println("[Sessions] Switched to notebook: $(notebook.path !== nothing ? notebook.path : string(notebook_id))")
    end
end

"""
Handle close_notebook channel messages.
Message: {notebook_id}
Shuts down worker, unregisters signals, removes from NOTEBOOKS.
Auto-switches to another notebook if available.
"""
function setup_close_notebook_channel!()
    on_channel_message("close_notebook") do conn, data
        notebook_id_str = get(data, "notebook_id", "")
        if isempty(notebook_id_str)
            send_channel!("error", conn.id, Dict("message" => "Missing notebook_id"))
            return
        end

        notebook_id = UUID(notebook_id_str)
        if !haskey(NOTEBOOKS, notebook_id)
            return  # Already closed, ignore
        end

        notebook = NOTEBOOKS[notebook_id]
        nb_path = notebook.path

        # Shutdown the worker if running
        if notebook.worker !== nothing
            try
                Malt.stop(notebook.worker)
            catch
                # Worker may already be dead
            end
            notebook.worker = nothing
        end

        # Unregister all cell signals for this notebook
        for cell in values(notebook.cells)
            unregister_cell_signals!(cell.id)
        end

        # Remove from NOTEBOOKS
        delete!(NOTEBOOKS, notebook_id)

        # Clean up any connections pointing to this notebook
        for (conn_id, nb_id) in collect(CONN_NOTEBOOK)
            if nb_id == notebook_id
                delete!(CONN_NOTEBOOK, conn_id)
            end
        end

        # Broadcast close event
        broadcast_channel!("notebook_closed", Dict(
            "notebook_id" => string(notebook_id)
        ))

        # If there are remaining notebooks, switch to the first one
        if !isempty(NOTEBOOKS)
            first_nb = first(values(NOTEBOOKS))
            CONN_NOTEBOOK[conn.id] = first_nb.id
            register_all_cell_signals!(first_nb)
            broadcast_channel!("notebook_switched", Dict(
                "notebook_id" => string(first_nb.id),
                "title" => first_nb.path !== nothing ? basename(first_nb.path) : "Untitled"
            ))
        end

        println("[Sessions] Closed notebook: $(nb_path !== nothing ? nb_path : string(notebook_id))")
    end
end

# =============================================================================
# SECTION 6B2: PACKAGE MANAGEMENT CHANNEL HANDLERS (SESSIONS-3602)
# =============================================================================
#
# Package management via Malt worker. Operations run Pkg commands in the
# notebook's worker process so they don't block the server.

"""
Run a Pkg operation in the notebook's Malt worker.
Returns the result or sends an error via pkg_error channel.
"""
function run_pkg_operation!(conn_id::String, operation::String, args::Dict)
    # Find the notebook for this connection
    nb_id = get(CONN_NOTEBOOK, conn_id, nothing)
    if nb_id === nothing
        send_channel!("pkg_error", conn_id, Dict("message" => "No notebook open. Run a cell first."))
        return nothing
    end

    notebook = get(NOTEBOOKS, nb_id, nothing)
    if notebook === nothing
        send_channel!("pkg_error", conn_id, Dict("message" => "Notebook not found"))
        return nothing
    end

    worker = notebook.worker
    if worker === nothing
        send_channel!("pkg_error", conn_id, Dict("message" => "No worker running. Run a cell first."))
        return nothing
    end

    try
        if operation == "add"
            pkg_name = get(args, "name", "")
            if isempty(pkg_name)
                send_channel!("pkg_error", conn_id, Dict("message" => "Package name required"))
                return nothing
            end
            Malt.remote_eval_wait(worker, :(import Pkg; Pkg.add($(pkg_name))))
            send_channel!("pkg_success", conn_id, Dict("operation" => "add", "name" => pkg_name))
        elseif operation == "remove"
            pkg_name = get(args, "name", "")
            if isempty(pkg_name)
                send_channel!("pkg_error", conn_id, Dict("message" => "Package name required"))
                return nothing
            end
            Malt.remote_eval_wait(worker, :(import Pkg; Pkg.rm($(pkg_name))))
            send_channel!("pkg_success", conn_id, Dict("operation" => "remove", "name" => pkg_name))
        elseif operation == "update"
            Malt.remote_eval_wait(worker, :(import Pkg; Pkg.update()))
            send_channel!("pkg_success", conn_id, Dict("operation" => "update"))
        elseif operation == "status"
            # Get package list from worker
            result = Malt.remote_eval_wait(worker, quote
                import Pkg
                deps = Pkg.dependencies()
                packages = []
                for (uuid, info) in deps
                    push!(packages, Dict(
                        "name" => info.name,
                        "version" => string(info.version),
                        "is_direct" => info.is_direct_dep
                    ))
                end
                sort!(packages, by=p -> lowercase(p["name"]))
                packages
            end)
            send_channel!("pkg_list", conn_id, Dict("packages" => result))
        end
    catch e
        msg = sprint(showerror, e)
        send_channel!("pkg_error", conn_id, Dict("message" => msg))
    end

    return nothing
end

function setup_pkg_add_channel!()
    on_channel_message("pkg_add") do conn, data
        @async run_pkg_operation!(conn.id, "add", Dict{String,Any}(data))
    end
end

function setup_pkg_remove_channel!()
    on_channel_message("pkg_remove") do conn, data
        @async run_pkg_operation!(conn.id, "remove", Dict{String,Any}(data))
    end
end

function setup_pkg_update_channel!()
    on_channel_message("pkg_update") do conn, data
        @async run_pkg_operation!(conn.id, "update", Dict{String,Any}(data))
    end
end

function setup_pkg_status_channel!()
    on_channel_message("pkg_status") do conn, data
        @async run_pkg_operation!(conn.id, "status", Dict{String,Any}(data))
    end
end

# =============================================================================
# SECTION 6B3: WORKSPACE INSPECTOR CHANNEL HANDLER (SESSIONS-3606)
# =============================================================================

"""
Query workspace variables from the notebook's Malt worker.
Returns list of {name, type, size} dicts.
"""
function setup_workspace_vars_channel!()
    on_channel_message("workspace_vars") do conn, data
        nb_id = get(CONN_NOTEBOOK, conn.id, nothing)
        if nb_id === nothing
            send_channel!("workspace_vars", conn.id, Dict("variables" => []))
            return
        end

        notebook = get(NOTEBOOKS, nb_id, nothing)
        if notebook === nothing || notebook.worker === nothing
            send_channel!("workspace_vars", conn.id, Dict("variables" => []))
            return
        end

        @async try
            result = Malt.remote_eval_wait(notebook.worker, quote
                vars = []
                for name in names(Main; all=false, imported=false)
                    name === :Main && continue
                    name === :Base && continue
                    name === :Core && continue
                    try
                        val = getfield(Main, name)
                        t = string(typeof(val))
                        s = try
                            if val isa AbstractArray
                                join(size(val), "×")
                            elseif val isa AbstractString
                                string(length(val)) * " chars"
                            elseif val isa AbstractDict
                                string(length(val)) * " entries"
                            else
                                ""
                            end
                        catch
                            ""
                        end
                        push!(vars, Dict("name" => string(name), "type" => t, "size" => s))
                    catch
                    end
                end
                sort!(vars, by=v -> lowercase(v["name"]))
                vars
            end)
            send_channel!("workspace_vars", conn.id, Dict("variables" => result))
        catch e
            send_channel!("workspace_vars", conn.id, Dict("variables" => []))
        end
    end
end

# =============================================================================
# SECTION 6C: TERMINAL CHANNEL HANDLERS (SESSIONS-2110)
# =============================================================================
#
# Terminal emulation via PTY (pseudo-terminal).
# Uses Julia's UnixIO package for PTY management on Unix systems.
# On Windows, uses ConPTY via external process.

"""
Active terminal sessions.
Maps session_id -> PTY process info
"""
const TERMINAL_SESSIONS = Dict{String, Dict{String, Any}}()

"""
Terminal session cleanup task references.
"""
const TERMINAL_CLEANUP_TASKS = Dict{String, Any}()

"""
Create a new terminal session with PTY.
Returns session info dict.
"""
function create_terminal_session!(session_id::String; cols::Int=80, rows::Int=24)
    # Check if session already exists
    if haskey(TERMINAL_SESSIONS, session_id)
        return TERMINAL_SESSIONS[session_id]
    end

    # Get shell from environment
    shell = get(ENV, "SHELL", "/bin/bash")
    if !isfile(shell)
        shell = Sys.iswindows() ? "cmd.exe" : "/bin/sh"
    end

    try
        env = copy(ENV)
        env["TERM"] = "xterm-256color"
        env["COLUMNS"] = string(cols)
        env["LINES"] = string(rows)

        # Use explicit Pipe objects for bidirectional I/O
        inp = Pipe()
        out = Pipe()
        cmd = setenv(`$(shell)`, env)
        proc = Base.run(pipeline(cmd; stdin=inp, stdout=out, stderr=out), wait=false)
        close(out.in)   # Close write end of output pipe (server reads from out)
        close(inp.out)   # Close read end of input pipe (server writes to inp)

        session = Dict{String, Any}(
            "id" => session_id,
            "process" => proc,
            "stdin" => inp,
            "stdout" => out,
            "shell" => shell,
            "cols" => cols,
            "rows" => rows,
            "created_at" => time(),
            "active" => true
        )

        TERMINAL_SESSIONS[session_id] = session

        # Start output reader task
        start_terminal_reader!(session_id)

        println("[Sessions] Terminal created: $session_id (shell: $shell)")
        return session

    catch e
        println("[Sessions] Failed to create terminal: $(sprint(showerror, e))")
        return nothing
    end
end

"""
Start a task to read terminal output and broadcast to clients.
"""
function start_terminal_reader!(session_id::String)
    session = get(TERMINAL_SESSIONS, session_id, nothing)
    if session === nothing
        return
    end

    out = session["stdout"]

    # Create async task to read output
    task = @async begin
        try
            while session["active"] && !eof(out)
                data = readavailable(out)
                if !isempty(data)
                    output = String(data)
                    # Broadcast to all clients subscribed to this terminal
                    broadcast_channel!("terminal_output_$session_id", Dict(
                        "session_id" => session_id,
                        "output" => output
                    ))
                end
            end
        catch e
            if !(e isa EOFError || e isa Base.IOError)
                println("[Sessions] Terminal reader error: $(sprint(showerror, e))")
            end
        finally
            # Mark session as inactive
            if haskey(TERMINAL_SESSIONS, session_id)
                TERMINAL_SESSIONS[session_id]["active"] = false
            end
        end
    end

    TERMINAL_CLEANUP_TASKS[session_id] = task
end

"""
Write data to a terminal session.
"""
function terminal_write!(session_id::String, data::String)
    session = get(TERMINAL_SESSIONS, session_id, nothing)
    if session === nothing || !session["active"]
        return false
    end

    try
        inp = session["stdin"]
        write(inp, data)
        flush(inp)
        return true
    catch e
        println("[Sessions] Terminal write error: $(sprint(showerror, e))")
    end

    return false
end

"""
Resize a terminal session.
"""
function terminal_resize!(session_id::String, cols::Int, rows::Int)
    session = get(TERMINAL_SESSIONS, session_id, nothing)
    if session === nothing
        return false
    end

    session["cols"] = cols
    session["rows"] = rows

    # On Unix, send SIGWINCH to notify of resize
    # Note: This is a simplified version - full PTY resize requires ioctl
    if !Sys.iswindows()
        try
            process = session["process"]
            # Can't easily resize with script approach
            # Would need proper PTY library for this
        catch e
            println("[Sessions] Terminal resize error: $(sprint(showerror, e))")
        end
    end

    return true
end

"""
Close a terminal session.
"""
function close_terminal_session!(session_id::String)
    session = get(TERMINAL_SESSIONS, session_id, nothing)
    if session === nothing
        return
    end

    session["active"] = false

    try
        # Close stdin pipe to signal EOF to the shell
        inp = session["stdin"]
        close(inp)
    catch; end

    try
        # Kill the process
        proc = session["process"]
        if process_running(proc)
            kill(proc)
        end
    catch; end

    # Cancel reader task
    if haskey(TERMINAL_CLEANUP_TASKS, session_id)
        delete!(TERMINAL_CLEANUP_TASKS, session_id)
    end

    delete!(TERMINAL_SESSIONS, session_id)
    println("[Sessions] Terminal closed: $session_id")
end

"""
Handle create_terminal channel messages.
Message: {session_id, cols?, rows?}
"""
function setup_create_terminal_channel!()
    on_channel_message("create_terminal") do conn, data
        session_id = get(data, "session_id", string(uuid4()))
        cols = get(data, "cols", 80)
        rows = get(data, "rows", 24)

        session = create_terminal_session!(session_id; cols=cols, rows=rows)

        if session !== nothing
            # Create output channel for this terminal
            create_channel("terminal_output_$session_id")

            # Send confirmation
            send_channel!("terminal_created", conn.id, Dict(
                "session_id" => session_id,
                "shell" => session["shell"]
            ))

            # Send initial message
            broadcast_channel!("terminal_output_$session_id", Dict(
                "session_id" => session_id,
                "output" => "\x1b[32mTerminal ready.\x1b[0m\r\n"
            ))
        else
            send_channel!("error", conn.id, Dict(
                "message" => "Failed to create terminal"
            ))
        end
    end
end

"""
Handle terminal_input channel messages.
Message: {session_id, data}
"""
function setup_terminal_input_channel!()
    on_channel_message("terminal_input") do conn, data
        session_id = get(data, "session_id", "")
        input_data = get(data, "data", "")

        if !isempty(session_id) && !isempty(input_data)
            terminal_write!(session_id, input_data)
        end
    end
end

"""
Handle terminal_resize channel messages.
Message: {session_id, cols, rows}
"""
function setup_terminal_resize_channel!()
    on_channel_message("terminal_resize") do conn, data
        session_id = get(data, "session_id", "")
        cols = get(data, "cols", 80)
        rows = get(data, "rows", 24)

        if !isempty(session_id)
            terminal_resize!(session_id, cols, rows)
        end
    end
end

"""
Handle close_terminal channel messages.
Message: {session_id}
"""
function setup_close_terminal_channel!()
    on_channel_message("close_terminal") do conn, data
        session_id = get(data, "session_id", "")
        if !isempty(session_id)
            close_terminal_session!(session_id)
        end
    end
end

"""
Handle new_terminal channel messages (create terminal and return ID).
Message: {title?}
"""
function setup_new_terminal_channel!()
    on_channel_message("new_terminal") do conn, data
        title = get(data, "title", "Terminal")
        session_id = string(uuid4())

        session = create_terminal_session!(session_id)

        if session !== nothing
            create_channel("terminal_output_$session_id")

            # Send terminal info to client for UI creation
            send_channel!("terminal_created", conn.id, Dict(
                "session_id" => session_id,
                "title" => title,
                "shell" => session["shell"]
            ))
        else
            send_channel!("error", conn.id, Dict(
                "message" => "Failed to create terminal"
            ))
        end
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
    create_channel("toggle_fold")
    create_channel("update_code")
    create_channel("paste_content")
    create_channel("interrupt")
    create_channel("run_all")
    create_channel("restart")
    create_channel("save")
    create_channel("load")
    create_channel("set_bond")  # Bond value updates from browser

    # File browser channels
    create_channel("navigate_directory")
    create_channel("refresh_filebrowser")
    create_channel("create_file")
    create_channel("create_folder")
    create_channel("create_notebook")
    create_channel("delete_item")
    create_channel("rename_item")
    create_channel("open_file")

    # Package management channels (SESSIONS-3602)
    create_channel("pkg_add")
    create_channel("pkg_remove")
    create_channel("pkg_update")
    create_channel("pkg_status")
    create_channel("pkg_list")      # Response: package list
    create_channel("pkg_error")     # Response: error message
    create_channel("pkg_success")   # Response: operation succeeded

    # Workspace inspector channel (SESSIONS-3606)
    create_channel("workspace_vars")

    # Multi-notebook channels (SESSIONS-3701)
    create_channel("switch_notebook")
    create_channel("close_notebook")
    create_channel("notebook_switched")  # Response
    create_channel("notebook_closed")    # Response

    # Export channels (SESSIONS-3702)
    create_channel("export_notebook")
    create_channel("export_result")      # Response

    # Terminal channels (SESSIONS-2110)
    create_channel("create_terminal")
    create_channel("terminal_input")
    create_channel("terminal_resize")
    create_channel("close_terminal")
    create_channel("new_terminal")
    create_channel("terminal_created")  # Response

    # Response channels
    create_channel("cell_state")
    create_channel("cell_output")
    create_channel("cell_added")
    create_channel("cell_deleted")
    create_channel("cell_moved")
    create_channel("cell_folded")
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

    # Notebook channels
    setup_execute_channel!()
    setup_add_cell_channel!()
    setup_delete_cell_channel!()
    setup_move_cell_channel!()
    setup_toggle_fold_channel!()
    setup_update_code_channel!()
    setup_paste_content_channel!()
    setup_interrupt_channel!()
    setup_run_all_channel!()
    setup_restart_channel!()
    setup_save_channel!()
    setup_load_channel!()
    setup_set_bond_channel!()  # @bind support
    setup_export_channel!()    # Export (SESSIONS-3702)

    # File browser channels
    setup_navigate_directory_channel!()
    setup_refresh_filebrowser_channel!()
    setup_create_file_channel!()
    setup_create_folder_channel!()
    setup_create_notebook_channel!()
    setup_delete_item_channel!()
    setup_rename_item_channel!()
    setup_open_file_channel!()

    # Multi-notebook channels (SESSIONS-3701)
    setup_switch_notebook_channel!()
    setup_close_notebook_channel!()

    # Package management channels (SESSIONS-3602)
    setup_pkg_add_channel!()
    setup_pkg_remove_channel!()
    setup_pkg_update_channel!()
    setup_pkg_status_channel!()

    # Workspace inspector (SESSIONS-3606)
    setup_workspace_vars_channel!()

    # Terminal channels (SESSIONS-2110)
    setup_create_terminal_channel!()
    setup_terminal_input_channel!()
    setup_terminal_resize_channel!()
    setup_close_terminal_channel!()
    setup_new_terminal_channel!()
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
        delete!(FILEBROWSER_STATE, conn.id)  # Clean up file browser state
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
