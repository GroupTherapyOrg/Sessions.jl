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

# HTTP is needed for the server. Therapy.jl provides:
# - handle_websocket(stream) - WebSocket upgrade handling
# - websocket_client_script() - Client JS for WebSocket
# - Server signals, channels, and all real-time features
#
# We only import HTTP to handle the HTTP layer. Therapy.jl handles WebSocket.

"""
Render the main notebook content (cells + header).
Returns a Therapy.jl component (no Layout wrapper).
"""
function render_notebook_content()
    # Get or create the first notebook
    notebook = if !isempty(NOTEBOOKS)
        first(values(NOTEBOOKS))
    else
        nb = Notebook()
        add_cell!(nb; code="# Welcome to Sessions.jl\n# A reactive Julia notebook powered by Therapy.jl")
        add_cell!(nb; code="1 + 1")
        add_cell!(nb; code="x = 42")
        add_cell!(nb; code="x * 2")
        NOTEBOOKS[nb.id] = nb
        register_all_cell_signals!(nb)
        nb
    end

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
function render_sidebar_content()
    workspace = pwd()
    file_entries = list_directory(workspace)

    # Get current notebook path if one is open
    nb_path = if !isempty(NOTEBOOKS)
        nb = first(values(NOTEBOOKS))
        nb.path !== nothing ? nb.path : ""
    else
        ""
    end

    IDESidebar(
        entries=file_entries,
        current_path=workspace,
        current_notebook_path=nb_path
    )
end

"""
Build the tab bar from currently open notebooks.
"""
function render_tabs()
    if isempty(NOTEBOOKS)
        return IDEEmptyTabs()
    end

    # Build notebook info list for tabs
    active_nb = first(values(NOTEBOOKS))
    notebooks_info = [
        Dict{String,Any}(
            "id" => nb.id,
            "title" => nb.path !== nothing ? basename(nb.path) : "Untitled",
            "modified" => false
        )
        for nb in values(NOTEBOOKS)
    ]

    IDENotebookTabs(notebooks_info;
        active_id=active_nb.id,
        is_running=false
    )
end

"""
Build the status bar with current notebook context.
"""
function render_statusbar()
    # Get notebook path for display
    nb_path = if !isempty(NOTEBOOKS)
        nb = first(values(NOTEBOOKS))
        nb.path !== nothing ? nb.path : ""
    else
        ""
    end

    IDEStatusBar(
        kernel_state="idle",
        notebook_path=nb_path
    )
end

"""
Render full notebook page with IDE Layout.
"""
function render_notebook_page()
    content = render_notebook_content()
    sidebar = render_sidebar_content()
    tabs = render_tabs()
    statusbar = render_statusbar()
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
            html = render_notebook_page()
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
