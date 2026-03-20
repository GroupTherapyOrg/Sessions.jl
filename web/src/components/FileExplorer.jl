# FileExplorer.jl — Filesystem-backed file tree with folder toggle
#
# Reads the real directory tree via _build_file_tree() and renders a nested
# collapsible tree. Folders expand/collapse via inline JS (no WASM needed).
# This is a plain function (not @island) since interactivity is pure DOM.

# --- SVG icon strings ---

const _ICON_JULIA = """<svg width="14" height="14" viewBox="0 0 20 20"><circle cx="10" cy="6" r="2.8" fill="#e06b65"/><circle cx="5.5" cy="14" r="2.8" fill="#56d4a0"/><circle cx="14.5" cy="14" r="2.8" fill="#b08fd8"/></svg>"""

const _ICON_TOML = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><rect x="3" y="3" width="14" height="14" rx="2" stroke="#6b7d93" stroke-width="1.3"/><path d="M7 7h6M7 10h4M7 13h5" stroke="#6b7d93" stroke-width="1.2" stroke-linecap="round"/></svg>"""

const _ICON_MD = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><rect x="2" y="4" width="16" height="12" rx="1.5" stroke="#7bb8e8" stroke-width="1.3"/><path d="M5 13V7l2.5 3L10 7v6M13 10l2-3 2 3M15 7v6" stroke="#7bb8e8" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/></svg>"""

const _ICON_YML = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><path d="M6 4l4 5.5L14 4M10 9.5V16" stroke="#d4a056" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>"""

const _ICON_GIT = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><circle cx="10" cy="10" r="6" stroke="#e06b65" stroke-width="1.3"/><path d="M10 6v4l2.5 2.5" stroke="#e06b65" stroke-width="1.2" stroke-linecap="round"/></svg>"""

const _ICON_LIC = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><rect x="4" y="2" width="12" height="16" rx="1.5" stroke="#d4a056" stroke-width="1.2"/><path d="M7 6h6M7 9h6M7 12h4" stroke="#d4a056" stroke-width="1" stroke-linecap="round"/></svg>"""

const _ICON_FOLDER_OPEN = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><path d="M2 5.5A1.5 1.5 0 013.5 4H8l1.5 2h7A1.5 1.5 0 0118 7.5V9H4.5L2 15.5v-10z" fill="#3d5068" opacity=".4" stroke="#7bb8e8" stroke-width="1"/><path d="M2 15.5L4.5 9H18l-2.5 6.5H2z" fill="#1a2332" stroke="#7bb8e8" stroke-width="1"/></svg>"""

const _ICON_FOLDER_CLOSED = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><path d="M2 5.5A1.5 1.5 0 013.5 4H8l1.5 2h7A1.5 1.5 0 0118 7.5v7a1.5 1.5 0 01-1.5 1.5h-13A1.5 1.5 0 012 14.5v-9z" fill="#3d5068" opacity=".5" stroke="#5a7a99" stroke-width="1"/></svg>"""

const _ICON_GENERIC = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><path d="M5 2h7l4 4v12a1 1 0 01-1 1H5a1 1 0 01-1-1V3a1 1 0 011-1z" stroke="#4a6178" stroke-width="1.2"/><path d="M12 2v4h4" stroke="#4a6178" stroke-width="1.2"/></svg>"""

const _ICON_STATUS_OK = """<svg width="7" height="7"><circle cx="3.5" cy="3.5" r="3.5" fill="#56d4a0"/></svg>"""

const _ICON_MODIFIED = """<svg width="6" height="6" class="shrink-0"><circle cx="3" cy="3" r="3" fill="#56d4a0"/></svg>"""

# Shared tree item base style
const _TREE_ITEM = "display:flex;align-items:center;gap:6px;padding:2px 0;border-radius:4px;cursor:pointer;font-size:12px;font-family:'JetBrains Mono',ui-monospace,monospace;white-space:nowrap;overflow:hidden;user-select:none;transition:color .15s,background .15s;"

# Chevron style
const _CHV_STYLE = "width:12px;height:12px;font-size:8px;display:inline-flex;align-items:center;justify-content:center;flex-shrink:0;transition:transform .15s;"

# Inline JS for folder toggle (click handler) — also swaps folder icon SVG
const _FOLDER_SVG_OPEN = """<svg width='14' height='14' viewBox='0 0 20 20' fill='none'><path d='M2 5.5A1.5 1.5 0 013.5 4H8l1.5 2h7A1.5 1.5 0 0118 7.5V9H4.5L2 15.5v-10z' fill='#3d5068' opacity='.4' stroke='#7bb8e8' stroke-width='1'/><path d='M2 15.5L4.5 9H18l-2.5 6.5H2z' fill='#1a2332' stroke='#7bb8e8' stroke-width='1'/></svg>"""
const _FOLDER_SVG_CLOSED = """<svg width='14' height='14' viewBox='0 0 20 20' fill='none'><path d='M2 5.5A1.5 1.5 0 013.5 4H8l1.5 2h7A1.5 1.5 0 0118 7.5v7a1.5 1.5 0 01-1.5 1.5h-13A1.5 1.5 0 012 14.5v-9z' fill='#3d5068' opacity='.5' stroke='#5a7a99' stroke-width='1'/></svg>"""
const _FOLDER_TOGGLE_JS = "onclick=\"(function(e){e.stopPropagation();var c=this.nextElementSibling;var ch=this.querySelector('.chv');var ic=this.querySelectorAll('svg')[1];if(c.style.display==='none'){c.style.display='block';ch.classList.add('open');if(ic)ic.outerHTML='$(_FOLDER_SVG_OPEN)'}else{c.style.display='none';ch.classList.remove('open');if(ic)ic.outerHTML='$(_FOLDER_SVG_CLOSED)'}}).call(this,event)\""

# Hover JS for non-active items
const _HOVER_ENTER = "onmouseenter=\"this.style.background='rgba(255,255,255,.03)'\""
const _HOVER_LEAVE = "onmouseleave=\"this.style.background=''\""

"""Get SVG icon string for a file type."""
function _icon_for_type(ft::Symbol)::String
    ft === :jl && return _ICON_JULIA
    ft === :toml && return _ICON_TOML
    ft === :md && return _ICON_MD
    ft === :yml && return _ICON_YML
    ft === :git && return _ICON_GIT
    ft === :lic && return _ICON_LIC
    return _ICON_GENERIC
end

"""Check if a tree node (recursively) contains the active file path."""
function _contains_active(node::Main.Sessions.FileNode, active_path::String)::Bool
    node.path == active_path && return true
    for child in node.children
        _contains_active(child, active_path) && return true
    end
    false
end

"""Render a single tree node (file or directory) as an HTML string."""
function _render_tree_node(node::Main.Sessions.FileNode, depth::Int, active_path::String; root_dir::String="")::String
    pad = depth * 14 + 6
    is_active = !node.is_dir && node.path == active_path

    if node.is_dir
        # Directory: clickable row + children container
        # Only open folders that contain the active file
        start_open = _contains_active(node, active_path)
        children_display = start_open ? "block" : "none"
        chv_class = start_open ? "chv open" : "chv"
        folder_icon = start_open ? _ICON_FOLDER_OPEN : _ICON_FOLDER_CLOSED
        # Chevron rotation via open class: .chv.open { transform: rotate(90deg) }
        # We inline the transform since CSS class may not exist
        chv_transform = start_open ? "transform:rotate(90deg);" : ""

        row = string(
            "<div style=\"", _TREE_ITEM, "padding-left:", pad, "px;color:#9baabd;\" ",
            _FOLDER_TOGGLE_JS, " ", _HOVER_ENTER, " ", _HOVER_LEAVE, ">",
            "<span class=\"", chv_class, "\" style=\"", _CHV_STYLE, chv_transform, "\">&#9656;</span>",
            folder_icon,
            "<span>", _html_escape(node.name), "</span>",
            "</div>"
        )

        # Children container
        children_html = IOBuffer()
        write(children_html, "<div style=\"display:", children_display, ";\">")
        for child in node.children
            write(children_html, _render_tree_node(child, depth + 1, active_path; root_dir=root_dir))
        end
        write(children_html, "</div>")

        return row * String(take!(children_html))
    else
        # File: single row
        icon = _icon_for_type(node.file_type)

        # .jl files: clickable to open in a new tab
        jl_onclick = ""
        if node.file_type === :jl && !isempty(root_dir)
            # Use the absolute path so the server can resolve it
            abs_file_path = _html_escape(joinpath(root_dir, node.path))
            jl_onclick = " onclick=\"TherapyWS.sendMessage('notebook',{action:'open_notebook',path:'$(abs_file_path)'})\""
        end

        if is_active
            # Active file: green left border, subtle green bg, bright text, modified dot
            return string(
                "<div style=\"", _TREE_ITEM, "padding-left:", pad, "px;",
                "color:#d4dce8;border-left:2px solid #56d4a0;background:rgba(86,212,160,.06);\"",
                jl_onclick, ">",
                icon,
                "<span>", _html_escape(node.name), "</span>",
                "<span style=\"flex:1;\"></span>",
                _ICON_MODIFIED,
                "</div>"
            )
        else
            return string(
                "<div style=\"", _TREE_ITEM, "padding-left:", pad, "px;color:#6b7d93;\" ",
                _HOVER_ENTER, " ", _HOVER_LEAVE,
                jl_onclick, ">",
                icon,
                "<span>", _html_escape(node.name), "</span>",
                "</div>"
            )
        end
    end
end

"""Escape HTML special characters."""
function _html_escape(s::String)::String
    s = replace(s, "&" => "&amp;")
    s = replace(s, "<" => "&lt;")
    s = replace(s, ">" => "&gt;")
    s = replace(s, "\"" => "&quot;")
    return s
end

"""
    FileExplorer()

Render a filesystem-backed file explorer tree. Reads the notebook directory
from `Main.WEB_STATE` and builds a real file tree using `_build_file_tree()`.
Folder expand/collapse is handled via inline JavaScript (no WASM).
"""
function FileExplorer()
    # Read notebook state
    state = if isdefined(Main, :WEB_STATE) && Main.WEB_STATE[] !== nothing
        Main.WEB_STATE[]
    else
        nothing
    end

    nb = state !== nothing ? Main.Sessions.active_nb(state) : nothing
    nb_path = nb !== nothing ? nb.path : "Untitled.jl"
    nb_name = basename(nb_path)

    # Determine root directory to scan
    root_dir = if nb !== nothing && isfile(nb.path)
        # Walk up to find project root (has Project.toml or src/)
        dir = dirname(abspath(nb.path))
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
        found
    else
        pwd()
    end

    # Build the file tree
    tree = Main.Sessions._build_file_tree(root_dir; max_depth=4)

    # Compute active path (relative to root_dir)
    active_rel = if nb !== nothing && isfile(nb.path)
        relpath(abspath(nb.path), root_dir)
    else
        ""
    end

    # Cell counts for status bar
    cell_count = nb !== nothing ? length(Main.Sessions.ordered_cells(nb)) : 0
    done_count = nb !== nothing ? count(c -> c.state == Main.Sessions.cell_done, Main.Sessions.ordered_cells(nb)) : 0

    # Build tree HTML
    tree_html = IOBuffer()
    for node in tree
        write(tree_html, _render_tree_node(node, 0, active_rel; root_dir=root_dir))
    end

    # CSS for chevron rotation (inline style block)
    chevron_css = """<style>.chv.open{transform:rotate(90deg);}</style>"""

    Fragment(
        # Chevron CSS
        RawHtml(chevron_css),

        # File tree area
        Div(:class => "flex-1 overflow-y-auto py-1.5 px-1",
            RawHtml(String(take!(tree_html)))),

        # Status bar at bottom
        Div(:class => "flex items-center gap-1.5 px-3 py-2 shrink-0",
            :style => "border-top:1px solid #1c2736; font-size:11px; color:#3d5068;",
            RawHtml(_ICON_STATUS_OK),
            Span("No issues"),
            Span(:class => "flex-1"),
            Span(:class => "font-mono",
                :style => "font-size:10px;",
                "$(done_count)/$(cell_count)")))
end
