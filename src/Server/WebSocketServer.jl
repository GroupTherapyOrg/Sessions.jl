# =============================================================================
# WebSocket Server for Sessions.jl
# =============================================================================
#
# Following Pluto's approach:
# - Message format: { type: "...", body: {...} }
# - Handlers dictionary maps types to functions
# - Simple, direct communication

using Therapy

include("ClientBridge.jl")

# =============================================================================
# Global State
# =============================================================================

const CELLS = Dict{UUID, Cell}()
const CELL_ORDER = Vector{UUID}()
const EXECUTOR = Ref{Executor}(Executor())
const WS_CLIENTS = Set{Any}()

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
        elseif path == "/"
            HTTP.setstatus(http, 200)
            HTTP.setheader(http, "Content-Type" => "text/html; charset=utf-8")
            HTTP.startwrite(http)
            write(http, generate_page())
        else
            HTTP.setstatus(http, 404)
            HTTP.startwrite(http)
            write(http, "Not Found")
        end
    end

    wait(server)
end

function generate_page()
    page = Layout(
        Div(:class => "flex-1 flex overflow-hidden",
            Sidebar(),
            Div(:class => "flex-1 flex flex-col overflow-hidden",
                Div(:id => "cells", :class => "flex-1 overflow-auto p-4"),
                Terminal()
            )
        )
    )

    html = render_page(page; title="Sessions.jl", head_extra=head_extra())
    html = replace(html, "</body>" => websocket_bridge_script() * "</body>")
    return html
end

# =============================================================================
# WebSocket Handler (Pluto-style)
# =============================================================================

function handle_websocket(ws)
    push!(WS_CLIENTS, ws)
    println("WebSocket client connected")

    try
        # Pluto-style: iterate over WebSocket messages
        for msg in ws
            msg_str = msg isa String ? msg : String(msg)
            println("Received message: $(first(msg_str, 100))")
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
# Message Handlers (Pluto-style responses dict)
# =============================================================================

const HANDLERS = Dict{String, Function}(
    "get_state" => (ws, body) -> begin
        send_cells_state(ws)
        send_files(ws, ".")
    end,

    "run_cell" => (ws, body) -> begin
        cell_id = UUID(body["cell_id"])
        code = get(body, "code", "")

        if haskey(CELLS, cell_id)
            cell = CELLS[cell_id]
            cell.code = code
            cell.status = RUNNING
            broadcast_cell(cell)

            execute_cell!(EXECUTOR[], cell)
            broadcast_cell(cell)
        end
    end,

    "add_cell" => (ws, body) -> begin
        cell = Cell("")
        CELLS[cell.id] = cell
        push!(CELL_ORDER, cell.id)
        broadcast_cells_state()
    end,

    "delete_cell" => (ws, body) -> begin
        cell_id = UUID(body["cell_id"])
        if haskey(CELLS, cell_id) && length(CELLS) > 1
            delete!(CELLS, cell_id)
            filter!(id -> id != cell_id, CELL_ORDER)
            broadcast_cells_state()
        end
    end,

    "run_all" => (ws, body) -> begin
        for id in CELL_ORDER
            if haskey(CELLS, id)
                cell = CELLS[id]
                if !isempty(strip(cell.code))
                    cell.status = RUNNING
                    broadcast_cell(cell)
                    execute_cell!(EXECUTOR[], cell)
                    broadcast_cell(cell)
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
        broadcast_cells_state()
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
    println("Received: $(first(msg_str, 100))")

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
# Cell Helpers
# =============================================================================

function cell_to_dict(cell::Cell)
    Dict(
        "id" => string(cell.id),
        "code" => cell.code,
        "status" => Int(cell.status),
        "status_name" => string(cell.status),
        "output" => cell.output !== nothing ? repr(cell.output) : nothing,
        "stdout" => cell.stdout,
        "stderr" => cell.stderr,
        "error_msg" => cell.error_msg,
        "execution_count" => cell.execution_count
    )
end

function send_cells_state(ws)
    cells = [cell_to_dict(CELLS[id]) for id in CELL_ORDER if haskey(CELLS, id)]
    send_msg(ws, "cells_state", Dict("cells" => cells))
end

function broadcast_cells_state()
    cells = [cell_to_dict(CELLS[id]) for id in CELL_ORDER if haskey(CELLS, id)]
    broadcast_msg("cells_state", Dict("cells" => cells))
end

function broadcast_cell(cell::Cell)
    broadcast_msg("cell_update", Dict("cell" => cell_to_dict(cell)))
end

function send_files(ws, path::String)
    try
        entries = []
        for name in readdir(path)
            startswith(name, ".") && continue
            full = joinpath(path, name)
            push!(entries, Dict("name" => name, "path" => full, "is_directory" => isdir(full)))
        end
        sort!(entries, by = e -> (!e["is_directory"], lowercase(e["name"])))
        send_msg(ws, "files", Dict("path" => path, "entries" => entries))
    catch e
        send_msg(ws, "error", Dict("message" => string(e)))
    end
end
