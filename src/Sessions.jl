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

# Placeholder — files will be added by ralph loop stories
# Layer 1: Engine
# include("types.jl")
# include("format.jl")
# include("analysis.jl")
# include("kernel.jl")
# include("run.jl")

# Layer 2: TUI
# include("tui/app.jl")
# include("tui/cell_widget.jl")
# include("tui/output_widget.jl")
# include("tui/notebook_view.jl")
# include("tui/status_bar.jl")

# Layer 3: CLI
# include("cli.jl")
# include("watcher.jl")

end # module
