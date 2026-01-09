# =============================================================================
# WebSocket Server for Sessions.jl
# Pure Therapy.jl approach: All UI rendered server-side, minimal client JS
# =============================================================================

using Therapy

# Global state
const CELLS = Dict{UUID, Cell}()
const EXECUTOR = Ref{Executor}(Executor())
const WS_CLIENTS = Set{Any}()

"""
    start_server(host::String, port::Int)

Start the HTTP + WebSocket server.
"""
function start_server(host::String, port::Int)
    # Initialize with one empty cell
    if isempty(CELLS)
        cell = Cell("")
        CELLS[cell.id] = cell
    end

    # Use stream-based handler for WebSocket support
    server = HTTP.listen!(host, port) do http
        path = HTTP.URI(http.message.target).path

        if path == "/ws"
            # WebSocket upgrade
            try
                HTTP.WebSockets.upgrade(http) do ws
                    handle_websocket(ws)
                end
            catch e
                @error "WebSocket error" exception=e
            end
        elseif path == "/"
            # Main page
            HTTP.setstatus(http, 200)
            HTTP.setheader(http, "Content-Type" => "text/html; charset=utf-8")
            HTTP.startwrite(http)
            write(http, generate_page())
        else
            # 404
            HTTP.setstatus(http, 404)
            HTTP.setheader(http, "Content-Type" => "text/plain")
            HTTP.startwrite(http)
            write(http, "Not Found")
        end
    end

    wait(server)
end

function handle_websocket(ws)
    push!(WS_CLIENTS, ws)
    println("WebSocket client connected")

    # Send initial state as pre-rendered HTML
    broadcast_cells_html()
    send_file_list(ws, ".")

    try
        for msg in ws
            handle_ws_message(ws, String(msg))
        end
    catch e
        if !(e isa HTTP.WebSockets.WebSocketError)
            @error "WebSocket error" exception=e
        end
    finally
        delete!(WS_CLIENTS, ws)
        println("WebSocket client disconnected")
    end
end

"""
Render all cells to HTML using Therapy.jl components.
"""
function render_cells_html()
    cells = sort(collect(values(CELLS)), by = c -> c.execution_count)

    # Build the cells using Therapy.jl's For and CellView
    cells_vnode = Div(:id => "cells-content",
        [render_cell_vnode(cell) for cell in cells]...
    )

    render_to_string(cells_vnode)
end

"""
Render a single cell to VNode using Therapy.jl.
"""
function render_cell_vnode(cell::Cell)
    status_str = string(cell.status)
    status_class = Dict(
        "IDLE" => "cell-idle",
        "RUNNING" => "cell-running",
        "COMPLETED" => "cell-completed",
        "ERRORED" => "cell-errored"
    )[status_str]

    # Status icon
    status_icon = if cell.status == RUNNING
        Div(:class => "w-4 h-4 border-2 border-gray-600 border-t-yellow-500 rounded-full animate-spin")
    elseif cell.status == COMPLETED
        Span(:class => "text-green-500", "✓")
    elseif cell.status == ERRORED
        Span(:class => "text-red-500", "✗")
    else
        Span(:class => "text-gray-600", "○")
    end

    # Output sections
    output_children = Any[]

    if !isempty(cell.stdout)
        push!(output_children,
            Div(:class => "bg-gray-800 rounded p-2 text-sm text-gray-300 whitespace-pre-wrap",
                cell.stdout))
    end

    if cell.status == COMPLETED && cell.output !== nothing
        output_str = repr(cell.output)
        if output_str != "nothing"
            push!(output_children,
                Div(:class => "bg-gray-800 rounded p-2 text-sm text-blue-400 font-mono",
                    output_str))
        end
    end

    if cell.status == ERRORED && !isempty(cell.error_msg)
        push!(output_children,
            Div(:class => "bg-red-900 bg-opacity-30 rounded p-2 text-sm text-red-400 font-mono whitespace-pre-wrap",
                cell.error_msg))
    end

    cell_id = string(cell.id)

    Div(:class => "cell bg-gray-850 rounded-lg overflow-hidden $status_class",
        :data_cell_id => cell_id,

        # Header
        Div(:class => "flex items-center h-8 px-2 bg-gray-800",
            Div(:class => "w-6 h-6 flex items-center justify-center", status_icon),
            Span(:class => "text-xs text-gray-500 ml-2", "[$(cell.execution_count)]"),
            Div(:class => "flex-1"),
            Button(:class => "cell-run px-2 py-1 text-xs text-gray-500 hover:text-white hover:bg-gray-700 rounded",
                   :data_cell_id => cell_id, "Run"),
            Button(:class => "cell-delete px-2 py-1 text-xs text-gray-500 hover:text-red-400 hover:bg-gray-700 rounded ml-1",
                   :data_cell_id => cell_id, "×")
        ),

        # Code area
        Div(:class => "p-3",
            Textarea(:class => "cell-code w-full bg-gray-800 text-gray-200 p-3 rounded font-mono text-sm outline-none resize-none",
                     :rows => "3",
                     :data_cell_id => cell_id,
                     :placeholder => "# Enter Julia code...",
                     cell.code)
        ),

        # Output
        if !isempty(output_children)
            Div(:class => "px-3 pb-3 space-y-2", output_children...)
        else
            nothing
        end
    )
end

"""
Render file tree to HTML using Therapy.jl.
"""
function render_file_tree_html(path::String, entries::Vector)
    children = Any[]

    # Parent directory link
    if path != "."
        parent = dirname(path)
        if isempty(parent)
            parent = "."
        end
        push!(children,
            Div(:class => "cursor-pointer hover:bg-gray-700 px-2 py-1 rounded file-item",
                :data_path => parent, :data_action => "list", ".."))
    end

    # Entries
    for entry in entries
        icon = entry["is_directory"] ? "📁" : "📄"
        action = entry["is_directory"] ? "list" : "open"
        push!(children,
            Div(:class => "cursor-pointer hover:bg-gray-700 px-2 py-1 rounded flex items-center file-item",
                :data_path => entry["path"], :data_action => action,
                Span(:class => "mr-2", icon),
                entry["name"]))
    end

    render_to_string(Div(:id => "file-tree-content", children...))
end

"""
Broadcast pre-rendered cells HTML to all clients.
"""
function broadcast_cells_html()
    html = render_cells_html()
    msg = JSON3.write(Dict("type" => "cells", "html" => html))

    for ws in WS_CLIENTS
        try
            send(ws, msg)
        catch
        end
    end
end

function handle_ws_message(ws, msg::String)
    data = JSON3.read(msg, Dict)
    action = get(data, "action", "")

    if action == "execute"
        cell_id = UUID(data["cell_id"])
        code = get(data, "code", "")

        if haskey(CELLS, cell_id)
            cell = CELLS[cell_id]
            cell.code = code
            execute_cell!(EXECUTOR[], cell)
            broadcast_cells_html()
        end

    elseif action == "update_code"
        cell_id = UUID(data["cell_id"])
        code = get(data, "code", "")
        if haskey(CELLS, cell_id)
            CELLS[cell_id].code = code
        end

    elseif action == "add_cell"
        cell = Cell("")
        CELLS[cell.id] = cell
        broadcast_cells_html()

    elseif action == "delete_cell"
        cell_id = UUID(data["cell_id"])
        if haskey(CELLS, cell_id) && length(CELLS) > 1
            delete!(CELLS, cell_id)
            broadcast_cells_html()
        end

    elseif action == "restart"
        restart!(EXECUTOR[])
        for cell in values(CELLS)
            cell.status = IDLE
            cell.output = nothing
            cell.stdout = ""
            cell.stderr = ""
            cell.error_msg = ""
        end
        broadcast_cells_html()

    elseif action == "run_all"
        cells = sort(collect(values(CELLS)), by = c -> c.execution_count)
        for cell in cells
            if !isempty(strip(cell.code))
                execute_cell!(EXECUTOR[], cell)
            end
        end
        broadcast_cells_html()

    elseif action == "terminal"
        input = get(data, "input", "")
        result = execute(EXECUTOR[], input)
        output = result.success ?
            (result.stdout * (result.value !== nothing ? repr(result.value) : "")) :
            (result.stderr * "\n" * result.error_msg)
        send(ws, JSON3.write(Dict("type" => "terminal", "output" => output)))

    elseif action == "files"
        path = get(data, "path", ".")
        send_file_list(ws, path)

    elseif action == "open_file"
        path = data["path"]
        try
            content = read(path, String)
            send(ws, JSON3.write(Dict("type" => "file", "path" => path, "content" => content)))
        catch e
            send(ws, JSON3.write(Dict("type" => "error", "message" => string(e))))
        end
    end
end

function send_file_list(ws, path::String)
    try
        entries = []
        for name in readdir(path)
            startswith(name, ".") && continue
            full_path = joinpath(path, name)
            push!(entries, Dict(
                "name" => name,
                "path" => full_path,
                "is_directory" => isdir(full_path)
            ))
        end
        sort!(entries, by = e -> (!e["is_directory"], lowercase(e["name"])))

        html = render_file_tree_html(path, entries)
        send(ws, JSON3.write(Dict("type" => "files", "html" => html)))
    catch e
        send(ws, JSON3.write(Dict("type" => "error", "message" => string(e))))
    end
end

"""
Generate the page using Therapy.jl's render_page with our components.
"""
function generate_page()
    head = """
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        .cell-running { border-left: 4px solid #eab308; }
        .cell-completed { border-left: 4px solid #22c55e; }
        .cell-errored { border-left: 4px solid #ef4444; }
        .cell-idle { border-left: 4px solid transparent; }
        @keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
        .animate-spin { animation: spin 1s linear infinite; }
    </style>
    """

    # Build the main page using Therapy.jl components
    page = Layout(
        Div(:class => "flex-1 flex overflow-hidden",
            Sidebar(),
            Div(:class => "flex-1 flex flex-col overflow-hidden",
                Div(:id => "cells", :class => "flex-1 overflow-auto p-4 space-y-4"),
                Terminal()
            )
        )
    )

    html = render_page(page; title="Sessions.jl", head_extra=head)

    # Inject minimal WebSocket client
    html = replace(html, "</body>" => ws_client_script() * "</body>")
    return html
end

"""
Minimal WebSocket client - just transport, no rendering logic.
All HTML comes pre-rendered from the server via Therapy.jl.
"""
function ws_client_script()
    """
    <script>
    (function(){
        var ws, currentPath = '.';

        function connect() {
            ws = new WebSocket('ws://' + location.host + '/ws');
            ws.onmessage = function(e) {
                var d = JSON.parse(e.data);
                if (d.type === 'cells') {
                    document.getElementById('cells').innerHTML = d.html;
                    bindCells();
                } else if (d.type === 'files') {
                    document.getElementById('file-tree').innerHTML = d.html;
                    bindFiles();
                } else if (d.type === 'terminal') {
                    var out = document.getElementById('terminal-output');
                    out.textContent += d.output + '\\n';
                    out.scrollTop = out.scrollHeight;
                } else if (d.type === 'file') {
                    ws.send(JSON.stringify({action:'add_cell'}));
                    setTimeout(function(){
                        var ta = document.querySelector('.cell-code:last-of-type');
                        if(ta) { ta.value = d.content; ws.send(JSON.stringify({action:'update_code',cell_id:ta.dataset.cellId,code:d.content})); }
                    }, 100);
                }
            };
            ws.onclose = function() { setTimeout(connect, 2000); };
        }

        function bindCells() {
            document.querySelectorAll('.cell-run').forEach(function(b){
                b.onclick = function(){
                    var id = this.dataset.cellId;
                    var ta = document.querySelector('.cell-code[data-cell-id="'+id+'"]');
                    if(ta) ws.send(JSON.stringify({action:'execute',cell_id:id,code:ta.value}));
                };
            });
            document.querySelectorAll('.cell-delete').forEach(function(b){
                b.onclick = function(){ ws.send(JSON.stringify({action:'delete_cell',cell_id:this.dataset.cellId})); };
            });
            document.querySelectorAll('.cell-code').forEach(function(ta){
                ta.onkeydown = function(e){
                    if(e.key==='Enter' && e.shiftKey) {
                        e.preventDefault();
                        ws.send(JSON.stringify({action:'execute',cell_id:this.dataset.cellId,code:this.value}));
                    }
                };
            });
        }

        function bindFiles() {
            document.querySelectorAll('.file-item').forEach(function(el){
                el.onclick = function(){
                    var action = this.dataset.action === 'list' ? 'files' : 'open_file';
                    ws.send(JSON.stringify({action:action,path:this.dataset.path}));
                };
            });
        }

        document.addEventListener('DOMContentLoaded', function(){
            document.getElementById('btn-run-all').onclick = function(){ ws.send(JSON.stringify({action:'run_all'})); };
            document.getElementById('btn-restart').onclick = function(){ ws.send(JSON.stringify({action:'restart'})); };
            document.getElementById('btn-add-cell').onclick = function(){ ws.send(JSON.stringify({action:'add_cell'})); };
            document.getElementById('btn-refresh-files').onclick = function(){ ws.send(JSON.stringify({action:'files',path:currentPath})); };
            document.getElementById('btn-toggle-terminal').onclick = function(){ document.getElementById('terminal-panel').classList.toggle('hidden'); };
            document.getElementById('terminal-input').onkeydown = function(e){
                if(e.key==='Enter' && this.value.trim()) {
                    var out = document.getElementById('terminal-output');
                    out.textContent += 'julia> ' + this.value + '\\n';
                    ws.send(JSON.stringify({action:'terminal',input:this.value}));
                    this.value = '';
                }
            };
            connect();
        });
    })();
    </script>
    """
end
