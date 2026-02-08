# App.jl - Sessions.jl HTTP Server
#
# Sessions.jl uses Therapy.jl for ALL real-time infrastructure:
#
# ═══════════════════════════════════════════════════════════════════════════════
# THERAPY.JL WEBSOCKET ARCHITECTURE (Leptos.rs-inspired)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Therapy.jl provides a Leptos-style reactive WebSocket system:
#
# 1. SERVER SIGNALS (like Leptos leptos_server_signal)
#    - Server-controlled, read-only on client
#    - Updates broadcast as JSON patches (RFC 6902) for efficiency
#    - Client: TherapyWS.subscribe("signal_name")
#    - Server: set_server_signal!(signal, value)
#    - DOM: <span data-server-signal="visitors">0</span>
#    - Event: therapy:signal:visitors
#
# 2. BIDIRECTIONAL SIGNALS (like Leptos leptos_ws)
#    - Both server AND client can modify
#    - Client sends patch → Server validates → broadcasts to OTHER clients
#    - Optimistic updates on client
#    - Server: create_bidirectional_signal("shared_doc", "")
#    - DOM: <textarea data-bidirectional-signal="shared_doc">
#    - JS: TherapyWS.setBidirectional("shared_doc", newValue)
#
# 3. CHANNELS (like Leptos channel signals)
#    - Discrete messages (events), NOT continuous state
#    - Perfect for chat, notifications, game events
#    - Server: on_channel_message("chat") do conn, data ... end
#    - Server: broadcast_channel!("chat", message)
#    - Client: TherapyWS.sendMessage("chat", {text: "Hello"})
#    - Event: therapy:channel:chat
#
# 4. CONNECTION LIFECYCLE
#    - on_ws_connect(fn) / on_ws_disconnect(fn) callbacks
#    - Auto-reconnect with exponential backoff
#    - Graceful degradation for static sites (GitHub Pages)
#
# ═══════════════════════════════════════════════════════════════════════════════
# HOW SESSIONS.JL USES THIS
# ═══════════════════════════════════════════════════════════════════════════════
#
# Sessions.jl uses Therapy.jl's WebSocket system for:
#
# - cell_states signal: Broadcasts cell execution state (RUNNING/IDLE/ERROR)
# - cell_outputs signal: Broadcasts cell outputs when execution completes
# - execute channel: Receives cell execution requests from client
# - add_cell/delete_cell channels: Cell management operations
#
# The client JavaScript (in Layout.jl) listens to these:
#   window.addEventListener('therapy:signal:cell_states', ...)
#   window.addEventListener('therapy:signal:cell_outputs', ...)
#   TherapyWS.sendMessage('execute', {cell_id, code})
#
# ═══════════════════════════════════════════════════════════════════════════════

using HTTP

# Module-level CSS storage (populated by serve()/dev(), served at /styles.css)
const _CSS_BYTES = Ref(UInt8[])

# HTTP is needed for the server. Therapy.jl provides:
# - handle_websocket(stream) - WebSocket upgrade handling
# - websocket_client_script() - Client JS for WebSocket
# - Server signals, channels, and all real-time features
#
# We only import HTTP to handle the HTTP layer. Therapy.jl handles WebSocket.

"""
    get_active_notebook(; notebook_id=nothing)

Get the active notebook. Priority:
1. Explicit notebook_id (from URL query param)
2. First notebook in NOTEBOOKS
3. Create a default welcome notebook

Returns a Notebook instance.
"""
function get_active_notebook(; notebook_id::Union{UUID, Nothing}=nothing)
    # 1. Explicit notebook_id
    if notebook_id !== nothing && haskey(NOTEBOOKS, notebook_id)
        return NOTEBOOKS[notebook_id]
    end

    # 2. First available notebook
    if !isempty(NOTEBOOKS)
        return first(values(NOTEBOOKS))
    end

    # 3. Create default
    nb = Notebook()
    add_cell!(nb; code="# Welcome to Sessions.jl\n# A reactive Julia notebook powered by Therapy.jl")
    add_cell!(nb; code="1 + 1")
    add_cell!(nb; code="x = 42")
    add_cell!(nb; code="x * 2")
    NOTEBOOKS[nb.id] = nb
    register_all_cell_signals!(nb)
    return nb
end

"""
Render the main notebook content (cells + header).
Returns a Therapy.jl component (no Layout wrapper).
"""
function render_notebook_content(notebook::Notebook)
    cells = cells_in_order(notebook)

    # Notebook content (without sidebar — Layout handles that)
    Div(:class => "space-y-8",
        # Notebook header
        Div(:class => "mb-8 pb-6 border-b border-warm-200/30 dark:border-[#252422]/30",
            H2(:class => "text-2xl font-serif font-medium text-warm-700 dark:text-warm-200 tracking-wide",
                notebook.path === nothing ? "Untitled Notebook" : basename(notebook.path)
            ),
            P(:class => "text-xs text-warm-400 dark:text-warm-500 mt-2 tracking-wider uppercase",
                "$(length(cells)) cells"
            )
        ),

        # Search bar (hidden, toggled by Ctrl+F)
        IDESearchBar(),

        # Cells (IDE design: output above, code card below)
        IDECellsView(cells),

        # Command palette (Ctrl+P dialog)
        IDECommandPalette(),

        # Set notebook ID for client
        Script("setNotebookId('$(notebook.id)');")
    )
end

"""
Build the sidebar content for the IDE layout.
Uses IDESidebar from IDE/Sidebar.jl (SESSIONS-3401).
"""
function render_sidebar_content(notebook::Notebook)
    workspace = pwd()
    file_entries = list_directory(workspace)
    nb_path = notebook.path !== nothing ? notebook.path : ""

    IDESidebar(
        entries=file_entries,
        current_path=workspace,
        current_notebook_path=nb_path
    )
end

"""
Build the tab bar from currently open notebooks.
"""
function render_tabs(active_notebook::Notebook)
    if isempty(NOTEBOOKS)
        return IDEEmptyTabs()
    end

    notebooks_info = [
        Dict{String,Any}(
            "id" => nb.id,
            "title" => nb.path !== nothing ? basename(nb.path) : "Untitled",
            "modified" => false
        )
        for nb in values(NOTEBOOKS)
    ]

    IDENotebookTabs(notebooks_info;
        active_id=active_notebook.id,
        is_running=false
    )
end

"""
Build the status bar with current notebook context.
"""
function render_statusbar(notebook::Notebook)
    nb_path = notebook.path !== nothing ? notebook.path : ""

    IDEStatusBar(
        kernel_state="idle",
        notebook_path=nb_path
    )
end

"""
Render full notebook page with IDE Layout.

# Arguments
- `notebook_id::Union{UUID, Nothing}`: Specific notebook to display (from URL query param).
  If nothing, displays the first available notebook.
"""
function render_notebook_page(; notebook_id::Union{UUID, Nothing}=nothing)
    notebook = get_active_notebook(; notebook_id)
    content = render_notebook_content(notebook)
    sidebar = render_sidebar_content(notebook)
    tabs = render_tabs(notebook)
    statusbar = render_statusbar(notebook)
    terminal = IDETerminalPanel(collapsed=true)

    page = Layout(content;
        sidebar=sidebar,
        tabs=tabs,
        statusbar=statusbar,
        terminal=terminal
    )

    render_page(page; title="Sessions.jl", head_extra=sessions_head_extra() * search_styles() * statusbar_ide_script() * terminal_panel_script() * package_panel_script() * keyboard_shortcuts_script() * run_controls_script() * search_replace_script() * workspace_inspector_script() * command_palette_script())
end

"""
Check if an error is a benign broken pipe (client disconnected).
"""
function is_broken_pipe(e)
    return isa(e, Base.IOError) && contains(string(e), "EPIPE")
end

"""
Handle HTTP stream (supports both regular requests and WebSocket upgrades).

WebSocket handling is delegated to Therapy.jl's handle_websocket().
"""
function handle_stream(stream::HTTP.Stream)
    request = stream.message
    path = HTTP.URI(request.target).path

    # Handle WebSocket upgrade on /ws path
    # Therapy.jl's handle_websocket() manages the connection, signals, and channels
    if path == "/ws"
        is_upgrade = any(h -> lowercase(String(h.first)) == "upgrade" &&
                              lowercase(String(h.second)) == "websocket", request.headers)
        if is_upgrade
            # Delegate to Therapy.jl's WebSocket handler
            handle_websocket(stream)
            return
        end
    end

    # Serve compiled Tailwind CSS
    if path == "/styles.css" && !isempty(_CSS_BYTES[])
        try
            HTTP.setstatus(stream, 200)
            HTTP.setheader(stream, "Content-Type" => "text/css; charset=utf-8")
            HTTP.setheader(stream, "Cache-Control" => "no-cache")
            HTTP.startwrite(stream)
            write(stream, _CSS_BYTES[])
        catch e
            is_broken_pipe(e) || rethrow(e)
        end
        return
    end

    # Ignore Chrome DevTools probe requests
    if startswith(path, "/.well-known/")
        try
            HTTP.setstatus(stream, 404)
            HTTP.startwrite(stream)
            write(stream, "Not Found")
        catch
            # Silently ignore - Chrome disconnects before we can respond
        end
        return
    end

    # Handle normal HTTP requests
    try
        if path == "/" || path == ""
            # Parse ?notebook=<uuid> query parameter for multi-notebook routing
            uri = HTTP.URI(request.target)
            notebook_id = nothing
            query_str = uri.query
            if !isempty(query_str)
                for param in split(query_str, "&")
                    kv = split(param, "="; limit=2)
                    if length(kv) == 2 && kv[1] == "notebook"
                        try
                            notebook_id = UUID(kv[2])
                        catch
                            # Invalid UUID, ignore
                        end
                    end
                end
            end

            html = render_notebook_page(; notebook_id)
            HTTP.setstatus(stream, 200)
            HTTP.setheader(stream, "Content-Type" => "text/html; charset=utf-8")
            HTTP.startwrite(stream)
            write(stream, html)
        else
            HTTP.setstatus(stream, 404)
            HTTP.startwrite(stream)
            write(stream, "Not Found")
        end
    catch e
        # Silently ignore broken pipe errors (client disconnected)
        if is_broken_pipe(e)
            return
        end
        @error "Request error" exception=(e, catch_backtrace())
        try
            HTTP.setstatus(stream, 500)
            HTTP.startwrite(stream)
            write(stream, "Internal Server Error")
        catch
            # Client already disconnected, ignore
        end
    end
end

"""
Try to find an available port.
Returns the port number or nothing if no port available.
"""
function find_available_port(start_port::Int, host::String; max_tries::Int=10)
    for offset in 0:(max_tries-1)
        port = start_port + offset
        try
            # Try to listen briefly to check if port is available
            server = HTTP.listen!(x -> nothing, host, port)
            close(server)
            return port
        catch e
            # Port in use, try next
            continue
        end
    end
    return nothing
end

"""
    serve(; port=8080, host="127.0.0.1", auto_port=true)

Start the Sessions.jl development server.

# Arguments
- `port::Int=8080`: The port to listen on
- `host::String="127.0.0.1"`: The host address to bind to
- `auto_port::Bool=true`: If true, automatically find an available port if the requested port is in use

# Example
```julia
using Sessions
Sessions.serve()
# Open http://localhost:8080
```

# Architecture
Sessions.jl uses Therapy.jl for all real-time features:
- Server signals for cell state broadcasting
- Channels for cell operations (execute, add, delete)
- WebSocket with auto-reconnect and JSON patches
"""
function serve(; port::Int=8080, host::String="127.0.0.1", auto_port::Bool=true)
    # Build Tailwind CSS
    _build_tailwind!()

    # Set up Therapy.jl WebSocket channels and signals
    setup_channels!()
    setup_signals!()
    setup_lifecycle!()

    # Create a default notebook if none exists
    if isempty(NOTEBOOKS)
        notebook = Notebook()
        add_cell!(notebook; code="# Welcome to Sessions.jl\n# A reactive Julia notebook powered by Therapy.jl")
        add_cell!(notebook; code="1 + 1")
        NOTEBOOKS[notebook.id] = notebook

        # Register per-cell signals for all cells
        register_all_cell_signals!(notebook)
    end

    # Find available port
    actual_port = port
    if auto_port
        found_port = find_available_port(port, host)
        if found_port === nothing
            println("\n┌─────────────────────────────────────────────────────┐")
            println("│  Port $port and alternatives are in use              │")
            println("├─────────────────────────────────────────────────────┤")
            println("│  Try: lsof -ti:$port | xargs kill                    │")
            println("│   Or: Sessions.serve(port=9000)                     │")
            println("└─────────────────────────────────────────────────────┘")
            error("No available ports found")
        end
        if found_port != port
            printstyled("Note: Port $port in use, using port $found_port\n", color=:yellow)
        end
        actual_port = found_port
    end

    println("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    println("  Sessions.jl - Julia Notebook")
    println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    println()
    println("  Server: http://$host:$actual_port")
    println("  Powered by Therapy.jl")
    println("  Press Ctrl+C to stop")
    println()

    # Start HTTP server with streaming API (required for WebSocket)
    server = HTTP.listen!(handle_stream, host, actual_port)

    # Keep server running
    try
        wait(server)
    catch e
        if isa(e, InterruptException)
            println("\nShutting down...")
        else
            rethrow(e)
        end
    finally
        close(server)
    end
end

# =============================================================================
# Tailwind CSS Build Helper
# =============================================================================

"""
    _build_tailwind!()

Build Tailwind CSS from Sessions.jl's input.css and store in `_CSS_BYTES`.
Uses Therapy.jl's `build_tailwind_css()` which auto-provisions the CLI.
"""
function _build_tailwind!()
    println("Building Tailwind CSS...")
    # Find input.css relative to Sessions.jl package root
    pkg_root = normpath(joinpath(@__DIR__, "..", ".."))
    input_path = joinpath(pkg_root, "input.css")

    if !isfile(input_path)
        @warn "input.css not found at $input_path, skipping Tailwind build"
        return
    end

    css_output = tempname() * ".css"
    try
        if build_tailwind_css(input_css=input_path, output_file=css_output, minify=false, cwd=pkg_root)
            _CSS_BYTES[] = read(css_output)
            println("  Built: $(round(length(_CSS_BYTES[]) / 1024, digits=1)) KB")
        else
            @warn "Tailwind CLI not available — styles will be missing"
        end
    finally
        rm(css_output, force=true)
    end
end

# =============================================================================
# Development Server
# =============================================================================

"""
    dev(; port=8080, host="127.0.0.1", auto_port=true)

Start the Sessions.jl development server with file watching.

Watches `.jl` source files and `input.css` for changes. When files change,
Tailwind CSS is rebuilt automatically.

# Example
```julia
using Sessions
Sessions.dev()
# Open http://localhost:8080
# Edit .jl files → Tailwind CSS auto-rebuilds on next request
```
"""
function dev(; port::Int=8080, host::String="127.0.0.1", auto_port::Bool=true)
    # Build Tailwind CSS
    _build_tailwind!()

    # Set up Therapy.jl WebSocket channels and signals
    setup_channels!()
    setup_signals!()
    setup_lifecycle!()

    # Create a default notebook if none exists
    if isempty(NOTEBOOKS)
        notebook = Notebook()
        add_cell!(notebook; code="# Welcome to Sessions.jl\n# A reactive Julia notebook powered by Therapy.jl")
        add_cell!(notebook; code="1 + 1")
        NOTEBOOKS[notebook.id] = notebook
        register_all_cell_signals!(notebook)
    end

    # Track file modification times for CSS rebuild
    pkg_root = normpath(joinpath(@__DIR__, "..", ".."))
    input_css_path = joinpath(pkg_root, "input.css")
    src_dir = joinpath(pkg_root, "src")
    last_css_build = Ref(time())

    function check_and_rebuild_css()
        # Check if any .jl files or input.css changed since last build
        needs_rebuild = false

        if isfile(input_css_path) && mtime(input_css_path) > last_css_build[]
            needs_rebuild = true
        end

        if !needs_rebuild && isdir(src_dir)
            for (root, _, files) in walkdir(src_dir)
                for file in files
                    endswith(file, ".jl") || continue
                    if mtime(joinpath(root, file)) > last_css_build[]
                        needs_rebuild = true
                        break
                    end
                end
                needs_rebuild && break
            end
        end

        if needs_rebuild
            println("\n━━━ Files changed, rebuilding CSS ━━━")
            _build_tailwind!()
            last_css_build[] = time()
            println("━━━ Ready ━━━\n")
        end
    end

    # Dev handler wraps handle_stream with CSS rebuild check
    last_check = Ref(time())
    check_interval = 2.0  # Check every 2 seconds

    function dev_handle_stream(stream::HTTP.Stream)
        # Periodically check for file changes
        if time() - last_check[] > check_interval
            check_and_rebuild_css()
            last_check[] = time()
        end
        handle_stream(stream)
    end

    # Find available port
    actual_port = port
    if auto_port
        found_port = find_available_port(port, host)
        if found_port === nothing
            error("No available ports found (tried $port-$(port+9))")
        end
        if found_port != port
            printstyled("Note: Port $port in use, using port $found_port\n", color=:yellow)
        end
        actual_port = found_port
    end

    println("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    println("  Sessions.jl - Dev Server")
    println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    println()
    println("  Server:  http://$host:$actual_port")
    println("  Watching: src/**/*.jl, input.css")
    println("  Press Ctrl+C to stop")
    println()

    server = HTTP.listen!(dev_handle_stream, host, actual_port)

    try
        wait(server)
    catch e
        if isa(e, InterruptException)
            println("\nShutting down...")
        else
            rethrow(e)
        end
    finally
        close(server)
    end
end
