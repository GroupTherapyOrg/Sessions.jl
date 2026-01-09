# ClientBridge.jl - WebSocket client JavaScript for Sessions.jl
#
# Following Pluto's approach: simple message types mapped to handlers.
# Messages have format: { type: "...", body: {...} }
# Server responds with: { type: "...", body: {...} }

"""
    head_extra()

Returns the CSS for the page.
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
        .cell[data-status="error"] { border-left: 3px solid #ef4444; }

        @keyframes pulse { 50% { opacity: 0.7; } }

        /* File tree */
        .file-item:hover { background: rgba(255,255,255,0.1); }
        .file-item.directory::before { content: "📁 "; }
        .file-item.file::before { content: "📄 "; }

        /* CodeMirror */
        .cm-editor { background: #1e1e2e !important; border-radius: 0.375rem; }
        .cm-editor.cm-focused { outline: none !important; }
        .cm-editor .cm-content { font-family: 'JuliaMono', monospace; padding: 8px; }
        .cm-editor .cm-gutters { background: #181825 !important; border-right: 1px solid #313244; }
    </style>
    """
end

"""
    websocket_bridge_script()

JavaScript client following Pluto's pattern:
- Simple message format: { type, body }
- Handler functions for each message type
"""
function websocket_bridge_script()
    raw"""
    <script type="module">
    console.log('Sessions.jl: Script module loading...');

    // CodeMirror from Pluto's bundle
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

    console.log('Sessions.jl: CodeMirror imports successful');

    // ==========================================================================
    // State
    // ==========================================================================
    let ws = null;
    let cells = [];
    let editors = new Map();

    // ==========================================================================
    // WebSocket (Pluto-style)
    // ==========================================================================
    function connect() {
        ws = new WebSocket(`ws://${location.host}/ws`);

        ws.onopen = () => {
            console.log('Connected to Sessions');
            // Request initial state
            send('get_state', {});
        };

        ws.onmessage = (event) => {
            const msg = JSON.parse(event.data);
            console.log('Received:', msg.type, msg);
            handleMessage(msg);
        };

        ws.onclose = () => {
            console.log('Disconnected, reconnecting...');
            setTimeout(connect, 1000);
        };

        ws.onerror = (e) => console.error('WebSocket error:', e);
    }

    function send(type, body) {
        const msg = JSON.stringify({ type, body });
        console.log('Sending:', type, body);
        if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(msg);
        } else {
            console.error('WebSocket not ready');
        }
    }

    // ==========================================================================
    // Message Handlers (Pluto-style responses dict)
    // ==========================================================================
    const handlers = {
        cells_state: (body) => {
            cells = body.cells;
            renderCells();
        },

        cell_update: (body) => {
            const idx = cells.findIndex(c => c.id === body.cell.id);
            if (idx >= 0) {
                cells[idx] = body.cell;
                updateCell(body.cell);
            }
        },

        files: (body) => {
            renderFiles(body.path, body.entries);
        },

        terminal_output: (body) => {
            const el = document.getElementById('terminal-output');
            if (el) {
                el.textContent += body.output + '\n';
                el.scrollTop = el.scrollHeight;
            }
        }
    };

    function handleMessage(msg) {
        const handler = handlers[msg.type];
        if (handler) {
            handler(msg.body || msg);
        } else {
            console.warn('Unknown message type:', msg.type);
        }
    }

    // ==========================================================================
    // Cell Rendering
    // ==========================================================================
    function renderCells() {
        const container = document.getElementById('cells');
        if (!container) return;

        // Clear old editors
        editors.forEach(e => e.destroy());
        editors.clear();

        container.innerHTML = cells.map(cell => `
            <div class="cell bg-gray-800 rounded-lg mb-4" data-id="${cell.id}" data-status="${cell.status_name?.toLowerCase() || 'idle'}">
                <div class="flex items-center h-10 px-3 bg-gray-700 rounded-t-lg">
                    <span class="text-xs text-gray-500 mr-2">[${cell.execution_count || 0}]</span>
                    <div class="flex-1"></div>
                    <button class="run-btn px-3 py-1 text-xs text-gray-300 hover:bg-gray-600 rounded">Run</button>
                    <button class="delete-btn px-2 py-1 text-xs text-gray-400 hover:text-red-400 rounded ml-1">×</button>
                </div>
                <div class="editor-container" data-id="${cell.id}"></div>
                <div class="output px-3 pb-3"></div>
            </div>
        `).join('');

        // Create editors and bind events
        cells.forEach(cell => {
            const container = document.querySelector(`.editor-container[data-id="${cell.id}"]`);
            if (!container) return;

            const editor = new EditorView({
                state: EditorState.create({
                    doc: cell.code || '',
                    extensions: [
                        lineNumbers(),
                        history(),
                        drawSelection(),
                        bracketMatching(),
                        closeBrackets(),
                        julia(),
                        EditorView.theme({ '&': { backgroundColor: '#1e1e2e', color: '#cdd6f4' } }, { dark: true }),
                        keymap.of([
                            ...closeBracketsKeymap,
                            ...defaultKeymap,
                            ...historyKeymap,
                            { key: 'Shift-Enter', run: () => { runCell(cell.id, editor); return true; } }
                        ])
                    ]
                }),
                parent: container
            });

            editors.set(cell.id, editor);
            updateCellOutput(cell);
        });

        // Bind button events
        document.querySelectorAll('.run-btn').forEach(btn => {
            btn.onclick = () => {
                const cellEl = btn.closest('.cell');
                const id = cellEl.dataset.id;
                const editor = editors.get(id);
                if (editor) runCell(id, editor);
            };
        });

        document.querySelectorAll('.delete-btn').forEach(btn => {
            btn.onclick = () => {
                const cellEl = btn.closest('.cell');
                send('delete_cell', { cell_id: cellEl.dataset.id });
            };
        });
    }

    function updateCell(cell) {
        const cellEl = document.querySelector(`.cell[data-id="${cell.id}"]`);
        if (!cellEl) return;

        cellEl.dataset.status = cell.status_name?.toLowerCase() || 'idle';
        const countEl = cellEl.querySelector('.text-xs.text-gray-500');
        if (countEl) countEl.textContent = `[${cell.execution_count || 0}]`;

        updateCellOutput(cell);
    }

    function updateCellOutput(cell) {
        const cellEl = document.querySelector(`.cell[data-id="${cell.id}"]`);
        if (!cellEl) return;

        const outputEl = cellEl.querySelector('.output');
        if (!outputEl) return;

        let html = '';
        if (cell.stdout) {
            html += `<pre class="bg-gray-900 rounded p-2 text-sm text-gray-300 whitespace-pre-wrap">${escapeHtml(cell.stdout)}</pre>`;
        }
        if (cell.status_name === 'COMPLETED' && cell.output && cell.output !== 'nothing') {
            html += `<pre class="bg-gray-900 rounded p-2 text-sm text-blue-400 mt-2">${escapeHtml(cell.output)}</pre>`;
        }
        if (cell.status_name === 'ERRORED' && cell.error_msg) {
            html += `<pre class="bg-red-900/30 rounded p-2 text-sm text-red-400 mt-2 whitespace-pre-wrap">${escapeHtml(cell.error_msg)}</pre>`;
        }
        outputEl.innerHTML = html;
    }

    function runCell(id, editor) {
        send('run_cell', { cell_id: id, code: editor.state.doc.toString() });
    }

    function escapeHtml(s) {
        return s ? s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;') : '';
    }

    // ==========================================================================
    // Files
    // ==========================================================================
    let currentPath = '.';

    function renderFiles(path, entries) {
        currentPath = path;
        const tree = document.getElementById('file-tree');
        if (!tree) return;

        let html = '';
        if (path !== '.') {
            const parent = path.split('/').slice(0,-1).join('/') || '.';
            html += `<div class="file-item cursor-pointer px-2 py-1" data-path="${parent}" data-dir="1">..</div>`;
        }
        entries.forEach(e => {
            const cls = e.is_directory ? 'directory' : 'file';
            html += `<div class="file-item ${cls} cursor-pointer px-2 py-1" data-path="${e.path}" data-dir="${e.is_directory?1:0}">${e.name}</div>`;
        });
        tree.innerHTML = html;

        tree.querySelectorAll('.file-item').forEach(el => {
            el.onclick = () => send(el.dataset.dir==='1' ? 'list_files' : 'open_file', { path: el.dataset.path });
        });
    }

    // ==========================================================================
    // Initialize
    // ==========================================================================
    document.addEventListener('DOMContentLoaded', () => {
        document.getElementById('btn-add-cell')?.addEventListener('click', () => send('add_cell', {}));
        document.getElementById('btn-run-all')?.addEventListener('click', () => send('run_all', {}));
        document.getElementById('btn-restart')?.addEventListener('click', () => send('restart', {}));
        document.getElementById('btn-refresh-files')?.addEventListener('click', () => send('list_files', { path: currentPath }));

        const termInput = document.getElementById('terminal-input');
        if (termInput) {
            termInput.onkeydown = (e) => {
                if (e.key === 'Enter' && termInput.value.trim()) {
                    send('terminal', { input: termInput.value });
                    termInput.value = '';
                }
            };
        }

        console.log('Sessions.jl: DOMContentLoaded, calling connect()...');
        connect();
    });
    </script>
    """
end
