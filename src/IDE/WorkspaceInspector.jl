# IDE/WorkspaceInspector.jl - Sessions.jl IDE Workspace Inspector
#
# Sidebar panel showing defined variables in the notebook workspace.
# Shows name, type, and size for each variable.
#
# Architecture:
# - Server queries workspace via Malt worker after each cell execution
# - Results broadcast via workspace_vars channel
# - Client-side JS renders variable list with Suite.Collapsible groups
# - Auto-updates after each cell execution
# - Filterable via search input
#
# SESSIONS-3606

import Suite

# =============================================================================
# Workspace Inspector Panel
# =============================================================================

"""
    IDEWorkspaceInspector()

Workspace inspector panel for the sidebar.
Shows defined variables, types, sizes. Updated via JS after cell execution.
"""
function IDEWorkspaceInspector()
    Div(:class => "px-1",
        # Filter input
        Div(:class => "px-2 py-1",
            Input(:id => "workspace-filter",
                :type => "text",
                :class => "w-full bg-warm-100 dark:bg-warm-900 border border-warm-200 dark:border-warm-700 rounded px-2 py-0.5 text-[10px] font-mono text-warm-600 dark:text-warm-400 placeholder:text-warm-400 dark:placeholder:text-warm-600 focus:outline-none focus:ring-1 focus:ring-accent-500",
                :placeholder => "Filter variables...",
                :oninput => "filterWorkspaceVars(this.value)"
            )
        ),

        # Variables list (populated by JS)
        Div(:id => "workspace-vars",
            :class => "py-1",
            Div(:class => "px-3 py-2 text-[11px] text-warm-400 dark:text-warm-500",
                :id => "workspace-placeholder",
                "Run a cell to inspect workspace."
            )
        ),

        # Refresh button
        Div(:class => "px-2 py-1",
            Suite.Button(
                Span(:class => "text-[10px]", "Refresh");
                variant="ghost", size="sm",
                class="h-5 w-full text-warm-400 hover:text-warm-600 dark:text-warm-500 dark:hover:text-warm-300",
                kwargs=Dict(:onclick => "refreshWorkspace()")
            )
        )
    )
end

# =============================================================================
# Workspace Inspector Script
# =============================================================================

"""
    workspace_inspector_script()

Client-side JS for workspace variable display, filtering, and auto-refresh.
"""
function workspace_inspector_script()
    """
    <script>
    (function() {
        if (window._workspaceInspectorInitialized) return;
        window._workspaceInspectorInitialized = true;

        var _workspaceVars = [];

        // Request workspace variables from server
        window.refreshWorkspace = function() {
            if (typeof sendAction === 'function') {
                sendAction('workspace_vars', { notebook_id: getNotebookId() });
            }
        };

        // Filter variables
        window.filterWorkspaceVars = function(query) {
            renderWorkspaceVars(_workspaceVars, query);
        };

        // Render variable list
        function renderWorkspaceVars(vars, filter) {
            var container = document.getElementById('workspace-vars');
            if (!container) return;

            filter = (filter || '').toLowerCase();

            var filtered = vars.filter(function(v) {
                return !filter || v.name.toLowerCase().indexOf(filter) >= 0 || v.type.toLowerCase().indexOf(filter) >= 0;
            });

            if (filtered.length === 0 && vars.length === 0) {
                container.innerHTML = '<div class="px-3 py-2 text-[11px] text-warm-400 dark:text-warm-500">No variables defined.</div>';
                return;
            }

            if (filtered.length === 0) {
                container.innerHTML = '<div class="px-3 py-2 text-[11px] text-warm-400 dark:text-warm-500">No matches.</div>';
                return;
            }

            var html = '';
            filtered.forEach(function(v) {
                var typeColor = 'text-warm-500 dark:text-warm-500';
                if (v.type.indexOf('Int') >= 0 || v.type.indexOf('Float') >= 0) {
                    typeColor = 'text-blue-500 dark:text-blue-400';
                } else if (v.type === 'String') {
                    typeColor = 'text-rose-500 dark:text-rose-400';
                } else if (v.type === 'Bool') {
                    typeColor = 'text-purple-500 dark:text-purple-400';
                } else if (v.type.indexOf('Array') >= 0 || v.type.indexOf('Vector') >= 0 || v.type.indexOf('Matrix') >= 0) {
                    typeColor = 'text-accent-600 dark:text-accent-400';
                }

                html += '<div class="group flex items-center gap-2 px-3 py-0.5 text-[11px] hover:bg-warm-100 dark:hover:bg-warm-800 transition-colors cursor-default">';
                html += '<span class="font-mono font-medium text-warm-700 dark:text-warm-300 truncate">' + escapeHtml(v.name) + '</span>';
                html += '<span class="ml-auto text-[9px] font-mono ' + typeColor + ' truncate">' + escapeHtml(v.type) + '</span>';

                if (v.size) {
                    html += '<span class="text-[9px] font-mono text-warm-400 dark:text-warm-600">' + escapeHtml(v.size) + '</span>';
                }

                html += '</div>';
            });

            container.innerHTML = html;
        }

        function escapeHtml(str) {
            var div = document.createElement('div');
            div.textContent = str;
            return div.innerHTML;
        }

        // Listen for workspace variable updates
        if (typeof TherapyWS !== 'undefined') {
            TherapyWS.onChannelMessage('workspace_vars', function(data) {
                _workspaceVars = data.variables || [];
                var filterInput = document.getElementById('workspace-filter');
                var filter = filterInput ? filterInput.value : '';
                renderWorkspaceVars(_workspaceVars, filter);
            });
        }

        // Auto-refresh after cell execution completes
        if (typeof TherapyWS !== 'undefined') {
            TherapyWS.onChannelMessage('cell_output', function(data) {
                // Small delay to let execution complete
                setTimeout(refreshWorkspace, 300);
            });
        }
    })();
    </script>
    """
end
