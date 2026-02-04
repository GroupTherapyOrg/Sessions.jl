# Layout.jl - Main application layout (SSR component)
#
# The root layout component for Sessions, wrapping all pages.
# Theme: Therapy.jl clean styling with Pluto.jl reactive accents
#
# Design Philosophy:
# - Pure Tailwind CSS (no custom CSS variables)
# - font-serif for headings (scholarly/calligraphy aesthetic like Therapy.jl)
# - Pluto.jl blue accent instead of Therapy.jl emerald
# - Clean, minimal, professional

using Therapy

# Import the DarkModeToggle from islands
# Note: The SSR version uses onclick, island version for future Wasm

"""
Head content for Sessions - fonts, Tailwind config, CodeMirror.
Uses ONLY Tailwind for styling (no custom CSS).
"""
function sessions_styles()
    """
    <!-- BLOCKING: Set dark mode BEFORE content renders to prevent flicker -->
    <script>
    (function() {
        var saved = localStorage.getItem('sessions-dark-mode');
        if (saved === 'true' || (!saved && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
            document.documentElement.classList.add('dark');
        }
    })();
    </script>

    <!-- Google Fonts: Serif for headings (calligraphy), Mono for code -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Crimson+Pro:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">

    <!-- Tailwind CSS with Pluto.jl color config -->
    <!-- Note: Using CDN for development. For production, use Tailwind CLI build. -->
    <script src="https://cdn.tailwindcss.com?plugins=typography"></script>
    <script>
    // Suppress Tailwind CDN console warning (we know this is dev mode)
    if (typeof console !== 'undefined') {
        const origWarn = console.warn;
        console.warn = function(...args) {
            if (args[0] && typeof args[0] === 'string' && args[0].includes('cdn.tailwindcss.com')) return;
            origWarn.apply(console, args);
        };
    }
    tailwind.config = {
        darkMode: 'class',
        theme: {
            extend: {
                colors: {
                    // Pluto.jl color palette
                    pluto: {
                        blue: '#375bbd',
                        'blue-light': '#5e7ad3',
                        purple: '#815ba4',
                        green: '#48b685',
                        orange: '#f99b15',
                        cyan: '#00a9d1',
                        pink: '#cc80ac',
                    }
                },
                fontFamily: {
                    // Crimson Pro for calligraphy/scholarly headings
                    serif: ['Crimson Pro', 'Georgia', 'serif'],
                    // Inter for clean UI text
                    sans: ['Inter', '-apple-system', 'BlinkMacSystemFont', 'sans-serif'],
                    // JetBrains Mono for code
                    mono: ['JetBrains Mono', 'Fira Code', 'monospace'],
                }
            }
        }
    }
    </script>

    <!-- CodeMirror 6 via Pluto's pre-bundled setup (includes all deps) -->
    <script type="importmap">
    {
        "imports": {
            "codemirror-pluto": "https://cdn.jsdelivr.net/gh/JuliaPluto/codemirror-pluto-setup@0.19.3/dist/index.es.min.js"
        }
    }
    </script>

    <!-- xterm.js for terminal emulation -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.css">
    <script src="https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.8.0/lib/xterm-addon-fit.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/xterm-addon-web-links@0.9.0/lib/xterm-addon-web-links.min.js"></script>

    <!-- Elegant parchment-inspired styling -->
    <style>
    /* ═══════════════════════════════════════════════════════════════════
       CodeMirror - Scholarly, elegant like writing with a quill
       ═══════════════════════════════════════════════════════════════════ */
    .cm-editor {
        font-family: 'JetBrains Mono', monospace;
        font-size: 13px;
        line-height: 1.75;
        background: transparent;
        min-height: 48px;
    }
    .cm-editor.cm-focused { outline: none; }
    .cm-scroller { padding: 20px 24px; }
    .cm-content {
        caret-color: #8b5a2b;
        background: transparent;
    }
    .cm-cursor {
        border-left: 1.5px solid #8b5a2b;
    }
    .cm-selectionBackground {
        background: rgba(139, 90, 43, 0.15) !important;
    }
    .cm-activeLine {
        background: rgba(139, 90, 43, 0.05);
    }
    .cm-gutters {
        background: transparent;
        border-right: none;
        color: #c4a77d;
        padding-right: 12px;
        font-size: 11px;
    }
    .cm-lineNumbers .cm-gutterElement {
        min-width: 2.5em;
        text-align: right;
        padding-right: 8px;
    }

    /* Dark mode - rich leather-bound book aesthetic */
    .dark .cm-content { caret-color: #c9a86c; }
    .dark .cm-cursor { border-left-color: #c9a86c; }
    .dark .cm-activeLine { background: rgba(201, 168, 108, 0.06); }
    .dark .cm-selectionBackground { background: rgba(201, 168, 108, 0.18) !important; }
    .dark .cm-gutters { color: #5c5344; }

    /* ═══════════════════════════════════════════════════════════════════
       Syntax highlighting - rich, refined colors
       ═══════════════════════════════════════════════════════════════════ */
    /* Light mode - ink on parchment */
    .cm-keyword { color: #7c4d8a; font-weight: 500; }
    .cm-function, .cm-callee { color: #2d5a8a; }
    .cm-string { color: #3d7a5a; }
    .cm-number { color: #b8860b; }
    .cm-comment { color: #9a8b7a; font-style: italic; }
    .cm-operator { color: #7c4d8a; }
    .cm-typeName { color: #0077aa; }
    .cm-variableName { color: #3d3226; }
    .cm-propertyName { color: #9a5b6a; }
    .cm-bool { color: #b8860b; }
    .cm-atom { color: #0077aa; }

    /* Dark mode - glowing ink on dark leather */
    .dark .cm-keyword { color: #c9a0dc; font-weight: 500; }
    .dark .cm-function, .dark .cm-callee { color: #8ab4f8; }
    .dark .cm-string { color: #81c995; }
    .dark .cm-number { color: #f0c674; }
    .dark .cm-comment { color: #7a7265; font-style: italic; }
    .dark .cm-operator { color: #c9a0dc; }
    .dark .cm-typeName { color: #7dd3e8; }
    .dark .cm-variableName { color: #e8e0d5; }
    .dark .cm-propertyName { color: #e8a0b0; }
    .dark .cm-bool { color: #f0c674; }
    .dark .cm-atom { color: #7dd3e8; }

    /* ═══════════════════════════════════════════════════════════════════
       Cell state indicators - subtle, refined
       ═══════════════════════════════════════════════════════════════════ */
    .cell-state-bar { background: transparent; }
    .cell.cell-idle .cell-state-bar { background: transparent; }
    .cell.cell-running .cell-state-bar {
        background: linear-gradient(to bottom, #d4a853, #c9a040);
    }
    .cell.cell-queued .cell-state-bar {
        background: linear-gradient(to bottom, #9a7baa, #8a6b9a);
    }
    .cell.cell-error .cell-state-bar {
        background: linear-gradient(to bottom, #c97070, #b86060);
    }

    /* Run button - elegant pill with gradient */
    .run-btn {
        position: relative;
        overflow: hidden;
    }
    .cell.cell-idle .run-btn {
        background: linear-gradient(135deg, #3d6aa5, #2d5a95);
    }
    .cell.cell-running .run-btn {
        background: linear-gradient(135deg, #d4a853, #c9a040);
    }
    .cell.cell-queued .run-btn {
        background: linear-gradient(135deg, #9a7baa, #8a6b9a);
    }
    .cell.cell-error .run-btn {
        background: linear-gradient(135deg, #c97070, #b86060);
    }
    .dark .cell.cell-idle .run-btn {
        background: linear-gradient(135deg, #5a7dba, #4a6daa);
    }

    /* Running animation - gentle gold shimmer */
    .cell.cell-running .run-btn::after {
        content: '';
        position: absolute;
        inset: 0;
        background: linear-gradient(90deg, transparent, rgba(255,255,255,0.25), transparent);
        animation: shimmer 2s ease-in-out infinite;
    }
    @keyframes shimmer {
        0% { transform: translateX(-100%); }
        100% { transform: translateX(100%); }
    }

    /* Dirty indicator - amber glow */
    .dirty-indicator {
        box-shadow: 0 0 4px rgba(217, 119, 6, 0.5);
    }
    .dirty-indicator:not(.hidden) {
        animation: amber-pulse 2.5s ease-in-out infinite;
    }
    @keyframes amber-pulse {
        0%, 100% { opacity: 1; box-shadow: 0 0 4px rgba(217, 119, 6, 0.5); }
        50% { opacity: 0.6; box-shadow: 0 0 8px rgba(217, 119, 6, 0.3); }
    }

    /* ═══════════════════════════════════════════════════════════════════
       Global refinements
       ═══════════════════════════════════════════════════════════════════ */
    /* Smoother scrollbars */
    ::-webkit-scrollbar { width: 8px; height: 8px; }
    ::-webkit-scrollbar-track { background: transparent; }
    ::-webkit-scrollbar-thumb {
        background: rgba(0,0,0,0.15);
        border-radius: 4px;
    }
    ::-webkit-scrollbar-thumb:hover { background: rgba(0,0,0,0.25); }
    .dark ::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.15); }
    .dark ::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,0.25); }

    /* Selection color */
    ::selection { background: rgba(139, 90, 43, 0.2); }
    .dark ::selection { background: rgba(201, 168, 108, 0.25); }
    </style>
    """
end

"""
Sessions.jl Minimal JavaScript Bridge

Architecture: Uses Therapy.jl for Everything Possible
=====================================================
Therapy.jl handles:
- CodeMirror initialization via ExternalLibrary pattern (register_codemirror_pluto)
- Signal updates via data-signal-match (CSS classes) and data-signal-html (output)
- Action handlers via data-action attribute
- SPA navigation via client router

Sessions.jl handles ONLY what Therapy.jl can't:
- Notebook ID context (global variable for channel messages)
- Global action functions (runAll, saveNotebook)
- Channel handlers for DOM manipulation (cell_added, cell_deleted)
- Paste handler for Pluto notebook import
- Dark mode toggle (for island interop)
"""
function sessions_script()
    """
    <script>
    // Sessions.jl - Minimal bridge (Therapy.jl does the heavy lifting)
    (function() {
        'use strict';

        let notebookId = null;

        // =====================================================================
        // Helpers
        // =====================================================================

        function sendAction(channel, data) {
            console.log('[Sessions] sendAction:', channel, 'notebook_id:', data.notebook_id);
            if (!data.notebook_id) {
                console.error('[Sessions] ERROR: notebook_id is null/empty! Current notebookId var:', notebookId);
            }
            if (typeof TherapyWS !== 'undefined' && TherapyWS.isConnected()) {
                TherapyWS.sendMessage(channel, data);
            } else {
                console.warn('[Sessions] TherapyWS not connected, cannot send:', channel);
            }
        }

        // Get code from a cell's CodeMirror editor
        function getCode(cellId) {
            const cell = document.querySelector('[data-cell-id="' + cellId + '"]');
            if (!cell) return '';
            const container = cell.querySelector('[data-codemirror]');
            if (container && container._cmView) {
                return container._cmView.state.doc.toString();
            }
            // Fallback to pre element if CodeMirror not initialized
            const pre = cell.querySelector('.cell-code');
            return pre ? pre.textContent : '';
        }

        // =====================================================================
        // Global API (for buttons, keybindings, etc.)
        // =====================================================================

        window.setNotebookId = function(id) {
            console.log('[Sessions] setNotebookId called with:', id);
            notebookId = id;
        };

        window.getNotebookId = function() {
            return notebookId;
        };

        // Expose sendAction for testing
        window.sendAction = function(channel, data) {
            return sendAction(channel, data);
        };

        window.runAll = function() {
            sendAction('run_all', { notebook_id: notebookId });
        };

        window.saveNotebook = function() {
            sendAction('save', { notebook_id: notebookId });
        };

        window.addCell = function(afterId) {
            sendAction('add_cell', { notebook_id: notebookId, after_cell_id: afterId });
        };

        // Add cell after a specific cell (called by onclick)
        // Optional code parameter for testing
        window.addCellAfter = function(afterId, code) {
            var data = { notebook_id: notebookId, after_cell_id: afterId };
            if (code !== undefined && code !== null) {
                data.code = code;
            }
            sendAction('add_cell', data);
        };

        // Delete cell with confirmation (called by onclick)
        window.deleteCell = function(cellId) {
            if (confirm('Delete this cell?')) {
                sendAction('delete_cell', { notebook_id: notebookId, cell_id: cellId });
            }
        };

        // Execute cell - called by onclick and CodeMirror keybindings
        window.executeCell = function(cellId) {
            sendAction('execute', {
                notebook_id: notebookId,
                cell_id: cellId,
                code: getCode(cellId)
            });
        };

        // =====================================================================
        // Dark Mode (for DarkModeToggle island)
        // =====================================================================

        window.toggleDarkMode = function() {
            document.documentElement.classList.toggle('dark');
            const isDark = document.documentElement.classList.contains('dark');
            localStorage.setItem('sessions-dark-mode', isDark ? 'true' : 'false');
        };

        window.set_dark_mode = function(value) {
            if (value === 1 || value === true) {
                document.documentElement.classList.add('dark');
            } else {
                document.documentElement.classList.remove('dark');
            }
            localStorage.setItem('sessions-dark-mode', value ? 'true' : 'false');
        };

        // =====================================================================
        // Bond Handling (@bind macro support)
        // =====================================================================

        // Get event type for an input element
        function getBondEventType(el) {
            if (el.tagName === 'BUTTON') return 'click';
            if (el.type === 'file') return 'change';
            return 'input';
        }

        // Extract value from an input element
        function extractBondValue(el) {
            if (el.type === 'range' || el.type === 'number') return el.valueAsNumber;
            if (el.type === 'checkbox') return el.checked;
            if (el.type === 'select-multiple') {
                return Array.from(el.selectedOptions).map(o => o.value);
            }
            return el.value;
        }

        // Set up bonds in a container (cell output)
        function setupBonds(container) {
            const bonds = container.querySelectorAll('bond');

            bonds.forEach(function(bond) {
                // Skip if already set up
                if (bond._bondSetup) return;
                bond._bondSetup = true;

                const name = bond.getAttribute('def');
                if (!name) return;

                const input = bond.querySelector('input, select, button, textarea');
                if (!input) return;

                const eventType = getBondEventType(input);
                input.addEventListener(eventType, function() {
                    const value = extractBondValue(input);
                    console.log('[Sessions] Bond change:', name, '=', value);

                    sendAction('set_bond', {
                        notebook_id: notebookId,
                        name: name,
                        value: value
                    });
                });

                console.log('[Sessions] Bond registered:', name, 'on', input.tagName, input.type || '');
            });
        }

        // Set up bonds for all cells
        function setupAllBonds() {
            const outputs = document.querySelectorAll('.cell-output');
            outputs.forEach(setupBonds);
        }

        // =====================================================================
        // Channel Handlers (cell_added, cell_deleted) - SPA DOM Updates
        // =====================================================================

        function setupChannelHandlers() {
            if (typeof TherapyWS === 'undefined') return;

            // Handle new cell - insert HTML into DOM (no page reload)
            TherapyWS.onChannelMessage('cell_added', function(data) {
                const cellHtml = data.cell_html;
                const afterCellId = data.after_cell_id;
                const cellId = data.cell_id;

                // Parse the HTML
                const temp = document.createElement('div');
                temp.innerHTML = cellHtml;
                const newCell = temp.firstElementChild;

                // Find insertion point
                const container = document.querySelector('.cells-container');
                if (!container) return;

                if (afterCellId) {
                    const afterCell = document.querySelector('[data-cell-id="' + afterCellId + '"]');
                    if (afterCell) {
                        afterCell.after(newCell);
                    } else {
                        container.appendChild(newCell);
                    }
                } else {
                    container.appendChild(newCell);
                }

                // Initialize CodeMirror for the new cell via Therapy.jl's external library reinit
                if (window.TherapyExternalLibs && window.TherapyExternalLibs.reinit) {
                    window.TherapyExternalLibs.reinit();
                }

                // CRITICAL: Subscribe to the new cell's signals (state, output, runtime)
                // Without this, dynamically added cells won't receive signal updates
                if (typeof TherapyWS !== 'undefined' && TherapyWS.discoverAndSubscribe) {
                    TherapyWS.discoverAndSubscribe();
                }

                // Remove empty state if it exists
                const emptyState = container.querySelector('.text-center.py-20');
                if (emptyState) emptyState.remove();

                console.log('[Sessions] Cell added:', cellId);
            });

            TherapyWS.onChannelMessage('cell_deleted', function(data) {
                const cell = document.querySelector('[data-cell-id="' + data.cell_id + '"]');
                if (cell) {
                    cell.remove();
                    console.log('[Sessions] Cell deleted:', data.cell_id);
                }
            });

            TherapyWS.onChannelMessage('paste_complete', function(data) {
                if (data.cells_created > 0) {
                    console.log('[Sessions] Pasted ' + data.cells_created + ' cell(s)' +
                        (data.is_pluto_format ? ' from Pluto notebook' : ''));
                }
            });
        }

        // =====================================================================
        // File Browser API (SESSIONS-2100)
        // =====================================================================

        // Navigate to a directory
        window.navigateToDirectory = function(path) {
            sendAction('navigate_directory', { path: path });
        };

        // Refresh file browser
        window.refreshFileBrowser = function() {
            sendAction('refresh_filebrowser', {});
        };

        // Create a new file
        window.createFile = function(name) {
            var filename = name || prompt('Enter file name:', 'untitled.jl');
            if (filename) {
                sendAction('create_file', { name: filename });
            }
        };

        // Create a new folder
        window.createFolder = function(name) {
            var foldername = name || prompt('Enter folder name:', 'New Folder');
            if (foldername) {
                sendAction('create_folder', { name: foldername });
            }
        };

        // Delete a file or folder
        window.deleteItem = function(path) {
            if (confirm('Delete this item?')) {
                sendAction('delete_item', { path: path });
            }
        };

        // Rename a file or folder
        window.renameItem = function(oldPath) {
            var currentName = oldPath.split('/').pop();
            var newName = prompt('Enter new name:', currentName);
            if (newName && newName !== currentName) {
                sendAction('rename_item', { old_path: oldPath, new_name: newName });
            }
        };

        // Open a notebook file
        window.openNotebook = function(path) {
            sendAction('open_file', { path: path });
        };

        // =====================================================================
        // Context Menu API (SESSIONS-2102)
        // =====================================================================

        // Track currently selected item for context menu
        var contextMenuPath = null;
        var contextMenuIsDirectory = false;
        var contextMenuIsJulia = false;

        // Show context menu at position
        window.showContextMenu = function(event, path, isDirectory, isJulia) {
            event.preventDefault();
            event.stopPropagation();

            contextMenuPath = path;
            contextMenuIsDirectory = isDirectory;
            contextMenuIsJulia = isJulia;

            var menu = document.getElementById('file-context-menu');
            if (!menu) return;

            // Show/hide "Open" option based on file type
            var openItem = document.getElementById('ctx-menu-open');
            var openSeparator = document.getElementById('ctx-menu-separator-open');
            if (openItem && openSeparator) {
                if (isJulia || isDirectory) {
                    openItem.style.display = 'block';
                    openSeparator.style.display = 'block';
                } else {
                    openItem.style.display = 'none';
                    openSeparator.style.display = 'none';
                }
            }

            // Position the menu
            var x = event.clientX;
            var y = event.clientY;

            // Make visible to measure
            menu.classList.remove('hidden');
            menu.style.visibility = 'hidden';
            menu.style.left = x + 'px';
            menu.style.top = y + 'px';

            // Adjust if menu would go off screen
            var rect = menu.getBoundingClientRect();
            if (rect.right > window.innerWidth) {
                x = window.innerWidth - rect.width - 10;
            }
            if (rect.bottom > window.innerHeight) {
                y = window.innerHeight - rect.height - 10;
            }

            menu.style.left = x + 'px';
            menu.style.top = y + 'px';
            menu.style.visibility = 'visible';
        };

        // Hide context menu
        window.hideContextMenu = function() {
            var menu = document.getElementById('file-context-menu');
            if (menu) {
                menu.classList.add('hidden');
            }
            contextMenuPath = null;
        };

        // Context menu action handlers
        window.contextMenuOpen = function() {
            hideContextMenu();
            if (contextMenuPath) {
                if (contextMenuIsDirectory) {
                    navigateToDirectory(contextMenuPath);
                } else if (contextMenuIsJulia) {
                    openNotebook(contextMenuPath);
                }
            }
        };

        window.contextMenuRename = function() {
            hideContextMenu();
            if (contextMenuPath) {
                renameItem(contextMenuPath);
            }
        };

        window.contextMenuDelete = function() {
            hideContextMenu();
            if (contextMenuPath) {
                deleteItem(contextMenuPath);
            }
        };

        window.contextMenuCopyPath = function() {
            hideContextMenu();
            if (contextMenuPath) {
                navigator.clipboard.writeText(contextMenuPath).then(function() {
                    console.log('[Sessions] Path copied:', contextMenuPath);
                }).catch(function(err) {
                    console.error('[Sessions] Failed to copy path:', err);
                    // Fallback: show in prompt
                    prompt('Copy this path:', contextMenuPath);
                });
            }
        };

        // Close context menu on click outside
        document.addEventListener('click', function(e) {
            var menu = document.getElementById('file-context-menu');
            if (menu && !menu.contains(e.target)) {
                hideContextMenu();
            }
        });

        // Close context menu on Escape
        document.addEventListener('keydown', function(e) {
            if (e.key === 'Escape') {
                hideContextMenu();
            }
        });

        // =====================================================================
        // Terminal API (SESSIONS-2110)
        // =====================================================================

        // Registry of active terminal instances
        var terminalInstances = {};

        // Initialize xterm.js for a terminal container
        function initTerminal(sessionId) {
            var container = document.getElementById('terminal-' + sessionId);
            if (!container || !container.hasAttribute('data-xterm')) return null;

            // Skip if already initialized
            if (terminalInstances[sessionId]) {
                return terminalInstances[sessionId];
            }

            // Check that xterm is loaded
            if (typeof Terminal === 'undefined') {
                console.warn('[Sessions] xterm.js not loaded yet');
                return null;
            }

            // Create terminal with elegant theme
            var term = new Terminal({
                fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
                fontSize: 13,
                lineHeight: 1.5,
                cursorBlink: true,
                cursorStyle: 'bar',
                theme: {
                    background: '#0a0a0a',
                    foreground: '#e8e0d5',
                    cursor: '#c9a86c',
                    cursorAccent: '#0a0a0a',
                    selectionBackground: 'rgba(201, 168, 108, 0.3)',
                    black: '#1a1816',
                    red: '#c97070',
                    green: '#81c995',
                    yellow: '#f0c674',
                    blue: '#8ab4f8',
                    magenta: '#c9a0dc',
                    cyan: '#7dd3e8',
                    white: '#e8e0d5',
                    brightBlack: '#5c5344',
                    brightRed: '#e8a0a0',
                    brightGreen: '#a0e0b0',
                    brightYellow: '#f8d898',
                    brightBlue: '#a8c8f8',
                    brightMagenta: '#d8b8e8',
                    brightCyan: '#98e0f0',
                    brightWhite: '#f8f0e8'
                }
            });

            // Load addons
            var fitAddon = null;
            var webLinksAddon = null;

            if (typeof FitAddon !== 'undefined') {
                fitAddon = new FitAddon.FitAddon();
                term.loadAddon(fitAddon);
            }

            if (typeof WebLinksAddon !== 'undefined') {
                webLinksAddon = new WebLinksAddon.WebLinksAddon();
                term.loadAddon(webLinksAddon);
            }

            // Remove loading indicator
            var loading = document.getElementById('terminal-loading-' + sessionId);
            if (loading) loading.remove();

            // Open terminal in container
            term.open(container);

            // Fit to container
            if (fitAddon) {
                try {
                    fitAddon.fit();
                } catch (e) {
                    console.warn('[Sessions] Fit addon error:', e);
                }
            }

            // Handle window resize
            var resizeHandler = function() {
                if (fitAddon) {
                    try {
                        fitAddon.fit();
                        // Send resize to server
                        sendAction('terminal_resize', {
                            session_id: sessionId,
                            cols: term.cols,
                            rows: term.rows
                        });
                    } catch (e) {}
                }
            };
            window.addEventListener('resize', resizeHandler);

            // Handle user input - send to server
            term.onData(function(data) {
                sendAction('terminal_input', {
                    session_id: sessionId,
                    data: data
                });
            });

            // Store instance
            terminalInstances[sessionId] = {
                term: term,
                fitAddon: fitAddon,
                resizeHandler: resizeHandler
            };

            // Subscribe to terminal output channel
            if (typeof TherapyWS !== 'undefined') {
                TherapyWS.onChannelMessage('terminal_output_' + sessionId, function(data) {
                    if (data.output) {
                        term.write(data.output);
                    }
                });
            }

            // Request terminal creation on server
            sendAction('create_terminal', {
                session_id: sessionId,
                cols: term.cols,
                rows: term.rows
            });

            // Write welcome message
            term.writeln('\\x1b[2mConnecting to server...\\x1b[0m');

            console.log('[Sessions] Terminal initialized:', sessionId);
            return terminalInstances[sessionId];
        }

        // Initialize all terminals on the page
        function initAllTerminals() {
            var containers = document.querySelectorAll('[data-xterm]');
            containers.forEach(function(container) {
                var sessionId = container.getAttribute('data-session-id');
                if (sessionId && !terminalInstances[sessionId]) {
                    initTerminal(sessionId);
                }
            });
        }

        // Clear terminal content
        window.clearTerminal = function(sessionId) {
            var instance = terminalInstances[sessionId];
            if (instance && instance.term) {
                instance.term.clear();
            }
        };

        // Close terminal
        window.closeTerminal = function(sessionId) {
            var instance = terminalInstances[sessionId];
            if (instance) {
                // Notify server
                sendAction('close_terminal', { session_id: sessionId });

                // Remove event listener
                if (instance.resizeHandler) {
                    window.removeEventListener('resize', instance.resizeHandler);
                }

                // Dispose terminal
                if (instance.term) {
                    instance.term.dispose();
                }

                delete terminalInstances[sessionId];
            }

            // Remove panel from DOM
            var panel = document.querySelector('[data-terminal-id="' + sessionId + '"]');
            if (panel) {
                panel.remove();
            }

            console.log('[Sessions] Terminal closed:', sessionId);
        };

        // Create new terminal
        window.createTerminal = function(title) {
            sendAction('new_terminal', { title: title || 'Terminal' });
        };

        // Switch active terminal (for tabbed interface)
        window.switchTerminal = function(sessionId) {
            // Hide all panels
            var panels = document.querySelectorAll('.terminal-panel-wrapper');
            panels.forEach(function(panel) {
                panel.style.display = 'none';
            });

            // Show selected panel
            var selected = document.querySelector('[data-panel-id="' + sessionId + '"]');
            if (selected) {
                selected.style.display = 'block';
            }

            // Update tab states
            var tabs = document.querySelectorAll('.terminal-tab');
            tabs.forEach(function(tab) {
                var isActive = tab.getAttribute('data-tab-id') === sessionId;
                tab.classList.toggle('bg-white', isActive);
                tab.classList.toggle('dark:bg-neutral-800', isActive);
                tab.classList.toggle('border-t-2', isActive);
                tab.classList.toggle('border-pluto-blue', isActive);
            });

            // Fit terminal
            var instance = terminalInstances[sessionId];
            if (instance && instance.fitAddon) {
                setTimeout(function() {
                    try { instance.fitAddon.fit(); } catch (e) {}
                }, 50);
            }
        };

        // =====================================================================
        // Notebook Tab Management (SESSIONS-2200)
        // =====================================================================

        // Track open notebooks locally for unsaved changes prompt
        window.openNotebooks = window.openNotebooks || {};

        // Switch to a different notebook tab
        window.switchTab = function(notebookId) {
            console.log('[Tabs] Switching to notebook:', notebookId);

            // Send channel message to switch notebook
            sendAction('switch_notebook', { notebook_id: notebookId });

            // Update local active state immediately for responsiveness
            updateActiveTab(notebookId);
        };

        // Close a notebook tab
        window.closeTab = function(notebookId) {
            console.log('[Tabs] Closing notebook:', notebookId);

            // Check for unsaved changes
            var tabEl = document.querySelector('[data-tab-id="' + notebookId + '"]');
            var hasUnsaved = tabEl && tabEl.querySelector('.bg-amber-500, .bg-amber-400');

            if (hasUnsaved) {
                if (!confirm('This notebook has unsaved changes. Close anyway?')) {
                    return;
                }
            }

            // Send channel message to close notebook
            sendAction('close_notebook', { notebook_id: notebookId });
        };

        // Create a new notebook
        window.createNewNotebook = function() {
            console.log('[Tabs] Creating new notebook');
            sendAction('create_notebook', {});
        };

        // Update active tab styling
        function updateActiveTab(notebookId) {
            var tabs = document.querySelectorAll('.notebook-tab');
            tabs.forEach(function(tab) {
                var isActive = tab.getAttribute('data-tab-id') === notebookId;
                tab.setAttribute('data-active', isActive ? 'true' : 'false');

                if (isActive) {
                    tab.classList.remove('bg-stone-200/50', 'text-stone-500');
                    tab.classList.add('bg-stone-100', 'text-stone-800', 'shadow-sm');
                } else {
                    tab.classList.remove('bg-stone-100', 'text-stone-800', 'shadow-sm');
                    tab.classList.add('bg-stone-200/50', 'text-stone-500');
                }
            });

            // Update container data attribute
            var container = document.querySelector('.notebook-tabs-container');
            if (container) {
                container.setAttribute('data-active-notebook', notebookId);
            }

            // Update notebook ID for cell operations
            if (typeof setNotebookId === 'function') {
                setNotebookId(notebookId);
            }
        }

        // Setup notebook tab channel handlers
        function setupTabChannelHandlers() {
            if (typeof TherapyWS === 'undefined') return;

            // Listen for notebook switched events from server
            TherapyWS.onChannelMessage('notebook_switched', function(data) {
                console.log('[Tabs] Notebook switched:', data);
                updateActiveTab(data.notebook_id);

                // Reload page to show the new notebook content
                window.location.reload();
            });

            TherapyWS.onChannelMessage('notebook_closed', function(data) {
                console.log('[Tabs] Notebook closed:', data);
                // Tab will be removed by page reload
            });

            TherapyWS.onChannelMessage('notebook_created', function(data) {
                console.log('[Tabs] Notebook created:', data);
                // Page will reload to show new notebook
            });

            TherapyWS.onChannelMessage('notebook_opened', function(data) {
                console.log('[Tabs] Notebook opened:', data);
                // Page will reload to show new notebook
            });
        }

        // =====================================================================
        // Paste Handler (Pluto notebook import)
        // =====================================================================

        function setupPasteHandler() {
            document.addEventListener('paste', function(e) {
                // Don't intercept if focused on editor
                const activeEl = document.activeElement;
                if (activeEl && (activeEl.closest('.cm-editor') ||
                    activeEl.tagName === 'TEXTAREA' || activeEl.tagName === 'INPUT')) {
                    return;
                }

                // Only handle paste in notebook area
                if (!e.target.closest('.cells-container, #page-content, main')) return;

                const text = e.clipboardData?.getData('text/plain');
                if (!text || text.trim().length === 0) return;

                // Check if it's Pluto content or multi-line code
                const isPluto = text.includes('### A Pluto.jl notebook ###');
                const isMultiLine = text.includes('\\n') || text.split('\\n').length > 3;
                if (!isPluto && !isMultiLine) return;

                e.preventDefault();

                // Find last cell to insert after
                const cells = document.querySelectorAll('.cell');
                const lastCell = cells.length > 0 ? cells[cells.length - 1] : null;

                sendAction('paste_content', {
                    notebook_id: notebookId,
                    content: text,
                    after_cell_id: lastCell ? lastCell.dataset.cellId : null
                });

                console.log('[Sessions] Paste detected, sending to server...');
            });
        }

        // =====================================================================
        // Initialization
        // =====================================================================

        function init() {
            // Set up channel handlers (only once)
            if (!window._sessionsChannelHandlers) {
                window._sessionsChannelHandlers = true;
                setupChannelHandlers();
                setupTabChannelHandlers();
            }

            // Set up paste handler (only once)
            if (!window._sessionsPasteHandler) {
                window._sessionsPasteHandler = true;
                setupPasteHandler();
            }

            // Set up bonds on initial page load and after mutations
            setupAllBonds();

            // Initialize any terminals on the page
            initAllTerminals();

            // Watch for cell output changes via MutationObserver
            // This catches when data-signal-html updates the output
            if (!window._sessionsBondObserver) {
                window._sessionsBondObserver = new MutationObserver(function(mutations) {
                    mutations.forEach(function(mutation) {
                        if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
                            // Check if this is a cell output update
                            const target = mutation.target;
                            if (target.classList && target.classList.contains('cell-output')) {
                                setupBonds(target);
                            }
                            // Also check added nodes
                            mutation.addedNodes.forEach(function(node) {
                                if (node.nodeType === 1) { // Element node
                                    if (node.classList && node.classList.contains('cell-output')) {
                                        setupBonds(node);
                                    }
                                    // Check for bond tags in added content
                                    if (node.querySelectorAll) {
                                        const bonds = node.querySelectorAll('bond');
                                        if (bonds.length > 0) {
                                            setupBonds(node);
                                        }
                                    }
                                }
                            });
                        }
                    });
                });

                // Observe the whole document for cell output changes
                window._sessionsBondObserver.observe(document.body, {
                    childList: true,
                    subtree: true
                });
            }
        }

        // Wait for TherapyWS to be ready
        function waitForWS() {
            if (typeof TherapyWS !== 'undefined') {
                init();
            } else {
                setTimeout(waitForWS, 100);
            }
        }

        // Start
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', waitForWS);
        } else {
            waitForWS();
        }

        // Re-init after SPA navigation
        window.addEventListener('therapy:router:loaded', init);
    })();
    </script>
    """
end

"""
Main layout component for Sessions.
Returns the body content (not full HTML - use render_page for that).

Design: Elegant, minimal, scholarly aesthetic.
- Serif font for branding (calligraphy feel)
- Pluto blue as accent color
- Generous whitespace and subtle shadows
"""
function Layout(content; dark_mode_toggle=nothing, notebooks=nothing, active_notebook_id=nothing)
    # Use provided toggle or default
    toggle = dark_mode_toggle !== nothing ? dark_mode_toggle : DarkModeToggle()

    # Show tabs if notebooks provided
    show_tabs = notebooks !== nothing && !isempty(notebooks)

    Div(:class => "min-h-screen flex flex-col bg-stone-100 dark:bg-neutral-950 transition-colors duration-300",
        # Navigation Bar - refined, scholarly
        Nav(:class => "sticky top-0 z-50 bg-stone-50/90 dark:bg-neutral-900/90 backdrop-blur-lg border-b border-stone-200/60 dark:border-neutral-800/60 transition-colors duration-300",
            Div(:class => "max-w-4xl mx-auto px-8",
                Div(:class => "flex justify-between h-12",
                    # Logo & Title - illuminated manuscript style
                    Div(:class => "flex items-center",
                        A(:href => "/", :class => "flex items-baseline group",
                            # Each letter colored like an illuminated manuscript
                            Span(:class => "text-lg font-serif font-semibold text-rose-700 dark:text-rose-400", "S"),
                            Span(:class => "text-lg font-serif font-semibold text-amber-700 dark:text-amber-400", "e"),
                            Span(:class => "text-lg font-serif font-semibold text-emerald-700 dark:text-emerald-400", "s"),
                            Span(:class => "text-lg font-serif font-semibold text-sky-700 dark:text-sky-400", "s"),
                            Span(:class => "text-lg font-serif font-semibold text-violet-700 dark:text-violet-400", "i"),
                            Span(:class => "text-lg font-serif font-semibold text-rose-700 dark:text-rose-400", "o"),
                            Span(:class => "text-lg font-serif font-semibold text-amber-700 dark:text-amber-400", "n"),
                            Span(:class => "text-lg font-serif font-semibold text-emerald-700 dark:text-emerald-400", "s"),
                            Span(:class => "text-lg font-serif font-light text-stone-400 dark:text-stone-500", ".jl")
                        )
                    ),

                    # Actions - understated elegance
                    Div(:class => "flex items-center gap-3",
                        # Save - ghost button
                        Button(:class => "px-3 py-1 text-xs font-medium text-stone-500 dark:text-stone-400 hover:text-stone-700 dark:hover:text-stone-200 hover:bg-stone-200/50 dark:hover:bg-stone-800/50 rounded-full transition-all duration-200",
                            :onclick => "saveNotebook()",
                            "Save"
                        ),
                        # Divider
                        Span(:class => "w-px h-4 bg-stone-300 dark:bg-stone-700"),
                        # Theme Toggle
                        toggle
                    )
                )
            )
        ),

        # Notebook Tabs Bar (SESSIONS-2200) - only shown when multiple notebooks
        show_tabs ? NotebookTabs(notebooks; active_id=active_notebook_id) : nothing,

        # Main Content Area - generous, breathable
        MainEl(:id => "page-content", :class => "flex-1 max-w-4xl w-full mx-auto px-8 py-12",
            content
        ),

        # Footer - whisper quiet
        Footer(:class => "border-t border-stone-200/40 dark:border-neutral-800/40 transition-colors duration-300",
            Div(:class => "max-w-4xl mx-auto py-5 px-8",
                P(:class => "text-center text-stone-400 dark:text-stone-600 text-xs tracking-wide",
                    "Built with ",
                    A(:href => "https://github.com/TherapeuticJulia/Therapy.jl",
                      :class => "text-stone-500 dark:text-stone-500 hover:text-amber-600 dark:hover:text-amber-500 transition-colors",
                      :target => "_blank",
                      "Therapy.jl"
                    )
                )
            )
        )
    )
end

"""
Get complete head_extra content for render_page.
Includes: styles, WebSocket client, client router (SPA), external libraries, and minimal Sessions.js
"""
function sessions_head_extra()
    # Register CodeMirror with Therapy.jl's external library pattern
    # This provides CodeMirror initialization with Julia syntax highlighting
    register_codemirror_pluto()

    # WebSocket client script (includes data-signal-match, data-signal-html, data-action handling)
    ws_script = websocket_client_script()
    ws_str = ws_script isa Therapy.RawHtml ? ws_script.content : string(ws_script)

    # Client-side router for SPA navigation
    router_script = client_router_script(content_selector="#page-content")
    router_str = router_script isa Therapy.RawHtml ? router_script.content : render_to_string(router_script)

    # External libraries (CodeMirror initialization)
    ext_libs = external_library_script()
    ext_libs_str = ext_libs isa Therapy.RawHtml ? ext_libs.content : render_to_string(ext_libs)

    sessions_styles() * ws_str * router_str * ext_libs_str * sessions_script()
end
