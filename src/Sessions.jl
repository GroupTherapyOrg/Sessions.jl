module Sessions

# Sessions.jl v2 — Terminal-Native Reactive Julia Notebook
# Built on Tachikoma.jl (TUI framework)
# NO browser dependencies (Therapy.jl, Suite.jl, HTTP.jl)

# Dependencies will be added as stories are implemented:
# - Tachikoma.jl (TUI)
# - ExpressionExplorer.jl (reactive analysis)
# - PlutoDependencyExplorer.jl (topological sort)
# - UUIDs (cell identifiers)
# - FileWatching (agent integration)
# - OrderedCollections (ordered cell storage)

using UUIDs
import Tachikoma

# Layer 1: Engine
include("types.jl")
include("format.jl")

export CellState, cell_idle, cell_queued, cell_running, cell_done, cell_errored
export CellOutput, Cell, Notebook
export add_cell!, insert_cell!, remove_cell!, get_cell, ordered_cells
export source_hash, is_stale, is_never_run, stale_cells, never_run_cells, mark_executed!
export load_notebook, save_notebook, parse_notebook, serialize_notebook

include("analysis.jl")
export analyze_cell, cell_definitions, cell_references, build_topology, execution_order, downstream_dependents

include("kernel.jl")
export Workspace, execute_cell!, execute_notebook!, execute_changed!
export classify_output, text_representation
export format_error, format_cell_error

include("run.jl")

# Layer 2: TUI
include("tui/cell_widget.jl")
include("tui/output_widget.jl")
include("tui/status_bar.jl")
include("tui/notebook_view.jl")
include("tui/app.jl")

# Layer 3: CLI
include("cli.jl")
include("watcher.jl")

end # module
