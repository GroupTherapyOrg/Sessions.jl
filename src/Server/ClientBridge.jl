# ClientBridge.jl - Minimal JavaScript for Sessions.jl
#
# Architecture:
# - Server renders ALL UI as Therapy.jl VNodes → HTML
# - This file contains ONLY:
#   1. WebSocket connection (network I/O - unavoidable in JS)
#   2. CodeMirror editor management (external JS library)
#   3. DOM insertion for server-rendered HTML
#
# Everything else is handled by:
# - Therapy.jl components (server-side rendering)
# - Wasm islands (reactive UI state)

"""
    head_extra()

CSS styles for the page. No JavaScript here.
"""
function head_extra()
    raw"""
    <script src="https://cdn.tailwindcss.com"></script>

    <style>
        /* Cell status indicators */
        .cell[data-status="idle"] { border-left: 3px solid #6b7280; }
        .cell[data-status="queued"] { border-left: 3px solid #eab308; }
        .cell[data-status="running"] { border-left: 3px solid #eab308; animation: pulse 1s infinite; }
        .cell[data-status="completed"] { border-left: 3px solid #22c55e; }
        .cell[data-status="errored"] { border-left: 3px solid #ef4444; }

        @keyframes pulse { 50% { opacity: 0.7; } }

        /* File tree */
        .file-item:hover { background: rgba(255,255,255,0.1); }

        /* CodeMirror */
        .cm-editor { background: #1e1e2e !important; border-radius: 0.375rem; }
        .cm-editor.cm-focused { outline: none !important; }
        .cm-editor .cm-content { font-family: 'JuliaMono', monospace; padding: 8px; }
        .cm-editor .cm-gutters { background: #181825 !important; border-right: 1px solid #313244; }
    </style>
    """
end

"""
    client_script()

Minimal JavaScript:
- WebSocket connection
- CodeMirror editor management
- DOM updates for server-rendered HTML
"""
function client_script()
    raw"""
    <script type="module">
    // ==========================================================================
    // CodeMirror (external library - requires JS)
    // ==========================================================================
    import {
        EditorView,
        EditorState,
        julia_andrey as julia,
        keymap,
        defaultKeymap,
        history,
        historyKeymap,
        lineNumbers,
        bracketMatching,
        closeBrackets,
        closeBracketsKeymap,
        drawSelection
    } from 'https://cdn.jsdelivr.net/gh/JuliaPluto/codemirror-pluto-setup@0.19.6/dist/index.es.min.js';

    // ==========================================================================
    // State (minimal - just what JS needs)
    // ==========================================================================
    let ws = null;
    const editors = new Map();  // cell_id -> EditorView
    let currentPath = '.';

    // Update cell count in the NotebookControlsIsland
    function updateCellCount(count) {
        // Find the cell count element within the island (has data-hk attribute)
        const island = document.querySelector('therapy-island[data-component="notebookcontrolsisland"]');
        if (island) {
            // The cell count is in the span with hydration key 3
            const countEl = island.querySelector('[data-hk="3"]');
            if (countEl) {
                countEl.textContent = count;
            }
        }
    }

    // ==========================================================================
    // WebSocket (network I/O - unavoidable in JS)
    // ==========================================================================
    function connect() {
        ws = new WebSocket(`ws://${location.host}/ws`);

        ws.onopen = () => {
            console.log('Sessions: Connected');
            send('get_state', {});
        };

        ws.onmessage = (event) => {
            const msg = JSON.parse(event.data);
            handleMessage(msg);
        };

        ws.onclose = () => {
            console.log('Sessions: Disconnected, reconnecting...');
            setTimeout(connect, 1000);
        };

        ws.onerror = (e) => console.error('Sessions: WebSocket error', e);
    }

    function send(type, body) {
        if (ws?.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({ type, body }));
        }
    }

    // ==========================================================================
    // Message Handlers (receive server-rendered HTML)
    // ==========================================================================
    const handlers = {
        // Full cells HTML from server
        cells_html: (body) => {
            const container = document.getElementById('cells');
            if (container) {
                // Clear old editors
                editors.forEach(e => e.destroy());
                editors.clear();

                // Insert server-rendered HTML
                container.innerHTML = body.html;

                // Initialize CodeMirror for each cell
                initializeEditors();
                bindCellEvents();

                // Update cell count display
                updateCellCount(body.cell_count);
            }
        },

        // Single cell update from server
        cell_html: (body) => {
            const cellEl = document.querySelector(`.cell[data-id="${body.cell_id}"]`);
            if (cellEl) {
                // Preserve editor state
                const editor = editors.get(body.cell_id);
                const code = editor ? editor.state.doc.toString() : '';

                // Update cell HTML
                const temp = document.createElement('div');
                temp.innerHTML = body.html;
                const newCell = temp.firstElementChild;

                // Replace the cell
                cellEl.replaceWith(newCell);

                // Reinitialize editor with preserved code
                initializeEditor(body.cell_id, code);
                bindCellEvent(body.cell_id);
            }
        },

        // File tree HTML from server
        files_html: (body) => {
            currentPath = body.path;
            const tree = document.getElementById('file-tree');
            if (tree) {
                tree.innerHTML = body.html;
                bindFileEvents();
            }
        },

        // Terminal output
        terminal_output: (body) => {
            const el = document.getElementById('terminal-output');
            if (el) {
                el.textContent += body.output + '\n';
                el.scrollTop = el.scrollHeight;
            }
        },

        // File content
        file_content: (body) => {
            console.log('File opened:', body.path, body.content.slice(0, 100));
        }
    };

    function handleMessage(msg) {
        const handler = handlers[msg.type];
        if (handler) {
            handler(msg.body);
        }
    }

    // ==========================================================================
    // CodeMirror Editor Management
    // ==========================================================================
    function initializeEditors() {
        document.querySelectorAll('.editor-container').forEach(container => {
            const cellId = container.dataset.id;
            const code = container.dataset.code || '';
            initializeEditor(cellId, code);
        });
    }

    function initializeEditor(cellId, code) {
        const container = document.querySelector(`.editor-container[data-id="${cellId}"]`);
        if (!container) return;

        // Remove any existing content
        container.innerHTML = '';

        const editor = new EditorView({
            state: EditorState.create({
                doc: code,
                extensions: [
                    lineNumbers(),
                    history(),
                    drawSelection(),
                    bracketMatching(),
                    closeBrackets(),
                    julia(),
                    EditorView.theme({
                        '&': { backgroundColor: '#1e1e2e', color: '#cdd6f4' }
                    }, { dark: true }),
                    keymap.of([
                        ...closeBracketsKeymap,
                        ...defaultKeymap,
                        ...historyKeymap,
                        {
                            key: 'Shift-Enter',
                            run: () => {
                                runCell(cellId);
                                return true;
                            }
                        }
                    ])
                ]
            }),
            parent: container
        });

        editors.set(cellId, editor);
    }

    function runCell(cellId) {
        const editor = editors.get(cellId);
        if (editor) {
            send('run_cell', {
                cell_id: cellId,
                code: editor.state.doc.toString()
            });
        }
    }

    // ==========================================================================
    // Event Bindings (minimal - just connect DOM to WebSocket)
    // ==========================================================================
    function bindCellEvents() {
        document.querySelectorAll('.cell').forEach(cell => {
            bindCellEvent(cell.dataset.id);
        });
    }

    function bindCellEvent(cellId) {
        const cell = document.querySelector(`.cell[data-id="${cellId}"]`);
        if (!cell) return;

        const runBtn = cell.querySelector('.run-btn');
        const deleteBtn = cell.querySelector('.delete-btn');

        if (runBtn) {
            runBtn.onclick = () => runCell(cellId);
        }
        if (deleteBtn) {
            deleteBtn.onclick = () => send('delete_cell', { cell_id: cellId });
        }
    }

    function bindFileEvents() {
        document.querySelectorAll('.file-item').forEach(el => {
            el.onclick = () => {
                const isDir = el.dataset.dir === '1';
                send(isDir ? 'list_files' : 'open_file', { path: el.dataset.path });
            };
        });
    }

    // ==========================================================================
    // Initialize
    // ==========================================================================
    document.addEventListener('DOMContentLoaded', () => {
        // Toolbar buttons
        document.getElementById('btn-add-cell')?.addEventListener('click', () => send('add_cell', {}));
        document.getElementById('btn-run-all')?.addEventListener('click', () => send('run_all', {}));
        document.getElementById('btn-restart')?.addEventListener('click', () => send('restart', {}));
        document.getElementById('btn-refresh-files')?.addEventListener('click', () => send('list_files', { path: currentPath }));

        // Terminal input (WebSocket communication still needed)
        const termInput = document.getElementById('terminal-input');
        if (termInput) {
            termInput.onkeydown = (e) => {
                if (e.key === 'Enter' && termInput.value.trim()) {
                    send('terminal', { input: termInput.value });
                    termInput.value = '';
                }
            };
        }

        // Connect WebSocket
        connect();
    });
    </script>
    """
end
