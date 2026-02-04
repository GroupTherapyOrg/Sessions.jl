# StatusBar.jl - Bottom status bar showing kernel, git, and connection status
#
# SESSIONS-2203: StatusBar with kernel info
#
# Components:
# - StatusBar: Main container (bottom bar)
# - KernelStatus: Julia kernel state (idle/busy/error)
# - GitStatus: Git branch name and dirty indicator
# - ConnectionStatus: WebSocket connection state
#
# Design:
# - Compact, unobtrusive (like VS Code/JupyterLab status bar)
# - Real-time updates via Therapy.jl signals
# - Click for more details

using Therapy

# ═══════════════════════════════════════════════════════════════════════════════
# SVG Icon Paths
# ═══════════════════════════════════════════════════════════════════════════════

const STATUS_ICON_KERNEL = "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z"  # Circle outline for kernel
const STATUS_ICON_KERNEL_BUSY = "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"  # Filled circle for busy
const STATUS_ICON_GIT = "M2.6 10.59L8.38 4.8l1.69 1.7c-.24.85.15 1.78.93 2.23v5.54c-.6.34-1 .99-1 1.73 0 1.1.9 2 2 2s2-.9 2-2c0-.74-.4-1.39-1-1.73V9.41l2.07 2.09c-.07.15-.07.32-.07.5 0 1.1.9 2 2 2s2-.9 2-2-.9-2-2-2c-.18 0-.35 0-.5.07L12.93 7.5c.19-.69.05-1.44-.48-1.97-.59-.59-1.5-.72-2.25-.39L8.5 3.43l.89-.89c.39-.39.39-1.02 0-1.41-.39-.39-1.02-.39-1.41 0l-6.59 6.59c-.39.39-.39 1.02 0 1.41.39.39 1.02.39 1.41 0l.89-.89-.09.35z"  # Git branch icon
const STATUS_ICON_CONNECTED = "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"  # Checkmark circle
const STATUS_ICON_DISCONNECTED = "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"  # Warning circle
const STATUS_ICON_JULIA = "M14.75 2H9.25C9.11 2 9 2.11 9 2.25v.5c0 .14.11.25.25.25h.25v8H9c-.41 0-.75.34-.75.75v.5c0 .41.34.75.75.75h6c.41 0 .75-.34.75-.75v-.5c0-.41-.34-.75-.75-.75h-.5V3h.25c.14 0 .25-.11.25-.25v-.5c0-.14-.11-.25-.25-.25z"  # Julia logo simplified

# ═══════════════════════════════════════════════════════════════════════════════
# Helper Components
# ═══════════════════════════════════════════════════════════════════════════════

"""
SVG icon with consistent styling for status bar.
"""
function StatusIcon(path::String; class="")
    Svg(:viewBox => "0 0 24 24",
        :class => "w-3.5 h-3.5 " * class,
        :fill => "currentColor",
        Path(:d => path)
    )
end

"""
Status bar item wrapper with hover effect.
"""
function StatusItem(children...; onclick="", class="", title="")
    base_class = "flex items-center gap-1.5 px-2 py-0.5 text-xs font-mono rounded hover:bg-stone-200/80 dark:hover:bg-neutral-700/80 cursor-pointer transition-colors"

    full_class = base_class * " " * class

    if !isempty(onclick) && !isempty(title)
        Div(:class => full_class, :on_click => onclick, :title => title, children...)
    elseif !isempty(onclick)
        Div(:class => full_class, :on_click => onclick, children...)
    elseif !isempty(title)
        Div(:class => full_class, :title => title, children...)
    else
        Div(:class => full_class, children...)
    end
end

# ═══════════════════════════════════════════════════════════════════════════════
# Kernel Status Component
# ═══════════════════════════════════════════════════════════════════════════════

"""
KernelStatus shows the Julia kernel state (idle/busy/error).
Uses Therapy.jl signals for real-time updates.
"""
function KernelStatus(; kernel_state="idle")
    # Color based on state
    state_colors = Dict(
        "idle" => "text-emerald-600 dark:text-emerald-400",
        "busy" => "text-amber-600 dark:text-amber-400",
        "error" => "text-rose-600 dark:text-rose-400",
        "starting" => "text-sky-600 dark:text-sky-400"
    )
    color = get(state_colors, kernel_state, "text-stone-500 dark:text-stone-400")

    # Icon based on state
    icon_path = kernel_state == "busy" ? STATUS_ICON_KERNEL_BUSY : STATUS_ICON_KERNEL

    # Status text
    state_text = Dict(
        "idle" => "Julia Ready",
        "busy" => "Julia Busy",
        "error" => "Julia Error",
        "starting" => "Julia Starting..."
    )
    text = get(state_text, kernel_state, "Julia")

    StatusItem(
        StatusIcon(icon_path; class=color),
        Span(:data_server_signal => "kernel_status",
             :class => color,
             text
        );
        onclick = "showKernelDetails()",
        title = "Kernel status - click for details"
    )
end

# ═══════════════════════════════════════════════════════════════════════════════
# Git Status Component
# ═══════════════════════════════════════════════════════════════════════════════

"""
GitStatus shows the current git branch and dirty state.
Only shown when in a git repository.
"""
function GitStatus(; branch="main", dirty=false, show_git=true)
    if !show_git
        return nothing
    end

    dirty_indicator = dirty ? " •" : ""
    color = dirty ? "text-amber-600 dark:text-amber-400" : "text-stone-600 dark:text-stone-400"

    StatusItem(
        StatusIcon(STATUS_ICON_GIT; class="text-stone-500 dark:text-stone-400"),
        Span(:data_server_signal => "git_branch",
             :class => color,
             branch * dirty_indicator
        );
        onclick = "showGitDetails()",
        title = dirty ? "Branch: $branch (uncommitted changes)" : "Branch: $branch"
    )
end

# ═══════════════════════════════════════════════════════════════════════════════
# Connection Status Component
# ═══════════════════════════════════════════════════════════════════════════════

"""
ConnectionStatus shows the WebSocket connection state.
Updates automatically via Therapy.jl client-side JS.
"""
function ConnectionStatus()
    # Default state (JS will update based on actual connection)
    StatusItem(
        Span(:id => "ws-status-icon",
             :class => "text-emerald-500 dark:text-emerald-400",
             StatusIcon(STATUS_ICON_CONNECTED)
        ),
        Span(:id => "ws-status-text",
             :class => "text-stone-600 dark:text-stone-400",
             "Connected"
        );
        onclick = "showConnectionDetails()",
        title = "WebSocket connection status"
    )
end

# ═══════════════════════════════════════════════════════════════════════════════
# Main StatusBar Component
# ═══════════════════════════════════════════════════════════════════════════════

"""
    StatusBar(; kernel_state="idle", branch="main", dirty=false, show_git=true)

Bottom status bar showing kernel, git, and connection status.
JupyterLab/VS Code style with real-time updates.

# Arguments
- `kernel_state`: Current kernel state ("idle", "busy", "error", "starting")
- `branch`: Current git branch name
- `dirty`: Whether there are uncommitted changes
- `show_git`: Whether to show git status

# Example
```julia
StatusBar(kernel_state="busy", branch="feature-x", dirty=true)
```
"""
function StatusBar(; kernel_state="idle", branch="main", dirty=false, show_git=true)
    # Status bar with left and right sections
    Div(:id => "status-bar",
        :class => "fixed bottom-0 left-0 right-0 h-6 bg-stone-200/90 dark:bg-neutral-800/90 backdrop-blur-sm border-t border-stone-300/60 dark:border-neutral-700/60 flex items-center justify-between px-2 z-40 text-stone-600 dark:text-stone-400 transition-colors duration-200",

        # Left section: Kernel status + Connection
        Div(:class => "flex items-center gap-1",
            KernelStatus(; kernel_state),
            # Separator
            Span(:class => "text-stone-300 dark:text-neutral-600 mx-1", "|"),
            ConnectionStatus()
        ),

        # Right section: Git status + Version
        Div(:class => "flex items-center gap-1",
            GitStatus(; branch, dirty, show_git),
            # Separator (only if git shown)
            show_git ? Span(:class => "text-stone-300 dark:text-neutral-600 mx-1", "|") : nothing,
            # Version/info
            StatusItem(
                Span(:class => "text-stone-500 dark:text-stone-500",
                     "Sessions.jl"
                );
                onclick = "showAbout()",
                title = "Sessions.jl - Reactive Julia Notebooks"
            )
        )
    )
end

# ═══════════════════════════════════════════════════════════════════════════════
# JavaScript Handlers (to be added to sessions_script)
# ═══════════════════════════════════════════════════════════════════════════════

"""
JavaScript for status bar interactions and real-time updates.
"""
function statusbar_script()
    """
    <script>
    // Status bar interaction handlers
    window.showKernelDetails = function() {
        console.log('[Sessions] Kernel details clicked');
        // TODO: Show kernel details modal
        alert('Kernel Status:\\n\\nJulia version: ' + (window.JULIA_VERSION || 'Unknown') + '\\nStatus: ' + (document.querySelector('[data-server-signal="kernel_status"]')?.textContent || 'Unknown'));
    };

    window.showGitDetails = function() {
        console.log('[Sessions] Git details clicked');
        // TODO: Show git details modal
        const branch = document.querySelector('[data-server-signal="git_branch"]')?.textContent || 'Unknown';
        alert('Git Status:\\n\\nBranch: ' + branch);
    };

    window.showConnectionDetails = function() {
        console.log('[Sessions] Connection details clicked');
        const connected = window.TherapyWS && window.TherapyWS.isConnected();
        const connId = connected && window.TherapyWS.getConnectionId ? window.TherapyWS.getConnectionId() : 'N/A';
        alert('WebSocket Status:\\n\\nConnected: ' + (connected ? 'Yes' : 'No') + '\\nConnection ID: ' + connId);
    };

    window.showAbout = function() {
        console.log('[Sessions] About clicked');
        alert('Sessions.jl\\n\\nA reactive notebook IDE built with Therapy.jl\\n\\nhttps://github.com/TherapeuticJulia/Sessions.jl');
    };

    // Update WebSocket status indicator
    function updateWSStatus() {
        const icon = document.getElementById('ws-status-icon');
        const text = document.getElementById('ws-status-text');
        if (!icon || !text) return;

        const connected = window.TherapyWS && window.TherapyWS.isConnected();

        if (connected) {
            icon.innerHTML = '<svg viewBox="0 0 24 24" class="w-3.5 h-3.5 text-emerald-500 dark:text-emerald-400" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>';
            text.textContent = 'Connected';
            text.className = 'text-stone-600 dark:text-stone-400';
        } else {
            icon.innerHTML = '<svg viewBox="0 0 24 24" class="w-3.5 h-3.5 text-rose-500 dark:text-rose-400" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/></svg>';
            text.textContent = 'Disconnected';
            text.className = 'text-rose-600 dark:text-rose-400';
        }
    }

    // Listen for WebSocket events
    window.addEventListener('therapy:ws:connected', updateWSStatus);
    window.addEventListener('therapy:ws:disconnected', updateWSStatus);

    // Initial check after a short delay
    setTimeout(updateWSStatus, 500);

    // Periodic check (in case events are missed)
    setInterval(updateWSStatus, 5000);
    </script>
    """
end

export StatusBar, KernelStatus, GitStatus, ConnectionStatus, statusbar_script
