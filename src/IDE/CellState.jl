# IDE/CellState.jl - Cell state management and display
#
# Defines how cells transition between states and how the UI reflects it:
# - idle (neutral), queued (amber), running (green pulse), error (red), stale (amber dot)
# - State badge using Suite.Badge
# - Running skeleton in output area
# - Error display using Suite.Alert(variant="destructive")
# - CSS for left accent bar color transitions
#
# SESSIONS-3502: Cell state management and display

import Suite

# =============================================================================
# State Badge
# =============================================================================

"""
    CellStateBadge(state::CellState)

Small badge showing current cell state using Suite.Badge.
"""
function CellStateBadge(state::CellState)
    if state == CELL_IDLE
        return nothing  # No badge for idle — clean default
    elseif state == CELL_QUEUED
        Suite.Badge(variant="secondary", :class => "text-[9px] px-1.5 py-0 bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400 border-amber-200 dark:border-amber-700",
            "Queued"
        )
    elseif state == CELL_RUNNING
        Suite.Badge(variant="secondary", :class => "text-[9px] px-1.5 py-0 bg-accent-100 dark:bg-accent-900/30 text-accent-700 dark:text-accent-400 border-accent-200 dark:border-accent-700",
            Span(:class => "inline-block w-1.5 h-1.5 rounded-full bg-accent-500 animate-pulse mr-1"),
            "Running"
        )
    elseif state == CELL_ERROR
        Suite.Badge(variant="secondary", :class => "text-[9px] px-1.5 py-0 bg-rose-100 dark:bg-rose-900/30 text-rose-700 dark:text-rose-400 border-rose-200 dark:border-rose-700",
            "Error"
        )
    elseif state == CELL_STALE
        Suite.Badge(variant="secondary", :class => "text-[9px] px-1.5 py-0 bg-amber-100 dark:bg-amber-900/30 text-amber-600 dark:text-amber-400 border-amber-200 dark:border-amber-700",
            "Stale"
        )
    else
        nothing
    end
end

# =============================================================================
# Running Skeleton
# =============================================================================

"""
    CellRunningIndicator()

Skeleton loading indicator shown in output area when cell is running.
"""
function CellRunningIndicator()
    Div(:class => "cell-running-skeleton py-3 space-y-2",
        # Animated bars
        Div(:class => "h-3 w-3/4 rounded bg-accent-500/10 animate-pulse"),
        Div(:class => "h-3 w-1/2 rounded bg-accent-500/8 animate-pulse", :style => "animation-delay: 0.2s"),
        Div(:class => "h-3 w-2/3 rounded bg-accent-500/6 animate-pulse", :style => "animation-delay: 0.4s")
    )
end

# =============================================================================
# Error Display
# =============================================================================

"""
    CellErrorDisplay(error_html::String; logs=String[])

Error output display using Suite.Alert(variant="destructive").
Shows stacktrace in a scrollable pre block.
"""
function CellErrorDisplay(error_html::String; logs::Vector{String}=String[])
    Suite.Alert(variant="destructive",
        :class => "rounded-lg",

        Suite.AlertTitle("Cell Error"),

        Suite.AlertDescription(
            # Error content
            Div(:class => "mt-2",
                Pre(:class => "text-xs font-mono overflow-x-auto max-h-[200px] overflow-y-auto p-2 rounded bg-rose-50/50 dark:bg-rose-950/30 text-rose-800 dark:text-rose-300 whitespace-pre-wrap",
                    RawHtml(error_html)
                )
            ),

            # Stderr logs (if any)
            !isempty(logs) ?
                Div(:class => "mt-2 text-[10px] font-mono text-warm-400 dark:text-warm-500",
                    [P(log) for log in logs]...
                ) : nothing
        )
    )
end

# =============================================================================
# Stale Indicator
# =============================================================================

"""
    CellStaleIndicator()

Small amber dot shown when a cell's upstream dependency has changed.
"""
function CellStaleIndicator()
    Div(:class => "flex items-center gap-1 text-[10px] font-mono text-amber-500 dark:text-amber-400",
        Span(:class => "w-1.5 h-1.5 rounded-full bg-amber-500"),
        Span("Upstream changed — re-run to update")
    )
end

# =============================================================================
# Cell State CSS
# =============================================================================

"""
    cell_state_styles()

CSS for cell state visual transitions.
- Left accent bar color changes
- Running state pulse animation
- Error state red accent
- Stale state amber indicators
"""
function cell_state_styles()
    """
    <style>
    /* Cell state transitions */
    .cell .cell-accent-bar {
        transition: background-color 0.3s ease, opacity 0.3s ease;
    }

    /* Running state — green pulse on accent bar */
    .cell.cell-running .cell-accent-bar {
        background-color: #389826 !important;
        opacity: 1 !important;
        animation: cell-accent-pulse 1.5s ease-in-out infinite;
    }

    /* Queued state — amber accent bar */
    .cell.cell-queued .cell-accent-bar {
        background-color: #f59e0b !important;
        opacity: 0.6 !important;
    }

    /* Error state — red accent bar */
    .cell.cell-error .cell-accent-bar {
        background-color: #cb3c33 !important;
        opacity: 1 !important;
    }

    /* Stale state — amber dashed accent */
    .cell.cell-stale .cell-accent-bar {
        background-color: #f59e0b !important;
        opacity: 0.4 !important;
    }

    /* Pulse animation for running cells */
    @keyframes cell-accent-pulse {
        0%, 100% { opacity: 0.4; }
        50% { opacity: 1; }
    }

    /* Running state — show skeleton, hide output */
    .cell.cell-running .cell-running-skeleton {
        display: block;
    }
    .cell:not(.cell-running) .cell-running-skeleton {
        display: none;
    }

    /* Error state — subtle red border on code card */
    .cell.cell-error [data-suite-card] {
        border-color: rgba(203, 60, 51, 0.3);
    }
    .dark .cell.cell-error [data-suite-card] {
        border-color: rgba(203, 60, 51, 0.2);
    }

    /* Queued state — subtle amber tint */
    .cell.cell-queued [data-suite-card] {
        border-color: rgba(245, 158, 11, 0.2);
    }

    /* Transition for state signal CSS class changes */
    .cell {
        transition: border-color 0.3s ease;
    }

    /* Folded state — hide code card and separator, show fold indicator */
    .cell.cell-folded .cell-code-card,
    .cell.cell-folded .cell-separator {
        display: none;
    }
    .cell.cell-folded .cell-fold-indicator {
        display: flex;
    }
    .cell:not(.cell-folded) .cell-fold-indicator {
        display: none;
    }
    </style>
    """
end
