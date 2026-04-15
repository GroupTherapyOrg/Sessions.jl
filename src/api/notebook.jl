function notebook_api_routes(get_state)
    _S = Main.Sessions
    [
        "/api/notebook" => Dict(
            "GET" => (req, params) -> begin
                state = get_state()
                state === nothing && return json_response(Dict("tabs" => [], "active" => 0))
                tabs = [Dict(
                    "idx" => i,
                    "id" => string(t.id),
                    "label" => t.label,
                    "path" => t.path,
                    "type" => string(t.tab_type),
                    "active" => i == state.active_tab_idx
                ) for (i, t) in enumerate(state.tabs)]
                Dict("tabs" => tabs, "active" => state.active_tab_idx)
            end
        ),
        "/api/notebook/open" => Dict(
            "POST" => (req, params) -> begin
                state = get_state()
                state === nothing && return json_response(Dict("error" => "no state"); status=503)
                body = json_body(req)
                body === nothing && return json_response(Dict("error" => "missing body"); status=400)
                raw_path = get(body, "path", "")
                isempty(raw_path) && return json_response(Dict("error" => "missing path"); status=400)

                full_path = if isabspath(raw_path)
                    abspath(raw_path)
                else
                    dir = dirname(abspath(_S.active_tab(state).path))
                    abspath(joinpath(dir, raw_path))
                end

                !isfile(full_path) && return json_response(Dict("error" => "file not found: $full_path"); status=404)

                for (i, tab) in enumerate(state.tabs)
                    if tab.path == full_path
                        state.active_tab_idx = i
                        return Dict("tab_idx" => i, "label" => tab.label, "path" => tab.path, "already_open" => true)
                    end
                end

                is_nb = endswith(full_path, ".jl") && _S.is_notebook_file(full_path)

                if is_nb
                    nb = _S.load_notebook(full_path)
                    session_data = _S.load_session(_S.session_path(nb.path))
                    session_data !== nothing && _S.apply_session!(nb, session_data)
                    worker = _S.NotebookWorker(; notebook_path=nb.path)
                    tab = _S.WebTab(Main.UUIDs.uuid4(), nb, worker, basename(full_path), full_path)
                    push!(state.tabs, tab)
                    state.active_tab_idx = length(state.tabs)
                else
                    content = try
                        read(full_path, String)
                    catch
                        return json_response(Dict("error" => "cannot read file"); status=500)
                    end
                    tab = _S.WebTab(Main.UUIDs.uuid4(), basename(full_path), full_path, content)
                    push!(state.tabs, tab)
                    state.active_tab_idx = length(state.tabs)
                end

                Dict("tab_idx" => state.active_tab_idx, "label" => basename(full_path),
                     "path" => full_path, "type" => is_nb ? "notebook" : "file")
            end
        ),
        "/api/notebook/save" => Dict(
            "POST" => (req, params) -> begin
                state = get_state()
                state === nothing && return json_response(Dict("error" => "no state"); status=503)
                tab = _S.active_tab(state)
                tab === nothing && return json_response(Dict("error" => "no active tab"); status=404)

                if tab.tab_type == :file
                    body = json_body(req)
                    if body !== nothing && haskey(body, "content")
                        tab.file_content = String(body["content"])
                    end
                    write(tab.path, tab.file_content)
                else
                    nb = _S.active_nb(state)
                    body = json_body(req)
                    if body !== nothing && haskey(body, "codes")
                        for (cid, code) in body["codes"]
                            cell = _S.get_cell(nb, Main.UUIDs.UUID(String(cid)))
                            cell !== nothing && (cell.code = String(code))
                        end
                    end
                    _S.save_notebook(nb)
                    _S.save_session!(nb)
                end

                Dict("saved" => true, "path" => tab.path)
            end
        ),
        "/api/notebook/export" => Dict(
            "GET" => (req, params) -> begin
                state = get_state()
                state === nothing && return json_response(Dict("error" => "no state"); status=503)
                tab = _S.active_tab(state)
                tab === nothing && return json_response(Dict("error" => "no active tab"); status=404)
                tab.tab_type != :notebook && return json_response(Dict("error" => "not a notebook tab"); status=400)

                nb = _S.active_nb(state)
                source = _S.serialize_notebook(nb)
                Dict("filename" => basename(nb.path), "source" => source)
            end
        )
    ]
end

notebook_api_routes
