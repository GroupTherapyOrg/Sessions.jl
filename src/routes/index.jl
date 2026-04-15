function Index()
    state = isdefined(Main, :WEB_STATE) ? Main.WEB_STATE[] : nothing
    SessionsApp(NotebookPanel(state))
end

Index
