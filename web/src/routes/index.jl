# Main route — renders the full Sessions.jl web IDE
#
# SessionsApp wraps NotebookPanel with the three-panel layout
# (activity bar + file explorer + REPL + status bar).

function Index()
    SessionsApp(NotebookPanel())
end

Index
