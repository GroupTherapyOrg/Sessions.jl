# FileExplorer.jl — Shoelace sl-tree file explorer with context menu
#
# Uses Shoelace <sl-tree> web components for a robust, accessible file tree.
# Features: lazy-load directories, right-click context menu (rename/delete/new),
# inline rename, parent directory navigation, file type icons.

# --- SVG icon strings (reused from original) ---

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

# --- Helpers ---

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

"""Escape HTML special characters."""
function _html_escape(s::String)::String
    s = replace(s, "&" => "&amp;")
    s = replace(s, "<" => "&lt;")
    s = replace(s, ">" => "&gt;")
    s = replace(s, "\"" => "&quot;")
    return s
end

"""Check if a tree node (recursively) contains the active file path."""
function _contains_active(node::Main.Sessions.FileNode, active_path::String)::Bool
    node.path == active_path && return true
    for child in node.children
        _contains_active(child, active_path) && return true
    end
    false
end

# --- Shoelace sl-tree rendering ---

"""Render a FileNode as a Shoelace `<sl-tree-item>` HTML string."""
function _render_tree_item(node::Main.Sessions.FileNode, active_path::String; root_dir::String="")::String
    esc_path = _html_escape(node.path)

    if node.is_dir
        start_open = _contains_active(node, active_path)
        expanded_attr = start_open ? " expanded" : ""
        # Directories not containing the active file use lazy loading
        lazy_attr = (!start_open && !isempty(node.children)) ? " lazy" : ""

        children_html = IOBuffer()
        if start_open
            for child in node.children
                write(children_html, _render_tree_item(child, active_path; root_dir=root_dir))
            end
        end

        return string(
            "<sl-tree-item data-is-dir data-path=\"", esc_path, "\"",
            " data-abs-path=\"", _html_escape(joinpath(root_dir, node.path)), "\"",
            expanded_attr, lazy_attr, ">",
            _ICON_FOLDER_CLOSED,
            "<span class=\"tree-label\">", _html_escape(node.name), "</span>",
            String(take!(children_html)),
            "</sl-tree-item>"
        )
    else
        icon = _icon_for_type(node.file_type)
        selected_attr = (node.path == active_path) ? " selected" : ""
        abs_path = _html_escape(joinpath(root_dir, node.path))

        return string(
            "<sl-tree-item data-path=\"", esc_path, "\"",
            " data-abs-path=\"", abs_path, "\"",
            " data-file-type=\"", node.file_type, "\"",
            selected_attr, ">",
            icon,
            "<span class=\"tree-label\">", _html_escape(node.name), "</span>",
            (node.path == active_path ? _ICON_MODIFIED : ""),
            "</sl-tree-item>"
        )
    end
end

# --- Context menu HTML ---

function _file_context_menu_html()
    """<div id="file-context-menu" class="file-ctx-menu">
<div class="file-ctx-item fm-new-file" data-action="new_file">
<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"><path d="M9 1H4a1 1 0 00-1 1v12a1 1 0 001 1h8a1 1 0 001-1V5L9 1z"/><path d="M9 1v4h4M8 7v6M5 10h6"/></svg>
New File</div>
<div class="file-ctx-item fm-new-folder" data-action="new_folder">
<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"><path d="M1 4a1 1 0 011-1h4l1.5 1.5H14a1 1 0 011 1V12a1 1 0 01-1 1H2a1 1 0 01-1-1V4z"/><path d="M8 7v4M6 9h4"/></svg>
New Folder</div>
<div class="file-ctx-sep"></div>
<div class="file-ctx-item fm-rename" data-action="rename">
<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"><path d="M11.5 1.5l3 3L5 14H2v-3L11.5 1.5z"/></svg>
Rename</div>
<div class="file-ctx-sep"></div>
<div class="file-ctx-item fm-delete danger" data-action="delete">
<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"><path d="M2 4h12M5 4V3a1 1 0 011-1h4a1 1 0 011 1v1M6 7v5M10 7v5"/><path d="M3 4l1 9a1 1 0 001 1h6a1 1 0 001-1l1-9"/></svg>
Delete</div>
</div>"""
end

# --- Client-side JavaScript ---

function _file_explorer_js(root_dir::String)
    esc_root = _html_escape(root_dir)
    """
(function() {
  if (window._fileExplorerInit) return;
  window._fileExplorerInit = true;

  var tree = document.getElementById('file-tree');
  var ctxMenu = document.getElementById('file-context-menu');
  var _ctxTarget = null;      // sl-tree-item that was right-clicked
  var _clickTimer = null;     // debounce single-click vs double-click

  if (!tree) return;

  // ── File selection: single click opens .jl files ──
  tree.addEventListener('sl-selection-change', function(e) {
    var items = e.detail.selection;
    if (!items || !items.length) return;
    var item = items[0];
    if (item.hasAttribute('data-is-dir')) return;
    var fileType = item.dataset.fileType;
    var absPath = item.dataset.absPath;
    if (fileType === 'jl' && absPath && window.TherapyWS) {
      // Debounce to avoid firing during double-click rename
      clearTimeout(_clickTimer);
      _clickTimer = setTimeout(function() {
        TherapyWS.sendMessage('notebook', {action: 'open_notebook', path: absPath});
      }, 250);
    }
  });

  // ── Lazy loading: fetch directory contents on expand ──
  tree.addEventListener('sl-lazy-load', function(e) {
    var item = e.target;
    if (!item || !item.dataset || !item.dataset.path) return;
    var dirPath = item.dataset.path;
    if (window.TherapyWS) {
      TherapyWS.sendMessage('file_explorer', {action: 'list_dir', path: dirPath});
    }
  });

  // ── Context menu: right-click ──
  tree.addEventListener('contextmenu', function(e) {
    e.preventDefault();
    var item = e.target.closest('sl-tree-item');
    if (!item) return;
    _ctxTarget = item;
    var isDir = item.hasAttribute('data-is-dir');

    // Show/hide directory-only items
    ctxMenu.querySelector('.fm-new-file').style.display = isDir ? '' : 'none';
    ctxMenu.querySelector('.fm-new-folder').style.display = isDir ? '' : 'none';

    // Position and show
    var x = e.clientX, y = e.clientY;
    ctxMenu.style.display = 'block';
    // Clamp to viewport
    var rect = ctxMenu.getBoundingClientRect();
    if (x + rect.width > window.innerWidth) x = window.innerWidth - rect.width - 8;
    if (y + rect.height > window.innerHeight) y = window.innerHeight - rect.height - 8;
    ctxMenu.style.left = x + 'px';
    ctxMenu.style.top = y + 'px';
  });

  // Close context menu on click outside
  document.addEventListener('click', function(e) {
    if (!e.target.closest('#file-context-menu')) {
      ctxMenu.style.display = 'none';
    }
  });
  document.addEventListener('contextmenu', function(e) {
    if (!e.target.closest('#file-tree')) {
      ctxMenu.style.display = 'none';
    }
  });

  // ── Context menu actions ──
  ctxMenu.addEventListener('click', function(e) {
    var item = e.target.closest('.file-ctx-item');
    if (!item || !_ctxTarget) return;
    var action = item.dataset.action;
    ctxMenu.style.display = 'none';

    if (action === 'rename') {
      startInlineRename(_ctxTarget);
    } else if (action === 'delete') {
      var name = _ctxTarget.querySelector('.tree-label');
      var displayName = name ? name.textContent : _ctxTarget.dataset.path;
      var isDir = _ctxTarget.hasAttribute('data-is-dir');
      if (confirm('Delete ' + (isDir ? 'folder' : 'file') + ' "' + displayName + '"?')) {
        if (window.TherapyWS) {
          TherapyWS.sendMessage('file_explorer', {
            action: 'delete', path: _ctxTarget.dataset.path
          });
        }
      }
    } else if (action === 'new_file' || action === 'new_folder') {
      var promptMsg = action === 'new_file' ? 'New file name:' : 'New folder name:';
      var name = prompt(promptMsg);
      if (name && name.trim()) {
        if (window.TherapyWS) {
          TherapyWS.sendMessage('file_explorer', {
            action: action === 'new_file' ? 'create_file' : 'create_dir',
            parent_path: _ctxTarget.dataset.path,
            name: name.trim()
          });
        }
      }
    }
  });

  // ── Inline rename: double-click ──
  tree.addEventListener('dblclick', function(e) {
    var item = e.target.closest('sl-tree-item');
    if (!item) return;
    e.preventDefault();
    clearTimeout(_clickTimer);  // cancel the single-click open
    startInlineRename(item);
  });

  function startInlineRename(item) {
    var label = item.querySelector('.tree-label');
    if (!label) return;
    var oldName = label.textContent;
    var input = document.createElement('input');
    input.type = 'text';
    input.value = oldName;
    input.className = 'tree-rename-input';

    label.style.display = 'none';
    label.parentNode.insertBefore(input, label.nextSibling);
    input.focus();
    // Select name without extension for files
    var dotIdx = oldName.lastIndexOf('.');
    if (dotIdx > 0 && !item.hasAttribute('data-is-dir')) {
      input.setSelectionRange(0, dotIdx);
    } else {
      input.select();
    }

    var committed = false;
    function commit() {
      if (committed) return;
      committed = true;
      var newName = input.value.trim();
      input.remove();
      label.style.display = '';
      if (newName && newName !== oldName) {
        label.textContent = newName;
        if (window.TherapyWS) {
          TherapyWS.sendMessage('file_explorer', {
            action: 'rename', path: item.dataset.path, new_name: newName
          });
        }
      }
    }
    input.addEventListener('blur', commit);
    input.addEventListener('keydown', function(ev) {
      if (ev.key === 'Enter') { ev.preventDefault(); commit(); }
      if (ev.key === 'Escape') { ev.preventDefault(); input.value = oldName; commit(); }
    });
  }

  // ── Navigate to parent directory ──
  var upBtn = document.getElementById('tree-nav-up');
  if (upBtn) {
    upBtn.addEventListener('click', function() {
      if (window.TherapyWS) {
        TherapyWS.sendMessage('file_explorer', {action: 'navigate_up'});
      }
    });
  }

  // ── WebSocket response handler for file_explorer channel ──
  window.addEventListener('therapy:channel:file_explorer', function(e) {
    var data = e.detail;
    if (!data || !data.event) return;

    if (data.event === 'dir_contents') {
      // Lazy-load response: find the tree item and inject children
      var item = tree.querySelector('sl-tree-item[data-path="' + CSS.escape(data.path) + '"]');
      if (item) {
        // Remove the lazy attribute so it doesn't fire again
        item.removeAttribute('lazy');
        // Parse and append children
        var tmp = document.createElement('div');
        tmp.innerHTML = data.children_html;
        while (tmp.firstChild) {
          item.appendChild(tmp.firstChild);
        }
      }
    }

    else if (data.event === 'file_deleted') {
      var item = tree.querySelector('sl-tree-item[data-path="' + CSS.escape(data.path) + '"]');
      if (item) item.remove();
    }

    else if (data.event === 'file_renamed') {
      var item = tree.querySelector('sl-tree-item[data-path="' + CSS.escape(data.old_path) + '"]');
      if (item) {
        item.dataset.path = data.new_path;
        if (data.new_abs_path) item.dataset.absPath = data.new_abs_path;
        var label = item.querySelector('.tree-label');
        if (label) label.textContent = data.new_name;
      }
    }

    else if (data.event === 'item_created') {
      // Find parent and append the new item
      var parent = tree.querySelector('sl-tree-item[data-path="' + CSS.escape(data.parent_path) + '"]');
      if (parent) {
        var tmp = document.createElement('div');
        tmp.innerHTML = data.item_html;
        while (tmp.firstChild) {
          parent.appendChild(tmp.firstChild);
        }
        // Expand parent if collapsed
        if (!parent.expanded) parent.expanded = true;
      }
    }

    else if (data.event === 'tree_replaced') {
      // Full tree refresh (e.g., after navigating to parent dir)
      var wrapper = document.getElementById('file-tree-wrapper');
      if (wrapper) wrapper.innerHTML = data.tree_html;
      // Update breadcrumb
      var crumb = document.querySelector('.tree-breadcrumb .crumb');
      if (crumb && data.root_name) crumb.textContent = data.root_name;
    }
  });
})();
"""
end

# --- Main component ---

"""
    FileExplorer()

Render a Shoelace sl-tree file explorer with lazy loading, context menu,
inline rename, and parent directory navigation. Reads the notebook directory
from `Main.WEB_STATE` and builds a real file tree using `_build_file_tree()`.
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

    # Determine root directory to scan
    root_dir = if nb !== nothing && isfile(nb.path)
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
        write(tree_html, _render_tree_item(node, active_rel; root_dir=root_dir))
    end

    root_name = basename(root_dir)

    Fragment(
        # Breadcrumb: parent nav + current dir name
        Div(:class => "tree-breadcrumb",
            :style => "border-bottom:1px solid #1c2736;",
            Button(:id => "tree-nav-up", :title => "Go to parent directory",
                RawHtml("""<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M8 12V4M4 8l4-4 4 4"/></svg>""")),
            Span(:class => "crumb", :title => root_dir, root_name)),

        # Shoelace tree
        Div(:id => "file-tree-wrapper", :class => "flex-1 overflow-y-auto py-1 px-1",
            RawHtml(string(
                "<sl-tree id=\"file-tree\" selection=\"leaf\" data-root-dir=\"",
                _html_escape(root_dir), "\">",
                String(take!(tree_html)),
                "</sl-tree>"))),

        # Context menu
        RawHtml(_file_context_menu_html()),

        # Client-side JS
        RawHtml(string("<script>", _file_explorer_js(root_dir), "</script>")),

        # Status bar
        Div(:class => "flex items-center gap-1.5 px-3 py-2 shrink-0",
            :style => "border-top:1px solid #1c2736; font-size:11px; color:#3d5068;",
            RawHtml(_ICON_STATUS_OK),
            Span("No issues"),
            Span(:class => "flex-1"),
            Span(:class => "font-mono",
                :style => "font-size:10px;",
                "$(done_count)/$(cell_count)")))
end
