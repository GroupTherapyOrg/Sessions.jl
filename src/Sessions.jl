module Sessions

# =============================================================================
# Dependencies
# =============================================================================

using Therapy
using HTTP
using HTTP.WebSockets
using Sockets
using JSON3
using UUIDs
using OrderedCollections
using ExpressionExplorer
import Malt
import PlutoDependencyExplorer as PDE

# =============================================================================
# Core Engine
# =============================================================================

include("Engine/Cell.jl")
include("Engine/Notebook.jl")
include("Engine/Output.jl")      # Must come before Worker.jl (defines escape_html)
include("Engine/Reactivity.jl")
include("Engine/Worker.jl")

# =============================================================================
# File Format (Pluto-compatible)
# =============================================================================

include("FileFormat/Parse.jl")
include("FileFormat/Write.jl")

# =============================================================================
# Server (Therapy.jl WebSocket)
# =============================================================================

include("Server/Signals.jl")
include("Server/Channels.jl")
include("Server/App.jl")

# =============================================================================
# UI Components
# =============================================================================

include("UI/CellView.jl")
include("UI/Layout.jl")

# =============================================================================
# Public API
# =============================================================================

export Cell, CellState, CellOutput
export CELL_IDLE, CELL_QUEUED, CELL_RUNNING, CELL_ERROR
export Notebook, add_cell!, delete_cell!, move_cell!, get_cell
export analyze_cell!, get_execution_order, get_all_execution_order
export execute_cell!, execute_reactive!, run_all!
export load_notebook, save_notebook, is_pluto_notebook
export serve

# =============================================================================
# Entry Points
# =============================================================================

"""
    dev(; port=8080, host="127.0.0.1")

Start the Sessions development server.

# Example
```julia
using Sessions
Sessions.dev()
# Open http://localhost:8080
```
"""
function dev(; port::Int=8080, host::String="127.0.0.1")
    serve(; port=port, host=host)
end

end # module
