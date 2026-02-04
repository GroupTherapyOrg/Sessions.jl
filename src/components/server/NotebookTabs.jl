# NotebookTabs.jl - Multi-notebook tab management component
#
# Implements a tab bar for managing multiple open notebooks.
# Based on JupyterLab's multi-document interface pattern.
#
# Components:
# - NotebookTabs: Main container with tab strip and controls
# - Tab: Individual tab with title, modified indicator, close button
#
# SESSIONS-2200: Multi-notebook tab management

using Therapy
using UUIDs

# =============================================================================
# Tab Component
# =============================================================================

"""
    Tab(; id, title, is_active, is_modified)

Individual notebook tab with title, modified indicator, and close button.

# Arguments
- `id::UUID`: The notebook ID
- `title::String`: Display title (filename or "Untitled")
- `is_active::Bool`: Whether this tab is currently selected
- `is_modified::Bool`: Whether the notebook has unsaved changes

# Styling
- Active tab: solid background, prominent text
- Inactive tab: subtle background, muted text
- Modified indicator: amber dot
- Close button: appears on hover
"""
function Tab(;
    id::UUID,
    title::String,
    is_active::Bool = false,
    is_modified::Bool = false
)
    id_str = string(id)

    Div(:class => join([
            "notebook-tab group relative flex items-center gap-2 px-3 py-1.5 rounded-t-lg cursor-pointer transition-all duration-200",
            is_active ? "bg-stone-100 dark:bg-neutral-800 text-stone-800 dark:text-stone-100 shadow-sm" :
                       "bg-stone-200/50 dark:bg-neutral-900/50 text-stone-500 dark:text-stone-400 hover:bg-stone-200 dark:hover:bg-neutral-800/70"
        ], " "),
        Symbol("data-tab-id") => id_str,
        Symbol("data-active") => is_active ? "true" : "false",
        :onclick => "switchTab('$(id_str)')",

        # Title with truncation
        Span(:class => "max-w-32 truncate text-sm font-medium",
            title
        ),

        # Modified indicator (amber dot)
        is_modified ? Span(:class => "w-1.5 h-1.5 rounded-full bg-amber-500 dark:bg-amber-400",
            :title => "Unsaved changes"
        ) : nothing,

        # Close button (appears on hover)
        Button(:class => "ml-1 p-0.5 rounded opacity-0 group-hover:opacity-100 hover:bg-stone-300 dark:hover:bg-neutral-700 transition-all duration-150",
            :onclick => "event.stopPropagation(); closeTab('$(id_str)')",
            :title => "Close notebook",
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

# =============================================================================
# NotebookTabs Component
# =============================================================================

"""
    NotebookTabs(notebooks; active_id=nothing)

Tab bar for managing multiple open notebooks.

# Arguments
- `notebooks::Vector`: List of notebook info dicts with keys: id, title, modified
- `active_id::Union{UUID, Nothing}`: Currently active notebook ID

# Features
- Horizontal scrolling when tabs overflow
- New notebook button (+)
- Tab click to switch
- Close button with unsaved changes prompt
- Modified indicator

# Data Flow
Uses server signals:
- `notebook_tabs` signal provides notebook list
- JavaScript handlers send channel messages for operations
"""
function NotebookTabs(notebooks::Vector; active_id::Union{UUID, String, Nothing} = nothing)
    # Normalize active_id to UUID
    resolved_active = if active_id isa String
        UUID(active_id)
    else
        active_id
    end

    # If no active specified, use first notebook
    if resolved_active === nothing && !isempty(notebooks)
        resolved_active = if haskey(notebooks[1], "id")
            notebooks[1]["id"] isa UUID ? notebooks[1]["id"] : UUID(notebooks[1]["id"])
        else
            nothing
        end
    end

    Div(:class => "notebook-tabs-container flex items-center border-b border-stone-200/60 dark:border-neutral-800/60 bg-stone-50/80 dark:bg-neutral-900/80",
        Symbol("data-active-notebook") => resolved_active !== nothing ? string(resolved_active) : "",

        # Tab strip (horizontal scrollable)
        Div(:class => "flex-1 flex items-end gap-0.5 overflow-x-auto px-2 py-1.5 scrollbar-thin scrollbar-thumb-stone-300 dark:scrollbar-thumb-neutral-700",
            # Tabs
            [
                Tab(
                    id = nb_id_from_dict(nb),
                    title = get(nb, "title", "Untitled"),
                    is_active = nb_id_from_dict(nb) == resolved_active,
                    is_modified = get(nb, "modified", false)
                )
                for nb in notebooks
            ]...
        ),

        # New notebook button
        Div(:class => "flex items-center px-2 border-l border-stone-200/40 dark:border-neutral-800/40",
            Button(:class => "p-1.5 rounded hover:bg-stone-200 dark:hover:bg-neutral-800 text-stone-500 dark:text-stone-400 transition-colors",
                :onclick => "createNewNotebook()",
                :title => "New notebook",
                Svg(:class => "w-4 h-4",
                    :fill => "none",
                    :viewBox => "0 0 24 24",
                    :stroke => "currentColor",
                    Symbol("stroke-width") => "2",
                    Path(:d => "M12 4v16m8-8H4")
                )
            )
        )
    )
end

"""
Extract UUID from notebook dict, handling both UUID and String values.
"""
function nb_id_from_dict(nb::Dict)::UUID
    id_val = get(nb, "id", nothing)
    if id_val isa UUID
        return id_val
    elseif id_val isa String
        return UUID(id_val)
    else
        error("Invalid notebook id: $id_val")
    end
end

# =============================================================================
# Empty State
# =============================================================================

"""
    EmptyTabsState()

Shown when no notebooks are open. Provides a quick way to create a new notebook.
"""
function EmptyTabsState()
    Div(:class => "flex items-center justify-center py-3 px-4 text-stone-400 dark:text-stone-500",
        Button(:class => "flex items-center gap-2 px-3 py-1.5 text-sm rounded-lg hover:bg-stone-200 dark:hover:bg-neutral-800 transition-colors",
            :onclick => "createNewNotebook()",
            Svg(:class => "w-4 h-4",
                :fill => "none",
                :viewBox => "0 0 24 24",
                :stroke => "currentColor",
                Symbol("stroke-width") => "2",
                Path(:d => "M12 4v16m8-8H4")
            ),
            Span("Create new notebook")
        )
    )
end

# =============================================================================
# JavaScript Handlers (for sessions_script())
# =============================================================================

"""
    notebook_tabs_script()

JavaScript handlers for tab operations.
Add to sessions_script() or include in head_extra.
"""
function notebook_tabs_script()
    """
    // =====================================================================
    // Notebook Tab Management
    // =====================================================================

    // Track open notebooks locally for unsaved changes prompt
    window.openNotebooks = window.openNotebooks || {};

    // Switch to a different notebook tab
    window.switchTab = function(notebookId) {
        console.log('[Tabs] Switching to notebook:', notebookId);

        // Send channel message to switch notebook
        if (typeof TherapyWS !== 'undefined' && TherapyWS.isConnected()) {
            TherapyWS.sendMessage('switch_notebook', { notebook_id: notebookId });
        }

        // Update local active state immediately for responsiveness
        updateActiveTab(notebookId);
    };

    // Close a notebook tab
    window.closeTab = function(notebookId) {
        console.log('[Tabs] Closing notebook:', notebookId);

        // Check for unsaved changes
        var tabEl = document.querySelector('[data-tab-id="' + notebookId + '"]');
        var hasUnsaved = tabEl && tabEl.querySelector('.bg-amber-500, .bg-amber-400');

        if (hasUnsaved) {
            if (!confirm('This notebook has unsaved changes. Close anyway?')) {
                return;
            }
        }

        // Send channel message to close notebook
        if (typeof TherapyWS !== 'undefined' && TherapyWS.isConnected()) {
            TherapyWS.sendMessage('close_notebook', { notebook_id: notebookId });
        }
    };

    // Create a new notebook
    window.createNewNotebook = function() {
        console.log('[Tabs] Creating new notebook');

        if (typeof TherapyWS !== 'undefined' && TherapyWS.isConnected()) {
            TherapyWS.sendMessage('create_notebook', {});
        }
    };

    // Update active tab styling
    function updateActiveTab(notebookId) {
        var tabs = document.querySelectorAll('.notebook-tab');
        tabs.forEach(function(tab) {
            var isActive = tab.getAttribute('data-tab-id') === notebookId;
            tab.setAttribute('data-active', isActive ? 'true' : 'false');

            if (isActive) {
                tab.classList.remove('bg-stone-200/50', 'dark:bg-neutral-900/50', 'text-stone-500', 'dark:text-stone-400');
                tab.classList.add('bg-stone-100', 'dark:bg-neutral-800', 'text-stone-800', 'dark:text-stone-100', 'shadow-sm');
            } else {
                tab.classList.remove('bg-stone-100', 'dark:bg-neutral-800', 'text-stone-800', 'dark:text-stone-100', 'shadow-sm');
                tab.classList.add('bg-stone-200/50', 'dark:bg-neutral-900/50', 'text-stone-500', 'dark:text-stone-400');
            }
        });

        // Update container data attribute
        var container = document.querySelector('.notebook-tabs-container');
        if (container) {
            container.setAttribute('data-active-notebook', notebookId);
        }

        // Update notebook ID for cell operations
        if (typeof setNotebookId === 'function') {
            setNotebookId(notebookId);
        }
    }

    // Listen for notebook switched events from server
    if (typeof TherapyWS !== 'undefined') {
        TherapyWS.onChannelMessage('notebook_switched', function(data) {
            console.log('[Tabs] Notebook switched:', data);
            updateActiveTab(data.notebook_id);

            // Reload page content for the new notebook
            if (typeof TherapyRouter !== 'undefined') {
                // SPA navigation to refresh content
                window.location.reload();
            }
        });

        TherapyWS.onChannelMessage('notebook_closed', function(data) {
            console.log('[Tabs] Notebook closed:', data);
            // Tab will be removed by signal update
            // If active notebook was closed, server will switch to another
        });

        TherapyWS.onChannelMessage('notebook_created', function(data) {
            console.log('[Tabs] Notebook created:', data);
            // Tab will be added by signal update
            // Server will switch to the new notebook
        });
    }
    """
end
