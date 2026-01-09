module Sessions

using Therapy
using HTTP
using HTTP.WebSockets
using Sockets
using JSON3
using UUIDs

# =============================================================================
# Data Structures
# =============================================================================

include("Notebook/Cell.jl")
include("Notebook/Executor.jl")

# =============================================================================
# Server (WebSocket + HTTP)
# =============================================================================

include("Server/WebSocketServer.jl")

# =============================================================================
# UI Components
# =============================================================================

include("Components/App.jl")

# =============================================================================
# Public API
# =============================================================================

export Cell, CellStatus, IDLE, QUEUED, RUNNING, COMPLETED, ERRORED
export Executor, execute, execute_cell!, restart!, shutdown!
export SessionsApp, NotebookView, CellView
export dev

"""
    dev(; port=8080, host="127.0.0.1")

Start the Sessions development server.
"""
function dev(; port::Int=8080, host::String="127.0.0.1")
    println("Starting Sessions.jl...")
    println("Open http://$host:$port in your browser")
    start_server(host, port)
end

end # module
