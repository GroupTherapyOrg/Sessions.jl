# IDE/StatusBar.jl - Bottom status bar (Suite.jl rewrite)
#
# VS Code / JupyterLab style status bar at the bottom of the IDE.
# Uses Suite.Badge for status indicators, warm-* tokens throughout.
#
# Layout:
#   ┌──────────────────┬──────────────────────┬──────────────────┐
#   │ ● Julia Ready     │  Running 3/12 cells  │  ● Connected  │
#   │ notebook.jl       │                      │  main •        │
#   └──────────────────┴──────────────────────┴──────────────────┘
#
# SESSIONS-3403: StatusBar component rewrite

import Suite

# =============================================================================
# Kernel Status Badge
# =============================================================================

"""
    IDEKernelStatus(; state)

Kernel status badge using Suite.Badge.
States: "idle" (Ready/green), "busy" (Busy/amber), "error" (Error/red), "starting" (Starting/blue)
"""
function IDEKernelStatus(; state::String="idle")
    # Dot color based on state
    dot_colors = Dict(
        "idle"     => "bg-accent-500",
        "busy"     => "bg-amber-500 animate-pulse",
        "error"    => "bg-rose-500",
        "starting" => "bg-blue-500 animate-pulse"
    )
    dot_class = get(dot_colors, state, "bg-warm-400")

    # Label text
    labels = Dict(
        "idle"     => "Julia Ready",
        "busy"     => "Julia Busy",
        "error"    => "Julia Error",
        "starting" => "Starting…"
    )
    label = get(labels, state, "Julia")

    Div(:class => "flex items-center gap-1.5 cursor-pointer hover:bg-warm-200/60 dark:hover:bg-warm-800/60 px-1.5 py-0.5 rounded transition-colors",
        :onclick => "showKernelDetails()",
        :title => "Kernel status",
        # Status dot
        Span(:class => "w-1.5 h-1.5 rounded-full flex-shrink-0 $dot_class"),
        # Label
        Span(:class => "text-[10px] font-mono text-warm-600 dark:text-warm-400",
            :data_server_signal => "kernel_status",
            label
        )
    )
end

# =============================================================================
# Notebook Path
# =============================================================================

"""
    IDENotebookPath(; path)

Shows current notebook filename in the status bar.
"""
function IDENotebookPath(; path::String="")
    display_name = if isempty(path)
        "Untitled"
    else
        basename(path)
    end

    Span(:class => "text-[10px] font-mono text-warm-400 dark:text-warm-500 truncate max-w-[200px]",
        :title => isempty(path) ? "No notebook open" : path,
        display_name
    )
end

# =============================================================================
# Cell Progress
# =============================================================================

"""
    IDECellProgress(; running, total)

Shows cell execution progress in center of status bar.
Only visible when cells are running.
"""
function IDECellProgress(; running::Int=0, total::Int=0)
    Div(:id => "ide-cell-progress",
        :class => "flex items-center gap-1.5 $(running == 0 ? "hidden" : "")",
        running > 0 ? Span(:class => "w-1.5 h-1.5 rounded-full bg-accent-500 animate-pulse flex-shrink-0") : nothing,
        running > 0 ? Span(:class => "text-[10px] font-mono text-warm-500 dark:text-warm-400",
            "Running $running/$total cells"
        ) : nothing
    )
end

# =============================================================================
# Connection Status
# =============================================================================

"""
    IDEConnectionStatus()

WebSocket connection status indicator.
JS in statusbar_ide_script() updates this in real-time.
"""
function IDEConnectionStatus()
    Div(:class => "flex items-center gap-1.5 cursor-pointer hover:bg-warm-200/60 dark:hover:bg-warm-800/60 px-1.5 py-0.5 rounded transition-colors",
        :id => "ide-ws-status",
        :onclick => "showConnectionDetails()",
        :title => "WebSocket connection status",
        # Connected dot (JS toggles between green and rose)
        Span(:id => "ide-ws-dot",
            :class => "w-1.5 h-1.5 rounded-full bg-accent-500 flex-shrink-0"
        ),
        Span(:id => "ide-ws-text",
            :class => "text-[10px] font-mono text-warm-500 dark:text-warm-400",
            "Connected"
        )
    )
end

# =============================================================================
# Git Status
# =============================================================================

"""
    IDEGitStatus(; branch, dirty)

Git branch indicator. Only shown if show_git is true.
"""
function IDEGitStatus(; branch::String="main", dirty::Bool=false)
    Div(:class => "flex items-center gap-1 cursor-pointer hover:bg-warm-200/60 dark:hover:bg-warm-800/60 px-1.5 py-0.5 rounded transition-colors",
        :onclick => "showGitDetails()",
        :title => dirty ? "Branch: $branch (uncommitted changes)" : "Branch: $branch",
        # Git branch icon (tiny)
        Svg(:class => "w-3 h-3 text-warm-400 dark:text-warm-500", :fill => "currentColor", :viewBox => "0 0 16 16",
            Path(:d => "M9.5 3.25a2.25 2.25 0 1 1 3 2.122V6A2.5 2.5 0 0 1 10 8.5H6a1 1 0 0 0-1 1v1.128a2.251 2.251 0 1 1-1.5 0V5.372a2.25 2.25 0 1 1 1.5 0v1.836A2.493 2.493 0 0 1 6 7h4a1 1 0 0 0 1-1v-.628A2.25 2.25 0 0 1 9.5 3.25Z")
        ),
        Span(:class => "text-[10px] font-mono text-warm-500 dark:text-warm-400",
            :data_server_signal => "git_branch",
            branch * (dirty ? " •" : "")
        )
    )
end

# =============================================================================
# Main StatusBar Component
# =============================================================================

"""
    IDEStatusBar(; kernel_state, notebook_path, branch, dirty, show_git, running_cells, total_cells)

Bottom status bar for the Sessions.jl IDE.

# Layout
- Left: Kernel status badge + notebook path
- Center: Cell execution progress (when running)
- Right: Connection status + git branch

# Arguments
- `kernel_state`: "idle", "busy", "error", "starting"
- `notebook_path`: Current notebook file path
- `branch`: Git branch name
- `dirty`: Uncommitted changes
- `show_git`: Show git section
- `running_cells`: Number of currently executing cells
- `total_cells`: Total cells in notebook
"""
function IDEStatusBar(;
    kernel_state::String="idle",
    notebook_path::String="",
    branch::String="main",
    dirty::Bool=false,
    show_git::Bool=true,
    running_cells::Int=0,
    total_cells::Int=0
)
    Div(:id => "ide-status-bar",
        :class => "h-6 flex items-center justify-between px-3 bg-warm-50 dark:bg-warm-950 border-t border-warm-200 dark:border-[#252422] flex-shrink-0 z-40",

        # Left: kernel + notebook path
        Div(:class => "flex items-center gap-2",
            IDEKernelStatus(state=kernel_state),
            # Separator
            Span(:class => "text-warm-200 dark:text-warm-800 text-[10px]", "│"),
            IDENotebookPath(path=notebook_path)
        ),

        # Center: cell progress (only when running)
        IDECellProgress(running=running_cells, total=total_cells),

        # Right: connection + git
        Div(:class => "flex items-center gap-2",
            IDEConnectionStatus(),
            show_git ? Span(:class => "text-warm-200 dark:text-warm-800 text-[10px]", "│") : nothing,
            show_git ? IDEGitStatus(branch=branch, dirty=dirty) : nothing
        )
    )
end

# =============================================================================
# JavaScript for Status Bar Updates
# =============================================================================

"""
    statusbar_ide_script()

JavaScript for real-time status bar updates.
Updates WebSocket connection indicator and kernel status via signals.
"""
function statusbar_ide_script()
    """
    <script>
    (function() {
        'use strict';
        if (window._statusbarIDEInitialized) return;
        window._statusbarIDEInitialized = true;

        // Kernel details dialog
        window.showKernelDetails = function() {
            var status = document.querySelector('[data-server-signal="kernel_status"]');
            alert('Kernel Status\\n\\nStatus: ' + (status ? status.textContent : 'Unknown'));
        };

        // Git details dialog
        window.showGitDetails = function() {
            var branch = document.querySelector('[data-server-signal="git_branch"]');
            alert('Git Status\\n\\nBranch: ' + (branch ? branch.textContent : 'Unknown'));
        };

        // Connection details dialog
        window.showConnectionDetails = function() {
            var connected = window.TherapyWS && window.TherapyWS.isConnected();
            alert('WebSocket Status\\n\\nConnected: ' + (connected ? 'Yes' : 'No'));
        };

        // Update WebSocket status indicator
        function updateWSStatus() {
            var dot = document.getElementById('ide-ws-dot');
            var text = document.getElementById('ide-ws-text');
            if (!dot || !text) return;

            var connected = window.TherapyWS && window.TherapyWS.isConnected();

            if (connected) {
                dot.className = 'w-1.5 h-1.5 rounded-full bg-accent-500 flex-shrink-0';
                text.textContent = 'Connected';
            } else {
                dot.className = 'w-1.5 h-1.5 rounded-full bg-rose-500 flex-shrink-0';
                text.textContent = 'Disconnected';
            }
        }

        // Listen for WebSocket events
        window.addEventListener('therapy:ws:connected', updateWSStatus);
        window.addEventListener('therapy:ws:disconnected', updateWSStatus);

        // Initial check
        setTimeout(updateWSStatus, 500);
        // Periodic fallback
        setInterval(updateWSStatus, 5000);
    })();
    </script>
    """
end
