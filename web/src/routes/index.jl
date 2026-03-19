# Main route — renders the full Sessions.jl web IDE
#
# SessionsApp @island wraps NotebookPanel with the three-panel layout
# (activity bar + file explorer + REPL).

function Index()
    SessionsApp(NotebookPanel())
end

Index
