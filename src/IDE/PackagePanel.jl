# IDE/PackagePanel.jl - Sessions.jl IDE Package Management Panel
#
# Package management panel in the sidebar PACKAGES section.
# Shows installed packages, allows add/remove/update via Malt worker.
#
# Architecture:
# - Server queries Pkg.status() via Malt worker (doesn't block notebook)
# - Results broadcast via pkg_list signal
# - Add/remove/update operations via WebSocket channels
# - Suite.jl components for UI
#
# SESSIONS-3602

import Suite

# =============================================================================
# SVG Icon Constants
# =============================================================================

const _PKG_ICON_PLUS = "M12 4v16m8-8H4"
const _PKG_ICON_TRASH = "M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
const _PKG_ICON_REFRESH = "M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
const _PKG_ICON_PACKAGE = "M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"

# =============================================================================
# Package List Item
# =============================================================================

"""
    IDEPackageItem(; name, version, is_direct)

Single package item in the packages list.
"""
function IDEPackageItem(; name::String, version::String="", is_direct::Bool=true)
    Div(:class => "group flex items-center gap-2 px-3 py-1 text-[11px] hover:bg-warm-100 dark:hover:bg-warm-800 transition-colors",
        # Package icon
        Svg(:class => "w-3.5 h-3.5 flex-shrink-0 text-accent-500 dark:text-accent-400",
            :fill => "none", :viewBox => "0 0 24 24",
            :stroke => "currentColor", Symbol("stroke-width") => "1.5",
            Path(:d => _PKG_ICON_PACKAGE)
        ),

        # Name
        Span(:class => "font-mono truncate $(is_direct ? "text-warm-700 dark:text-warm-300" : "text-warm-500 dark:text-warm-500")",
            name
        ),

        # Version badge
        version != "" ?
            Span(:class => "ml-auto text-[9px] font-mono text-warm-400 dark:text-warm-500 bg-warm-100 dark:bg-warm-800 px-1.5 py-0.5 rounded",
                "v$version"
            ) : nothing,

        # Remove button (on hover)
        is_direct ?
            Button(:class => "hidden group-hover:block ml-1 p-0.5 text-warm-400 hover:text-rose-500 dark:text-warm-500 dark:hover:text-rose-400 transition-colors",
                :onclick => "removePackage('$name')",
                :title => "Remove $name",
                Svg(:class => "w-3 h-3", :fill => "none", :viewBox => "0 0 24 24",
                    :stroke => "currentColor", Symbol("stroke-width") => "2",
                    Path(:d => "M6 18L18 6M6 6l12 12")
                )
            ) : nothing
    )
end

# =============================================================================
# Package Panel
# =============================================================================

"""
    IDEPackagePanel()

Package management panel for the sidebar PACKAGES section.
Shows installed packages, add/update controls.

Packages are loaded via the pkg_list signal (populated after first cell execution
or manual refresh).
"""
function IDEPackagePanel()
    Div(:class => "px-1",
        # Toolbar: Add + Update All + Refresh
        Div(:class => "flex items-center gap-1 px-2 py-1",
            # Add package button
            Suite.Button(
                Svg(:class => "w-3 h-3", :fill => "none", :viewBox => "0 0 24 24",
                    :stroke => "currentColor", Symbol("stroke-width") => "2",
                    Path(:d => _PKG_ICON_PLUS)
                ),
                Span(:class => "text-[10px]", "Add");
                variant="ghost", size="sm",
                class="h-5 gap-1 text-warm-500 hover:text-accent-600 dark:text-warm-400 dark:hover:text-accent-400 px-1.5",
                kwargs=Dict(:onclick => "addPackage()")
            ),

            Div(:class => "flex-1"),

            # Update all
            Suite.Button(
                Svg(:class => "w-3 h-3", :fill => "none", :viewBox => "0 0 24 24",
                    :stroke => "currentColor", Symbol("stroke-width") => "2",
                    Path(:d => _PKG_ICON_REFRESH)
                );
                variant="ghost", size="icon",
                class="h-5 w-5 text-warm-400 hover:text-warm-600 dark:text-warm-500 dark:hover:text-warm-300",
                title="Update All Packages",
                kwargs=Dict(:onclick => "updateAllPackages()")
            ),

            # Refresh list
            Suite.Button(
                Svg(:class => "w-3 h-3", :fill => "none", :viewBox => "0 0 24 24",
                    :stroke => "currentColor", Symbol("stroke-width") => "2",
                    Path(:d => _PKG_ICON_REFRESH)
                );
                variant="ghost", size="icon",
                class="h-5 w-5 text-warm-400 hover:text-warm-600 dark:text-warm-500 dark:hover:text-warm-300",
                title="Refresh Package List",
                kwargs=Dict(:onclick => "refreshPackages()")
            )
        ),

        # Package list (updated via signal)
        Div(:id => "pkg-list",
            :class => "py-1",
            # Placeholder — populated by JS when pkg_list signal updates
            Div(:class => "px-3 py-2 text-[11px] text-warm-400 dark:text-warm-500",
                :id => "pkg-list-placeholder",
                "Run a cell to load packages."
            )
        ),

        # Loading indicator (hidden by default)
        Div(:id => "pkg-loading",
            :class => "hidden px-3 py-2 text-[11px] text-warm-400 dark:text-warm-500",
            Span(:class => "animate-pulse", "Loading packages...")
        )
    )
end

# =============================================================================
# Package Panel Script
# =============================================================================

"""
    package_panel_script()

Client-side JS for package management operations.
"""
function package_panel_script()
    """
    <script>
    (function() {
        if (window._packagePanelInitialized) return;
        window._packagePanelInitialized = true;

        // Add package via prompt
        window.addPackage = function() {
            var name = prompt('Enter package name to add:');
            if (!name) return;
            showPkgLoading(true);
            sendAction('pkg_add', { name: name.trim() });
        };

        // Remove package
        window.removePackage = function(name) {
            if (!confirm('Remove package ' + name + '?')) return;
            showPkgLoading(true);
            sendAction('pkg_remove', { name: name });
        };

        // Update all packages
        window.updateAllPackages = function() {
            showPkgLoading(true);
            sendAction('pkg_update', {});
        };

        // Refresh package list
        window.refreshPackages = function() {
            showPkgLoading(true);
            sendAction('pkg_status', {});
        };

        // Show/hide loading indicator
        function showPkgLoading(show) {
            var loading = document.getElementById('pkg-loading');
            if (loading) loading.classList.toggle('hidden', !show);
        }

        // Render package list from data
        function renderPkgList(packages) {
            var container = document.getElementById('pkg-list');
            if (!container) return;

            showPkgLoading(false);

            if (!packages || packages.length === 0) {
                container.innerHTML = '<div class="px-3 py-2 text-[11px] text-warm-400 dark:text-warm-500">No packages installed.</div>';
                return;
            }

            var html = '';
            packages.forEach(function(pkg) {
                var isDirect = pkg.is_direct !== false;
                var nameClass = isDirect ? 'text-warm-700 dark:text-warm-300' : 'text-warm-500 dark:text-warm-500';
                var removeBtn = isDirect ?
                    '<button class="hidden group-hover:block ml-1 p-0.5 text-warm-400 hover:text-rose-500 dark:text-warm-500 dark:hover:text-rose-400 transition-colors" onclick="removePackage(\\'' + pkg.name + '\\')" title="Remove ' + pkg.name + '">' +
                    '<svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path d="M6 18L18 6M6 6l12 12"/></svg></button>' : '';

                html += '<div class="group flex items-center gap-2 px-3 py-1 text-[11px] hover:bg-warm-100 dark:hover:bg-warm-800 transition-colors">' +
                    '<svg class="w-3.5 h-3.5 flex-shrink-0 text-accent-500 dark:text-accent-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"/></svg>' +
                    '<span class="font-mono truncate ' + nameClass + '">' + pkg.name + '</span>';

                if (pkg.version) {
                    html += '<span class="ml-auto text-[9px] font-mono text-warm-400 dark:text-warm-500 bg-warm-100 dark:bg-warm-800 px-1.5 py-0.5 rounded">v' + pkg.version + '</span>';
                }

                html += removeBtn + '</div>';
            });

            container.innerHTML = html;
        }

        // Listen for package list updates
        if (typeof TherapyWS !== 'undefined') {
            TherapyWS.onChannelMessage('pkg_list', function(data) {
                renderPkgList(data.packages || []);
            });

            TherapyWS.onChannelMessage('pkg_error', function(data) {
                showPkgLoading(false);
                alert('Package error: ' + (data.message || 'Unknown error'));
            });

            TherapyWS.onChannelMessage('pkg_success', function(data) {
                showPkgLoading(false);
                // Auto-refresh list after successful operation
                refreshPackages();
            });
        }
    })();
    </script>
    """
end
