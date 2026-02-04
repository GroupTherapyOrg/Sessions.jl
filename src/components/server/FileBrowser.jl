# FileBrowser.jl - File browser sidebar component (SSR)
#
# Provides filesystem navigation for Sessions.jl workspaces.
# Design: Elegant, minimal, scholarly aesthetic matching CellView.jl
#
# Architecture (per SESSIONS-2100):
# - FileBrowser: Main container with toolbar, breadcrumbs, file list
# - BrowserToolbar: New file, new folder, refresh buttons
# - Breadcrumbs: Path navigation with clickable segments
# - FileList: Scrollable file/folder list
# - FileItem: Individual file/folder row with icon
#
# Data: Uses ServerSignal "filebrowser:listing" for reactive directory updates
#
# IMPORTANT: This is an SSR component. For interactive features (like drag-drop),
# use islands pattern with Julia closures compiled to Wasm.

using Therapy

# =============================================================================
# FILE ENTRY TYPE
# =============================================================================
# Note: FileEntry is defined in server/server.jl and imported into Sessions scope.
# This component uses the shared FileEntry type for consistency.

# =============================================================================
# ICONS (SVG paths for file type icons)
# =============================================================================

# Folder icon (closed)
const FOLDER_ICON_PATH = "M2 6a2 2 0 012-2h5l2 2h5a2 2 0 012 2v6a2 2 0 01-2 2H4a2 2 0 01-2-2V6z"

# File icon (generic)
const FILE_ICON_PATH = "M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9z"

# Julia file icon (simplified .jl)
const JULIA_ICON_PATH = "M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8l-6-6zm-1 2l5 5h-5V4zm-3 9a2 2 0 100 4 2 2 0 000-4z"

# Plus icon (add)
const PLUS_ICON_PATH = "M12 4v16m8-8H4"

# Refresh icon
const REFRESH_ICON_PATH = "M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"

# Home icon
const HOME_ICON_PATH = "M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"

# Chevron right icon
const CHEVRON_RIGHT_PATH = "M9 5l7 7-7 7"

# Ellipsis (three dots) icon for context menu trigger
const ELLIPSIS_ICON_PATH = "M12 5v.01M12 12v.01M12 19v.01M12 6a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2z"

# Pencil icon for rename
const PENCIL_ICON_PATH = "M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"

# Trash icon for delete
const TRASH_ICON_PATH = "M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"

# Copy icon for copy path
const COPY_ICON_PATH = "M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3"

# Open/Document icon
const OPEN_ICON_PATH = "M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================
# Note: format_file_size is defined in server/server.jl and available in Sessions scope.

"""
Get the appropriate icon for a file entry based on its type.
"""
function get_file_icon(entry::FileEntry)
    if entry.is_directory
        return FOLDER_ICON_PATH
    elseif endswith(lowercase(entry.name), ".jl")
        return JULIA_ICON_PATH
    else
        return FILE_ICON_PATH
    end
end

# =============================================================================
# BROWSER TOOLBAR COMPONENT
# =============================================================================

"""
Toolbar with new file, new folder, and refresh buttons.
"""
function BrowserToolbar()
    Div(:class => "flex items-center gap-2 px-3 py-2 border-b border-stone-200/50 dark:border-neutral-700/50",
        # New File button
        Button(:class => "flex items-center gap-1 px-2 py-1 text-xs text-stone-500 hover:text-stone-700 dark:text-stone-400 dark:hover:text-stone-200 hover:bg-stone-100 dark:hover:bg-neutral-700 rounded transition-colors",
            :on_click => "createFile()",
            :title => "New file",
            Svg(:class => "w-4 h-4",
                :fill => "none",
                :viewBox => "0 0 24 24",
                :stroke => "currentColor",
                Symbol("stroke-width") => "1.5",
                Path(:d => PLUS_ICON_PATH)
            ),
            Span("File")
        ),
        # New Folder button
        Button(:class => "flex items-center gap-1 px-2 py-1 text-xs text-stone-500 hover:text-stone-700 dark:text-stone-400 dark:hover:text-stone-200 hover:bg-stone-100 dark:hover:bg-neutral-700 rounded transition-colors",
            :on_click => "createFolder()",
            :title => "New folder",
            Svg(:class => "w-4 h-4",
                :fill => "none",
                :viewBox => "0 0 24 24",
                :stroke => "currentColor",
                Symbol("stroke-width") => "1.5",
                Path(:d => PLUS_ICON_PATH)
            ),
            Span("Folder")
        ),
        # Spacer
        Div(:class => "flex-1"),
        # Refresh button
        Button(:class => "p-1.5 text-stone-400 hover:text-stone-600 dark:hover:text-stone-300 hover:bg-stone-100 dark:hover:bg-neutral-700 rounded transition-colors",
            :on_click => "refreshFileBrowser()",
            :title => "Refresh",
            Svg(:class => "w-4 h-4",
                :fill => "none",
                :viewBox => "0 0 24 24",
                :stroke => "currentColor",
                Symbol("stroke-width") => "1.5",
                Path(:d => REFRESH_ICON_PATH)
            )
        )
    )
end

# =============================================================================
# BREADCRUMBS COMPONENT
# =============================================================================

"""
Breadcrumb navigation showing current path with clickable segments.
"""
function Breadcrumbs(current_path::String; root_path::String = "")
    # Split path into segments
    rel_path = if !isempty(root_path) && startswith(current_path, root_path)
        current_path[length(root_path)+1:end]
    else
        current_path
    end

    # Remove leading/trailing slashes and split
    rel_path = strip(rel_path, '/')
    segments = isempty(rel_path) ? String[] : split(rel_path, '/')

    Div(:class => "flex items-center gap-1 px-3 py-2 text-xs overflow-x-auto scrollbar-thin",
        # Home button
        Button(:class => "flex items-center gap-1 px-1.5 py-0.5 text-stone-500 hover:text-stone-700 dark:text-stone-400 dark:hover:text-stone-200 hover:bg-stone-100 dark:hover:bg-neutral-700 rounded transition-colors whitespace-nowrap",
            :on_click => "navigateToDirectory('$(root_path)')",
            :title => "Home",
            Svg(:class => "w-3.5 h-3.5",
                :fill => "none",
                :viewBox => "0 0 24 24",
                :stroke => "currentColor",
                Symbol("stroke-width") => "2",
                Path(:d => HOME_ICON_PATH)
            )
        ),
        # Path segments
        [begin
            # Build path up to this segment
            segment_path = joinpath(root_path, join(segments[1:i], "/"))

            Fragment(
                # Chevron separator
                Svg(:class => "w-3 h-3 text-stone-300 dark:text-stone-600 flex-shrink-0",
                    :fill => "none",
                    :viewBox => "0 0 24 24",
                    :stroke => "currentColor",
                    Symbol("stroke-width") => "2",
                    Path(:d => CHEVRON_RIGHT_PATH)
                ),
                # Segment button
                Button(:class => "px-1.5 py-0.5 text-stone-500 hover:text-stone-700 dark:text-stone-400 dark:hover:text-stone-200 hover:bg-stone-100 dark:hover:bg-neutral-700 rounded transition-colors whitespace-nowrap max-w-[150px] truncate",
                    :on_click => "navigateToDirectory('$(segment_path)')",
                    :title => segment,
                    segment
                )
            )
        end for (i, segment) in enumerate(segments)]...
    )
end

# =============================================================================
# CONTEXT MENU COMPONENT (SESSIONS-2102)
# =============================================================================

"""
Context menu item with icon.
"""
function ContextMenuItem(;
    label::String,
    icon_path::String,
    on_click::String,
    is_danger::Bool = false,
    disabled::Bool = false
)
    base_classes = "flex items-center gap-3 w-full px-3 py-2 text-sm transition-colors"
    color_classes = if disabled
        "text-stone-300 dark:text-stone-600 cursor-not-allowed"
    elseif is_danger
        "text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20"
    else
        "text-stone-700 dark:text-stone-300 hover:bg-stone-100 dark:hover:bg-neutral-700"
    end

    Button(:class => "$base_classes $color_classes",
        :onclick => disabled ? "" : on_click,
        :disabled => disabled ? "disabled" : nothing,
        Svg(:class => "w-4 h-4 flex-shrink-0",
            :fill => "none",
            :viewBox => "0 0 24 24",
            :stroke => "currentColor",
            Symbol("stroke-width") => "1.5",
            Path(:d => icon_path)
        ),
        Span(label)
    )
end

"""
    FileContextMenu()

Hidden context menu that appears on right-click.
Positioned via JavaScript based on click coordinates.

# Menu Items
- Open (for .jl files) - Opens file as notebook
- Rename - Prompts for new name
- Delete - Confirms and deletes
- New File - Creates new file in current directory
- New Folder - Creates new folder in current directory
- Copy Path - Copies full path to clipboard
"""
function FileContextMenu()
    Div(:id => "file-context-menu",
        :class => "hidden fixed z-[100] min-w-[180px] bg-white dark:bg-neutral-800 rounded-lg shadow-xl border border-stone-200/50 dark:border-neutral-700/50 py-1 overflow-hidden",
        # Open (shown only for .jl files)
        Div(:id => "ctx-menu-open",
            ContextMenuItem(
                label = "Open",
                icon_path = OPEN_ICON_PATH,
                on_click = "contextMenuOpen()"
            )
        ),
        # Separator (shown after Open)
        Div(:id => "ctx-menu-separator-open", :class => "border-t border-stone-200/50 dark:border-neutral-700/50 my-1"),
        # Rename
        ContextMenuItem(
            label = "Rename",
            icon_path = PENCIL_ICON_PATH,
            on_click = "contextMenuRename()"
        ),
        # Delete
        ContextMenuItem(
            label = "Delete",
            icon_path = TRASH_ICON_PATH,
            on_click = "contextMenuDelete()",
            is_danger = true
        ),
        # Separator
        Div(:class => "border-t border-stone-200/50 dark:border-neutral-700/50 my-1"),
        # New File
        ContextMenuItem(
            label = "New File",
            icon_path = PLUS_ICON_PATH,
            on_click = "createFile()"
        ),
        # New Folder
        ContextMenuItem(
            label = "New Folder",
            icon_path = PLUS_ICON_PATH,
            on_click = "createFolder()"
        ),
        # Separator
        Div(:class => "border-t border-stone-200/50 dark:border-neutral-700/50 my-1"),
        # Copy Path
        ContextMenuItem(
            label = "Copy Path",
            icon_path = COPY_ICON_PATH,
            on_click = "contextMenuCopyPath()"
        )
    )
end

# =============================================================================
# FILE ITEM COMPONENT
# =============================================================================

"""
Individual file or folder row.
Double-click folders to navigate, double-click .jl files to open as notebooks.
Right-click shows context menu (SESSIONS-2102).
"""
function FileItem(entry::FileEntry)
    icon_path = get_file_icon(entry)
    icon_color = entry.is_directory ? "text-amber-500 dark:text-amber-400" :
                 endswith(lowercase(entry.name), ".jl") ? "text-purple-500 dark:text-purple-400" :
                 "text-stone-400 dark:text-stone-500"

    # Determine action: folder -> navigate, .jl file -> open notebook, other -> nothing
    action = if entry.is_directory
        "navigateToDirectory('$(entry.path)')"
    elseif endswith(lowercase(entry.name), ".jl")
        "openNotebook('$(entry.path)')"
    else
        ""  # No action for other file types yet
    end

    # Determine if this is a Julia file (for context menu Open option)
    is_julia_file = endswith(lowercase(entry.name), ".jl")

    Div(:class => "group flex items-center gap-3 px-3 py-2 hover:bg-stone-100 dark:hover:bg-neutral-800 cursor-pointer transition-colors border-b border-stone-100/50 dark:border-neutral-800/50 last:border-b-0",
        :ondblclick => action,
        :oncontextmenu => "showContextMenu(event, '$(entry.path)', $(entry.is_directory), $(is_julia_file))",
        Symbol("data-path") => entry.path,
        Symbol("data-is-directory") => string(entry.is_directory),
        Symbol("data-is-julia") => string(is_julia_file),

        # Icon
        Div(:class => "flex-shrink-0 $icon_color",
            Svg(:class => "w-5 h-5",
                :fill => entry.is_directory ? "currentColor" : "none",
                :viewBox => "0 0 24 24",
                entry.is_directory ? nothing : (:stroke => "currentColor"),
                entry.is_directory ? nothing : (Symbol("stroke-width") => "1.5"),
                Path(:d => icon_path)
            )
        ),

        # Name
        Span(:class => "flex-1 text-sm text-stone-700 dark:text-stone-300 truncate",
            :title => entry.name,
            entry.name
        ),

        # Size (hidden on hover, replaced by actions)
        Span(:class => "text-xs text-stone-400 dark:text-stone-500 group-hover:hidden",
            entry.is_directory ? "" : format_file_size(entry.size)
        ),

        # Actions (appear on hover) - ellipsis button for context menu
        Div(:class => "hidden group-hover:flex items-center gap-1",
            Button(:class => "p-1 text-stone-400 hover:text-stone-600 dark:hover:text-stone-300 hover:bg-stone-200/50 dark:hover:bg-neutral-600/50 rounded transition-colors",
                :onclick => "showContextMenu(event, '$(entry.path)', $(entry.is_directory), $(is_julia_file))",
                :title => "More options",
                Svg(:class => "w-4 h-4",
                    :fill => "none",
                    :viewBox => "0 0 24 24",
                    :stroke => "currentColor",
                    Symbol("stroke-width") => "2",
                    Path(:d => ELLIPSIS_ICON_PATH)
                )
            )
        )
    )
end

# =============================================================================
# FILE LIST COMPONENT
# =============================================================================

"""
Scrollable list of files and folders.
Empty state shown when directory is empty.
"""
function FileList(entries::Vector{FileEntry})
    # Sort: directories first, then alphabetically
    sorted = sort(entries, by = e -> (!e.is_directory, lowercase(e.name)))

    Div(:class => "flex-1 overflow-y-auto",
        Symbol("data-signal-html") => "filebrowser_listing",

        isempty(sorted) ?
            # Empty state
            Div(:class => "flex flex-col items-center justify-center h-40 text-stone-400 dark:text-stone-500",
                Svg(:class => "w-12 h-12 mb-2 opacity-50",
                    :fill => "none",
                    :viewBox => "0 0 24 24",
                    :stroke => "currentColor",
                    Symbol("stroke-width") => "1",
                    Path(:d => FOLDER_ICON_PATH)
                ),
                P(:class => "text-sm", "Empty folder")
            ) :
            # File list
            Div(:class => "divide-y divide-stone-100/50 dark:divide-neutral-800/50",
                [FileItem(entry) for entry in sorted]...
            )
    )
end

# =============================================================================
# MAIN FILE BROWSER COMPONENT
# =============================================================================

"""
    FileBrowser(; root_path, current_path, entries)

Main file browser component for Sessions.jl sidebar.

# Arguments
- `root_path::String`: Workspace root (files outside this cannot be accessed)
- `current_path::String`: Currently displayed directory
- `entries::Vector{FileEntry}`: Directory listing

# Features
- Toolbar with new file, new folder, refresh buttons
- Breadcrumb navigation with clickable path segments
- Sorted file/folder list (directories first)
- Double-click to navigate or open notebooks
- Reactive updates via ServerSignal "filebrowser:listing"

# Usage
```julia
# In Layout.jl sidebar
FileBrowser(
    root_path = workspace_dir,
    current_path = workspace_dir,
    entries = list_directory(workspace_dir)
)
```
"""
function FileBrowser(;
    root_path::String = "",
    current_path::String = root_path,
    entries::Vector{FileEntry} = FileEntry[]
)
    Fragment(
        # Main file browser container
        Div(:class => "flex flex-col h-full bg-stone-50 dark:bg-neutral-900 border-r border-stone-200/50 dark:border-neutral-700/50",
            Symbol("data-component") => "file-browser",
            Symbol("data-root-path") => root_path,
            Symbol("data-current-path") => current_path,

            # Header
            Div(:class => "flex items-center px-3 py-2 border-b border-stone-200/50 dark:border-neutral-700/50",
                Span(:class => "text-sm font-medium text-stone-600 dark:text-stone-400", "Files")
            ),

            # Toolbar
            BrowserToolbar(),

            # Breadcrumbs
            Breadcrumbs(current_path; root_path = root_path),

            # File list
            FileList(entries)
        ),

        # Context menu (positioned via JavaScript)
        FileContextMenu()
    )
end

# =============================================================================
# DIRECTORY LISTING HELPER
# =============================================================================
# Note: list_directory is defined in server/server.jl and available in Sessions scope.
# This component uses the shared function for consistency.
