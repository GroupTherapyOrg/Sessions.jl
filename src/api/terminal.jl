function terminal_api_routes(get_term_state, get_web_state)
    _S = Main.Sessions

    [
        "/api/terminal/tabs" => Dict(
            "GET" => (req, params) -> begin
                ts = get_term_state()
                tabs = [Dict(
                    "id" => t.id,
                    "label" => t.label,
                    "active" => t.id == ts.active_tab_id,
                    "alive" => _S.pty_alive(t.pty)
                ) for t in ts.tabs]
                Dict("tabs" => tabs, "active" => ts.active_tab_id)
            end
        ),
        "/api/terminal/create" => Dict(
            "POST" => (req, params) -> begin
                ts = get_term_state()
                ws = get_web_state()
                cwd = try
                    nb = _S.active_nb(ws)
                    isfile(nb.path) ? dirname(abspath(nb.path)) : pwd()
                catch
                    isdefined(Main, :USER_CWD) ? Main.USER_CWD : pwd()
                end
                label = "Terminal $(ts.next_num)"
                id = string(Main.UUIDs.uuid4())
                pty = _S.pty_spawn(; cmd=_S._default_shell(), cwd=cwd)
                tab = _S.TerminalTab(id, label, pty, nothing, IOBuffer())
                push!(ts.tabs, tab)
                ts.active_tab_id = id
                ts.next_num += 1
                Dict("id" => id, "label" => label)
            end
        ),
        "/api/terminal/close" => Dict(
            "POST" => (req, params) -> begin
                ts = get_term_state()
                body = json_body(req)
                body === nothing && return json_response(Dict("error" => "missing body"); status=400)
                tab_id = get(body, "id", "")
                isempty(tab_id) && return json_response(Dict("error" => "missing id"); status=400)

                idx = findfirst(t -> t.id == tab_id, ts.tabs)
                idx === nothing && return json_response(Dict("error" => "tab not found"); status=404)

                tab = ts.tabs[idx]
                try; _S.pty_close!(tab.pty); catch; end
                tab.relay_task !== nothing && try; Base.schedule(tab.relay_task, InterruptException(); error=true); catch; end
                deleteat!(ts.tabs, idx)

                if ts.active_tab_id == tab_id && !isempty(ts.tabs)
                    ts.active_tab_id = ts.tabs[min(idx, length(ts.tabs))].id
                elseif isempty(ts.tabs)
                    ts.active_tab_id = ""
                end

                Dict("closed" => true, "id" => tab_id)
            end
        ),
        "/api/terminal/resize" => Dict(
            "POST" => (req, params) -> begin
                ts = get_term_state()
                body = json_body(req)
                body === nothing && return json_response(Dict("error" => "missing body"); status=400)
                tab_id = get(body, "id", ts.active_tab_id)
                cols = get(body, "cols", 80)
                rows = get(body, "rows", 24)

                idx = findfirst(t -> t.id == tab_id, ts.tabs)
                idx === nothing && return json_response(Dict("error" => "tab not found"); status=404)

                _S.pty_resize!(ts.tabs[idx].pty, Int(cols), Int(rows))
                Dict("resized" => true, "id" => tab_id, "cols" => cols, "rows" => rows)
            end
        )
    ]
end

terminal_api_routes
