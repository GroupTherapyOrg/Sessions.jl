# IDE/Sidebar.jl - Sessions.jl IDE Sidebar (Suite.jl rewrite)
#
# Sidebar matching the SVG design reference:
# - WORKSPACE section with file tree (Suite.TreeView)
# - PACKAGES section with package list
# - Sessions.jl wordmark at bottom
# - Collapsible sections (Suite.Collapsible)
# - 220px width on desktop, Suite.Sheet on mobile (handled by Layout)
#
# SESSIONS-3401

import Suite

# =============================================================================
# SVG Icon Paths
# =============================================================================

const _SIDEBAR_FOLDER_ICON = "M2 6a2 2 0 012-2h5l2 2h5a2 2 0 012 2v6a2 2 0 01-2 2H4a2 2 0 01-2-2V6z"
const _SIDEBAR_FILE_ICON = "M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9z"
const _SIDEBAR_JULIA_ICON = "M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8l-6-6zm-1 2l5 5h-5V4zm-3 9a2 2 0 100 4 2 2 0 000-4z"
const _SIDEBAR_PACKAGE_ICON = "M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"
const _SIDEBAR_COLLAPSE_LEFT = "M15 19l-7-7 7-7"
const _SIDEBAR_COLLAPSE_RIGHT = "M9 5l7 7-7 7"

# =============================================================================
# File Tree Item
# =============================================================================

"""
File icon SVG based on file type.
"""
function _file_icon_svg(entry::FileEntry)
    icon_path = if entry.is_directory
        _SIDEBAR_FOLDER_ICON
    elseif endswith(lowercase(entry.name), ".jl")
        _SIDEBAR_JULIA_ICON
    else
        _SIDEBAR_FILE_ICON
    end

    icon_color = if entry.is_directory
        "text-warm-500 dark:text-warm-400"
    elseif endswith(lowercase(entry.name), ".jl")
        "text-accent-600 dark:text-accent-400"
    else
        "text-warm-400 dark:text-warm-500"
    end

    Svg(:class => "w-4 h-4 flex-shrink-0 $icon_color",
        :fill => "none", :viewBox => "0 0 24 24",
        :stroke => "currentColor", Symbol("stroke-width") => "2",
        Path(:d => icon_path)
    )
end

"""
Single file/folder item in the sidebar file tree.
Uses CSS classes from sessions-specific input.css.
"""
function SidebarFileItem(entry::FileEntry; current_notebook_path::String="", depth::Int=0)
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

    Div(:class => join(filter(!isempty, [
            "sessions-file-item group flex items-center gap-2 px-3 py-1 cursor-pointer transition-colors text-[11px] font-mono",
            is_active ? "sessions-file-active bg-accent-500/[0.08] text-accent-700 dark:text-accent-400" :
                       "text-warm-600 dark:text-warm-400 hover:bg-warm-100 dark:hover:bg-warm-800"
        ]), " "),
        :style => "padding-left: $(12 + depth * 16)px",
        Symbol("data-depth") => string(depth),
        :onclick => onclick,
        :oncontextmenu => oncontextmenu,

        # Icon
        _file_icon_svg(entry),

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
# File Tree Section
# =============================================================================

"""
    FileTreeSection(entries; current_notebook_path, current_path)

File tree section using Suite.Collapsible with WORKSPACE header.
"""
function FileTreeSection(entries::Vector{FileEntry};
    current_notebook_path::String="",
    current_path::String=""
)
    # Filter hidden files and sort: directories first, then alphabetical
    visible = filter(e -> !startswith(e.name, ".") && e.name != "node_modules", entries)
    sorted = sort(visible; by=e -> (!e.is_directory, lowercase(e.name)))

    Suite.Collapsible(open=true,
        Suite.CollapsibleTrigger(
            Div(:class => "sessions-sidebar-section-label flex items-center justify-between w-full px-3 py-1.5",
                Span(:class => "text-[11px] font-serif font-medium text-warm-500 dark:text-warm-500 uppercase tracking-[2px]",
                    "Workspace"
                ),
                # Refresh button
                Button(:class => "p-0.5 rounded text-warm-400 hover:text-warm-600 dark:hover:text-warm-400 dark:text-warm-500 transition-colors",
                    :onclick => "event.stopPropagation(); refreshFileBrowser()",
                    :title => "Refresh",
                    Svg(:class => "w-3.5 h-3.5", :fill => "none", :viewBox => "0 0 24 24",
                        :stroke => "currentColor", Symbol("stroke-width") => "2",
                        Path(:d => "M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15")
                    )
                )
            )
        ),
        Suite.CollapsibleContent(
            # Current path breadcrumb
            current_path != "" ?
                Div(:class => "px-3 py-1 text-[10px] text-warm-400 dark:text-warm-500 truncate font-mono",
                    basename(current_path)
                ) : nothing,

            # File entries
            Div(:class => "py-1",
                [SidebarFileItem(entry; current_notebook_path, depth=0) for entry in sorted]...
            )
        )
    )
end

# =============================================================================
# Packages Section
# =============================================================================

"""
    PackagesSection()

Packages section showing installed packages with version badges.
Placeholder — actual package list comes from Malt worker in future stories.
"""
function PackagesSection()
    Suite.Collapsible(open=true,
        Suite.CollapsibleTrigger(
            Div(:class => "sessions-sidebar-section-label flex items-center w-full px-3 py-1.5",
                Span(:class => "text-[11px] font-serif font-medium text-warm-500 dark:text-warm-500 uppercase tracking-[2px]",
                    "Packages"
                )
            )
        ),
        Suite.CollapsibleContent(
            Div(:class => "px-3 py-2 text-[11px] text-warm-400 dark:text-warm-500",
                "Package list available after first cell execution."
            )
        )
    )
end

# =============================================================================
# Main Sidebar Component
# =============================================================================

"""
    IDESidebar(; entries, current_path, current_notebook_path)

Complete sidebar component for the Sessions.jl IDE.

Uses Suite.Collapsible for collapsible sections, Suite.Separator between sections,
and warm-* tokens throughout. The 220px width and mobile Sheet are handled by Layout.

# Arguments
- `entries::Vector{FileEntry}`: File entries for the workspace
- `current_path::String`: Current directory path
- `current_notebook_path::String`: Path of the currently open notebook (highlighted)
"""
function IDESidebar(;
    entries::Vector{FileEntry}=FileEntry[],
    current_path::String=pwd(),
    current_notebook_path::String=""
)
    Div(:class => "flex flex-col h-full",
        # File tree
        FileTreeSection(entries;
            current_notebook_path,
            current_path
        ),

        # Separator
        Suite.Separator(),

        # Packages
        PackagesSection(),

        # Spacer
        Div(:class => "flex-1"),

        # Wordmark at bottom
        Div(:class => "p-3 border-t border-warm-200 dark:border-[#252422]",
            SessionsWordmark(class="text-sm opacity-40")
        )
    )
end
