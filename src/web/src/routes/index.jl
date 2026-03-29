# Main route — renders the full Sessions.jl web IDE

function Index()
    state = isdefined(Main, :WEB_STATE) ? Main.WEB_STATE[] : nothing
    SessionsApp(NotebookPanel(state))
end

Index
