# IDE/CellToolbar.jl - Cell toolbar with action buttons
#
# Floating toolbar positioned top-right of the code card.
# Appears on hover/focus with ghost icon buttons.
#
# Actions: Run, Delete, Move Up, Move Down, Fold/Unfold
#
# SESSIONS-3507: Cell toolbar (run, delete, move, fold)

import Suite

# =============================================================================
# SVG Icon Helpers
# =============================================================================

const _PLAY_ICON_PATH = "M6.3 2.841A1.5 1.5 0 004 4.11v11.78a1.5 1.5 0 002.3 1.269l9.344-5.89a1.5 1.5 0 000-2.538L6.3 2.84z"
const _DELETE_ICON_PATH = "M6 18L18 6M6 6l12 12"
const _CHEVRON_UP_PATH = "M4.5 15.75l7.5-7.5 7.5 7.5"
const _CHEVRON_DOWN_PATH = "M19.5 8.25l-7.5 7.5-7.5-7.5"
const _FOLD_PATH = "M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15"
const _UNFOLD_PATH = "M9 9V4.5M9 9H4.5M9 9L3.75 3.75M9 15v4.5M9 15H4.5M9 15l-5.25 5.25M15 9h4.5M15 9V4.5M15 9l5.25-5.25M15 15h4.5M15 15v4.5m0-4.5l5.25 5.25"

function _toolbar_icon(path::String; fill_mode::String="stroke", size::String="w-3 h-3")
    if fill_mode == "fill"
        Svg(:class => size, :fill => "currentColor", :viewBox => "0 0 20 20",
            Path(:d => path)
        )
    else
        Svg(:class => size, :fill => "none", :viewBox => "0 0 24 24",
            :stroke => "currentColor", Symbol("stroke-width") => "1.5",
            Path(:stroke_linecap => "round", :stroke_linejoin => "round", :d => path)
        )
    end
end

# =============================================================================
# Cell Toolbar Component
# =============================================================================

"""
    IDECellToolbar(cell_id::String; runtime_ms=nothing, is_folded=false)

Floating toolbar for cell actions. Positioned top-right of code card.
Appears on group-hover with ghost icon buttons.

# Actions
- **Run** (green): Execute cell (Shift+Enter)
- **Move Up**: Reorder cell up
- **Move Down**: Reorder cell down
- **Fold/Unfold**: Toggle code visibility
- **Delete** (red on hover): Delete cell with confirmation
"""
function IDECellToolbar(cell_id::String; runtime_ms=nothing, is_folded::Bool=false)
    Div(:class => "absolute top-2 right-2 z-20 flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity duration-150",

        # Runtime badge
        runtime_ms !== nothing ?
            Span(:class => "text-[9px] font-mono text-warm-400 dark:text-warm-500 mr-1",
                Symbol("data-server-signal") => "cell_runtime_$(cell_id)",
                "$(round(runtime_ms, digits=1))ms"
            ) : nothing,

        # Run button (green accent)
        Suite.Button(
            variant="ghost", size="icon",
            :class => "h-6 w-6 text-accent-600 dark:text-accent-400 hover:bg-accent-500/10",
            :on_click => "executeCell('$(cell_id)')",
            :title => "Run cell (Shift+Enter)",
            _toolbar_icon(_PLAY_ICON_PATH; fill_mode="fill", size="w-2.5 h-2.5")
        ),

        # Move up
        Suite.Button(
            variant="ghost", size="icon",
            :class => "h-6 w-6 text-warm-400 dark:text-warm-500 hover:text-warm-600 dark:hover:text-warm-400",
            :on_click => "moveCellUp('$(cell_id)')",
            :title => "Move cell up",
            _toolbar_icon(_CHEVRON_UP_PATH; size="w-3 h-3")
        ),

        # Move down
        Suite.Button(
            variant="ghost", size="icon",
            :class => "h-6 w-6 text-warm-400 dark:text-warm-500 hover:text-warm-600 dark:hover:text-warm-400",
            :on_click => "moveCellDown('$(cell_id)')",
            :title => "Move cell down",
            _toolbar_icon(_CHEVRON_DOWN_PATH; size="w-3 h-3")
        ),

        # Fold/Unfold
        Suite.Button(
            variant="ghost", size="icon",
            :class => "h-6 w-6 text-warm-400 dark:text-warm-500 hover:text-warm-600 dark:hover:text-warm-400",
            :on_click => "toggleCellFold('$(cell_id)')",
            :title => is_folded ? "Show code" : "Hide code",
            _toolbar_icon(is_folded ? _UNFOLD_PATH : _FOLD_PATH; size="w-3 h-3")
        ),

        # Delete (red on hover)
        Suite.Button(
            variant="ghost", size="icon",
            :class => "h-6 w-6 text-warm-300 dark:text-warm-600 hover:text-rose-500 dark:hover:text-rose-400",
            :on_click => "deleteCell('$(cell_id)')",
            :title => "Delete cell",
            _toolbar_icon(_DELETE_ICON_PATH; size="w-3 h-3")
        )
    )
end

# =============================================================================
# Cell Toolbar JavaScript
# =============================================================================

"""
    cell_toolbar_script()

JavaScript for cell toolbar actions: move up/down, fold/unfold.
Run and delete are already in sessions_script().
"""
function cell_toolbar_script()
    """
    // Cell toolbar actions
    window.moveCellUp = function(cellId) {
        sendAction('move_cell', { notebook_id: getNotebookId(), cell_id: cellId, direction: 'up' });
    };

    window.moveCellDown = function(cellId) {
        sendAction('move_cell', { notebook_id: getNotebookId(), cell_id: cellId, direction: 'down' });
    };

    window.toggleCellFold = function(cellId) {
        sendAction('toggle_fold', { notebook_id: getNotebookId(), cell_id: cellId });
    };
    """
end
