# IDE/Sidebar.jl - Sessions.jl IDE Sidebar (Suite.jl rewrite)
#
# Sidebar matching the SVG design reference:
# - WORKSPACE section with file browser (IDEFileBrowser from FileBrowser.jl)
# - PACKAGES section with package list
# - Sessions.jl wordmark at bottom
# - Collapsible sections (Suite.Collapsible)
# - 220px width on desktop, Suite.Sheet on mobile (handled by Layout)
#
# SESSIONS-3401, updated by SESSIONS-3600

import Suite

# =============================================================================
# SVG Icon Paths (used by both Sidebar and FileBrowser)
# =============================================================================

const _SIDEBAR_FOLDER_ICON = "M2 6a2 2 0 012-2h5l2 2h5a2 2 0 012 2v6a2 2 0 01-2 2H4a2 2 0 01-2-2V6z"
const _SIDEBAR_FILE_ICON = "M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9z"
const _SIDEBAR_JULIA_ICON = "M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8l-6-6zm-1 2l5 5h-5V4zm-3 9a2 2 0 100 4 2 2 0 000-4z"
const _SIDEBAR_PACKAGE_ICON = "M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"
const _SIDEBAR_COLLAPSE_LEFT = "M15 19l-7-7 7-7"
const _SIDEBAR_COLLAPSE_RIGHT = "M9 5l7 7-7 7"

# =============================================================================
# File Tree Section (WORKSPACE)
# =============================================================================

"""
    FileTreeSection(entries; current_notebook_path, current_path)

WORKSPACE section with Suite.Collapsible header and IDEFileBrowser content.
"""
function FileTreeSection(entries::Vector{FileEntry};
    current_notebook_path::String="",
    current_path::String=""
)
    Suite.Collapsible(open=true,
        Suite.CollapsibleTrigger(
            Div(:class => "sessions-sidebar-section-label flex items-center justify-between w-full px-3 py-1.5",
                Span(:class => "text-[11px] font-serif font-medium text-warm-500 dark:text-warm-500 uppercase tracking-[2px]",
                    "Workspace"
                ),
                # Collapse chevron handled by Suite.Collapsible
                Span(:class => "text-warm-400 dark:text-warm-500 text-[10px]",
                    "▾"
                )
            )
        ),
        Suite.CollapsibleContent(
            # File browser panel (from IDE/FileBrowser.jl)
            IDEFileBrowser(
                entries=entries,
                current_path=current_path,
                current_notebook_path=current_notebook_path
            )
        )
    )
end

# =============================================================================
# Packages Section
# =============================================================================

"""
    PackagesSection()

Packages section with Suite.Collapsible header and IDEPackagePanel content.
Package list populated via Malt worker (SESSIONS-3602).
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
            IDEPackagePanel()
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
        # File tree (WORKSPACE section with IDEFileBrowser)
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
