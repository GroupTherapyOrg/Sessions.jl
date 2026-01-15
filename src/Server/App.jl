# App.jl - Simple HTTP server for Sessions
#
# Uses Therapy.jl for rendering and WebSocket handling.
# Uses streaming API for proper WebSocket integration.

using Therapy
using HTTP

"""
Render the main notebook page.
"""
function render_notebook_page()
    # Get or create the first notebook
    notebook = if !isempty(NOTEBOOKS)
        first(values(NOTEBOOKS))
    else
        nb = Notebook()
        add_cell!(nb; code="# Welcome to Sessions!\n# Start typing Julia code here.")
        add_cell!(nb; code="1 + 1")
        add_cell!(nb; code="x = 42")
        add_cell!(nb; code="x * 2")
        NOTEBOOKS[nb.id] = nb
        nb
    end

    cells = cells_in_order(notebook)

    # Build page content
    content = Div(:class => "notebook-container",
        # Notebook header
        Div(:class => "mb-6",
            H2(:class => "text-2xl font-semibold text-neutral-900 dark:text-neutral-100",
                notebook.path === nothing ? "Untitled Notebook" : basename(notebook.path)
            ),
            P(:class => "text-sm text-neutral-500",
                "$(length(cells)) cells"
            )
        ),

        # Cells
        CellsView(cells),

        # Add cell at end
        Div(:class => "text-center py-4",
            Button(:class => "px-4 py-2 text-sm bg-neutral-200 dark:bg-neutral-700 text-neutral-700 dark:text-neutral-200 rounded hover:bg-neutral-300 transition-colors",
                :onclick => "addCell(null)",
                "+ Add Cell"
            )
        ),

        # Set notebook ID for client
        Script("setNotebookId('$(notebook.id)');")
    )

    # Render with layout using Therapy.jl's render_page
    render_page(Layout(content); title="Sessions - Julia Notebook", head_extra=sessions_head_extra())
end

"""
Handle HTTP stream (supports both regular requests and WebSocket upgrades).
"""
function handle_stream(stream::HTTP.Stream)
    request = stream.message
    path = HTTP.URI(request.target).path

    # Handle WebSocket upgrade on /ws path (what Therapy's client connects to)
    if path == "/ws"
        is_upgrade = any(h -> lowercase(String(h.first)) == "upgrade" &&
                              lowercase(String(h.second)) == "websocket", request.headers)
        if is_upgrade
            # Pass stream to Therapy's WebSocket handler (handles upgrade internally)
            handle_websocket(stream)
            return
        end
    end

    # Handle normal HTTP requests
    try
        # Route the request
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
        @error "Request error" exception=(e, catch_backtrace())
        HTTP.setstatus(stream, 500)
        HTTP.startwrite(stream)
        write(stream, "Internal Server Error")
    end
end

"""
    serve(; port=8080, host="127.0.0.1")

Start the Sessions development server.
"""
function serve(; port::Int=8080, host::String="127.0.0.1")
    # Set up WebSocket channels
    setup_channels!()
    setup_signals!()
    setup_lifecycle!()

    # Create a default notebook if none exists
    if isempty(NOTEBOOKS)
        notebook = Notebook()
        add_cell!(notebook; code="# Welcome to Sessions!\n# Start typing Julia code here.")
        add_cell!(notebook; code="1 + 1")
        NOTEBOOKS[notebook.id] = notebook
    end

    println("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    println("  Sessions.jl - Julia Notebook")
    println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    println()
    println("  Server: http://$host:$port")
    println("  Press Ctrl+C to stop")
    println()

    # Start HTTP server with streaming API for WebSocket support
    server = HTTP.listen!(handle_stream, host, port)

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
