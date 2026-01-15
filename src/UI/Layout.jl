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
    }
    .cm-editor.cm-focused { outline: none; }
    .cm-scroller { padding: 16px 20px; }
    .cm-content { caret-color: #375bbd; }
    .cm-cursor { border-left: 2px solid #375bbd; }
    .cm-selectionBackground { background: rgba(55, 91, 189, 0.15) !important; }
    .cm-activeLine { background: rgba(55, 91, 189, 0.04); }
    .cm-gutters { background: #f5f5f4; border-right: 1px solid #e7e5e4; color: #a8a29e; }
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
    </style>
    """
end

"""
Sessions.jl JavaScript Bridge

Uses Therapy.jl's reactive WebSocket system properly:
1. Subscribes to server signals (cell_states, cell_outputs)
2. Listens to therapy:signal:* events for reactive updates
3. Sends actions via Therapy.jl channels
4. CodeMirror is the only external JS dependency
"""
function sessions_script()
    """
    <script>
    // Sessions.jl - Using Therapy.jl's Reactive WebSocket System
    (function() {
        'use strict';

        const editors = new Map();
        let notebookId = null;

        // =====================================================================
        // CodeMirror (Required - External JS Library)
        // =====================================================================

        async function initCodeMirror(container, code, cellId) {
            // Use Pluto's pre-bundled CodeMirror (avoids multiple instance issues)
            const CM = await import('codemirror-pluto');

            const view = new CM.EditorView({
                state: CM.EditorState.create({
                    doc: code,
                    extensions: [
                        // Core editor features
                        CM.lineNumbers(),
                        CM.highlightSpecialChars(),
                        CM.history(),
                        CM.drawSelection(),
                        CM.indentOnInput(),
                        CM.bracketMatching(),
                        CM.closeBrackets(),
                        CM.highlightSelectionMatches(),
                        CM.EditorView.lineWrapping,

                        // Julia syntax highlighting
                        CM.julia_andrey(),

                        // Keymaps
                        CM.keymap.of([
                            ...CM.defaultKeymap,
                            ...CM.historyKeymap,
                            ...CM.closeBracketsKeymap,
                            { key: 'Shift-Enter', run: () => { executeCell(cellId); return true; } },
                            { key: 'Mod-Enter', run: () => { executeCell(cellId); return true; } }
                        ])
                    ]
                }),
                parent: container
            });
            editors.set(cellId, view);
        }

        function getCode(cellId) {
            const editor = editors.get(cellId);
            return editor ? editor.state.doc.toString() : '';
        }

        // =====================================================================
        // Therapy.jl Channel Actions
        // =====================================================================

        function sendAction(channel, data) {
            if (typeof TherapyWS !== 'undefined' && TherapyWS.isConnected()) {
                TherapyWS.sendMessage(channel, data);
            }
        }

        function executeCell(cellId) {
            sendAction('execute', {
                notebook_id: notebookId,
                cell_id: cellId,
                code: getCode(cellId)
            });
        }

        // =====================================================================
        // Therapy.jl Server Signal Handlers
        // Using therapy:signal:* events for reactive updates
        // =====================================================================

        function setupSignalHandlers() {
            // Subscribe to cell_states and cell_outputs signals
            if (typeof TherapyWS !== 'undefined') {
                TherapyWS.subscribe('cell_states');
                TherapyWS.subscribe('cell_outputs');
            }

            // Handle cell_states signal updates (reactive CSS class updates)
            window.addEventListener('therapy:signal:cell_states', function(e) {
                const states = e.detail.value;
                if (!states) return;

                for (const [cellId, state] of Object.entries(states)) {
                    const cell = document.querySelector('[data-cell-id="' + cellId + '"]');
                    if (cell) {
                        cell.classList.remove('cell-running', 'cell-queued', 'cell-error', 'cell-idle');
                        const cls = state === 'CELL_RUNNING' ? 'cell-running' :
                                    state === 'CELL_QUEUED' ? 'cell-queued' :
                                    state === 'CELL_ERROR' ? 'cell-error' : 'cell-idle';
                        cell.classList.add(cls);
                    }
                }
            });

            // Handle cell_outputs signal updates (reactive HTML updates)
            window.addEventListener('therapy:signal:cell_outputs', function(e) {
                const outputs = e.detail.value;
                if (!outputs) return;

                for (const [cellId, outputData] of Object.entries(outputs)) {
                    const cell = document.querySelector('[data-cell-id="' + cellId + '"]');
                    if (!cell) continue;

                    let outputEl = cell.querySelector('.cell-output');

                    if (outputData && outputData.html) {
                        if (!outputEl) {
                            outputEl = document.createElement('div');
                            outputEl.className = 'cell-output border-t border-neutral-200 dark:border-neutral-700 p-4 bg-neutral-50 dark:bg-neutral-800/50 font-mono text-sm';
                            const container = cell.querySelector('.cell-code-container');
                            if (container) container.after(outputEl);
                        }
                        outputEl.innerHTML = outputData.html;

                        // Update runtime badge if present
                        if (outputData.runtime_ms) {
                            let badge = cell.querySelector('.runtime-badge');
                            if (badge) badge.textContent = outputData.runtime_ms.toFixed(1) + 'ms';
                        }
                    }
                }
            });
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
        // Channel Handlers (for cell_added, cell_deleted)
        // =====================================================================

        function setupChannelHandlers() {
            if (typeof TherapyWS === 'undefined') return;

            TherapyWS.onChannelMessage('cell_added', () => location.reload());
            TherapyWS.onChannelMessage('cell_deleted', function(data) {
                const cell = document.querySelector('[data-cell-id="' + data.cell_id + '"]');
                if (cell) {
                    editors.delete(data.cell_id);
                    cell.remove();
                }
            });
        }

        // =====================================================================
        // Initialization
        // =====================================================================

        function init() {
            console.log('[Sessions] Initializing with Therapy.jl reactive WebSocket...');

            // Action delegation
            document.addEventListener('click', handleAction);

            // Set up Therapy.jl signal handlers (reactive updates)
            setupSignalHandlers();

            // Set up channel handlers
            setupChannelHandlers();

            // Initialize CodeMirror editors
            document.querySelectorAll('.cell').forEach(async function(cell) {
                const cellId = cell.dataset.cellId;
                const container = cell.querySelector('.cell-code-container');
                const codeEl = cell.querySelector('.cell-code');
                if (container && codeEl && !editors.has(cellId)) {
                    const code = codeEl.textContent || '';
                    codeEl.remove();
                    await initCodeMirror(container, code, cellId);
                }
            });
        }

        // Global API
        window.setNotebookId = function(id) { notebookId = id; };
        window.runAll = function() { sendAction('run_all', { notebook_id: notebookId }); };
        window.saveNotebook = function() { sendAction('save', { notebook_id: notebookId }); };

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
                        # Theme Toggle
                        Button(:class => "p-2 rounded text-neutral-500 hover:text-neutral-700 dark:text-neutral-400 dark:hover:text-neutral-200 hover:bg-neutral-200 dark:hover:bg-neutral-800 transition-colors",
                            :onclick => "document.documentElement.classList.toggle('dark')",
                            :title => "Toggle dark mode",
                            Svg(:class => "w-5 h-5", :fill => "none", :viewBox => "0 0 24 24", :stroke => "currentColor", :stroke_width => "2",
                                Path(:d => "M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z")
                            )
                        )
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
