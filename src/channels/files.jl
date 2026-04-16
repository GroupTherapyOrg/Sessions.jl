# channels/files.jl — File explorer WebSocket channel handlers
#
# Provides directory tree listing, file/folder CRUD, and navigation
# for the Shoelace sl-tree file explorer. Uses Therapy's channel API.

using Therapy

# ═══════════════════════════════════════════════════════════════
# FileNode type + tree builder
# ═══════════════════════════════════════════════════════════════

struct FileNode
    name::String
    path::String
    is_dir::Bool
    children::Vector{FileNode}
    file_type::Symbol  # :jl, :toml, :md, :yml, :git, :lic, :generic
end

function _detect_file_type(name::String)::Symbol
    name == "LICENSE" && return :lic
    name == ".gitignore" && return :git
    endswith(name, ".jl") && return :jl
    endswith(name, ".toml") && return :toml
    endswith(name, ".md") && return :md
    (endswith(name, ".yml") || endswith(name, ".yaml")) && return :yml
    return :generic
end

const _SKIP_NAMES = Set(["node_modules", ".git", "Manifest.toml", "__pycache__", ".DS_Store"])

function _build_file_tree(root_dir::String; max_depth::Int=4)
    _build_tree_recursive(root_dir, root_dir, 0, max_depth)
end

function _build_tree_recursive(dir::String, root::String, depth::Int, max_depth::Int)::Vector{FileNode}
    depth >= max_depth && return FileNode[]
    entries = try
        readdir(dir)
    catch
        return FileNode[]
    end

    dirs = FileNode[]
    files = FileNode[]

    for name in entries
        if startswith(name, '.') && name != ".gitignore"
            continue
        end
        name in _SKIP_NAMES && continue

        full = joinpath(dir, name)
        rel = relpath(full, root)

        if isdir(full)
            children = _build_tree_recursive(full, root, depth + 1, max_depth)
            push!(dirs, FileNode(name, rel, true, children, :generic))
        elseif isfile(full)
            push!(files, FileNode(name, rel, false, FileNode[], _detect_file_type(name)))
        end
    end

    sort!(dirs; by=n -> lowercase(n.name))
    sort!(files; by=n -> lowercase(n.name))
    return vcat(dirs, files)
end

# ═══════════════════════════════════════════════════════════════
# Broadcast helpers
# ═══════════════════════════════════════════════════════════════

function _files_broadcast!(msg::Dict)
    msg["channel"] = "file_explorer"
    try; Therapy.broadcast_all(msg); catch; end
end

function _files_send!(conn, msg::Dict)
    msg["channel"] = "file_explorer"
    try; Therapy.send_ws_message(conn, msg); catch; end
end

# ═══════════════════════════════════════════════════════════════
# Explorer root directory
# ═══════════════════════════════════════════════════════════════

const _FILE_EXPLORER_ROOT = Ref("")

function _explorer_root_dir(state)::String
    nb = try active_nb(state) catch; nothing end
    nb_path = if nb !== nothing
        nb.path
    else
        tab = try active_tab(state) catch; nothing end
        tab !== nothing && tab.tab_type == :file ? tab.path : ""
    end
    if isfile(nb_path)
        dir = dirname(abspath(nb_path))
        found = dir
        for _ in 1:5
            if isfile(joinpath(dir, "Project.toml")) || isdir(joinpath(dir, "src"))
                found = dir
                break
            end
            parent = dirname(dir)
            parent == dir && break
            dir = parent
        end
        return found
    end
    return isdefined(Main, :USER_CWD) ? Main.USER_CWD : pwd()
end

function _get_explorer_root(state)::String
    if isempty(_FILE_EXPLORER_ROOT[])
        _FILE_EXPLORER_ROOT[] = _explorer_root_dir(state)
    end
    return _FILE_EXPLORER_ROOT[]
end

# ═══════════════════════════════════════════════════════════════
# Tree item HTML renderer (for Shoelace sl-tree-item)
# ═══════════════════════════════════════════════════════════════

function _render_tree_item_html(node::FileNode, active_path::String; root_dir::String="")::String
    esc(s) = replace(replace(replace(replace(s, "&" => "&amp;"), "<" => "&lt;"), ">" => "&gt;"), "\"" => "&quot;")
    esc_path = esc(node.path)

    icon_jl = """<svg width="14" height="14" viewBox="0 0 20 20"><circle cx="10" cy="6" r="2.8" fill="#e06b65"/><circle cx="5.5" cy="14" r="2.8" fill="#56d4a0"/><circle cx="14.5" cy="14" r="2.8" fill="#b08fd8"/></svg>"""
    icon_toml = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><rect x="3" y="3" width="14" height="14" rx="2" stroke="#6b7d93" stroke-width="1.3"/><path d="M7 7h6M7 10h4M7 13h5" stroke="#6b7d93" stroke-width="1.2" stroke-linecap="round"/></svg>"""
    icon_md = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><rect x="2" y="4" width="16" height="12" rx="1.5" stroke="#7bb8e8" stroke-width="1.3"/><path d="M5 13V7l2.5 3L10 7v6M13 10l2-3 2 3M15 7v6" stroke="#7bb8e8" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/></svg>"""
    icon_yml = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><path d="M6 4l4 5.5L14 4M10 9.5V16" stroke="#d4a056" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>"""
    icon_git = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><circle cx="10" cy="10" r="6" stroke="#e06b65" stroke-width="1.3"/><path d="M10 6v4l2.5 2.5" stroke="#e06b65" stroke-width="1.2" stroke-linecap="round"/></svg>"""
    icon_lic = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><rect x="4" y="2" width="12" height="16" rx="1.5" stroke="#d4a056" stroke-width="1.2"/><path d="M7 6h6M7 9h6M7 12h4" stroke="#d4a056" stroke-width="1" stroke-linecap="round"/></svg>"""
    icon_folder = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><path d="M2 5.5A1.5 1.5 0 013.5 4H8l1.5 2h7A1.5 1.5 0 0118 7.5v7a1.5 1.5 0 01-1.5 1.5h-13A1.5 1.5 0 012 14.5v-9z" fill="#3d5068" opacity=".5" stroke="#5a7a99" stroke-width="1"/></svg>"""
    icon_generic = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><path d="M5 2h7l4 4v12a1 1 0 01-1 1H5a1 1 0 01-1-1V3a1 1 0 011-1z" stroke="#4a6178" stroke-width="1.2"/><path d="M12 2v4h4" stroke="#4a6178" stroke-width="1.2"/></svg>"""

    function _icon(ft::Symbol)
        ft === :jl && return icon_jl
        ft === :toml && return icon_toml
        ft === :md && return icon_md
        ft === :yml && return icon_yml
        ft === :git && return icon_git
        ft === :lic && return icon_lic
        return icon_generic
    end

    if node.is_dir
        return string(
            "<sl-tree-item data-is-dir data-path=\"", esc_path, "\"",
            " data-abs-path=\"", esc(joinpath(root_dir, node.path)), "\"",
            " lazy>",
            icon_folder,
            "<span class=\"tree-label\">", esc(node.name), "</span>",
            "</sl-tree-item>"
        )
    else
        icon = _icon(node.file_type)
        selected_attr = (node.path == active_path) ? " selected" : ""
        return string(
            "<sl-tree-item data-path=\"", esc_path, "\"",
            " data-abs-path=\"", esc(joinpath(root_dir, node.path)), "\"",
            " data-file-type=\"", node.file_type, "\"",
            selected_attr, ">",
            icon,
            "<span class=\"tree-label\">", esc(node.name), "</span>",
            "</sl-tree-item>"
        )
    end
end

# ═══════════════════════════════════════════════════════════════
# Channel registration
# ═══════════════════════════════════════════════════════════════

function setup_files_channel!(state)
    Therapy.on_channel_message() do channel, conn, msg
        channel == "file_explorer" || return
        action = get(msg, "action", "")
        try
            if action == "list_dir"
                _handle_list_dir!(state, conn, msg)
            elseif action == "rename"
                _handle_file_rename!(state, conn, msg)
            elseif action == "delete"
                _handle_file_delete!(state, conn, msg)
            elseif action == "create_file"
                _handle_file_create!(state, conn, msg)
            elseif action == "create_dir"
                _handle_dir_create!(state, conn, msg)
            elseif action == "navigate_up"
                _handle_navigate_up!(state, conn, msg)
            else
                @warn "[files] Unknown action" action=action
            end
        catch e
            @warn "[files] Handler error" action=action exception=(e, catch_backtrace())
        end
    end
end

# ═══════════════════════════════════════════════════════════════
# Path safety
# ═══════════════════════════════════════════════════════════════

function _safe_path(root_dir::String, rel_path::String)::Union{String, Nothing}
    full = abspath(joinpath(root_dir, rel_path))
    startswith(full, abspath(root_dir)) || return nothing
    return full
end

# ═══════════════════════════════════════════════════════════════
# Handlers
# ═══════════════════════════════════════════════════════════════

function _handle_list_dir!(state, conn, data)
    rel_path = get(data, "path", "")
    root_dir = _get_explorer_root(state)
    full_path = _safe_path(root_dir, rel_path)

    # Always send a response so the client's lazy-load spinner can be cleared.
    # Empty children_html on invalid path tells JS to remove the lazy attr.
    if full_path === nothing || !isdir(full_path)
        _files_broadcast!(Dict(
            "event" => "dir_contents",
            "path" => rel_path,
            "children_html" => ""
        ))
        return
    end

    children = _build_tree_recursive(full_path, root_dir, 0, 1)

    nb = try active_nb(state) catch; nothing end
    active_rel = nb !== nothing && isfile(nb.path) ? relpath(abspath(nb.path), root_dir) : ""

    children_html = IOBuffer()
    for child in children
        write(children_html, _render_tree_item_html(child, active_rel; root_dir=root_dir))
    end

    # Broadcast (not send-to-conn) so the right tree element sees it even if
    # the FileExplorer's WS handler holds a stale conn reference after reload.
    _files_broadcast!(Dict(
        "event" => "dir_contents",
        "path" => rel_path,
        "children_html" => String(take!(children_html))
    ))
end

function _handle_file_rename!(state, conn, data)
    rel_path = get(data, "path", "")
    new_name = get(data, "new_name", "")
    isempty(new_name) && return

    root_dir = _get_explorer_root(state)
    old_full = _safe_path(root_dir, rel_path)
    old_full === nothing && return
    (isfile(old_full) || isdir(old_full)) || return

    new_full = joinpath(dirname(old_full), new_name)
    startswith(abspath(new_full), abspath(root_dir)) || return
    (isfile(new_full) || isdir(new_full)) && return

    mv(old_full, new_full)
    new_rel = relpath(new_full, root_dir)

    _files_broadcast!(Dict(
        "event" => "file_renamed",
        "old_path" => rel_path,
        "new_path" => new_rel,
        "new_abs_path" => new_full,
        "new_name" => new_name
    ))
end

function _handle_file_delete!(state, conn, data)
    rel_path = get(data, "path", "")
    root_dir = _get_explorer_root(state)
    full_path = _safe_path(root_dir, rel_path)
    full_path === nothing && return
    full_path == abspath(root_dir) && return

    if isdir(full_path)
        rm(full_path; recursive=true)
    elseif isfile(full_path)
        rm(full_path)
    else
        return
    end

    _files_broadcast!(Dict(
        "event" => "file_deleted",
        "path" => rel_path
    ))
end

function _handle_file_create!(state, conn, data)
    parent_path = get(data, "parent_path", "")
    name = get(data, "name", "")
    isempty(name) && return

    root_dir = _get_explorer_root(state)
    parent_full = _safe_path(root_dir, parent_path)
    parent_full === nothing && return
    isdir(parent_full) || return

    file_full = joinpath(parent_full, name)
    startswith(abspath(file_full), abspath(root_dir)) || return
    isfile(file_full) && return

    write(file_full, "")
    file_rel = relpath(file_full, root_dir)
    node = FileNode(name, file_rel, false, FileNode[], _detect_file_type(name))

    _files_broadcast!(Dict(
        "event" => "item_created",
        "parent_path" => parent_path,
        "item_html" => _render_tree_item_html(node, ""; root_dir=root_dir)
    ))
end

function _handle_dir_create!(state, conn, data)
    parent_path = get(data, "parent_path", "")
    name = get(data, "name", "")
    isempty(name) && return

    root_dir = _get_explorer_root(state)
    parent_full = _safe_path(root_dir, parent_path)
    parent_full === nothing && return
    isdir(parent_full) || return

    dir_full = joinpath(parent_full, name)
    startswith(abspath(dir_full), abspath(root_dir)) || return
    isdir(dir_full) && return

    mkpath(dir_full)
    dir_rel = relpath(dir_full, root_dir)
    node = FileNode(name, dir_rel, true, FileNode[], :generic)

    _files_broadcast!(Dict(
        "event" => "item_created",
        "parent_path" => parent_path,
        "item_html" => _render_tree_item_html(node, ""; root_dir=root_dir)
    ))
end

function _handle_navigate_up!(state, conn, data)
    current_root = _get_explorer_root(state)
    parent = dirname(current_root)
    parent == current_root && return

    _FILE_EXPLORER_ROOT[] = parent
    tree = _build_file_tree(parent; max_depth=4)

    nb = try active_nb(state) catch; nothing end
    active_rel = nb !== nothing && isfile(nb.path) ? relpath(abspath(nb.path), parent) : ""

    tree_html = IOBuffer()
    write(tree_html, "<sl-tree id=\"file-tree\" selection=\"leaf\" data-root-dir=\"")
    for ch in parent
        if ch == '"'
            write(tree_html, "&quot;")
        elseif ch == '&'
            write(tree_html, "&amp;")
        elseif ch == '<'
            write(tree_html, "&lt;")
        else
            write(tree_html, ch)
        end
    end
    write(tree_html, "\">")
    for node in tree
        write(tree_html, _render_tree_item_html(node, active_rel; root_dir=parent))
    end
    write(tree_html, "</sl-tree>")

    _files_broadcast!(Dict(
        "event" => "tree_replaced",
        "tree_html" => String(take!(tree_html)),
        "root_name" => basename(parent),
        "root_dir" => parent
    ))
end
