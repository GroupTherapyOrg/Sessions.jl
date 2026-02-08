# IDE/RunControls.jl - Sessions.jl IDE Run Controls & Progress
#
# Run controls: Run Above, Run Below, Cancel execution.
# Progress tracking: live status bar updates for running/queued cells.
# Toast notifications on completion via Suite.Toaster.
#
# Architecture:
# - Server-side: RunAllButton already in NotebookTabs.jl, Run in CellToolbar.jl
# - Client-side: run_controls_script() adds Run Above/Below JS actions,
#   progress monitoring (MutationObserver on cell states), cancel button,
#   and toast notifications on completion
#
# SESSIONS-3604

"""
    run_controls_script()

Client-side JS for run controls, progress tracking, and toast notifications.

Features:
- `runAbove(cellId)`: Execute all cells above (inclusive)
- `runBelow(cellId)`: Execute all cells below (inclusive)
- `cancelExecution()`: Cancel running cells via interrupt channel
- Progress: MutationObserver on cell class changes updates status bar
- Toast: Suite.toast.success on batch completion
"""
function run_controls_script()
    """
    <script>
    (function() {
        if (window._runControlsInitialized) return;
        window._runControlsInitialized = true;

        // =====================================================================
        // Run Above / Run Below
        // =====================================================================

        // Run all cells above and including the given cell
        window.runAbove = function(cellId) {
            var cells = Array.from(document.querySelectorAll('[data-cell-id]'));
            var found = false;
            cells.forEach(function(cell) {
                var id = cell.getAttribute('data-cell-id');
                if (!found) {
                    if (typeof window.executeCell === 'function') {
                        window.executeCell(id);
                    }
                }
                if (id === cellId) found = true;
            });
        };

        // Run all cells below and including the given cell
        window.runBelow = function(cellId) {
            var cells = Array.from(document.querySelectorAll('[data-cell-id]'));
            var found = false;
            cells.forEach(function(cell) {
                var id = cell.getAttribute('data-cell-id');
                if (id === cellId) found = true;
                if (found && typeof window.executeCell === 'function') {
                    window.executeCell(id);
                }
            });
        };

        // =====================================================================
        // Cancel Execution
        // =====================================================================

        window.cancelExecution = function() {
            if (typeof window.sendAction === 'function') {
                sendAction('interrupt', { notebook_id: getNotebookId() });
            }
        };

        // =====================================================================
        // Progress Tracking
        // =====================================================================

        var _lastRunningCount = 0;
        var _batchStarted = false;

        function updateRunProgress() {
            var cells = document.querySelectorAll('[data-cell-id]');
            var total = cells.length;
            var running = 0;
            var queued = 0;

            cells.forEach(function(cell) {
                if (cell.classList.contains('cell-running')) running++;
                if (cell.classList.contains('cell-queued')) queued++;
            });

            var activeCount = running + queued;

            // Update status bar progress
            var progressEl = document.getElementById('ide-cell-progress');
            if (progressEl) {
                if (activeCount > 0) {
                    progressEl.innerHTML =
                        '<span class="w-1.5 h-1.5 rounded-full bg-accent-500 animate-pulse flex-shrink-0"></span>' +
                        '<span class="text-[10px] font-mono text-warm-500 dark:text-warm-400">Running ' + (running) + '/' + total + ' cells</span>';
                    progressEl.classList.remove('hidden');
                } else {
                    progressEl.innerHTML = '';
                    progressEl.classList.add('hidden');
                }
            }

            // Update Run All button indicator
            var runAllDot = document.getElementById('run-all-indicator');
            if (runAllDot) {
                if (activeCount > 0) {
                    runAllDot.classList.remove('hidden');
                } else {
                    runAllDot.classList.add('hidden');
                }
            }

            // Toast on completion
            if (_batchStarted && activeCount === 0 && _lastRunningCount > 0) {
                _batchStarted = false;
                if (typeof Suite !== 'undefined' && Suite.toast) {
                    Suite.toast.success('All cells executed');
                }
            }

            if (activeCount > 0) {
                _batchStarted = true;
            }

            _lastRunningCount = activeCount;
        }

        // Watch for class changes on cell elements (cell-running, cell-queued)
        var observer = new MutationObserver(function(mutations) {
            var relevant = false;
            mutations.forEach(function(m) {
                if (m.type === 'attributes' && m.attributeName === 'class') {
                    relevant = true;
                }
            });
            if (relevant) updateRunProgress();
        });

        // Observe the cells container
        function startObserving() {
            var container = document.getElementById('cells-container') ||
                            document.querySelector('.cells-container') ||
                            document.body;
            observer.observe(container, {
                attributes: true,
                attributeFilter: ['class'],
                subtree: true
            });
        }

        // Initial setup
        setTimeout(function() {
            startObserving();
            updateRunProgress();
        }, 500);
    })();
    </script>
    """
end
