# =============================================================================
# WebSocket Server for Sessions.jl
# =============================================================================
#
# Architecture:
# - Uses Therapy.jl's island() for reactive UI components
# - Islands are auto-discovered and compiled to Wasm
# - WebSocket handles compute (code execution, files, terminal)
# - Server renders UI using Therapy.jl VNodes

using Therapy

include("ClientBridge.jl")

# =============================================================================
# Global State
# =============================================================================

const CELLS = Dict{UUID, Cell}()
const CELL_ORDER = Vector{UUID}()
const EXECUTOR = Ref{Executor}(Executor())
const WS_CLIENTS = Set{Any}()

# Compiled islands cache
const COMPILED_ISLANDS_CACHE = Ref{Any}(nothing)

# =============================================================================
# Island Discovery & Compilation (Using Therapy.jl's Pattern)
# =============================================================================

"""
Discover and compile islands using Therapy.jl's pattern.
Islands are registered via register_islands!() at runtime.
"""
function get_compiled_islands()
    if COMPILED_ISLANDS_CACHE[] !== nothing
        return COMPILED_ISLANDS_CACHE[]
    end

    # Register islands at runtime (avoids precompilation issues)
    register_islands!()

    println("Discovering and compiling islands...")

    # Get all registered islands from Therapy.jl's registry
    registered = get_islands()

    if isempty(registered)
        println("  No islands found")
        COMPILED_ISLANDS_CACHE[] = Dict{Symbol, Any}()
        return COMPILED_ISLANDS_CACHE[]
    end

    compiled = Dict{Symbol, Any}()

    for island_def in registered
        name = island_def.name
        println("  Compiling: $name")

        try
            # Use therapy-island element as container (Therapy.jl's convention)
            selector = "therapy-island[data-component=\"$(lowercase(string(name)))\"]"

            # Compile the island
            result = compile_component(island_def.render_fn; container_selector=selector)

            wasm_filename = "$(lowercase(string(name))).wasm"
            # Replace default app.wasm path with island-specific path
            js = replace(result.hydration.js, "./app.wasm" => "/$wasm_filename")

            compiled[name] = (
                html = result.html,
                js = js,
                wasm_bytes = result.wasm.bytes,
                wasm_filename = wasm_filename
            )

            println("    Wasm: $(length(result.wasm.bytes)) bytes")
        catch e
            @warn "Failed to compile island: $name" exception=e
        end
    end

    COMPILED_ISLANDS_CACHE[] = compiled
    println("  Compiled $(length(compiled)) islands")
    return compiled
end

# =============================================================================
# Server
# =============================================================================

function start_server(host::String, port::Int)
    # Initialize with one empty cell
    if isempty(CELLS)
        cell = Cell("")
        CELLS[cell.id] = cell
        push!(CELL_ORDER, cell.id)
    end

    # Pre-compile islands (optional - can be lazy)
    compiled_islands = get_compiled_islands()

    server = HTTP.listen!(host, port) do http
        path = HTTP.URI(http.message.target).path

        if path == "/ws"
            try
                HTTP.WebSockets.upgrade(http) do ws
                    handle_websocket(ws)
                end
            catch e
                @error "WebSocket upgrade error" exception=e
            end

        # Serve Wasm files for islands
        elseif endswith(path, ".wasm")
            filename = basename(path)
            for (name, island) in compiled_islands
                if island.wasm_filename == filename
                    HTTP.setstatus(http, 200)
                    HTTP.setheader(http, "Content-Type" => "application/wasm")
                    HTTP.startwrite(http)
                    write(http, island.wasm_bytes)
                    return
                end
            end
            HTTP.setstatus(http, 404)
            HTTP.startwrite(http)
            write(http, "Wasm not found")

        elseif path == "/"
            HTTP.setstatus(http, 200)
            HTTP.setheader(http, "Content-Type" => "text/html; charset=utf-8")
            HTTP.startwrite(http)
            write(http, generate_page(compiled_islands))

        else
            HTTP.setstatus(http, 404)
            HTTP.startwrite(http)
            write(http, "Not Found")
        end
    end

    wait(server)
end

function generate_page(compiled_islands::Dict)
    # Get island HTML for toolbar
    island_html = ""
    for (name, island) in compiled_islands
        if name == :NotebookControlsIsland
            island_html = "<therapy-island data-component=\"notebookcontrolsisland\">$(island.html)</therapy-island>"
        end
    end

    # Build page using Therapy.jl components
    page = Layout(
        Div(:class => "flex-1 flex overflow-hidden",
            # Sidebar with file explorer
            Sidebar(),

            # Main content area
            Div(:class => "flex-1 flex flex-col overflow-hidden",
                # Cells container - populated via WebSocket
                Div(:id => "cells", :class => "flex-1 overflow-auto p-4"),

                # Terminal panel
                Terminal()
            )
        );
        island_html = island_html
    )

    html = render_page(page; title="Sessions.jl", head_extra=head_extra())

    # Only include hydration for islands actually in the page
    islands_in_page = [:NotebookControlsIsland]
    hydration = island_hydration_script(compiled_islands, islands_in_page)

    html = replace(html, "</body>" => client_script() * hydration * "</body>")
    return html
end

"""
Generate hydration script for specified islands.
"""
function island_hydration_script(compiled_islands::Dict, island_names::Vector{Symbol})
    scripts = String[]

    for name in island_names
        if haskey(compiled_islands, name)
            island = compiled_islands[name]
            push!(scripts, """
            // Island: $name
            $(island.js)
            """)
        end
    end

    isempty(scripts) && return ""
    return "<script>\n" * join(scripts, "\n") * "\n</script>"
end

# =============================================================================
# WebSocket Handler
# =============================================================================

function handle_websocket(ws)
    push!(WS_CLIENTS, ws)
    println("WebSocket client connected")

    try
        for msg in ws
            msg_str = msg isa String ? msg : String(msg)
            println("Received: $(first(msg_str, 100))")
            handle_message(ws, msg_str)
        end
    catch e
        if !(e isa HTTP.WebSockets.WebSocketError) && !(e isa EOFError)
            @error "WebSocket error" exception=(e, catch_backtrace())
        end
    finally
        delete!(WS_CLIENTS, ws)
        println("WebSocket client disconnected")
    end
end

# =============================================================================
# Message Handlers
# =============================================================================

const HANDLERS = Dict{String, Function}(
    "get_state" => (ws, body) -> begin
        send_cells_html(ws)
        send_files(ws, ".")
    end,

    "run_cell" => (ws, body) -> begin
        cell_id = UUID(body["cell_id"])
        code = get(body, "code", "")

        if haskey(CELLS, cell_id)
            cell = CELLS[cell_id]
            cell.code = code
            cell.status = RUNNING
            broadcast_cell_html(cell)

            execute_cell!(EXECUTOR[], cell)
            broadcast_cell_html(cell)
        end
    end,

    "add_cell" => (ws, body) -> begin
        cell = Cell("")
        CELLS[cell.id] = cell
        push!(CELL_ORDER, cell.id)
        broadcast_cells_html()
    end,

    "delete_cell" => (ws, body) -> begin
        cell_id = UUID(body["cell_id"])
        if haskey(CELLS, cell_id) && length(CELLS) > 1
            delete!(CELLS, cell_id)
            filter!(id -> id != cell_id, CELL_ORDER)
            broadcast_cells_html()
        end
    end,

    "run_all" => (ws, body) -> begin
        for id in CELL_ORDER
            if haskey(CELLS, id)
                cell = CELLS[id]
                if !isempty(strip(cell.code))
                    cell.status = RUNNING
                    broadcast_cell_html(cell)
                    execute_cell!(EXECUTOR[], cell)
                    broadcast_cell_html(cell)
                end
            end
        end
    end,

    "restart" => (ws, body) -> begin
        restart!(EXECUTOR[])
        for cell in values(CELLS)
            cell.status = IDLE
            cell.output = nothing
            cell.stdout = ""
            cell.stderr = ""
            cell.error_msg = ""
        end
        broadcast_cells_html()
    end,

    "list_files" => (ws, body) -> begin
        send_files(ws, get(body, "path", "."))
    end,

    "open_file" => (ws, body) -> begin
        path = body["path"]
        try
            content = read(path, String)
            send_msg(ws, "file_content", Dict("path" => path, "content" => content))
        catch e
            send_msg(ws, "error", Dict("message" => string(e)))
        end
    end,

    "terminal" => (ws, body) -> begin
        input = get(body, "input", "")
        result = execute(EXECUTOR[], input)
        output = result.success ?
            (result.stdout * (result.value !== nothing ? repr(result.value) : "")) :
            (result.stderr * "\n" * result.error_msg)
        send_msg(ws, "terminal_output", Dict("output" => output))
    end
)

function handle_message(ws, msg_str::String)
    msg = JSON3.read(msg_str, Dict)
    msg_type = get(msg, "type", "")
    body = get(msg, "body", Dict())

    handler = get(HANDLERS, msg_type, nothing)
    if handler !== nothing
        println("  Handling: $msg_type")
        handler(ws, body)
    else
        println("  Unknown type: $msg_type")
    end
end

# =============================================================================
# Send Messages
# =============================================================================

function send_msg(ws, type::String, body::Dict)
    msg = JSON3.write(Dict("type" => type, "body" => body))
    try
        send(ws, msg)
    catch
    end
end

function broadcast_msg(type::String, body::Dict)
    msg = JSON3.write(Dict("type" => type, "body" => body))
    for ws in WS_CLIENTS
        try
            send(ws, msg)
        catch
        end
    end
end

# =============================================================================
# Server-Side Cell Rendering (Therapy.jl)
# =============================================================================

function send_cells_html(ws)
    cells = [CELLS[id] for id in CELL_ORDER if haskey(CELLS, id)]
    html = render_to_string(CellsContainer(cells))
    send_msg(ws, "cells_html", Dict("html" => html, "cell_count" => length(cells)))
end

function broadcast_cells_html()
    cells = [CELLS[id] for id in CELL_ORDER if haskey(CELLS, id)]
    html = render_to_string(CellsContainer(cells))
    broadcast_msg("cells_html", Dict("html" => html, "cell_count" => length(cells)))
end

function broadcast_cell_html(cell::Cell)
    html = render_to_string(CellComponent(cell))
    broadcast_msg("cell_html", Dict(
        "cell_id" => string(cell.id),
        "html" => html,
        "status" => lowercase(string(cell.status))
    ))
end

# =============================================================================
# File Helpers (Server-rendered)
# =============================================================================

function send_files(ws, path::String)
    try
        entries = []
        for name in readdir(path)
            startswith(name, ".") && continue
            full = joinpath(path, name)
            push!(entries, Dict("name" => name, "path" => full, "is_directory" => isdir(full)))
        end
        sort!(entries, by = e -> (!e["is_directory"], lowercase(e["name"])))

        html = render_to_string(FileTreeComponent(path, entries))
        send_msg(ws, "files_html", Dict("path" => path, "html" => html))
    catch e
        send_msg(ws, "error", Dict("message" => string(e)))
    end
end

function FileTreeComponent(path::String, entries::Vector)
    Div(:id => "file-tree-content",
        if path != "."
            parent = dirname(path)
            parent = isempty(parent) ? "." : parent
            Div(:class => "file-item cursor-pointer px-2 py-1 hover:bg-gray-700",
                Symbol("data-path") => parent,
                Symbol("data-dir") => "1",
                "..")
        else
            nothing
        end,
        [FileEntryComponent(e) for e in entries]...
    )
end

function FileEntryComponent(entry::Dict)
    is_dir = entry["is_directory"]
    icon = is_dir ? "📁" : "📄"
    Div(:class => "file-item cursor-pointer px-2 py-1 hover:bg-gray-700 $(is_dir ? "directory" : "file")",
        Symbol("data-path") => entry["path"],
        Symbol("data-dir") => is_dir ? "1" : "0",
        "$icon $(entry["name"])")
end
