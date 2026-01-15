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
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
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

    <!-- CodeMirror 6 via Pluto's pre-bundled setup -->
    <script type="importmap">
    {
        "imports": {
            "codemirror-pluto": "https://cdn.jsdelivr.net/gh/JuliaPluto/codemirror-pluto-setup@0.19.3/dist/index.es.min.js"
        }
    }
    </script>

    <!-- Minimal CodeMirror styling (Tailwind handles everything else) -->
    <style>
    .cm-editor {
        font-family: 'JetBrains Mono', monospace;
        font-size: 14px;
        line-height: 1.6;
        background: #fafaf9; /* stone-50 */
        min-height: 60px;
    }
    .cm-editor.cm-focused { outline: none; }
    .cm-scroller { padding: 16px 20px; }
    .cm-content { caret-color: #375bbd; background: transparent; }
    .cm-cursor { border-left: 2px solid #375bbd; }
    .cm-selectionBackground { background: rgba(55, 91, 189, 0.15) !important; }
    .cm-activeLine { background: rgba(55, 91, 189, 0.06); }
    .cm-gutters { background: #f5f5f4; border-right: 1px solid #e7e5e4; color: #a8a29e; }
    .dark .cm-editor { background: #171717; /* neutral-900 */ }
    .dark .cm-gutters { background: #262626; border-right-color: #404040; color: #737373; }
    .dark .cm-activeLine { background: rgba(94, 122, 211, 0.08); }
    .dark .cm-selectionBackground { background: rgba(94, 122, 211, 0.25) !important; }
    .dark .cm-content { caret-color: #5e7ad3; }
    .dark .cm-cursor { border-left-color: #5e7ad3; }

    /* Pluto syntax highlighting */
    .cm-keyword { color: #815ba4; font-weight: 500; }
    .cm-function, .cm-callee { color: #375bbd; }
    .cm-string { color: #48b685; }
    .cm-number { color: #f99b15; }
    .cm-comment { color: #a8a29e; font-style: italic; }
    .cm-operator { color: #815ba4; }
    .cm-typeName { color: #00a9d1; }
    .cm-variableName { color: #1c1917; }
    .cm-propertyName { color: #cc80ac; }
    .dark .cm-variableName { color: #fafaf9; }
    .dark .cm-function, .dark .cm-callee { color: #5e7ad3; }
    .dark .cm-string { color: #00ab85; }
    .dark .cm-typeName { color: #00e7b4; }

    /* Cell state indicators */
    .cell.cell-running { border-color: #f99b15; }
    .cell.cell-running .run-btn { background: #f99b15; }
    .cell.cell-queued { border-color: #815ba4; }
    .cell.cell-queued .run-btn { background: #815ba4; }
    .cell.cell-error { border-color: #ef4444; }
    .cell.cell-error .run-btn { background: #ef4444; }
    .cell.cell-idle .run-btn { background: #375bbd; }
    .dark .cell.cell-idle .run-btn { background: #5e7ad3; }

    /* Running animation */
    .cell.cell-running .run-btn::after {
        content: '';
        position: absolute;
        width: 100%;
        height: 100%;
        top: 0;
        left: 0;
        background: linear-gradient(90deg, transparent, rgba(255,255,255,0.3), transparent);
        animation: shimmer 1.5s infinite;
    }
    @keyframes shimmer {
        0% { transform: translateX(-100%); }
        100% { transform: translateX(100%); }
    }
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
                console.log('[Sessions] CodeMirror loaded, available exports:', Object.keys(CM));

                // Build extensions array, checking each one exists
                const extensions = [];

                // Core extensions (should always exist)
                if (CM.lineNumbers) extensions.push(CM.lineNumbers());
                if (CM.highlightSpecialChars) extensions.push(CM.highlightSpecialChars());
                if (CM.history) extensions.push(CM.history());
                if (CM.drawSelection) extensions.push(CM.drawSelection());
                if (CM.indentOnInput) extensions.push(CM.indentOnInput());
                if (CM.bracketMatching) extensions.push(CM.bracketMatching());
                if (CM.closeBrackets) extensions.push(CM.closeBrackets());
                if (CM.highlightSelectionMatches) extensions.push(CM.highlightSelectionMatches());
                if (CM.EditorView?.lineWrapping) extensions.push(CM.EditorView.lineWrapping);

                // Julia syntax highlighting (Pluto's lezer-based highlighter)
                if (CM.julia_andrey) {
                    extensions.push(CM.julia_andrey());
                    console.log('[Sessions] Julia syntax highlighting enabled');
                }

                // Keymaps
                const keymaps = [];
                if (CM.defaultKeymap) keymaps.push(...CM.defaultKeymap);
                if (CM.historyKeymap) keymaps.push(...CM.historyKeymap);
                if (CM.closeBracketsKeymap) keymaps.push(...CM.closeBracketsKeymap);
                // Custom keybindings for cell execution
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
                    outputEl.style.display = html ? '' : 'none';
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
        // Channel Handlers (cell_added, cell_deleted)
        // =====================================================================

        function setupChannelHandlers() {
            if (typeof TherapyWS === 'undefined') return;

            // TODO: Implement proper DOM insertion for new cells
            // For now, reload on cell_added (cells_list signal will enable no-refresh later)
            TherapyWS.onChannelMessage('cell_added', () => location.reload());

            TherapyWS.onChannelMessage('cell_deleted', function(data) {
                const cell = document.querySelector('[data-cell-id="' + data.cell_id + '"]');
                if (cell) {
                    editors.delete(data.cell_id);
                    initialCode.delete(data.cell_id);
                    cell.remove();
                }
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

Design: Therapy.jl clean patterns with Pluto.jl branding.
- font-serif for headings (scholarly/calligraphy aesthetic)
- Pluto blue (#375bbd) as primary accent
- Clean transitions and dark mode support
"""
function Layout(content)
    Div(:class => "min-h-screen bg-neutral-100 dark:bg-neutral-950 transition-colors duration-200",
        # Navigation Bar (Therapy.jl style)
        Nav(:class => "bg-neutral-50 dark:bg-neutral-900 border-b border-neutral-300 dark:border-neutral-800 transition-colors duration-200",
            Div(:class => "max-w-5xl mx-auto px-4 sm:px-6 lg:px-8",
                Div(:class => "flex justify-between h-16",
                    # Logo & Title (serif font for calligraphy feel)
                    Div(:class => "flex items-center",
                        A(:href => "/", :class => "flex items-center",
                            Span(:class => "text-2xl font-serif font-bold text-pluto-blue dark:text-pluto-blue-light", "Sessions"),
                            Span(:class => "text-2xl font-serif font-light text-neutral-500 dark:text-neutral-500", ".jl")
                        )
                    ),

                    # Actions
                    Div(:class => "flex items-center gap-3",
                        # Run All Button (Pluto green)
                        Button(:class => "bg-pluto-green hover:bg-emerald-600 text-white px-4 py-2 rounded font-medium text-sm transition-colors shadow-sm flex items-center gap-2",
                            :onclick => "runAll()",
                            Span("▶"),
                            Span("Run All")
                        ),
                        # Save Button
                        Button(:class => "bg-neutral-200 dark:bg-neutral-800 text-neutral-700 dark:text-neutral-200 px-4 py-2 rounded font-medium text-sm hover:bg-neutral-300 dark:hover:bg-neutral-700 transition-colors",
                            :onclick => "saveNotebook()",
                            "Save"
                        ),
                        # Theme Toggle (Therapy.jl island - compiled to Wasm, no JavaScript)
                        DarkModeToggle()
                    )
                )
            )
        ),

        # Main Content Area
        MainEl(:id => "page-content", :class => "max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-8",
            content
        ),

        # Footer (Therapy.jl style)
        Footer(:class => "bg-neutral-50 dark:bg-neutral-900 border-t border-neutral-300 dark:border-neutral-800 mt-auto transition-colors duration-200",
            Div(:class => "max-w-5xl mx-auto py-6 px-4 sm:px-6 lg:px-8",
                Div(:class => "text-center",
                    P(:class => "text-neutral-500 dark:text-neutral-400 text-sm",
                        "Built with ",
                        A(:href => "https://github.com/TherapeuticJulia/Therapy.jl",
                          :class => "text-pluto-blue dark:text-pluto-blue-light hover:text-pluto-purple dark:hover:text-pluto-purple transition-colors",
                          :target => "_blank",
                          "Therapy.jl"
                        ),
                        " — A reactive web framework for Julia"
                    )
                )
            )
        )
    )
end

"""
Get complete head_extra content for render_page.
"""
function sessions_head_extra()
    # websocket_client_script() returns RawHtml, extract the content string
    ws_script = websocket_client_script()
    ws_str = ws_script isa Therapy.RawHtml ? ws_script.content : string(ws_script)
    sessions_styles() * ws_str * sessions_script()
end
