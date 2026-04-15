function files_api_routes(get_root_dir)
    _S = Main.Sessions

    function _tree_json(nodes)
        [Dict(
            "name" => n.name,
            "path" => n.path,
            "is_dir" => n.is_dir,
            "type" => string(n.file_type),
            "children" => n.is_dir ? _tree_json(n.children) : nothing
        ) for n in nodes]
    end

    [
        "/api/files/tree" => Dict(
            "GET" => (req, params) -> begin
                root = get_root_dir()
                isempty(root) && return json_response(Dict("error" => "no root directory"); status=503)
                tree = _S._build_file_tree(root)
                Dict("root" => root, "tree" => _tree_json(tree))
            end
        ),
        "/api/files/read" => Dict(
            "GET" => (req, params) -> begin
                root = get_root_dir()
                isempty(root) && return json_response(Dict("error" => "no root directory"); status=503)
                qp = query_params(req)
                rel_path = get(qp, "path", "")
                isempty(rel_path) && return json_response(Dict("error" => "missing path parameter"); status=400)

                full_path = abspath(joinpath(root, rel_path))
                startswith(full_path, root) || return json_response(Dict("error" => "path outside root"); status=403)
                !isfile(full_path) && return json_response(Dict("error" => "file not found"); status=404)

                content = try
                    read(full_path, String)
                catch
                    return json_response(Dict("error" => "cannot read file"); status=500)
                end
                Dict("path" => rel_path, "content" => content)
            end
        ),
        "/api/files/write" => Dict(
            "POST" => (req, params) -> begin
                root = get_root_dir()
                isempty(root) && return json_response(Dict("error" => "no root directory"); status=503)
                body = json_body(req)
                body === nothing && return json_response(Dict("error" => "missing body"); status=400)
                rel_path = get(body, "path", "")
                content = get(body, "content", nothing)
                isempty(rel_path) && return json_response(Dict("error" => "missing path"); status=400)
                content === nothing && return json_response(Dict("error" => "missing content"); status=400)

                full_path = abspath(joinpath(root, rel_path))
                startswith(full_path, root) || return json_response(Dict("error" => "path outside root"); status=403)

                mkpath(dirname(full_path))
                write(full_path, content)
                Dict("written" => true, "path" => rel_path)
            end
        )
    ]
end

files_api_routes
