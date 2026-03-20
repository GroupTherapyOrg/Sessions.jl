# Main route — renders the full Sessions.jl web IDE
#
# SessionsApp wraps NotebookPanel with the three-panel layout
# (activity bar + file explorer + REPL + status bar).
# Props passed explicitly so data-props attribute exists for localStorage patching.

function Index()
    SessionsApp(NotebookPanel(); initial_sidebar=1, initial_repl=1)
end

Index
