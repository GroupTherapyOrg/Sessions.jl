# Main route — renders the full Sessions.jl web IDE
#
# Props passed explicitly so data-props exists for localStorage patching.

function Index()
    SessionsApp(NotebookPanel(); initial_sidebar=1, initial_repl=1)
end

Index
