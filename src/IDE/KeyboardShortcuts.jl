# IDE/KeyboardShortcuts.jl - Sessions.jl IDE Keyboard Shortcuts System
#
# Centralized keyboard shortcut manager. Registers all IDE-level shortcuts
# using event delegation at document level.
#
# Architecture:
# - Global shortcuts: Ctrl/Cmd+S save, Ctrl/Cmd+Shift+N new notebook,
#   Ctrl/Cmd+P command palette, Ctrl/Cmd+` terminal (already in TerminalPanel.jl)
# - Cell shortcuts: Shift+Enter run cell, Ctrl/Cmd+Enter run and advance,
#   Ctrl/Cmd+Shift+Enter run all above, Ctrl/Cmd+Delete delete cell
# - Navigation: Ctrl/Cmd+Up/Down move focus between cells,
#   Ctrl/Cmd+Home/End first/last cell
# - Platform aware: Ctrl on Windows/Linux, Cmd on macOS
# - Avoids conflicts with CodeMirror keybindings (Shift+Enter is CM-handled)
#
# SESSIONS-3603

"""
    keyboard_shortcuts_script()

Client-side JS for the centralized keyboard shortcuts system.
Platform-aware (Ctrl vs Cmd), uses event delegation at document level.
"""
function keyboard_shortcuts_script()
    """
    <script>
    (function() {
        if (window._keyboardShortcutsInitialized) return;
        window._keyboardShortcutsInitialized = true;

        var isMac = navigator.platform.toUpperCase().indexOf('MAC') >= 0;

        // Helper: check if the modifier key is pressed (Ctrl on Win/Linux, Cmd on Mac)
        function modKey(e) {
            return isMac ? e.metaKey : e.ctrlKey;
        }

        // Helper: get the cell element containing the active element
        function getFocusedCell() {
            var el = document.activeElement;
            if (!el) return null;
            return el.closest('[data-cell-id]');
        }

        // Helper: get cell ID from a cell element
        function getCellId(cellEl) {
            return cellEl ? cellEl.getAttribute('data-cell-id') : null;
        }

        // Helper: get all cell elements in DOM order
        function getAllCells() {
            return Array.from(document.querySelectorAll('[data-cell-id]'));
        }

        // Helper: focus the CodeMirror editor inside a cell
        function focusCellEditor(cellEl) {
            if (!cellEl) return;
            var cm = cellEl.querySelector('.cm-editor .cm-content');
            if (cm) {
                cm.focus();
            }
        }

        // =====================================================================
        // Global Keyboard Handler
        // =====================================================================

        document.addEventListener('keydown', function(e) {
            var mod = modKey(e);

            // -----------------------------------------------------------------
            // Global shortcuts (work anywhere)
            // -----------------------------------------------------------------

            // Ctrl/Cmd+S — Save notebook
            if (mod && !e.shiftKey && e.key === 's') {
                e.preventDefault();
                if (typeof window.saveNotebook === 'function') {
                    window.saveNotebook();
                }
                return;
            }

            // Ctrl/Cmd+Shift+N — New notebook
            if (mod && e.shiftKey && (e.key === 'N' || e.key === 'n')) {
                e.preventDefault();
                if (typeof window.createNewNotebook === 'function') {
                    window.createNewNotebook();
                }
                return;
            }

            // Ctrl/Cmd+P — Command palette (placeholder for SESSIONS-3607)
            if (mod && !e.shiftKey && e.key === 'p') {
                e.preventDefault();
                if (typeof window.toggleCommandPalette === 'function') {
                    window.toggleCommandPalette();
                }
                return;
            }

            // Note: Ctrl/Cmd+` (terminal toggle) is handled by terminal_panel_script()

            // -----------------------------------------------------------------
            // Cell shortcuts (only when a cell is focused)
            // -----------------------------------------------------------------

            var cell = getFocusedCell();
            if (!cell) return;
            var cellId = getCellId(cell);
            if (!cellId) return;

            // Ctrl/Cmd+Enter — Run cell and move to next
            if (mod && !e.shiftKey && e.key === 'Enter') {
                e.preventDefault();
                if (typeof window.executeCell === 'function') {
                    window.executeCell(cellId);
                }
                // Move focus to next cell
                var cells = getAllCells();
                var idx = cells.indexOf(cell);
                if (idx >= 0 && idx < cells.length - 1) {
                    focusCellEditor(cells[idx + 1]);
                }
                return;
            }

            // Ctrl/Cmd+Shift+Enter — Run all cells above (inclusive)
            if (mod && e.shiftKey && e.key === 'Enter') {
                e.preventDefault();
                var cells = getAllCells();
                var idx = cells.indexOf(cell);
                for (var i = 0; i <= idx; i++) {
                    var id = getCellId(cells[i]);
                    if (id && typeof window.executeCell === 'function') {
                        window.executeCell(id);
                    }
                }
                return;
            }

            // Note: Shift+Enter (run cell, stay) is handled by CodeMirror keybindings

            // Ctrl/Cmd+Delete or Ctrl/Cmd+Backspace — Delete cell
            if (mod && (e.key === 'Delete' || e.key === 'Backspace') && e.shiftKey) {
                e.preventDefault();
                if (typeof window.deleteCell === 'function') {
                    window.deleteCell(cellId);
                }
                return;
            }

            // -----------------------------------------------------------------
            // Cell navigation
            // -----------------------------------------------------------------

            // Ctrl/Cmd+ArrowUp — Focus previous cell
            if (mod && !e.shiftKey && e.key === 'ArrowUp') {
                e.preventDefault();
                var cells = getAllCells();
                var idx = cells.indexOf(cell);
                if (idx > 0) {
                    focusCellEditor(cells[idx - 1]);
                }
                return;
            }

            // Ctrl/Cmd+ArrowDown — Focus next cell
            if (mod && !e.shiftKey && e.key === 'ArrowDown') {
                e.preventDefault();
                var cells = getAllCells();
                var idx = cells.indexOf(cell);
                if (idx >= 0 && idx < cells.length - 1) {
                    focusCellEditor(cells[idx + 1]);
                }
                return;
            }

            // Ctrl/Cmd+Home — Focus first cell
            if (mod && e.key === 'Home') {
                e.preventDefault();
                var cells = getAllCells();
                if (cells.length > 0) {
                    focusCellEditor(cells[0]);
                }
                return;
            }

            // Ctrl/Cmd+End — Focus last cell
            if (mod && e.key === 'End') {
                e.preventDefault();
                var cells = getAllCells();
                if (cells.length > 0) {
                    focusCellEditor(cells[cells.length - 1]);
                }
                return;
            }
        });
    })();
    </script>
    """
end
