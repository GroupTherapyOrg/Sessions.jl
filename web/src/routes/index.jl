# Main route — renders the full Sessions.jl web IDE
#
# Props passed explicitly so data-props exists for localStorage patching.

function Index()
    SessionsApp(NotebookPanel(); initial_sidebar=0, initial_repl=0)
end

Index
