# IDE/FileBrowser.jl - Sessions.jl IDE File Browser Panel
#
# Enhanced file browser for the sidebar panel using Suite.jl components.
# Builds on IDESidebar's file tree with:
# - Suite.ContextMenu for right-click actions
# - "New Notebook" option that creates Pluto-format .jl files
# - Filesystem polling for auto-refresh
# - Notebook opening wired to tab system
#
# Server channel handlers already exist in server/server.jl:
#   navigate_directory, refresh_filebrowser, create_file, create_folder,
#   delete_item, rename_item, open_file
#
# SESSIONS-3600

import Suite

# =============================================================================
# SVG Icon Constants
# =============================================================================

const _FB_ICON_FILE_PLUS = "M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8l-6-6zm-1 2l5 5h-5V4zM12 18v-6m-3 3h6"
const _FB_ICON_FOLDER_PLUS = "M9 13h6m-3-3v6M2 6a2 2 0 012-2h5l2 2h5a2 2 0 012 2v8a2 2 0 01-2 2H4a2 2 0 01-2-2V6z"
const _FB_ICON_NOTEBOOK = "M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
const _FB_ICON_PENCIL = "M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"
const _FB_ICON_TRASH = "M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
const _FB_ICON_COPY = "M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3"
const _FB_ICON_OPEN = "M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"

# =============================================================================
# SVG Icon Helper
# =============================================================================

function _fb_icon(path_d::String; class::String="w-4 h-4")
    Svg(:class => class,
        :fill => "none", :viewBox => "0 0 24 24",
        :stroke => "currentColor", Symbol("stroke-width") => "1.5",
        Path(:d => path_d)
    )
end

# =============================================================================
# File Browser Toolbar
# =============================================================================

"""
    IDEBrowserToolbar()

Toolbar above the file tree with New Notebook, New File, New Folder buttons.
Uses Suite.Button for actions.
"""
function IDEBrowserToolbar()
    Div(:class => "flex items-center gap-1 px-2 py-1.5",
        # New Notebook
        Suite.Button(
            _fb_icon(_FB_ICON_NOTEBOOK; class="w-3.5 h-3.5");
            variant="ghost", size="icon",
            class="h-6 w-6 text-warm-500 hover:text-accent-600 dark:text-warm-400 dark:hover:text-accent-400",
            title="New Notebook",
            kwargs=Dict(:onclick => "createNotebook()")
        ),
        # New File
        Suite.Button(
            _fb_icon(_FB_ICON_FILE_PLUS; class="w-3.5 h-3.5");
            variant="ghost", size="icon",
            class="h-6 w-6 text-warm-500 hover:text-warm-700 dark:text-warm-400 dark:hover:text-warm-200",
            title="New File",
            kwargs=Dict(:onclick => "createFile()")
        ),
        # New Folder
        Suite.Button(
            _fb_icon(_FB_ICON_FOLDER_PLUS; class="w-3.5 h-3.5");
            variant="ghost", size="icon",
            class="h-6 w-6 text-warm-500 hover:text-warm-700 dark:text-warm-400 dark:hover:text-warm-200",
            title="New Folder",
            kwargs=Dict(:onclick => "createFolder()")
        ),
        # Spacer
        Div(:class => "flex-1"),
        # Refresh
        Suite.Button(
            _fb_icon("M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"; class="w-3.5 h-3.5");
            variant="ghost", size="icon",
            class="h-6 w-6 text-warm-400 hover:text-warm-600 dark:text-warm-500 dark:hover:text-warm-300",
            title="Refresh",
            kwargs=Dict(:onclick => "refreshFileBrowser()")
        )
    )
end

# =============================================================================
# File Browser Context Menu
# =============================================================================

"""
    IDEFileContextMenu()

Hidden context menu that appears on right-click. Positioned via JS.
Uses warm-* tokens and Suite.jl-style menu item design.
"""
function IDEFileContextMenu()
    Div(:id => "file-context-menu",
        :class => "hidden fixed z-[100] min-w-[180px] bg-warm-50 dark:bg-warm-900 rounded-md shadow-xl border border-warm-200 dark:border-[#252422] py-1 overflow-hidden",

        # Open (shown only for .jl files / directories)
        Div(:id => "ctx-menu-open",
            _context_menu_item("Open", _FB_ICON_OPEN, "contextMenuOpen()")
        ),
        Div(:id => "ctx-menu-separator-open",
            :class => "border-t border-warm-200 dark:border-[#252422] my-1"
        ),

        # New Notebook
        _context_menu_item("New Notebook", _FB_ICON_NOTEBOOK, "createNotebook()"),

        # New File
        _context_menu_item("New File", _FB_ICON_FILE_PLUS, "createFile()"),

        # New Folder
        _context_menu_item("New Folder", _FB_ICON_FOLDER_PLUS, "createFolder()"),

        # Separator
        Div(:class => "border-t border-warm-200 dark:border-[#252422] my-1"),

        # Rename
        _context_menu_item("Rename", _FB_ICON_PENCIL, "contextMenuRename()"),

        # Delete
        _context_menu_item("Delete", _FB_ICON_TRASH, "contextMenuDelete()";
            is_danger=true),

        # Separator
        Div(:class => "border-t border-warm-200 dark:border-[#252422] my-1"),

        # Copy Path
        _context_menu_item("Copy Path", _FB_ICON_COPY, "contextMenuCopyPath()")
    )
end

"""
Context menu item with icon, matching Suite.jl DropdownMenuItem styling.
"""
function _context_menu_item(label::String, icon_path::String, onclick::String;
    is_danger::Bool=false)

    color_classes = if is_danger
        "text-rose-600 dark:text-rose-400 hover:bg-rose-50 dark:hover:bg-rose-900/20"
    else
        "text-warm-700 dark:text-warm-300 hover:bg-warm-100 dark:hover:bg-warm-800"
    end

    Button(:class => "flex items-center gap-3 w-full px-3 py-1.5 text-[12px] transition-colors $color_classes",
        :onclick => onclick,
        _fb_icon(icon_path; class="w-3.5 h-3.5 flex-shrink-0"),
        Span(label)
    )
end

# =============================================================================
# Enhanced File Tree (recursive with depth support)
# =============================================================================

"""
    IDEFileTreeItem(entry; current_notebook_path, depth, expanded_dirs)

Single file/folder item in the file browser tree.
"""
function IDEFileTreeItem(entry::FileEntry;
    current_notebook_path::String="",
    depth::Int=0
)
    is_active = !entry.is_directory && entry.path == current_notebook_path
    is_julia = endswith(lowercase(entry.name), ".jl")

    # Click handler
    onclick = if entry.is_directory
        "navigateToDirectory('$(entry.path)')"
    elseif is_julia
        "openNotebook('$(entry.path)')"
    else
        ""
    end

    # Context menu
    oncontextmenu = "showContextMenu(event, '$(entry.path)', $(entry.is_directory), $(is_julia))"

    # Icon
    icon_path = if entry.is_directory
        _SIDEBAR_FOLDER_ICON
    elseif is_julia
        _SIDEBAR_JULIA_ICON
    else
        _SIDEBAR_FILE_ICON
    end

    icon_color = if entry.is_directory
        "text-warm-500 dark:text-warm-400"
    elseif is_julia
        "text-accent-600 dark:text-accent-400"
    else
        "text-warm-400 dark:text-warm-500"
    end

    Div(:class => join(filter(!isempty, [
            "sessions-file-item group flex items-center gap-2 px-3 py-1 cursor-pointer transition-colors text-[11px] font-mono",
            is_active ? "sessions-file-active bg-accent-500/[0.08] text-accent-700 dark:text-accent-400 font-medium" :
                       "text-warm-600 dark:text-warm-400 hover:bg-warm-100 dark:hover:bg-warm-800"
        ]), " "),
        :style => "padding-left: $(12 + depth * 16)px",
        Symbol("data-depth") => string(depth),
        Symbol("data-path") => entry.path,
        :onclick => onclick,
        :oncontextmenu => oncontextmenu,

        # Icon
        Svg(:class => "w-4 h-4 flex-shrink-0 $icon_color",
            :fill => "none", :viewBox => "0 0 24 24",
            :stroke => "currentColor", Symbol("stroke-width") => "2",
            Path(:d => icon_path)
        ),

        # Name
        Span(:class => "truncate", entry.name),

        # File size (for files only, on hover)
        !entry.is_directory ?
            Span(:class => "ml-auto text-[10px] text-warm-400 dark:text-warm-500 opacity-0 group-hover:opacity-100 transition-opacity",
                format_file_size(entry.size)
            ) : nothing
    )
end

# =============================================================================
# File Browser Panel
# =============================================================================

"""
    IDEFileBrowser(; entries, current_path, current_notebook_path)

Complete file browser panel for the Sessions.jl IDE sidebar.
Integrates with the WORKSPACE section in the sidebar.

Features:
- Toolbar with New Notebook, New File, New Folder, Refresh buttons
- File tree with accent-highlighted .jl files and active notebook
- Right-click context menu with file operations
- Hidden files and node_modules filtered out
- Directories sorted first, then alphabetical

Server channels used:
- navigate_directory, open_file, create_file, create_folder
- delete_item, rename_item, refresh_filebrowser
"""
function IDEFileBrowser(;
    entries::Vector{FileEntry}=FileEntry[],
    current_path::String=pwd(),
    current_notebook_path::String=""
)
    # Filter hidden files and sort: directories first, then alphabetical
    visible = filter(e -> !startswith(e.name, ".") &&
                          e.name != "node_modules" &&
                          e.name != "Manifest.toml", entries)
    sorted = sort(visible; by=e -> (!e.is_directory, lowercase(e.name)))

    # Build file tree children
    tree_children = if isempty(sorted)
        [Div(:class => "px-3 py-6 text-center",
            Div(:class => "text-warm-400 dark:text-warm-500 text-[11px]",
                "No files found"
            ),
            Div(:class => "mt-2",
                Suite.Button("New Notebook";
                    variant="ghost", size="sm",
                    class="text-[11px] text-accent-600 dark:text-accent-400",
                    kwargs=Dict(:onclick => "createNotebook()")
                )
            )
        )]
    else
        [IDEFileTreeItem(entry;
            current_notebook_path,
            depth=0
        ) for entry in sorted]
    end

    Fragment(
        # Toolbar
        IDEBrowserToolbar(),

        # Current path breadcrumb
        current_path != "" ?
            Div(:class => "px-3 py-1 text-[10px] text-warm-400 dark:text-warm-500 truncate font-mono border-b border-warm-200/50 dark:border-[#252422]/50",
                :title => current_path,
                basename(current_path)
            ) : nothing,

        # File tree
        Div(:class => "py-1",
            :id => "file-browser-tree",
            Symbol("data-current-path") => current_path,
            tree_children...
        ),

        # Context menu (positioned via JS)
        IDEFileContextMenu()
    )
end

# =============================================================================
# File Browser Script (client-side enhancements)
# =============================================================================

"""
    file_browser_script()

Client-side JS for file browser enhancements:
- createNotebook(): creates a new Pluto-format .jl file
- loaded channel handler: reloads page when notebook opens
- Filesystem polling for auto-refresh (every 5s)
"""
function file_browser_script()
    """
    <script>
    (function() {
        if (window._fileBrowserInitialized) return;
        window._fileBrowserInitialized = true;

        // Create new notebook (.jl file with Pluto header)
        window.createNotebook = function(name) {
            var filename = name || prompt('Enter notebook name:', 'notebook.jl');
            if (!filename) return;
            // Ensure .jl extension
            if (!filename.endsWith('.jl')) filename += '.jl';
            sendAction('create_notebook', { name: filename });
        };

        // Handle notebook loaded — reload to show the new notebook
        if (typeof TherapyWS !== 'undefined') {
            TherapyWS.onChannelMessage('loaded', function(data) {
                console.log('[Sessions] Notebook loaded:', data.path);
                // Reload page to render the new notebook
                window.location.reload();
            });

            // Handle file browser updates — refresh tree without full reload
            TherapyWS.onChannelMessage('filebrowser_updated', function(data) {
                // Simple approach: refresh via reload of just the sidebar
                // For now, trigger a file browser refresh
                console.log('[Sessions] File browser updated');
            });
        }

        // Filesystem polling for auto-refresh (every 10 seconds)
        var _lastRefreshTime = Date.now();
        var _pollInterval = null;

        function startFilePoll() {
            if (_pollInterval) return;
            _pollInterval = setInterval(function() {
                // Only poll if tab is visible and WS is connected
                if (document.hidden) return;
                if (typeof TherapyWS === 'undefined' || !TherapyWS.isConnected()) return;

                // Only auto-refresh if user hasn't manually refreshed recently
                if (Date.now() - _lastRefreshTime < 8000) return;

                _lastRefreshTime = Date.now();
                sendAction('refresh_filebrowser', {});
            }, 10000);
        }

        function stopFilePoll() {
            if (_pollInterval) {
                clearInterval(_pollInterval);
                _pollInterval = null;
            }
        }

        // Start polling when page loads
        startFilePoll();

        // Pause when tab hidden, resume when visible
        document.addEventListener('visibilitychange', function() {
            if (document.hidden) stopFilePoll();
            else startFilePoll();
        });

        // Track manual refreshes
        var _origRefresh = window.refreshFileBrowser;
        window.refreshFileBrowser = function() {
            _lastRefreshTime = Date.now();
            if (_origRefresh) _origRefresh();
        };
    })();
    </script>
    """
end
