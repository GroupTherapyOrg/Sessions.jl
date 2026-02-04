# Sidebar.jl - Collapsible sidebar with switchable panels
#
# Implements JupyterLab-style sidebar with multiple panels:
# - Files: FileBrowser component
# - Running: List of open notebooks and terminals
# - Settings: User preferences and theme toggle
#
# SESSIONS-2201: Sidebar panel switching

using Therapy

# =============================================================================
# ICONS (SVG paths for panel icons)
# =============================================================================

# Files/folder icon
const SIDEBAR_FILES_ICON = "M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"

# Running/play icon
const SIDEBAR_RUNNING_ICON = "M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"
const SIDEBAR_RUNNING_CIRCLE = "M21 12a9 9 0 11-18 0 9 9 0 0118 0z"

# Settings/cog icon
const SIDEBAR_SETTINGS_ICON = "M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
const SIDEBAR_SETTINGS_INNER = "M15 12a3 3 0 11-6 0 3 3 0 016 0z"

# Collapse/expand chevron
const SIDEBAR_COLLAPSE_ICON = "M15 19l-7-7 7-7"
const SIDEBAR_EXPAND_ICON = "M9 5l7 7-7 7"

# Notebook icon (for running panel)
const NOTEBOOK_ICON = "M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"

# Terminal icon (for running panel)
const TERMINAL_ICON = "M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"

# Stop icon (for closing items)
const STOP_ICON = "M21 12a9 9 0 11-18 0 9 9 0 0118 0z M9 10a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1v-4z"

# =============================================================================
# SIDEBAR PANEL TYPES
# =============================================================================

@enum SidebarPanel begin
    PANEL_FILES
    PANEL_RUNNING
    PANEL_SETTINGS
end

# =============================================================================
# SIDEBAR TAB BUTTON
# =============================================================================

"""
    SidebarTabButton(; panel, icon_path, icon_circle, title, is_active)

Icon button for sidebar panel switching.
"""
function SidebarTabButton(;
    panel::SidebarPanel,
    icon_path::String,
    icon_circle::Union{String, Nothing} = nothing,
    title::String,
    is_active::Bool = false
)
    panel_name = lowercase(string(panel)[7:end])  # PANEL_FILES -> files

    Button(:class => join([
            "sidebar-tab w-10 h-10 flex items-center justify-center rounded-lg transition-all duration-200",
            is_active ? "bg-stone-200 dark:bg-neutral-700 text-stone-800 dark:text-stone-100" :
                       "text-stone-500 dark:text-stone-400 hover:bg-stone-100 dark:hover:bg-neutral-800 hover:text-stone-700 dark:hover:text-stone-200"
        ], " "),
        Symbol("data-panel") => panel_name,
        :onclick => "switchSidebarPanel('$(panel_name)')",
        :title => title,
        Svg(:class => "w-5 h-5",
            :fill => "none",
            :viewBox => "0 0 24 24",
            :stroke => "currentColor",
            Symbol("stroke-width") => "2",
            icon_circle !== nothing ? Path(:d => icon_circle) : nothing,
            Path(:d => icon_path)
        )
    )
end

# =============================================================================
# SIDEBAR TABS (Icon bar on the left)
# =============================================================================

"""
    SidebarTabs(; active_panel)

Vertical icon bar for switching between sidebar panels.
"""
function SidebarTabs(; active_panel::SidebarPanel = PANEL_FILES)
    Div(:class => "sidebar-tabs flex flex-col gap-1 py-2 px-1.5 border-r border-stone-200/60 dark:border-neutral-700/60 bg-stone-100/50 dark:bg-neutral-900/50",
        # Files panel button
        SidebarTabButton(
            panel = PANEL_FILES,
            icon_path = SIDEBAR_FILES_ICON,
            title = "Files",
            is_active = active_panel == PANEL_FILES
        ),

        # Running panel button
        SidebarTabButton(
            panel = PANEL_RUNNING,
            icon_path = SIDEBAR_RUNNING_ICON,
            icon_circle = SIDEBAR_RUNNING_CIRCLE,
            title = "Running",
            is_active = active_panel == PANEL_RUNNING
        ),

        # Settings panel button
        SidebarTabButton(
            panel = PANEL_SETTINGS,
            icon_path = SIDEBAR_SETTINGS_ICON,
            title = "Settings",
            is_active = active_panel == PANEL_SETTINGS
        ),

        # Spacer
        Div(:class => "flex-1"),

        # Collapse button
        Button(:class => "w-10 h-10 flex items-center justify-center text-stone-400 dark:text-stone-500 hover:text-stone-600 dark:hover:text-stone-300 transition-colors",
            :onclick => "toggleSidebar()",
            :title => "Collapse sidebar",
            Svg(:class => "w-4 h-4",
                :fill => "none",
                :viewBox => "0 0 24 24",
                :stroke => "currentColor",
                Symbol("stroke-width") => "2",
                Path(:d => SIDEBAR_COLLAPSE_ICON)
            )
        )
    )
end

# =============================================================================
# RUNNING PANEL
# =============================================================================

"""
    RunningItem(; id, title, type, is_active)

Single running item (notebook or terminal) in the Running panel.
"""
function RunningItem(;
    id::String,
    title::String,
    type::Symbol,  # :notebook or :terminal
    is_active::Bool = false
)
    icon_path = type == :notebook ? NOTEBOOK_ICON : TERMINAL_ICON

    Div(:class => join([
            "running-item group flex items-center gap-2 px-3 py-2 rounded cursor-pointer transition-all duration-150",
            is_active ? "bg-stone-200/70 dark:bg-neutral-700/70" :
                       "hover:bg-stone-100 dark:hover:bg-neutral-800"
        ], " "),
        Symbol("data-item-id") => id,
        Symbol("data-item-type") => string(type),
        :onclick => type == :notebook ? "switchTab('$(id)')" : "switchTerminal('$(id)')",

        # Icon
        Svg(:class => "w-4 h-4 text-stone-500 dark:text-stone-400",
            :fill => "none",
            :viewBox => "0 0 24 24",
            :stroke => "currentColor",
            Symbol("stroke-width") => "2",
            Path(:d => icon_path)
        ),

        # Title
        Span(:class => "flex-1 text-sm truncate text-stone-700 dark:text-stone-300",
            title
        ),

        # Stop/close button (appears on hover)
        Button(:class => "opacity-0 group-hover:opacity-100 p-1 rounded hover:bg-stone-300 dark:hover:bg-neutral-600 transition-opacity",
            :onclick => type == :notebook ? "event.stopPropagation(); closeTab('$(id)')" : "event.stopPropagation(); closeTerminal('$(id)')",
            :title => "Close",
            Svg(:class => "w-3 h-3 text-stone-500 dark:text-stone-400",
                :fill => "none",
                :viewBox => "0 0 24 24",
                :stroke => "currentColor",
                Symbol("stroke-width") => "2",
                Path(:d => "M6 18L18 6M6 6l12 12")
            )
        )
    )
end

"""
    RunningPanel(; notebooks, terminals, active_notebook_id)

Panel showing all running notebooks and terminals.
"""
function RunningPanel(;
    notebooks::Vector = [],
    terminals::Vector = [],
    active_notebook_id::Union{String, Nothing} = nothing
)
    has_items = !isempty(notebooks) || !isempty(terminals)

    Div(:class => "running-panel flex flex-col h-full",
        # Header
        Div(:class => "px-3 py-2 border-b border-stone-200/50 dark:border-neutral-700/50",
            H3(:class => "text-xs font-semibold text-stone-500 dark:text-stone-400 uppercase tracking-wider",
                "Running"
            )
        ),

        # Content
        Div(:class => "flex-1 overflow-y-auto py-2",
            # Notebooks section
            !isempty(notebooks) ?
                Fragment(
                    Div(:class => "px-3 py-1",
                        Span(:class => "text-xs text-stone-400 dark:text-stone-500", "NOTEBOOKS")
                    ),
                    [
                        RunningItem(
                            id = get(nb, "id", ""),
                            title = get(nb, "title", "Untitled"),
                            type = :notebook,
                            is_active = get(nb, "id", "") == active_notebook_id
                        )
                        for nb in notebooks
                    ]...
                ) : nothing,

            # Terminals section
            !isempty(terminals) ?
                Fragment(
                    Div(:class => "px-3 py-1 mt-2",
                        Span(:class => "text-xs text-stone-400 dark:text-stone-500", "TERMINALS")
                    ),
                    [
                        RunningItem(
                            id = get(t, "id", ""),
                            title = get(t, "title", "Terminal"),
                            type = :terminal,
                            is_active = false
                        )
                        for t in terminals
                    ]...
                ) : nothing,

            # Empty state
            !has_items ?
                Div(:class => "flex flex-col items-center justify-center h-32 text-stone-400 dark:text-stone-500",
                    Span(:class => "text-sm", "No running items")
                ) : nothing
        )
    )
end

# =============================================================================
# SETTINGS PANEL
# =============================================================================

"""
    SettingsPanel()

Settings panel with theme toggle and user preferences.
"""
function SettingsPanel()
    Div(:class => "settings-panel flex flex-col h-full",
        # Header
        Div(:class => "px-3 py-2 border-b border-stone-200/50 dark:border-neutral-700/50",
            H3(:class => "text-xs font-semibold text-stone-500 dark:text-stone-400 uppercase tracking-wider",
                "Settings"
            )
        ),

        # Settings list
        Div(:class => "flex-1 overflow-y-auto py-2",
            # Theme setting
            Div(:class => "px-3 py-2",
                Div(:class => "flex items-center justify-between",
                    Div(
                        Span(:class => "text-sm font-medium text-stone-700 dark:text-stone-300", "Dark Mode"),
                        P(:class => "text-xs text-stone-500 dark:text-stone-400", "Toggle dark theme")
                    ),
                    # Toggle switch
                    Button(:class => "relative w-11 h-6 rounded-full bg-stone-200 dark:bg-neutral-600 transition-colors",
                        :onclick => "toggleDarkMode()",
                        :role => "switch",
                        Symbol("aria-checked") => "false",
                        :id => "theme-toggle",
                        Span(:class => "absolute left-0.5 top-0.5 w-5 h-5 rounded-full bg-white dark:bg-neutral-300 shadow-sm transition-transform dark:translate-x-5")
                    )
                )
            ),

            # Editor font size (future)
            Div(:class => "px-3 py-2 opacity-50",
                Div(:class => "flex items-center justify-between",
                    Div(
                        Span(:class => "text-sm font-medium text-stone-700 dark:text-stone-300", "Editor Font Size"),
                        P(:class => "text-xs text-stone-500 dark:text-stone-400", "Coming soon")
                    ),
                    Span(:class => "text-sm text-stone-500", "13px")
                )
            ),

            # Auto-save (future)
            Div(:class => "px-3 py-2 opacity-50",
                Div(:class => "flex items-center justify-between",
                    Div(
                        Span(:class => "text-sm font-medium text-stone-700 dark:text-stone-300", "Auto-save"),
                        P(:class => "text-xs text-stone-500 dark:text-stone-400", "Coming soon")
                    ),
                    Span(:class => "text-sm text-stone-500", "Off")
                )
            )
        ),

        # Footer with version
        Div(:class => "px-3 py-2 border-t border-stone-200/50 dark:border-neutral-700/50",
            P(:class => "text-xs text-stone-400 dark:text-stone-500",
                "Sessions.jl v0.1.0"
            )
        )
    )
end

# =============================================================================
# SIDEBAR COMPONENT (Main container)
# =============================================================================

"""
    Sidebar(; active_panel, is_collapsed, notebooks, terminals, active_notebook_id, current_path)

Main sidebar component with switchable panels.

# Arguments
- `active_panel::SidebarPanel`: Currently active panel (PANEL_FILES, PANEL_RUNNING, PANEL_SETTINGS)
- `is_collapsed::Bool`: Whether sidebar is collapsed
- `notebooks::Vector`: List of open notebooks for Running panel
- `terminals::Vector`: List of open terminals for Running panel
- `active_notebook_id::String`: Currently active notebook ID
- `current_path::String`: Current directory path for Files panel
- `files::Vector`: Files in current directory for FileBrowser
"""
function Sidebar(;
    active_panel::SidebarPanel = PANEL_FILES,
    is_collapsed::Bool = false,
    notebooks::Vector = [],
    terminals::Vector = [],
    active_notebook_id::Union{String, Nothing} = nothing,
    current_path::String = "",
    files::Vector = []
)
    panel_name = lowercase(string(active_panel)[7:end])

    Div(:class => join([
            "sidebar flex h-full bg-stone-50 dark:bg-neutral-900 border-r border-stone-200/60 dark:border-neutral-800/60 transition-all duration-200",
            is_collapsed ? "w-12" : "w-64"
        ], " "),
        Symbol("data-sidebar-collapsed") => is_collapsed ? "true" : "false",
        Symbol("data-active-panel") => panel_name,

        # Tab icons (always visible)
        SidebarTabs(active_panel = active_panel),

        # Panel content (hidden when collapsed)
        !is_collapsed ?
            Div(:class => "flex-1 overflow-hidden",
                # Files panel
                active_panel == PANEL_FILES ?
                    Div(:class => "h-full",
                        # Use FileBrowser component here
                        # Note: FileBrowser is already included in Sessions.jl
                        FileBrowser(current_path, files)
                    ) : nothing,

                # Running panel
                active_panel == PANEL_RUNNING ?
                    RunningPanel(
                        notebooks = notebooks,
                        terminals = terminals,
                        active_notebook_id = active_notebook_id
                    ) : nothing,

                # Settings panel
                active_panel == PANEL_SETTINGS ?
                    SettingsPanel() : nothing
            ) : nothing
    )
end

# =============================================================================
# COLLAPSED SIDEBAR (Icon bar only)
# =============================================================================

"""
    CollapsedSidebar()

Minimal sidebar showing only the expand button.
"""
function CollapsedSidebar()
    Div(:class => "collapsed-sidebar flex flex-col items-center py-2 w-12 bg-stone-50 dark:bg-neutral-900 border-r border-stone-200/60 dark:border-neutral-800/60",
        # Expand button
        Button(:class => "w-10 h-10 flex items-center justify-center text-stone-400 dark:text-stone-500 hover:text-stone-600 dark:hover:text-stone-300 hover:bg-stone-100 dark:hover:bg-neutral-800 rounded-lg transition-colors",
            :onclick => "toggleSidebar()",
            :title => "Expand sidebar",
            Svg(:class => "w-4 h-4",
                :fill => "none",
                :viewBox => "0 0 24 24",
                :stroke => "currentColor",
                Symbol("stroke-width") => "2",
                Path(:d => SIDEBAR_EXPAND_ICON)
            )
        )
    )
end

# =============================================================================
# JAVASCRIPT HANDLERS
# =============================================================================

"""
    sidebar_script()

JavaScript handlers for sidebar operations.
"""
function sidebar_script()
    """
    // =====================================================================
    // Sidebar Panel Switching (SESSIONS-2201)
    // =====================================================================

    // Get saved sidebar state from localStorage
    function getSidebarState() {
        try {
            var state = localStorage.getItem('sessions-sidebar-state');
            return state ? JSON.parse(state) : { collapsed: false, panel: 'files' };
        } catch (e) {
            return { collapsed: false, panel: 'files' };
        }
    }

    // Save sidebar state to localStorage
    function saveSidebarState(state) {
        try {
            localStorage.setItem('sessions-sidebar-state', JSON.stringify(state));
        } catch (e) {}
    }

    // Toggle sidebar collapsed state
    window.toggleSidebar = function() {
        var sidebar = document.querySelector('.sidebar');
        if (!sidebar) return;

        var state = getSidebarState();
        state.collapsed = !state.collapsed;
        saveSidebarState(state);

        // Reload page to apply state (simplest approach)
        window.location.reload();
    };

    // Switch sidebar panel
    window.switchSidebarPanel = function(panelName) {
        var state = getSidebarState();
        state.panel = panelName;
        saveSidebarState(state);

        // Update tab states
        var tabs = document.querySelectorAll('.sidebar-tab');
        tabs.forEach(function(tab) {
            var isActive = tab.getAttribute('data-panel') === panelName;
            tab.classList.toggle('bg-stone-200', isActive);
            tab.classList.toggle('dark:bg-neutral-700', isActive);
            tab.classList.toggle('text-stone-800', isActive);
            tab.classList.toggle('dark:text-stone-100', isActive);
            tab.classList.toggle('text-stone-500', !isActive);
            tab.classList.toggle('dark:text-stone-400', !isActive);
        });

        // Reload to show new panel content
        window.location.reload();
    };

    // Initialize sidebar state on page load
    function initSidebar() {
        var state = getSidebarState();
        var sidebar = document.querySelector('.sidebar');
        if (sidebar) {
            sidebar.setAttribute('data-active-panel', state.panel);
            if (state.collapsed) {
                sidebar.setAttribute('data-sidebar-collapsed', 'true');
            }
        }
    }

    // Run on page load
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initSidebar);
    } else {
        initSidebar();
    }
    """
end
