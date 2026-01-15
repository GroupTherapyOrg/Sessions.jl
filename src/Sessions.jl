module Sessions

# =============================================================================
# Dependencies
# =============================================================================

# Core framework - provides reactivity, components, SSR, WebSocket handling
using Therapy

# HTTP server - Sessions needs to handle custom routes
# (Therapy.jl uses HTTP internally but doesn't expose all server utilities)
using HTTP

# Data handling
using JSON3
using UUIDs
using OrderedCollections

# Code analysis for reactive notebooks
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
# UI Components (loaded before Server for CellView access in Channels)
# =============================================================================

include("UI/CellView.jl")
include("UI/DarkModeToggle.jl")  # Island for theme toggle (compiled to Wasm)
include("UI/Layout.jl")

# =============================================================================
# Server (Therapy.jl WebSocket integration)
# =============================================================================

include("Server/Signals.jl")
include("Server/Channels.jl")

# =============================================================================
# App Entry Point
# =============================================================================

include("Server/App.jl")

# =============================================================================
# Public API
# =============================================================================

export Cell, CellState, CellOutput
export CELL_IDLE, CELL_QUEUED, CELL_RUNNING, CELL_ERROR
export Notebook, add_cell!, delete_cell!, move_cell!, get_cell
export analyze_cell!, get_execution_order, get_all_execution_order
export execute_cell!, execute_reactive!, run_all!
export load_notebook, save_notebook, is_pluto_notebook

# Server API
export serve

end # module
