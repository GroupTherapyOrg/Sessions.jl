# =============================================================================
# WebSocket Server
# =============================================================================

# Global state
const CELLS = Dict{UUID, Cell}()
const EXECUTOR = Ref{Executor}(Executor())
const WS_CLIENTS = Set{HTTP.WebSockets.WebSocket}()

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

    router = HTTP.Router()

    # Main page
    HTTP.register!(router, "GET", "/", (req) -> serve_app())

    # WebSocket endpoint
    HTTP.register!(router, "GET", "/ws", handle_ws_upgrade)

    # Static files
    HTTP.register!(router, "GET", "/static/*", serve_static)

    # Filesystem API
    HTTP.register!(router, "GET", "/api/files", (req) -> serve_files(req))
    HTTP.register!(router, "GET", "/api/files/*", (req) -> serve_file_content(req))
    HTTP.register!(router, "POST", "/api/files/*", (req) -> save_file_content(req))

    println("Server running at http://$host:$port")
    println("Press Ctrl+C to stop")

    HTTP.serve(router, host, port)
end

"""
Serve the main app page.
"""
function serve_app()
    html = generate_app_html()
    HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], html)
end

"""
Handle WebSocket upgrade.
"""
function handle_ws_upgrade(req::HTTP.Request)
    HTTP.WebSockets.upgrade(req) do ws
        push!(WS_CLIENTS, ws)
        println("WebSocket client connected")

        # Send initial state
        send_state(ws)

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
end

"""
Send current state to a client.
"""
function send_state(ws)
    cells = [Dict(cell) for cell in values(CELLS)]
    sort!(cells, by = c -> c["execution_count"])

    msg = JSON3.write(Dict(
        "type" => "state",
        "cells" => cells
    ))
    send(ws, msg)
end

"""
Broadcast to all connected clients.
"""
function broadcast_state()
    cells = [Dict(cell) for cell in values(CELLS)]
    sort!(cells, by = c -> c["execution_count"])

    msg = JSON3.write(Dict(
        "type" => "state",
        "cells" => cells
    ))

    for ws in WS_CLIENTS
        try
            send(ws, msg)
        catch
        end
    end
end

"""
Handle incoming WebSocket message.
"""
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
            broadcast_state()
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
        broadcast_state()

    elseif action == "delete_cell"
        cell_id = UUID(data["cell_id"])
        if haskey(CELLS, cell_id) && length(CELLS) > 1
            delete!(CELLS, cell_id)
            broadcast_state()
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
        broadcast_state()

    elseif action == "run_all"
        cells = collect(values(CELLS))
        sort!(cells, by = c -> c.execution_count)
        for cell in cells
            if !isempty(strip(cell.code))
                execute_cell!(EXECUTOR[], cell)
            end
        end
        broadcast_state()

    elseif action == "terminal_input"
        # Handle terminal input
        input = get(data, "input", "")
        handle_terminal_input(ws, input)

    elseif action == "list_files"
        path = get(data, "path", ".")
        send_file_list(ws, path)

    elseif action == "read_file"
        path = data["path"]
        send_file_content(ws, path)

    elseif action == "write_file"
        path = data["path"]
        content = data["content"]
        write_file(ws, path, content)
    end
end

"""
Handle terminal input and send output.
"""
function handle_terminal_input(ws, input::String)
    # Simple REPL-like execution
    result = execute(EXECUTOR[], input)

    output = if result.success
        output_str = result.stdout
        if result.value !== nothing && result.value !== Main.nothing
            output_str *= "\n" * repr(result.value)
        end
        output_str
    else
        result.stderr * "\n" * result.error_msg
    end

    msg = JSON3.write(Dict(
        "type" => "terminal_output",
        "output" => output
    ))
    send(ws, msg)
end

"""
Send file list for a directory.
"""
function send_file_list(ws, path::String)
    try
        entries = []
        for name in readdir(path)
            full_path = joinpath(path, name)
            push!(entries, Dict(
                "name" => name,
                "path" => full_path,
                "is_directory" => isdir(full_path)
            ))
        end
        sort!(entries, by = e -> (!e["is_directory"], lowercase(e["name"])))

        msg = JSON3.write(Dict(
            "type" => "file_list",
            "path" => path,
            "entries" => entries
        ))
        send(ws, msg)
    catch e
        send(ws, JSON3.write(Dict("type" => "error", "message" => string(e))))
    end
end

"""
Send file content.
"""
function send_file_content(ws, path::String)
    try
        content = read(path, String)
        msg = JSON3.write(Dict(
            "type" => "file_content",
            "path" => path,
            "content" => content
        ))
        send(ws, msg)
    catch e
        send(ws, JSON3.write(Dict("type" => "error", "message" => string(e))))
    end
end

"""
Write file content.
"""
function write_file(ws, path::String, content::String)
    try
        write(path, content)
        send(ws, JSON3.write(Dict("type" => "file_saved", "path" => path)))
    catch e
        send(ws, JSON3.write(Dict("type" => "error", "message" => string(e))))
    end
end

"""
Serve static files.
"""
function serve_static(req::HTTP.Request)
    path = HTTP.URI(req.target).path
    path = replace(path, "/static/" => "")

    # Security check
    if contains(path, "..")
        return HTTP.Response(403, "Forbidden")
    end

    static_dir = joinpath(@__DIR__, "..", "..", "static")
    file_path = joinpath(static_dir, path)

    if isfile(file_path)
        content = read(file_path)
        mime = get_mime_type(file_path)
        return HTTP.Response(200, ["Content-Type" => mime], content)
    end

    HTTP.Response(404, "Not Found")
end

"""
Serve files API.
"""
function serve_files(req::HTTP.Request)
    path = get(HTTP.queryparams(HTTP.URI(req.target)), "path", ".")
    entries = []

    try
        for name in readdir(path)
            full_path = joinpath(path, name)
            push!(entries, Dict(
                "name" => name,
                "path" => full_path,
                "is_directory" => isdir(full_path)
            ))
        end
        sort!(entries, by = e -> (!e["is_directory"], lowercase(e["name"])))
    catch e
        return HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end

    HTTP.Response(200, ["Content-Type" => "application/json"], JSON3.write(entries))
end

"""
Serve file content API.
"""
function serve_file_content(req::HTTP.Request)
    path = HTTP.URI(req.target).path
    path = replace(path, "/api/files/" => "")
    path = HTTP.URIs.unescapeuri(path)

    if !isfile(path)
        return HTTP.Response(404, "File not found")
    end

    content = read(path, String)
    HTTP.Response(200, ["Content-Type" => "text/plain; charset=utf-8"], content)
end

"""
Save file content API.
"""
function save_file_content(req::HTTP.Request)
    path = HTTP.URI(req.target).path
    path = replace(path, "/api/files/" => "")
    path = HTTP.URIs.unescapeuri(path)

    try
        write(path, String(req.body))
        HTTP.Response(200, JSON3.write(Dict("status" => "ok")))
    catch e
        HTTP.Response(500, JSON3.write(Dict("error" => string(e))))
    end
end

"""
Get MIME type for file.
"""
function get_mime_type(path::String)
    ext = lowercase(splitext(path)[2])
    types = Dict(
        ".html" => "text/html",
        ".css" => "text/css",
        ".js" => "application/javascript",
        ".json" => "application/json",
        ".png" => "image/png",
        ".jpg" => "image/jpeg",
        ".svg" => "image/svg+xml",
        ".wasm" => "application/wasm"
    )
    get(types, ext, "application/octet-stream")
end

"""
Generate the main app HTML.
"""
function generate_app_html()
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Sessions.jl</title>
        <script src="https://cdn.tailwindcss.com"></script>
        <style>
            .cell-running { border-left: 4px solid #eab308; }
            .cell-completed { border-left: 4px solid #22c55e; }
            .cell-errored { border-left: 4px solid #ef4444; }
            .cell-idle { border-left: 4px solid transparent; }
            .spinner { animation: spin 1s linear infinite; }
            @keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
            .terminal { font-family: 'SF Mono', 'Monaco', 'Menlo', monospace; }
            .code-editor { font-family: 'SF Mono', 'Monaco', 'Menlo', monospace; }
            .file-tree { font-size: 14px; }
        </style>
    </head>
    <body class="bg-gray-900 text-gray-200">
        <div id="app" class="h-screen flex flex-col">
            <!-- Top Bar -->
            <div class="h-10 bg-gray-800 border-b border-gray-700 flex items-center px-4">
                <span class="font-bold text-lg">Sessions.jl</span>
                <div class="flex-1"></div>
                <button onclick="runAll()" class="px-3 py-1 bg-green-600 hover:bg-green-500 rounded text-sm mr-2">Run All</button>
                <button onclick="restartKernel()" class="px-3 py-1 bg-gray-700 hover:bg-gray-600 rounded text-sm mr-2">Restart</button>
                <button onclick="addCell()" class="px-3 py-1 bg-blue-600 hover:bg-blue-500 rounded text-sm">+ Cell</button>
            </div>

            <!-- Main Content -->
            <div class="flex-1 flex overflow-hidden">
                <!-- Sidebar -->
                <div id="sidebar" class="w-64 bg-gray-800 border-r border-gray-700 flex flex-col">
                    <div class="p-2 border-b border-gray-700 flex items-center justify-between">
                        <span class="text-xs text-gray-500 uppercase">Explorer</span>
                        <button onclick="refreshFiles()" class="text-gray-500 hover:text-white text-sm">↻</button>
                    </div>
                    <div id="file-tree" class="flex-1 overflow-auto p-2 file-tree"></div>
                </div>

                <!-- Editor Area -->
                <div class="flex-1 flex flex-col overflow-hidden">
                    <!-- Notebook -->
                    <div id="cells" class="flex-1 overflow-auto p-4 space-y-4"></div>

                    <!-- Terminal -->
                    <div id="terminal-panel" class="h-48 bg-gray-800 border-t border-gray-700 flex flex-col">
                        <div class="h-8 bg-gray-900 border-b border-gray-700 flex items-center px-3 text-sm">
                            <span class="text-gray-400">Terminal</span>
                            <div class="flex-1"></div>
                            <button onclick="toggleTerminal()" class="text-gray-500 hover:text-white">×</button>
                        </div>
                        <div id="terminal-output" class="flex-1 overflow-auto p-2 terminal text-sm text-green-400 bg-gray-900"></div>
                        <div class="flex items-center px-2 py-1 bg-gray-900 border-t border-gray-700">
                            <span class="text-blue-400 mr-2 terminal">julia&gt;</span>
                            <input type="text" id="terminal-input"
                                class="flex-1 bg-transparent outline-none terminal text-green-400"
                                placeholder="Enter command..."
                                onkeydown="handleTerminalKey(event)">
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <script>
        // WebSocket connection
        let ws;
        let cells = [];
        let currentPath = '.';

        function connect() {
            ws = new WebSocket('ws://' + window.location.host + '/ws');

            ws.onopen = () => {
                console.log('Connected');
                listFiles('.');
            };

            ws.onmessage = (event) => {
                const data = JSON.parse(event.data);
                handleMessage(data);
            };

            ws.onclose = () => {
                console.log('Disconnected, reconnecting...');
                setTimeout(connect, 1000);
            };
        }

        function handleMessage(data) {
            if (data.type === 'state') {
                cells = data.cells;
                renderCells();
            } else if (data.type === 'terminal_output') {
                appendTerminalOutput(data.output);
            } else if (data.type === 'file_list') {
                renderFileTree(data.path, data.entries);
            } else if (data.type === 'file_content') {
                showFileContent(data.path, data.content);
            }
        }

        function renderCells() {
            const container = document.getElementById('cells');
            container.innerHTML = cells.map(cell => renderCell(cell)).join('');
        }

        function renderCell(cell) {
            const statusClass = {
                'IDLE': 'cell-idle',
                'RUNNING': 'cell-running',
                'COMPLETED': 'cell-completed',
                'ERRORED': 'cell-errored'
            }[cell.status] || 'cell-idle';

            const statusIcon = cell.status === 'RUNNING'
                ? '<div class="w-4 h-4 border-2 border-gray-600 border-t-yellow-500 rounded-full spinner"></div>'
                : (cell.status === 'COMPLETED' ? '<span class="text-green-500">✓</span>' :
                   (cell.status === 'ERRORED' ? '<span class="text-red-500">✗</span>' : '<span class="text-gray-600">○</span>'));

            let output = '';
            if (cell.stdout) {
                output += '<div class="bg-gray-800 rounded p-2 text-sm text-gray-300 whitespace-pre-wrap">' + escapeHtml(cell.stdout) + '</div>';
            }
            if (cell.status === 'COMPLETED' && cell.output && cell.output !== 'nothing') {
                output += '<div class="bg-gray-800 rounded p-2 text-sm text-blue-400 font-mono">' + escapeHtml(cell.output) + '</div>';
            }
            if (cell.status === 'ERRORED') {
                output += '<div class="bg-red-900 bg-opacity-30 rounded p-2 text-sm text-red-400 font-mono">' + escapeHtml(cell.error_msg) + '</div>';
            }

            return '<div class="cell bg-gray-850 rounded-lg overflow-hidden ' + statusClass + '">' +
                '<div class="flex items-center h-8 px-2 bg-gray-800">' +
                    '<div class="w-6 h-6 flex items-center justify-center">' + statusIcon + '</div>' +
                    '<span class="text-xs text-gray-500 ml-2">[' + cell.execution_count + ']</span>' +
                    '<div class="flex-1"></div>' +
                    '<button onclick="runCell(\\'' + cell.id + '\\')" class="px-2 py-1 text-xs text-gray-500 hover:text-white hover:bg-gray-700 rounded">Run</button>' +
                    '<button onclick="deleteCell(\\'' + cell.id + '\\')" class="px-2 py-1 text-xs text-gray-500 hover:text-red-400 hover:bg-gray-700 rounded ml-1">×</button>' +
                '</div>' +
                '<div class="p-3">' +
                    '<textarea id="code-' + cell.id + '" class="w-full bg-gray-800 text-gray-200 p-3 rounded code-editor text-sm outline-none resize-none" ' +
                        'rows="3" placeholder="# Enter Julia code..." ' +
                        'onkeydown="handleCodeKey(event, \\'' + cell.id + '\\')" ' +
                        'oninput="updateCode(\\'' + cell.id + '\\')">' + escapeHtml(cell.code) + '</textarea>' +
                '</div>' +
                (output ? '<div class="px-3 pb-3 space-y-2">' + output + '</div>' : '') +
            '</div>';
        }

        function escapeHtml(text) {
            if (!text) return '';
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        function runCell(id) {
            const textarea = document.getElementById('code-' + id);
            ws.send(JSON.stringify({ action: 'execute', cell_id: id, code: textarea.value }));
        }

        function updateCode(id) {
            const textarea = document.getElementById('code-' + id);
            ws.send(JSON.stringify({ action: 'update_code', cell_id: id, code: textarea.value }));
        }

        function addCell() {
            ws.send(JSON.stringify({ action: 'add_cell' }));
        }

        function deleteCell(id) {
            if (cells.length > 1) {
                ws.send(JSON.stringify({ action: 'delete_cell', cell_id: id }));
            }
        }

        function runAll() {
            ws.send(JSON.stringify({ action: 'run_all' }));
        }

        function restartKernel() {
            ws.send(JSON.stringify({ action: 'restart' }));
        }

        function handleCodeKey(event, id) {
            if (event.key === 'Enter' && event.shiftKey) {
                event.preventDefault();
                runCell(id);
            }
        }

        // Terminal
        function handleTerminalKey(event) {
            if (event.key === 'Enter') {
                const input = document.getElementById('terminal-input');
                const cmd = input.value;
                if (cmd.trim()) {
                    appendTerminalOutput('julia> ' + cmd);
                    ws.send(JSON.stringify({ action: 'terminal_input', input: cmd }));
                    input.value = '';
                }
            }
        }

        function appendTerminalOutput(text) {
            const output = document.getElementById('terminal-output');
            output.innerHTML += escapeHtml(text) + '\\n';
            output.scrollTop = output.scrollHeight;
        }

        function toggleTerminal() {
            const panel = document.getElementById('terminal-panel');
            panel.classList.toggle('hidden');
        }

        // File Explorer
        function listFiles(path) {
            currentPath = path;
            ws.send(JSON.stringify({ action: 'list_files', path: path }));
        }

        function refreshFiles() {
            listFiles(currentPath);
        }

        function renderFileTree(path, entries) {
            const container = document.getElementById('file-tree');

            let html = '';
            if (path !== '.') {
                const parent = path.split('/').slice(0, -1).join('/') || '.';
                html += '<div class="cursor-pointer hover:bg-gray-700 px-2 py-1 rounded" onclick="listFiles(\\'' + parent + '\\')">..</div>';
            }

            entries.forEach(entry => {
                const icon = entry.is_directory ? '📁' : '📄';
                const onClick = entry.is_directory
                    ? 'listFiles(\\'' + entry.path.replace(/'/g, "\\\\'") + '\\')'
                    : 'openFile(\\'' + entry.path.replace(/'/g, "\\\\'") + '\\')';
                html += '<div class="cursor-pointer hover:bg-gray-700 px-2 py-1 rounded flex items-center" onclick="' + onClick + '">' +
                    '<span class="mr-2">' + icon + '</span>' + escapeHtml(entry.name) +
                '</div>';
            });

            container.innerHTML = html;
        }

        function openFile(path) {
            ws.send(JSON.stringify({ action: 'read_file', path: path }));
        }

        function showFileContent(path, content) {
            // For now, create a new cell with the file content
            const ext = path.split('.').pop();
            if (ext === 'jl') {
                addCell();
                setTimeout(() => {
                    const lastCell = cells[cells.length - 1];
                    if (lastCell) {
                        ws.send(JSON.stringify({ action: 'update_code', cell_id: lastCell.id, code: content }));
                    }
                }, 100);
            } else {
                alert('File: ' + path + '\\n\\nContent preview not yet implemented for non-.jl files');
            }
        }

        // Initialize
        connect();
        </script>
    </body>
    </html>
    """
end
