module Sessions

using Therapy
using HTTP
using HTTP.WebSockets
using Sockets
using JSON3
using UUIDs

# =============================================================================
# Core Data Structures
# =============================================================================

include("Notebook/Cell.jl")
include("Notebook/Executor.jl")

# =============================================================================
# UI Components (Therapy.jl)
# =============================================================================

include("components/Layout.jl")
include("components/Sidebar.jl")
include("components/Terminal.jl")

# =============================================================================
# Server (WebSocket + HTTP with Therapy.jl rendering)
# =============================================================================

include("Server/WebSocketServer.jl")

# =============================================================================
# Public API
# =============================================================================

export Cell, CellStatus, IDLE, QUEUED, RUNNING, COMPLETED, ERRORED
export Executor, execute, execute_cell!, restart!, shutdown!
export Layout, TopBar, Sidebar, Terminal
export dev

"""
    dev(; port=8080, host="127.0.0.1")

Start the Sessions.jl development server.

This follows the Therapy.jl development pattern:
- All UI is rendered using Therapy.jl components (Layout, Sidebar, Terminal)
- Components are in src/components/
- Routes are in src/routes/
- Server handles Julia code execution via WebSocket

# Example
```julia
using Sessions
Sessions.dev(port=8080)
```
"""
function dev(; port::Int=8080, host::String="127.0.0.1")
    println("\n━━━ Sessions.jl Dev Server ━━━")
    println("Powered by Therapy.jl")
    println()

    # Find available port
    actual_port = port
    for attempt in 0:9
        test_port = port + attempt
        try
            server = Sockets.listen(Sockets.IPv4(host), test_port)
            close(server)
            actual_port = test_port
            break
        catch
            if attempt == 9
                error("Could not find available port (tried $port-$(port+9))")
            end
        end
    end

    if actual_port != port
        println("Note: Port $port in use, using port $actual_port")
    end

    println("Server running at http://$host:$actual_port")
    println("Press Ctrl+C to stop")
    println()

    start_server(host, actual_port)
end

end # module
