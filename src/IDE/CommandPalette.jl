# IDE/CommandPalette.jl - Sessions.jl IDE Command Palette
#
# Command palette (Ctrl/Cmd+P) using Suite.CommandDialog.
# Fuzzy search over all IDE commands with keyboard shortcut hints.
#
# Architecture:
# - SSR renders Suite.CommandDialog with all registered commands
# - JS handles Ctrl/Cmd+P toggle, command execution, recently used tracking
# - Commands are statically defined (extensible via pro features later)
#
# SESSIONS-3607

import Suite

# =============================================================================
# Command Palette Component
# =============================================================================

"""
    IDECommandPalette()

Command palette dialog. Opened via Ctrl/Cmd+P.
Contains all IDE commands grouped by category with keyboard shortcut hints.
"""
function IDECommandPalette()
    isMac = Sys.isapple()
    mod = isMac ? "\u2318" : "Ctrl"

    Suite.CommandDialog(
        Suite.Command(
            Suite.CommandInput(placeholder="Type a command or search..."),
            Suite.CommandList(
                Suite.CommandEmpty("No matching commands."),

                # Run commands
                Suite.CommandGroup(heading="Run",
                    _cmd_item("Run All Cells", "runAll()", "$(mod)+Shift+Enter", ["execute", "run"]),
                    _cmd_item("Run Current Cell", "_runFocusedCell()", "Shift+Enter", ["execute"]),
                    _cmd_item("Cancel Execution", "cancelExecution()", "", ["stop", "interrupt"]),
                ),

                Suite.CommandSeparator(),

                # Cell commands
                Suite.CommandGroup(heading="Cells",
                    _cmd_item("Add Cell Below", "_addCellAfterFocused()", "", ["new", "insert"]),
                    _cmd_item("Delete Cell", "_deleteFocusedCell()", "$(mod)+Shift+Delete", ["remove"]),
                    _cmd_item("Move Cell Up", "_moveFocusedCellUp()", "", ["reorder"]),
                    _cmd_item("Move Cell Down", "_moveFocusedCellDown()", "", ["reorder"]),
                    _cmd_item("Fold All Cells", "foldAllCells()", "", ["collapse", "hide"]),
                    _cmd_item("Unfold All Cells", "unfoldAllCells()", "", ["expand", "show"]),
                ),

                Suite.CommandSeparator(),

                # File commands
                Suite.CommandGroup(heading="File",
                    _cmd_item("Save Notebook", "saveNotebook()", "$(mod)+S", ["save"]),
                    _cmd_item("New Notebook", "createNewNotebook()", "$(mod)+Shift+N", ["create"]),
                    _cmd_item("Open File", "openSearch()", "$(mod)+F", ["find", "search"]),
                    _cmd_item("Export as HTML", "exportNotebook('html')", "", ["export", "download"]),
                    _cmd_item("Export as Julia Script", "exportNotebook('script')", "", ["export", "download"]),
                    _cmd_item("Export as Pluto .jl", "exportNotebook('pluto')", "", ["export", "download"]),
                ),

                Suite.CommandSeparator(),

                # View commands
                Suite.CommandGroup(heading="View",
                    _cmd_item("Toggle Terminal", "toggleTerminalPanel()", "$(mod)+\`", ["console", "shell"]),
                    _cmd_item("Toggle Sidebar", "_toggleSidebar()", "", ["panel"]),
                    _cmd_item("Toggle Theme", "_toggleDarkMode()", "", ["dark", "light", "mode"]),
                    _cmd_item("Search & Replace", "openSearch()", "$(mod)+F", ["find"]),
                    _cmd_item("Refresh Packages", "refreshPackages()", "", ["pkg"]),
                    _cmd_item("Refresh Workspace", "refreshWorkspace()", "", ["variables"]),
                ),
            )
        )
    )
end

"""
Helper to create a CommandItem with action, shortcut, and keywords.
"""
function _cmd_item(label::String, action::String, shortcut::String, keywords::Vector{String})
    Suite.CommandItem(
        Span(:class => "text-sm", label),
        shortcut != "" ? Suite.CommandShortcut(Suite.Kbd(shortcut; class="text-[10px]")) : nothing;
        value=label,
        keywords=keywords,
        kwargs=Dict(Symbol("data-action") => action)
    )
end

# =============================================================================
# Command Palette Script
# =============================================================================

"""
    command_palette_script()

Client-side JS for command palette: Ctrl/Cmd+P toggle, command execution.
"""
function command_palette_script()
    """
    <script>
    (function() {
        if (window._commandPaletteInitialized) return;
        window._commandPaletteInitialized = true;

        // Toggle command palette
        window.toggleCommandPalette = function() {
            var dialog = document.querySelector('[data-suite-command-dialog]');
            if (!dialog) return;

            var state = dialog.getAttribute('data-state');
            if (state === 'open') {
                dialog.setAttribute('data-state', 'closed');
            } else {
                dialog.setAttribute('data-state', 'open');
                // Focus the input
                var input = dialog.querySelector('[data-suite-command-input]');
                if (input) {
                    setTimeout(function() { input.focus(); input.value = ''; }, 50);
                }
            }
        };

        // Execute command when item is clicked/selected
        document.addEventListener('click', function(e) {
            var item = e.target.closest('[data-suite-command-item]');
            if (!item) return;

            var action = item.getAttribute('data-action');
            if (action) {
                // Close the palette
                var dialog = document.querySelector('[data-suite-command-dialog]');
                if (dialog) dialog.setAttribute('data-state', 'closed');

                // Execute the action
                try {
                    (new Function(action))();
                } catch (err) {
                    console.warn('[CommandPalette] Action failed:', action, err);
                }
            }
        });

        // Close on Escape inside palette
        document.addEventListener('keydown', function(e) {
            if (e.key === 'Escape') {
                var dialog = document.querySelector('[data-suite-command-dialog]');
                if (dialog && dialog.getAttribute('data-state') === 'open') {
                    e.preventDefault();
                    dialog.setAttribute('data-state', 'closed');
                }
            }
        });

        // Helper actions for command palette
        window._runFocusedCell = function() {
            var cell = getFocusedCellForPalette();
            if (cell && typeof window.executeCell === 'function') {
                window.executeCell(cell);
            }
        };

        window._deleteFocusedCell = function() {
            var cell = getFocusedCellForPalette();
            if (cell && typeof window.deleteCell === 'function') {
                window.deleteCell(cell);
            }
        };

        window._addCellAfterFocused = function() {
            var cell = getFocusedCellForPalette();
            if (typeof window.addCell === 'function') {
                window.addCell(cell || null);
            }
        };

        window._moveFocusedCellUp = function() {
            var cell = getFocusedCellForPalette();
            if (cell && typeof window.moveCellUp === 'function') {
                window.moveCellUp(cell);
            }
        };

        window._moveFocusedCellDown = function() {
            var cell = getFocusedCellForPalette();
            if (cell && typeof window.moveCellDown === 'function') {
                window.moveCellDown(cell);
            }
        };

        window._toggleSidebar = function() {
            var sidebar = document.getElementById('ide-sidebar');
            if (sidebar) sidebar.classList.toggle('hidden');
        };

        window._toggleDarkMode = function() {
            document.documentElement.classList.toggle('dark');
            // Persist via Suite theme system if available
            if (typeof Suite !== 'undefined' && Suite.setThemeMode) {
                var isDark = document.documentElement.classList.contains('dark');
                Suite.setThemeMode(isDark ? 'dark' : 'light');
            }
        };

        function getFocusedCellForPalette() {
            var el = document.activeElement;
            if (el) {
                var cellEl = el.closest('[data-cell-id]');
                if (cellEl) return cellEl.getAttribute('data-cell-id');
            }
            // Fallback: first cell
            var first = document.querySelector('[data-cell-id]');
            return first ? first.getAttribute('data-cell-id') : null;
        }
    })();
    </script>
    """
end
