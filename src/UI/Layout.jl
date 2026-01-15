# Layout.jl - Main application layout
#
# The root layout component for Sessions, wrapping all pages.
# Theme: Therapy.jl parchment base with Pluto.jl reactive accents

using Therapy

"""
CSS styles for Sessions (CodeMirror + Pluto theme).
"""
function sessions_styles()
    """
    <style>
    /* Font Loading */
    @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&display=swap');

    /* Pluto-inspired Color Variables */
    :root {
        --pluto-blue: #375bbd;
        --pluto-blue-light: #5e7ad3;
        --pluto-purple: #815ba4;
        --pluto-green: #48b685;
        --pluto-orange: #f99b15;
        --pluto-cyan: #00a9d1;
        --cell-running: #3b82f6;
        --cell-queued: #f59e0b;
        --cell-error: #ef4444;
        --cell-idle: transparent;
        --bg-primary: #fafaf9;
        --bg-secondary: #f5f5f4;
        --bg-tertiary: #e7e5e4;
        --text-primary: #1c1917;
        --text-secondary: #57534e;
        --text-muted: #a8a29e;
        --border-color: #d6d3d1;
        --accent-primary: #059669;
    }

    .dark {
        --bg-primary: #171717;
        --bg-secondary: #262626;
        --bg-tertiary: #404040;
        --text-primary: #fafaf9;
        --text-secondary: #d6d3d1;
        --text-muted: #737373;
        --border-color: #404040;
        --pluto-blue: #3271e7;
        --pluto-cyan: #00e7b4;
    }

    /* CodeMirror Theme */
    .cm-editor {
        font-family: 'JetBrains Mono', monospace;
        font-size: 14px;
        background: var(--bg-primary);
    }
    .cm-editor.cm-focused { outline: none; }
    .cm-scroller { padding: 12px 16px; }
    .cm-content { caret-color: var(--pluto-blue); }
    .cm-cursor { border-left: 2px solid var(--pluto-blue); }
    .cm-selectionBackground { background: rgba(55, 91, 189, 0.2) !important; }
    .cm-activeLine { background: rgba(55, 91, 189, 0.05); }
    .cm-gutters { background: var(--bg-secondary); border-right: 1px solid var(--border-color); }

    /* Syntax Highlighting */
    .cm-keyword { color: var(--pluto-purple); font-weight: 500; }
    .cm-function, .cm-callee { color: var(--pluto-blue); }
    .cm-string { color: var(--pluto-green); }
    .cm-number { color: var(--pluto-orange); }
    .cm-comment { color: var(--text-muted); font-style: italic; }
    .cm-operator { color: var(--pluto-purple); }
    .cm-typeName { color: var(--pluto-cyan); }

    /* Cell States */
    .cell { transition: border-color 0.2s, box-shadow 0.2s; position: relative; }
    .cell-running { border-left: 3px solid var(--cell-running) !important; }
    .cell-queued { border-left: 3px solid var(--cell-queued) !important; }
    .cell-error { border-left: 3px solid var(--cell-error) !important; }
    .cell-idle { border-left: 3px solid transparent; }

    /* Run Button */
    .run-btn { background: var(--pluto-green); transition: background 0.2s; }
    .run-btn:hover { background: #3da076; }

    /* Cell Output */
    .cell-output { font-family: 'JetBrains Mono', monospace; font-size: 13px; }
    .cell-output pre { white-space: pre-wrap; margin: 0; }
    .cell-output .error-message { color: #dc2626; font-weight: 500; }
    .dark .cell-output .error-message { color: #f87171; }

    /* Add Cell Button */
    .add-cell-btn { opacity: 0; transition: opacity 0.2s; }
    .cell:hover .add-cell-btn { opacity: 1; }

    .notebook-container { max-width: 900px; margin: 0 auto; }
    .runtime-badge { font-family: 'JetBrains Mono', monospace; font-size: 11px; }
    </style>

    <!-- Tailwind CSS -->
    <script src="https://cdn.tailwindcss.com"></script>

    <!-- CodeMirror 6 via Pluto's pre-bundled setup (avoids multiple instance issues) -->
    <script type="importmap">
    {
        "imports": {
            "codemirror-pluto": "https://cdn.jsdelivr.net/gh/JuliaPluto/codemirror-pluto-setup@0.19.3/dist/index.es.min.js"
        }
    }
    </script>
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
                            outputEl.className = 'cell-output border-t border-neutral-200 dark:border-neutral-700 p-4 bg-neutral-50 dark:bg-neutral-800/50';
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
"""
function Layout(content)
    Div(:class => "min-h-screen bg-neutral-50 dark:bg-neutral-900",
        # Header
        Header(:class => "bg-white dark:bg-neutral-800 border-b border-neutral-200 dark:border-neutral-700 px-4 py-2 flex items-center justify-between sticky top-0 z-10",
            Div(:class => "flex items-center gap-4",
                H1(:class => "text-xl font-semibold",
                    Span(:class => "text-emerald-600 dark:text-emerald-400", "Sessions"),
                    Span(:class => "text-neutral-400 font-light", ".jl")
                ),
                Span(:class => "text-sm text-neutral-500 hidden sm:inline", "Julia Notebook")
            ),
            Div(:class => "flex items-center gap-2",
                Button(:class => "run-btn px-3 py-1.5 text-sm text-white rounded font-medium",
                    :onclick => "runAll()",
                    "▶ Run All"
                ),
                Button(:class => "px-3 py-1.5 text-sm bg-neutral-200 dark:bg-neutral-700 text-neutral-700 dark:text-neutral-200 rounded hover:bg-neutral-300 transition-colors",
                    :onclick => "saveNotebook()",
                    "Save"
                )
            )
        ),

        # Main content
        MainEl(:id => "page-content", :class => "p-4",
            content
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
