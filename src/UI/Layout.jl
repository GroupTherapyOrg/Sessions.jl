# Layout.jl - Main application layout
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
Sessions.jl JavaScript Bridge

Architecture: Per-Cell Server Signals
=====================================
Each cell has its own signals: cell_state_{id}, cell_output_{id}, cell_runtime_{id}

This is simpler than Dict-based signals because:
1. Each cell subscribes only to its own signals
2. No need to iterate through Dict on every update
3. Therapy.jl auto-updates runtime via data-server-signal attribute

The JavaScript handles:
1. CodeMirror initialization (external JS library - cannot be avoided)
2. State CSS class updates (data-server-signal only updates textContent)
3. Output HTML updates (innerHTML, not textContent)
4. Dirty state tracking (yellow indicator when code changed)
5. Dark mode persistence (localStorage)
6. Action delegation (execute, delete, add-cell)
"""
function sessions_script()
    """
    <script>
    // Sessions.jl - Per-Cell Signal Architecture
    (function() {
        'use strict';

        const editors = new Map();
        const initialCode = new Map();  // Track original code for dirty detection
        let notebookId = null;

        // =====================================================================
        // CodeMirror Initialization (Required - External JS Library)
        // =====================================================================

        async function initCodeMirror(container, code, cellId) {
            try {
                const CM = await import('codemirror-pluto');

                // Use Pluto's pre-configured setup - it bundles everything correctly
                // pluto_syntax_colors() returns a complete extension with Julia highlighting
                const extensions = [];

                // Julia syntax with Pluto's colors (this is the main one we need)
                if (CM.pluto_syntax_colors) {
                    extensions.push(CM.pluto_syntax_colors());
                } else if (CM.julia_andrey) {
                    // Fallback to just the parser without custom colors
                    extensions.push(CM.julia_andrey());
                }

                // Core editing features
                if (CM.lineNumbers) extensions.push(CM.lineNumbers());
                if (CM.highlightSpecialChars) extensions.push(CM.highlightSpecialChars());
                if (CM.history) extensions.push(CM.history());
                if (CM.drawSelection) extensions.push(CM.drawSelection());
                if (CM.indentOnInput) extensions.push(CM.indentOnInput());
                if (CM.bracketMatching) extensions.push(CM.bracketMatching());
                if (CM.closeBrackets) extensions.push(CM.closeBrackets());
                if (CM.highlightSelectionMatches) extensions.push(CM.highlightSelectionMatches());
                if (CM.EditorView?.lineWrapping) extensions.push(CM.EditorView.lineWrapping);
                if (CM.foldGutter) extensions.push(CM.foldGutter());

                // Keymaps
                const keymaps = [];
                if (CM.defaultKeymap) keymaps.push(...CM.defaultKeymap);
                if (CM.historyKeymap) keymaps.push(...CM.historyKeymap);
                if (CM.closeBracketsKeymap) keymaps.push(...CM.closeBracketsKeymap);
                keymaps.push({ key: 'Shift-Enter', run: () => { executeCell(cellId); return true; } });
                keymaps.push({ key: 'Mod-Enter', run: () => { executeCell(cellId); return true; } });
                if (CM.keymap) extensions.push(CM.keymap.of(keymaps));

                // Track changes for dirty indicator
                if (CM.EditorView?.updateListener) {
                    extensions.push(CM.EditorView.updateListener.of(update => {
                        if (update.docChanged) updateDirtyState(cellId);
                    }));
                }

                const view = new CM.EditorView({
                    state: CM.EditorState.create({
                        doc: code,
                        extensions: extensions
                    }),
                    parent: container
                });
                editors.set(cellId, view);
                initialCode.set(cellId, code);
                console.log('[Sessions] CodeMirror initialized for cell:', cellId);
            } catch (err) {
                console.error('[Sessions] CodeMirror init failed:', err);
                // Fallback: show code in a textarea
                const textarea = document.createElement('textarea');
                textarea.value = code;
                textarea.className = 'w-full h-32 p-4 font-mono text-sm bg-stone-50 dark:bg-neutral-900 border-0 resize-none focus:outline-none';
                textarea.addEventListener('input', () => updateDirtyState(cellId));
                container.appendChild(textarea);
                editors.set(cellId, { state: { doc: { toString: () => textarea.value } } });
                initialCode.set(cellId, code);
            }
        }

        function getCode(cellId) {
            const editor = editors.get(cellId);
            return editor ? editor.state.doc.toString() : '';
        }

        // =====================================================================
        // Dirty State Tracking
        // =====================================================================

        function updateDirtyState(cellId) {
            const current = getCode(cellId);
            const original = initialCode.get(cellId) || '';
            const isDirty = current !== original;

            const cell = document.querySelector('[data-cell-id="' + cellId + '"]');
            if (!cell) return;

            const indicator = cell.querySelector('.dirty-indicator');
            if (indicator) {
                indicator.classList.toggle('hidden', !isDirty);
                indicator.classList.toggle('bg-yellow-500', isDirty);
                indicator.dataset.dirty = isDirty ? 'true' : 'false';
            }
        }

        function clearDirtyState(cellId) {
            // After execution, update initial code to current
            const current = getCode(cellId);
            initialCode.set(cellId, current);
            updateDirtyState(cellId);
        }

        // =====================================================================
        // Channel Actions (Therapy.jl)
        // =====================================================================

        function sendAction(channel, data) {
            if (typeof TherapyWS !== 'undefined' && TherapyWS.isConnected()) {
                TherapyWS.sendMessage(channel, data);
            }
        }

        function executeCell(cellId) {
            clearDirtyState(cellId);  // Mark as clean before execution
            sendAction('execute', {
                notebook_id: notebookId,
                cell_id: cellId,
                code: getCode(cellId)
            });
        }

        // =====================================================================
        // Per-Cell Signal Handlers
        // =====================================================================

        function subscribeToCell(cellId) {
            if (typeof TherapyWS === 'undefined') return;
            TherapyWS.subscribe('cell_state_' + cellId);
            TherapyWS.subscribe('cell_output_' + cellId);
        }

        function setupCellSignalHandler(cellId) {
            const stateSignal = 'cell_state_' + cellId;
            const outputSignal = 'cell_output_' + cellId;

            // Handle state changes (CSS classes)
            window.addEventListener('therapy:signal:' + stateSignal, function(e) {
                const state = e.detail.value;
                const cell = document.querySelector('[data-cell-id="' + cellId + '"]');
                if (!cell) return;

                cell.classList.remove('cell-running', 'cell-queued', 'cell-error', 'cell-idle');
                const cls = state === 'CELL_RUNNING' ? 'cell-running' :
                            state === 'CELL_QUEUED' ? 'cell-queued' :
                            state === 'CELL_ERROR' ? 'cell-error' : 'cell-idle';
                cell.classList.add(cls);
            });

            // Handle output changes (innerHTML)
            window.addEventListener('therapy:signal:' + outputSignal, function(e) {
                const html = e.detail.value || '';
                const cell = document.querySelector('[data-cell-id="' + cellId + '"]');
                if (!cell) return;

                const outputEl = cell.querySelector('.cell-output');
                if (outputEl) {
                    outputEl.innerHTML = html;
                    outputEl.classList.toggle('hidden', !html);
                }
            });
        }

        function setupAllCellSignals() {
            // Wait for TherapyWS to be ready
            function doSetup() {
                if (typeof TherapyWS === 'undefined' || !TherapyWS.isConnected()) {
                    setTimeout(doSetup, 200);
                    return;
                }

                document.querySelectorAll('.cell').forEach(cell => {
                    const cellId = cell.dataset.cellId;
                    if (cellId) {
                        subscribeToCell(cellId);
                        setupCellSignalHandler(cellId);
                    }
                });

                TherapyWS.subscribe('cells_list');
            }

            doSetup();
        }

        // =====================================================================
        // Action Delegation (data-action -> channel)
        // =====================================================================

        function handleAction(e) {
            const btn = e.target.closest('[data-action]');
            if (!btn) return;

            const action = btn.dataset.action;
            const cellId = btn.dataset.cellId;
            const afterCellId = btn.dataset.afterCellId;

            switch (action) {
                case 'execute':
                    executeCell(cellId);
                    break;
                case 'delete':
                    if (confirm('Delete this cell?')) {
                        sendAction('delete_cell', { notebook_id: notebookId, cell_id: cellId });
                    }
                    break;
                case 'add-cell':
                    sendAction('add_cell', { notebook_id: notebookId, after_cell_id: afterCellId });
                    break;
            }
        }

        // =====================================================================
        // Channel Handlers (cell_added, cell_deleted) - SPA Style
        // =====================================================================

        function setupChannelHandlers() {
            if (typeof TherapyWS === 'undefined') return;

            // Handle new cell - insert HTML directly into DOM (no page reload!)
            TherapyWS.onChannelMessage('cell_added', async function(data) {
                const cellHtml = data.cell_html;
                const afterCellId = data.after_cell_id;
                const cellId = data.cell_id;

                // Create a temporary container to parse the HTML
                const temp = document.createElement('div');
                temp.innerHTML = cellHtml;
                const newCell = temp.firstElementChild;

                // Find insertion point
                const container = document.querySelector('.cells-container');
                if (!container) return;

                if (afterCellId) {
                    // Insert after the specified cell
                    const afterCell = document.querySelector('[data-cell-id="' + afterCellId + '"]');
                    if (afterCell) {
                        afterCell.after(newCell);
                    } else {
                        container.appendChild(newCell);
                    }
                } else {
                    // Insert at end
                    container.appendChild(newCell);
                }

                // Initialize CodeMirror for the new cell
                const codeContainer = newCell.querySelector('.cell-code-container');
                const codeEl = newCell.querySelector('.cell-code');
                if (codeContainer && codeEl) {
                    const code = codeContainer.dataset.initialCode || codeEl.textContent || '';
                    codeEl.remove();
                    await initCodeMirror(codeContainer, code, cellId);
                }

                // Subscribe to the new cell's signals
                subscribeToCell(cellId);
                setupCellSignalHandler(cellId);

                // Remove empty state if it exists
                const emptyState = container.querySelector('.text-center.py-20');
                if (emptyState) emptyState.remove();

                console.log('[Sessions] Cell added via SPA:', cellId);
            });

            TherapyWS.onChannelMessage('cell_deleted', function(data) {
                const cell = document.querySelector('[data-cell-id="' + data.cell_id + '"]');
                if (cell) {
                    editors.delete(data.cell_id);
                    initialCode.delete(data.cell_id);
                    cell.remove();
                    console.log('[Sessions] Cell deleted:', data.cell_id);
                }
            });

            // Handle paste completion (feedback to user)
            TherapyWS.onChannelMessage('paste_complete', function(data) {
                const count = data.cells_created;
                const isPluto = data.is_pluto_format;
                if (count > 0) {
                    console.log('[Sessions] Pasted ' + count + ' cell(s)' + (isPluto ? ' from Pluto notebook' : ''));
                }
            });
        }

        // =====================================================================
        // Paste Handler (Pluto notebook import)
        // =====================================================================

        function setupPasteHandler() {
            // Listen for paste events on the cells container
            document.addEventListener('paste', function(e) {
                // Only handle paste when not focused on a CodeMirror editor
                const activeEl = document.activeElement;
                const isInEditor = activeEl && (
                    activeEl.closest('.cm-editor') ||
                    activeEl.tagName === 'TEXTAREA' ||
                    activeEl.tagName === 'INPUT'
                );

                // If in an editor, let the normal paste happen
                if (isInEditor) return;

                // Check if paste target is in the notebook area
                const target = e.target;
                const isInNotebook = target.closest('.cells-container') ||
                                     target.closest('#page-content') ||
                                     target.closest('main');

                if (!isInNotebook) return;

                // Get clipboard text
                const text = e.clipboardData?.getData('text/plain');
                if (!text || text.trim().length === 0) return;

                // Check if it looks like Pluto content or multi-line code
                const isPluto = text.includes('### A Pluto.jl notebook ###');
                const isMultiLine = text.includes('\\n') || text.split('\\n').length > 3;

                // Only intercept if it's Pluto content or significant code
                if (!isPluto && !isMultiLine) return;

                e.preventDefault();

                // Find the last cell to insert after
                const cells = document.querySelectorAll('.cell');
                const lastCell = cells.length > 0 ? cells[cells.length - 1] : null;
                const afterCellId = lastCell ? lastCell.dataset.cellId : null;

                // Send to server
                sendAction('paste_content', {
                    notebook_id: notebookId,
                    content: text,
                    after_cell_id: afterCellId
                });

                console.log('[Sessions] Paste detected, sending to server...');
            });
        }

        // =====================================================================
        // Dark Mode (initialization + toggle handler for island)
        // =====================================================================

        function initDarkMode() {
            const saved = localStorage.getItem('sessions-dark-mode');
            if (saved === 'true') {
                document.documentElement.classList.add('dark');
            } else if (saved === 'false') {
                document.documentElement.classList.remove('dark');
            } else {
                // Check system preference
                if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
                    document.documentElement.classList.add('dark');
                }
            }
        }

        // Global toggle function that the DarkModeToggle island can call
        // (Therapy.jl Wasm islands can call window.* functions)
        window.toggleDarkMode = function() {
            document.documentElement.classList.toggle('dark');
            const isDark = document.documentElement.classList.contains('dark');
            localStorage.setItem('sessions-dark-mode', isDark ? 'true' : 'false');
        };

        // Also expose set_dark_mode for island :dark_mode prop binding
        window.set_dark_mode = function(value) {
            if (value === 1 || value === true) {
                document.documentElement.classList.add('dark');
            } else {
                document.documentElement.classList.remove('dark');
            }
            localStorage.setItem('sessions-dark-mode', value ? 'true' : 'false');
        };

        // =====================================================================
        // Initialization
        // =====================================================================

        function init() {

            // Initialize dark mode from localStorage
            initDarkMode();

            // Action delegation
            document.addEventListener('click', handleAction);

            // Set up per-cell signal handlers
            setupAllCellSignals();

            // Set up channel handlers
            setupChannelHandlers();

            // Set up paste handler for Pluto notebook import
            setupPasteHandler();

            // Initialize CodeMirror editors
            document.querySelectorAll('.cell').forEach(async function(cell) {
                const cellId = cell.dataset.cellId;
                const container = cell.querySelector('.cell-code-container');
                const codeEl = cell.querySelector('.cell-code');
                if (container && codeEl && !editors.has(cellId)) {
                    const code = container.dataset.initialCode || codeEl.textContent || '';
                    codeEl.remove();
                    await initCodeMirror(container, code, cellId);
                }
            });
        }

        // Global API
        window.setNotebookId = function(id) { notebookId = id; };
        window.runAll = function() { sendAction('run_all', { notebook_id: notebookId }); };
        window.saveNotebook = function() { sendAction('save', { notebook_id: notebookId }); };
        window.addCell = function(afterId) { sendAction('add_cell', { notebook_id: notebookId, after_cell_id: afterId }); };
        // Note: toggleDarkMode is handled by the DarkModeToggle island (Wasm)

        // Start
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', init);
        } else {
            setTimeout(init, 100);
        }
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
function Layout(content)
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
                        DarkModeToggle()
                    )
                )
            )
        ),

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
Includes: styles, WebSocket client, and Sessions.js

Note: We intentionally do NOT use Therapy.jl's client_router_script here.
Sessions.jl is a notebook app where users stay on one page - SPA navigation
would break CodeMirror initialization on route changes.
"""
function sessions_head_extra()
    # WebSocket client script
    ws_script = websocket_client_script()
    ws_str = ws_script isa Therapy.RawHtml ? ws_script.content : string(ws_script)

    sessions_styles() * ws_str * sessions_script()
end
