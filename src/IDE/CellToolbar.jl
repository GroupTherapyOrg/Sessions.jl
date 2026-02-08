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

    window.foldAllCells = function() {
        document.querySelectorAll('.cell.group:not(.cell-folded)').forEach(function(cell) {
            var cellId = cell.getAttribute('data-cell-id') ||
                         (cell.querySelector('[data-cell-id]') || {}).getAttribute('data-cell-id');
            if (cellId) toggleCellFold(cellId);
        });
    };

    window.unfoldAllCells = function() {
        document.querySelectorAll('.cell.group.cell-folded').forEach(function(cell) {
            var cellId = cell.getAttribute('data-cell-id') ||
                         (cell.querySelector('[data-cell-id]') || {}).getAttribute('data-cell-id');
            if (cellId) toggleCellFold(cellId);
        });
    };

    // Ctrl+Shift+F to fold/unfold focused cell
    document.addEventListener('keydown', function(e) {
        if (e.ctrlKey && e.shiftKey && e.key === 'F') {
            e.preventDefault();
            var focused = document.activeElement;
            var cell = focused ? focused.closest('.cell.group') : null;
            if (cell) {
                var cellId = cell.getAttribute('data-cell-id') ||
                             (cell.querySelector('[data-cell-id]') || {}).getAttribute('data-cell-id');
                if (cellId) toggleCellFold(cellId);
            }
        }
    });

    // =====================================================================
    // Cell Drag & Drop (HTML5 API)
    // =====================================================================
    (function() {
        var draggedCellId = null;
        var dropIndicator = null;

        function getDropIndicator() {
            if (!dropIndicator) {
                dropIndicator = document.createElement('div');
                dropIndicator.className = 'cell-drop-indicator';
                dropIndicator.style.cssText = 'height:2px;background:#389826;border-radius:1px;margin:4px 0;opacity:0;transition:opacity 0.15s;pointer-events:none;';
            }
            return dropIndicator;
        }

        function getCellGroup(el) {
            return el ? el.closest('.cell.group') : null;
        }

        function getCellId(cellGroup) {
            if (!cellGroup) return null;
            return cellGroup.getAttribute('data-cell-id') ||
                   (cellGroup.querySelector('[data-cell-id]') || {}).getAttribute('data-cell-id');
        }

        // Drag start — on drag handle
        document.addEventListener('dragstart', function(e) {
            var handle = e.target.closest('[data-drag-cell]');
            if (!handle) return;
            draggedCellId = handle.getAttribute('data-drag-cell');
            var cellGroup = getCellGroup(handle);
            if (cellGroup) {
                cellGroup.style.opacity = '0.4';
                e.dataTransfer.effectAllowed = 'move';
                e.dataTransfer.setData('text/plain', draggedCellId);
            }
        });

        // Drag over — show drop indicator
        document.addEventListener('dragover', function(e) {
            if (!draggedCellId) return;
            var cellGroup = getCellGroup(e.target);
            if (!cellGroup || getCellId(cellGroup) === draggedCellId) return;
            e.preventDefault();
            e.dataTransfer.dropEffect = 'move';

            var rect = cellGroup.getBoundingClientRect();
            var midY = rect.top + rect.height / 2;
            var indicator = getDropIndicator();
            indicator.style.opacity = '1';

            if (e.clientY < midY) {
                cellGroup.parentNode.insertBefore(indicator, cellGroup);
            } else {
                cellGroup.parentNode.insertBefore(indicator, cellGroup.nextSibling);
            }
        });

        // Drag leave — hide indicator when leaving container
        document.addEventListener('dragleave', function(e) {
            if (!draggedCellId) return;
            var container = document.querySelector('.cells-container');
            if (container && !container.contains(e.relatedTarget)) {
                var indicator = getDropIndicator();
                indicator.style.opacity = '0';
            }
        });

        // Drop — reorder
        document.addEventListener('drop', function(e) {
            if (!draggedCellId) return;
            e.preventDefault();

            var indicator = getDropIndicator();
            if (indicator.parentNode) {
                // Calculate new index from indicator position
                var container = document.querySelector('.cells-container');
                if (container) {
                    var cells = Array.from(container.querySelectorAll('.cell.group'));
                    var newIndex = 0;
                    for (var i = 0; i < cells.length; i++) {
                        if (cells[i] === indicator.nextElementSibling) {
                            newIndex = i + 1;
                            break;
                        }
                        if (i === cells.length - 1) {
                            newIndex = cells.length;
                        }
                        newIndex = i + 1;
                    }
                    sendAction('move_cell', {
                        notebook_id: getNotebookId(),
                        cell_id: draggedCellId,
                        new_index: newIndex
                    });
                }
                indicator.style.opacity = '0';
                indicator.remove();
            }

            draggedCellId = null;
        });

        // Drag end — cleanup
        document.addEventListener('dragend', function(e) {
            if (!draggedCellId) return;
            // Restore opacity
            document.querySelectorAll('.cell.group').forEach(function(c) {
                c.style.opacity = '';
            });
            var indicator = getDropIndicator();
            indicator.style.opacity = '0';
            if (indicator.parentNode) indicator.remove();
            draggedCellId = null;
        });

        // Touch support — map touch events to drag events
        var touchDragCell = null;
        var touchClone = null;

        document.addEventListener('touchstart', function(e) {
            var handle = e.target.closest('[data-drag-cell]');
            if (!handle) return;
            touchDragCell = handle.getAttribute('data-drag-cell');
            var cellGroup = getCellGroup(handle);
            if (cellGroup) {
                cellGroup.style.opacity = '0.4';
                touchClone = cellGroup.cloneNode(true);
                touchClone.style.cssText = 'position:fixed;pointer-events:none;opacity:0.6;z-index:9999;width:' + cellGroup.offsetWidth + 'px;';
                document.body.appendChild(touchClone);
            }
        }, { passive: true });

        document.addEventListener('touchmove', function(e) {
            if (!touchDragCell || !touchClone) return;
            var touch = e.touches[0];
            touchClone.style.left = touch.clientX - 20 + 'px';
            touchClone.style.top = touch.clientY - 20 + 'px';

            var elementBelow = document.elementFromPoint(touch.clientX, touch.clientY);
            var cellGroup = getCellGroup(elementBelow);
            if (cellGroup && getCellId(cellGroup) !== touchDragCell) {
                var rect = cellGroup.getBoundingClientRect();
                var midY = rect.top + rect.height / 2;
                var indicator = getDropIndicator();
                indicator.style.opacity = '1';
                if (touch.clientY < midY) {
                    cellGroup.parentNode.insertBefore(indicator, cellGroup);
                } else {
                    cellGroup.parentNode.insertBefore(indicator, cellGroup.nextSibling);
                }
            }
        }, { passive: true });

        document.addEventListener('touchend', function(e) {
            if (!touchDragCell) return;
            var indicator = getDropIndicator();
            if (indicator.parentNode) {
                var container = document.querySelector('.cells-container');
                if (container) {
                    var cells = Array.from(container.querySelectorAll('.cell.group'));
                    var newIndex = cells.length;
                    for (var i = 0; i < cells.length; i++) {
                        if (cells[i] === indicator.nextElementSibling) {
                            newIndex = i + 1;
                            break;
                        }
                    }
                    sendAction('move_cell', {
                        notebook_id: getNotebookId(),
                        cell_id: touchDragCell,
                        new_index: newIndex
                    });
                }
                indicator.style.opacity = '0';
                indicator.remove();
            }

            // Cleanup
            document.querySelectorAll('.cell.group').forEach(function(c) {
                c.style.opacity = '';
            });
            if (touchClone && touchClone.parentNode) touchClone.remove();
            touchClone = null;
            touchDragCell = null;
        });
    })();
    """
end
