# Main route — renders the full Sessions.jl web IDE

function Index()
    SessionsApp(NotebookPanel())
end

Index
