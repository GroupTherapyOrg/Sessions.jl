# Layout.jl — HTML shell for Sessions.jl Web UI
#
# Always-dark IDE layout with custom color palette.
# Injects Google Fonts, Tailwind CDN with custom theme config,
# full CSS for cell controls / scrollbar / CodeMirror overrides,
# and the editor.js bundle + CM initialization scripts.

# Load CodeMirror bundle at include time (589KB, inlined into page)
const _EDITOR_BUNDLE_JS = let
    p = joinpath(@__DIR__, "..", "..", "static", "editor.js")
    isfile(p) ? read(p, String) : "/* editor.js not found */"
end

function Layout(children...; title="Sessions.jl")
    Fragment(
        # --- Google Fonts ---
        RawHtml("""<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,100..1000;1,9..40,100..1000&family=JetBrains+Mono:ital,wght@0,100..800;1,100..800&family=Fraunces:ital,opsz,wght@0,9..144,100..900;1,9..144,100..900&display=swap" rel="stylesheet">"""),

        # --- Shoelace Web Components (dark theme) ---
        RawHtml("""<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/themes/dark.css" />
<script type="module" src="https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/shoelace-autoloader.js"></script>
<script>document.documentElement.classList.add('sl-theme-dark');</script>"""),

        # --- xterm.js (terminal emulator) ---
        RawHtml("""<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/css/xterm.css" />
<script src="https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/lib/xterm.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/lib/addon-fit.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@xterm/addon-web-links@0.11.0/lib/addon-web-links.js"></script>"""),

        # --- Tailwind CDN + custom config ---
        RawHtml("""<script src="https://cdn.tailwindcss.com"></script>
<script>
tailwind.config = {
  theme: {
    extend: {
      colors: {
        deep:'#0a0e14', base:'#0f1419', surf:'#151c25', island:'#1a2332', hov:'#1f2b3d',
        b1:'#1c2736', b2:'#2a3a4f',
        t1:'#d4dce8', t2:'#9baabd', t3:'#4a5568', t4:'#3d5068', tout:'#7ca0bf',
        accent:'#56d4a0', jr:'#e06b65', jg:'#56d4a0', jp:'#b08fd8',
      },
      fontFamily: {
        sans:['DM Sans','system-ui','sans-serif'],
        mono:['JetBrains Mono','SF Mono','monospace'],
        display:['Fraunces','Georgia','serif'],
      },
    }
  }
}
</script>"""),

        # --- Full CSS ---
        RawHtml("""<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0;}
html,body{height:100%;overflow:hidden;margin:0;padding:0;}
/* #sessions-root is the layout owner — uses 100vh to bypass all Therapy wrappers */
#sessions-root{display:flex;flex-direction:column;height:100vh;overflow:hidden;position:fixed;top:0;left:0;right:0;bottom:0;z-index:1;}
/* IDE theme: Dark (neutral gray workspace — t3 #4a5568 as bg) */
#sessions-root[data-ide-theme="dark"]{background:#4a5568;}
#sessions-root[data-ide-theme="dark"] #status-bar{box-shadow:0 -4px 8px rgba(0,0,0,.25) !important;color:#0a0e14 !important;font-weight:600 !important;}
[data-ide-theme="dark"] #app-root{background:#4a5568 !important;}
#workspace{flex:1 1 0%;display:flex;gap:12px;padding:12px;min-height:0;overflow:hidden;}
#workspace>div{min-height:0;}
/* Activity bar button: active highlight when panel is open.
   !important needed to override inline style from _AB_BTN_STYLE */
/* Activity bar */
.ab-btn[data-state="on"]{background:rgba(86,212,160,.08) !important;color:#56d4a0 !important;}
.ab-btn:hover{background:rgba(86,212,160,.06) !important;color:#9baabd !important;}
/* Shared notebook CSS (cell chrome, md-prose, sst-*, cm overrides) */
$(Main.Sessions.NOTEBOOK_CSS)
/* Layout-only cell state overrides */
.code-cell.idle::before{background:#3d5068;opacity:.2;}
.code-cell.executing::before{opacity:0 !important;}
.md-cell::before{content:'';position:absolute;left:0;top:0;bottom:0;width:2px;background:#b08fd8;opacity:.4;border-radius:2px 0 0 2px;}
.cell-collapsed .cm-cell{display:none;}
.cell-collapsed .cell-ctrls{display:none;}
.cell-collapsed::before{opacity:.15!important;}
.cell-collapsed{border-style:dashed!important;opacity:.4;max-height:8px;overflow:hidden;}
.cdiv:hover .cdiv-inner{opacity:1;}
.chv{transition:transform .12s ease;}
.chv.open{transform:rotate(90deg);}
.tab.active::after{content:'';position:absolute;bottom:0;left:0;right:0;height:2px;background:#56d4a0;border-radius:2px 2px 0 0;}
#fpanel.hide{width:0!important;opacity:0;padding:0;border:none;overflow:hidden;pointer-events:none;}
::-webkit-scrollbar{width:5px;height:5px;}
::-webkit-scrollbar-track{background:transparent;}
::-webkit-scrollbar-thumb{background:#2a3a4f;border-radius:3px;}
::selection{background:rgba(86,212,160,.2);}
@keyframes blink{50%{opacity:0}}
.cblink{animation:blink 1s step-end infinite;}
@keyframes pulse{0%,100%{opacity:1;}50%{opacity:0.4;}}
.code-cell.stale::before{background:#d4a056;opacity:.5;}
.md-prose h5,.md-prose h6{font-family:'Fraunces',Georgia,serif;font-size:1rem;font-weight:600;color:#d4dce8;margin:0.6em 0 0.2em;}
/* Shoelace dark theme overrides — match Sessions.jl palette */
:root{--sl-color-neutral-0:#0a0e14;--sl-color-neutral-50:#0f1419;--sl-color-neutral-100:#151c25;--sl-color-neutral-200:#1a2332;--sl-color-neutral-300:#1c2736;--sl-color-neutral-400:#2a3a4f;--sl-color-neutral-500:#3d5068;--sl-color-neutral-600:#4a5568;--sl-color-neutral-700:#9baabd;--sl-color-neutral-800:#d4dce8;--sl-color-neutral-900:#d4dce8;--sl-color-neutral-1000:#ffffff;--sl-color-primary-600:#56d4a0;--sl-font-sans:'DM Sans',system-ui,sans-serif;--sl-font-mono:'JetBrains Mono',monospace;--sl-font-size-small:12px;}
sl-tree{--indent-size:14px;--indent-guide-width:1px;--indent-guide-color:#1c2736;}
sl-tree-item::part(label){font-size:12px;font-family:'JetBrains Mono',monospace;color:#4a5568;display:flex;align-items:center;gap:6px;}
sl-tree-item::part(item){border-radius:4px;padding:1px 4px;transition:background .12s,color .12s;}
sl-tree-item::part(item--selected){background:rgba(86,212,160,.08);outline:none;}
sl-tree-item::part(expand-button){color:#3d5068;padding-right:0;}
sl-tree-item[selected]::part(label){color:#d4dce8;}
sl-tree-item[selected]{border-left:2px solid #56d4a0;}
sl-tree-item::part(item):hover{background:rgba(255,255,255,.03);}
.tree-label{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
.tree-rename-input{background:#1a2332;border:1px solid #56d4a0;border-radius:3px;color:#d4dce8;font-family:'JetBrains Mono',monospace;font-size:12px;padding:1px 4px;outline:none;width:100%;}
.file-ctx-menu{display:none;position:fixed;z-index:9999;background:#1a2332;border:1px solid #2a3a4f;border-radius:8px;min-width:160px;box-shadow:0 8px 24px rgba(0,0,0,.5);overflow:hidden;padding:4px 0;}
.file-ctx-item{display:flex;align-items:center;gap:8px;padding:6px 12px;font-size:12px;cursor:pointer;color:#9baabd;font-family:'JetBrains Mono',monospace;transition:background .1s,color .1s;}
.file-ctx-item:hover{background:rgba(86,212,160,.08);color:#d4dce8;}
.file-ctx-item.danger:hover{background:rgba(224,107,101,.12);color:#e06b65;}
.file-ctx-sep{height:1px;background:#2a3a4f;margin:4px 8px;}
.tree-breadcrumb{display:flex;align-items:center;gap:4px;padding:4px 8px;font-size:11px;font-family:'JetBrains Mono',monospace;color:#3d5068;overflow:hidden;}
.tree-breadcrumb button{background:none;border:none;color:#4a5568;cursor:pointer;padding:2px 4px;border-radius:3px;display:flex;align-items:center;transition:color .12s,background .12s;}
.tree-breadcrumb button:hover{color:#d4dce8;background:rgba(255,255,255,.05);}
.tree-breadcrumb .crumb{color:#4a5568;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:140px;}
/* xterm.js overrides */
.xterm{height:100%;}
.xterm .xterm-viewport{overflow-y:auto!important;}
.xterm .xterm-viewport::-webkit-scrollbar{width:5px;}
.xterm .xterm-viewport::-webkit-scrollbar-track{background:transparent;}
.xterm .xterm-viewport::-webkit-scrollbar-thumb{background:#2a3a4f;border-radius:3px;}
.term-tab{display:flex;align-items:center;gap:4px;padding:3px 10px;font-size:11px;font-family:'JetBrains Mono',monospace;color:#4a5568;cursor:pointer;border-radius:4px 4px 0 0;transition:color .12s,background .12s;white-space:nowrap;user-select:none;}
.term-tab:hover{color:#9baabd;background:rgba(255,255,255,.03);}
.term-tab.active{color:#d4dce8;background:#0a0e14;border-bottom:2px solid #56d4a0;}
.term-tab .close-x{opacity:0;font-size:9px;padding:1px 3px;border-radius:3px;transition:opacity .1s,background .1s;}
.term-tab:hover .close-x,.term-tab.active .close-x{opacity:.6;}
.term-tab .close-x:hover{opacity:1;background:rgba(224,107,101,.2);color:#e06b65;}
/* Undo toast — bottom-left notification for deleted cells */
#undo-toast{position:fixed;bottom:20px;left:20px;z-index:9999;background:#1a2332;border:1px solid #2a3a4f;border-radius:8px;padding:10px 16px;font-size:12px;font-family:'JetBrains Mono',monospace;color:#9baabd;box-shadow:0 8px 24px rgba(0,0,0,.5);opacity:0;transform:translateY(10px);transition:opacity .2s,transform .2s;pointer-events:none;}
#undo-toast.show{opacity:1;transform:translateY(0);pointer-events:auto;}
#undo-toast kbd{background:#0f1419;border:1px solid #2a3a4f;border-radius:3px;padding:1px 5px;font-size:11px;color:#56d4a0;}
/* File editor — full-height CodeMirror for plain files */
.file-editor-wrap{height:100%;display:flex;flex-direction:column;}
.cm-file-editor{flex:1;min-height:0;}
.cm-file-editor .cm-editor{height:100%;}
</style>"""),

        # --- Editor bundle (inlined — Therapy dev server has no static file handler) ---
        RawHtml(string("<script>", _EDITOR_BUNDLE_JS, "</script>")),

        # --- Body: children render directly (no wrapper div — SessionsApp owns the layout) ---
        RawHtml("""<div id="app-root" class="bg-base text-t1 font-sans">"""),
        children...,
        RawHtml("""</div>"""),

        # --- Undo toast (for deleted cells) ---
        RawHtml("""<div id="undo-toast">Cell deleted &mdash; <kbd>Ctrl+Z</kbd> to undo</div>"""),

        # --- Panel state: persist to localStorage, restore after WASM hydration ---
        RawHtml("""<script>
(function(){
  // Panel persistence is handled by SessionsApp.jl (toggle + restore scripts)
})();
</script>"""),

        # --- Notebook channel handler ---
        _notebook_channel_script(),

        # --- CM initialization + cell execution + eye toggle ---
        RawHtml("""<script>
(function() {
  if (typeof C === 'undefined' || !C.EditorView) return;

  // ── Registry: cell_id → CM EditorView (on window for cross-script access) ──
  if (!window._sessionsEditors) window._sessionsEditors = {};
  var editors = window._sessionsEditors;

  // ── Shared theme + highlight ──
  var hlTheme = C.HighlightStyle.define([
    {tag:C.t.keyword,color:"#e06b65"},{tag:C.t.controlKeyword,color:"#e06b65"},
    {tag:C.t.operatorKeyword,color:"#e06b65"},{tag:C.t.definitionKeyword,color:"#e06b65"},
    {tag:C.t.moduleKeyword,color:"#e06b65"},
    {tag:C.t.string,color:"#56d4a0"},{tag:C.t.character,color:"#56d4a0"},
    {tag:C.t.comment,color:"#4a6178",fontStyle:"italic"},
    {tag:C.t.lineComment,color:"#4a6178",fontStyle:"italic"},
    {tag:C.t.number,color:"#d4a056"},{tag:C.t.integer,color:"#d4a056"},
    {tag:C.t.float,color:"#d4a056"},{tag:C.t.bool,color:"#d4a056"},
    {tag:C.t.function(C.t.variableName),color:"#7bb8e8"},
    {tag:C.t.definition(C.t.variableName),color:"#7bb8e8"},
    {tag:C.t.typeName,color:"#b08fd8"},{tag:C.t.className,color:"#b08fd8"},
    {tag:C.t.variableName,color:"#d4dce8"},
    {tag:C.t.punctuation,color:"#4a5568"},{tag:C.t.paren,color:"#4a5568"},
    {tag:C.t.squareBracket,color:"#4a5568"},{tag:C.t.brace,color:"#4a5568"},
    {tag:C.t.operator,color:"#d4dce8"},{tag:C.t.special(C.t.string),color:"#7bb8e8"},
    {tag:C.t.macroName,color:"#d4a056"},
  ]);

  var edTheme = C.EditorView.theme({
    "&":{backgroundColor:"transparent",color:"#d4dce8"},
    ".cm-gutters":{backgroundColor:"transparent",color:"#3d5068",border:"none",minWidth:"38px"},
    ".cm-activeLine":{backgroundColor:"transparent"},
    "&.cm-focused .cm-activeLine":{backgroundColor:"rgba(86,212,160,.03)"},
    ".cm-activeLineGutter":{backgroundColor:"transparent",color:"#3d5068"},
    "&.cm-focused .cm-activeLineGutter":{backgroundColor:"transparent",color:"#4a5568"},
    "&.cm-focused .cm-cursor":{borderLeftColor:"#56d4a0"},
    "&.cm-focused .cm-selectionBackground, .cm-selectionBackground":{backgroundColor:"rgba(86,212,160,.15) !important"},
    ".cm-content":{caretColor:"#56d4a0",fontFamily:"'JetBrains Mono',monospace",fontSize:"13px",lineHeight:"1.65",padding:"8px 0"},
    ".cm-scroller":{fontFamily:"'JetBrains Mono',monospace"},
    ".cm-matchingBracket":{color:"#56d4a0 !important",backgroundColor:"rgba(86,212,160,.1)",outline:"1px solid rgba(86,212,160,.2)"},
    ".cm-line":{paddingLeft:"4px"},
  },{dark:true});

  // ── Run cell: read code from CM editor, send to server ──
  window._sessionsRunCell = function(cellId) {
    var code = '';
    var ev = editors[cellId];
    if (ev) code = ev.state.doc.toString();
    if (!code) {
      var host = document.querySelector('.cm-cell[data-cell-id="' + cellId + '"]');
      if (host) code = host.dataset.src || '';
    }
    if (window.TherapyWS && TherapyWS.sendMessage) {
      TherapyWS.sendMessage('notebook', {action: 'execute', cell_id: cellId, code: code});
    }
  };

  // ── Collect all codes from CM editors ──
  function _collectCodes() {
    var codes = {};
    for (var cid in editors) {
      codes[cid] = editors[cid].state.doc.toString();
    }
    return codes;
  }

  // ── Run All: sync all codes then execute ──
  window._sessionsRunAll = function() {
    // Sync all codes to server, then run all
    var codes = _collectCodes();
    for (var cid in codes) {
      if (window.TherapyWS && TherapyWS.sendMessage) {
        TherapyWS.sendMessage('notebook', {action: 'update_code', cell_id: cid, code: codes[cid]});
      }
    }
    if (window.TherapyWS && TherapyWS.sendMessage) {
      TherapyWS.sendMessage('notebook', {action: 'run_all'});
    }
  };

  // ── Run Stale: sync codes then execute only stale cells ──
  window._sessionsRunStale = function() {
    if (window.TherapyWS && TherapyWS.sendMessage) {
      TherapyWS.sendMessage('notebook', {action: 'run_stale', codes: _collectCodes()});
    }
  };

  // ── Save: sync codes then save .jl + .sessions.toml ──
  window._sessionsSave = function() {
    if (!window.TherapyWS || !TherapyWS.sendMessage) return;
    // File editor tab: send raw content
    var fileEditor = window._fileEditorView;
    if (fileEditor) {
      TherapyWS.sendMessage('notebook', {action: 'save', content: fileEditor.state.doc.toString()});
      return;
    }
    // Notebook tab: send cell codes
    TherapyWS.sendMessage('notebook', {action: 'save', codes: _collectCodes()});
  };

  // ── Debounced code sync: sends update_code to server on edit ──
  // Server updates cell.code, recomputes stale state, broadcasts stale_count.
  // This is the bridge that keeps server in sync with client edits —
  // same result as agent editing the .jl file (file watcher path).
  var _syncTimers = {};
  var _suppressSync = {};  // suppress sync-back when server pushes code updates
  function syncCodeToServer(cellId) {
    if (_suppressSync[cellId]) { delete _suppressSync[cellId]; return; }
    if (window._sessionsMarkUnsaved) window._sessionsMarkUnsaved();
    if (_syncTimers[cellId]) clearTimeout(_syncTimers[cellId]);
    _syncTimers[cellId] = setTimeout(function() {
      var ev = editors[cellId];
      if (!ev) return;
      var code = ev.state.doc.toString();
      if (window.TherapyWS && TherapyWS.sendMessage) {
        TherapyWS.sendMessage('notebook', {action: 'update_code', cell_id: cellId, code: code});
      }
    }, 400);  // 400ms debounce
  }

  // CM extension: fire syncCodeToServer on any document change
  function editSyncExtension(cellId) {
    return C.EditorView.updateListener.of(function(update) {
      if (update.docChanged) syncCodeToServer(cellId);
    });
  }

  // ── Shift+Enter keybinding for CM ──
  function shiftEnterKeymap(cellId) {
    return C.keymap.of([{
      key: 'Shift-Enter',
      run: function() { window._sessionsRunCell(cellId); return true; }
    }]);
  }

  // ── Initialize CM editors (callable for new cells too) ──
  // Handles both notebook cell editors (.cm-cell with data-cell-id)
  // and file editors (.cm-file-editor with data-file-path)
  function initCMEditors() {
    document.querySelectorAll('.cm-cell').forEach(function(host) {
      if (host.querySelector('.cm-editor')) return;
      var src = host.dataset.src || '';
      var cellId = host.dataset.cellId || '';
      var isFileEditor = host.classList.contains('cm-file-editor');

      var exts = [
        C.lineNumbers(), C.highlightActiveLineGutter(), C.highlightSpecialChars(),
        C.history(), C.drawSelection(),
        C.EditorState.allowMultipleSelections.of(true),
        C.indentOnInput(), C.bracketMatching(), C.closeBrackets(),
        C.rectangularSelection(), C.highlightActiveLine(), C.highlightSelectionMatches(),
        C.keymap.of([
          ...C.closeBracketsKeymap, ...C.defaultKeymap, ...C.searchKeymap,
          ...C.historyKeymap, ...C.completionKeymap, C.indentWithTab,
        ]),
        C.julia(),
        C.syntaxHighlighting(hlTheme),
        edTheme,
      ];

      if (isFileEditor) {
        // File editor: full-height, no cell execution
        exts.push(C.EditorView.theme({
          '&': { height: '100%' },
          '.cm-scroller': { overflow: 'auto' }
        }));
      } else if (cellId) {
        // Notebook cell: Shift+Enter executes, debounced sync
        exts.push(shiftEnterKeymap(cellId));
        exts.push(editSyncExtension(cellId));
      }

      var view = new C.EditorView({ doc: src, extensions: exts, parent: host });

      if (isFileEditor) {
        window._fileEditorView = view;
      } else if (cellId) {
        editors[cellId] = view;
      }
    });
  }
  initCMEditors();
  window._sessionsInitNewCells = initCMEditors;

  // ── Fold persistence: watch CellToggle WASM toggle and sync to server ──
  // CellToggle @island handles the visual toggle via WASM signal + Show().
  // This observer detects when the Show wrapper hides/shows the code-cell
  // and sends the fold state to the server for .jl file persistence.
  document.querySelectorAll('.cell-island').forEach(function(island) {
    var cellWrap = island.closest('.cell-wrap');
    var cellId = cellWrap ? cellWrap.dataset.cellId : '';
    if (!cellId) return;
    var lastFolded = null;
    var observer = new MutationObserver(function() {
      var codeCell = island.querySelector('.code-cell');
      var folded = !codeCell || codeCell.offsetParent === null;
      if (folded !== lastFolded) {
        lastFolded = folded;
        if (window.TherapyWS && TherapyWS.sendMessage) {
          TherapyWS.sendMessage('notebook', {action: 'toggle_fold', cell_id: cellId, folded: folded});
        }
      }
    });
    observer.observe(island, {childList: true, subtree: true, attributes: true, attributeFilter: ['style']});
  });
})();
</script>"""))
end

"""Client-side JavaScript for handling notebook WebSocket channel messages."""
function _notebook_channel_script()
    RawHtml("""<script>
(function() {
  if (window._sessionsNotebookHandler) return;
  window._sessionsNotebookHandler = true;

  // ── Unsaved changes indicator ──
  window._sessionsUnsaved = false;
  function markUnsaved() {
    if (window._sessionsUnsaved) return;
    window._sessionsUnsaved = true;
    var btn = document.getElementById('save-indicator');
    if (btn) {
      btn.textContent = '\u25CF Save';
      btn.style.color = '#d4a056';
      btn.style.borderColor = '#d4a056';
    }
  }
  function markSaved() {
    window._sessionsUnsaved = false;
    var btn = document.getElementById('save-indicator');
    if (btn) {
      btn.textContent = 'Saved';
      btn.style.color = '';
      btn.style.borderColor = '';
      setTimeout(function(){ if (!window._sessionsUnsaved) btn.textContent = 'Save'; }, 2000);
    }
  }
  window._sessionsMarkUnsaved = markUnsaved;

  // ── Helper: find cell elements by ID ──
  function cellEls(cellId) {
    var wrap = document.querySelector('.cell-wrap[data-cell-id="' + cellId + '"]');
    if (!wrap) return null;
    return {
      wrap: wrap,
      code: wrap.querySelector('.code-cell'),
      out: wrap.querySelector('.cell-out'),
      ctrls: wrap.querySelector('.cell-ctrls')
    };
  }

  // ── Helper: format runtime ──
  function fmtRuntime(ns) {
    var ms = ns / 1e6;
    return ms < 1 ? (ns / 1e3).toFixed(1) + '\u00b5s' : ms < 1000 ? ms.toFixed(1) + 'ms' : (ms / 1000).toFixed(2) + 's';
  }

  // ── Helper: update cell CSS state (accent bar color) ──
  function setCellState(el, state) {
    if (!el) return;
    var cc = el.code;
    if (!cc) return;
    cc.classList.remove('idle', 'stale', 'executing');
    // Queued/running: colored border + hide the green/orange side accent bar
    if (state === 'cell_queued' || state === 'cell_running') {
      cc.style.borderColor = state === 'cell_queued' ? '#d4a056' : '#7bb8e8';
      cc.classList.add('executing');
    } else if (state === 'cell_errored') {
      cc.style.borderColor = '#e06b65';
    } else {
      cc.style.borderColor = '';  // revert to CSS default
    }
  }

  window.addEventListener('therapy:channel:notebook', function(e) {
    var data = e.detail;
    if (!data || !data.event) return;

    if (data.event === 'cell_state') {
      var el = cellEls(data.cell_id);
      setCellState(el, data.state);
    }

    else if (data.event === 'format_started') {
      // Show spinner on all Format buttons
      document.querySelectorAll('[data-format-btn]').forEach(function(btn) {
        btn.dataset.origText = btn.textContent;
        btn.textContent = 'Formatting...';
        btn.style.opacity = '0.6';
        btn.style.pointerEvents = 'none';
      });
    }

    else if (data.event === 'format_done') {
      // Restore Format buttons
      document.querySelectorAll('[data-format-btn]').forEach(function(btn) {
        btn.textContent = btn.dataset.origText || 'Format';
        btn.style.opacity = '';
        btn.style.pointerEvents = '';
      });
    }

    else if (data.event === 'cell_formatted') {
      markUnsaved();
      // Update CodeMirror editor with formatted code
      var eds = window._sessionsEditors || {};
      var ev = eds[data.cell_id];
      if (ev && data.code !== undefined) {
        var currentCode = ev.state.doc.toString();
        if (data.code !== currentCode) {
          _suppressSync[data.cell_id] = true;  // don't echo back to server
          ev.dispatch({
            changes: {from: 0, to: currentCode.length, insert: data.code}
          });
        }
      }
    }

    else if (data.event === 'cell_code_updated') {
      // External edit (agent, git, IDE) changed cell code on the server.
      // Push the new code into the CM editor so Run Stale sends the right content.
      var eds = window._sessionsEditors || {};
      var ev = eds[data.cell_id];
      if (ev && data.code !== undefined) {
        var currentCode = ev.state.doc.toString();
        if (data.code !== currentCode) {
          _suppressSync[data.cell_id] = true;  // don't echo back to server
          ev.dispatch({
            changes: {from: 0, to: currentCode.length, insert: data.code}
          });
        }
      }
    }

    else if (data.event === 'cell_output') {
      var el = cellEls(data.cell_id);
      if (!el) return;

      // Update output HTML
      if (el.out) {
        var html = data.output_html || '';
        if (html) {
          el.out.innerHTML = html;
          el.out.style.display = '';
          el.out.style.padding = '6px 0 10px';

          // innerHTML doesn't execute <script> tags — re-create them so they run.
          // This is needed for the WebSlider JS bridge (set_bond on input).
          el.out.querySelectorAll('script').forEach(function(oldScript) {
            var newScript = document.createElement('script');
            newScript.textContent = oldScript.textContent;
            oldScript.parentNode.replaceChild(newScript, oldScript);
          });

          // Re-hydrate any @island components in the new output
          // (WebSlider WASM signal needs to be initialized)
          if (window.__hydrateTherapyIslands) {
            window.__hydrateTherapyIslands(el.out);
          }
        } else {
          el.out.innerHTML = '';
          el.out.style.display = 'none';
        }
      }

      // Update cell state (done/errored)
      setCellState(el, data.state);

      // Update runtime badge
      if (el.ctrls && data.runtime_ns && data.runtime_ns > 0) {
        var old = el.ctrls.querySelector('.rt-badge');
        if (old) old.remove();
        var badge = document.createElement('span');
        badge.className = 'rt-badge';
        badge.style.cssText = 'font-size:10px;font-family:ui-monospace,monospace;padding:1px 7px;border-radius:9999px;color:#56d4a0;opacity:.8;background:rgba(86,212,160,.08);border:1px solid rgba(86,212,160,.12);';
        badge.textContent = fmtRuntime(data.runtime_ns);
        el.ctrls.insertBefore(badge, el.ctrls.firstChild);
      }
    }

    else if (data.event === 'cell_added') {
      markUnsaved();
      // Server renders the cell HTML — just insert it and init CM
      var html = data.cell_html || '';
      if (!html) return;

      var nb = document.getElementById('nb');
      if (!nb) return;
      var container = nb.firstElementChild; // max-width wrapper

      // Create a temp container to parse the HTML
      var tmp = document.createElement('div');
      tmp.innerHTML = html;

      // Find insertion point
      var afterId = data.after_cell_id;
      if (afterId) {
        var afterWrap = container.querySelector('.cell-wrap[data-cell-id="' + afterId + '"]');
        if (afterWrap) {
          // Insert after the divider that follows the target cell
          var ref = afterWrap.nextElementSibling;
          if (ref && ref.classList.contains('cdiv')) ref = ref.nextElementSibling;
          while (tmp.firstChild) {
            if (ref) container.insertBefore(tmp.firstChild, ref);
            else container.appendChild(tmp.firstChild);
          }
        } else {
          while (tmp.firstChild) container.appendChild(tmp.firstChild);
        }
      } else {
        // Insert at beginning
        var first = container.firstElementChild;
        if (first) first = first.nextElementSibling; // skip initial divider
        while (tmp.firstChild) {
          if (first) container.insertBefore(tmp.firstChild, first);
          else container.appendChild(tmp.firstChild);
        }
      }

      // Initialize CM editors + hydrate WASM islands in the new HTML
      window._sessionsInitNewCells && window._sessionsInitNewCells();
      if (window.__hydrateTherapyIslands) {
        var container = document.querySelector('#nb > div');
        if (container) window.__hydrateTherapyIslands(container);
      }
    }

    else if (data.event === 'cell_deleted') {
      markUnsaved();
      // Save deleted cell info for undo
      window._recentlyDeleted = {
        cell_id: data.cell_id,
        code: data.code || '',
        prev_cell_id: data.prev_cell_id || ''
      };
      // Show undo toast
      var toast = document.getElementById('undo-toast');
      if (toast) {
        toast.classList.add('show');
        if (window._undoToastTimer) clearTimeout(window._undoToastTimer);
        window._undoToastTimer = setTimeout(function() {
          toast.classList.remove('show');
          window._recentlyDeleted = null;
        }, 8000);
      }
      // Remove cell from DOM in-place (no page reload)
      var wrap = document.querySelector('.cell-wrap[data-cell-id="' + data.cell_id + '"]');
      if (wrap) {
        // Also remove the divider after this cell
        var next = wrap.nextElementSibling;
        if (next && next.classList.contains('cdiv')) next.remove();
        wrap.remove();
      }
      // Clean up editor reference
      delete editors[data.cell_id];
    }

    else if (data.event === 'cell_moved') {
      markUnsaved();
      // Swap cell DOM nodes in-place (no reload)
      var container = document.querySelector('#nb > div'); // max-width wrapper
      if (!container) return;
      var cellWrap = container.querySelector('.cell-wrap[data-cell-id="' + data.cell_id + '"]');
      if (!cellWrap) return;

      // Each cell has: cell-wrap + following cdiv (divider)
      var divider = cellWrap.nextElementSibling;
      if (data.direction === 'up') {
        // Find the previous cell-wrap (skip its divider)
        var prevDiv = cellWrap.previousElementSibling; // divider before this cell
        if (!prevDiv) return;
        var prevCell = prevDiv.previousElementSibling; // cell-wrap above
        if (!prevCell || !prevCell.classList.contains('cell-wrap')) return;
        // Move this cell+divider before the previous cell
        container.insertBefore(cellWrap, prevCell);
        if (divider && divider.classList.contains('cdiv')) container.insertBefore(divider, prevCell);
      } else if (data.direction === 'down') {
        // Find the next cell-wrap (after our divider)
        if (!divider || !divider.classList.contains('cdiv')) return;
        var nextCell = divider.nextElementSibling;
        if (!nextCell || !nextCell.classList.contains('cell-wrap')) return;
        var nextDiv = nextCell.nextElementSibling;
        // Move next cell+divider before this cell
        container.insertBefore(nextCell, cellWrap);
        if (nextDiv && nextDiv.classList.contains('cdiv')) container.insertBefore(nextDiv, cellWrap);
      }
      // Smooth scroll to keep moved cell visible
      cellWrap.scrollIntoView({behavior: 'smooth', block: 'nearest'});
    }

    else if (data.event === 'nb_replaced') {
      // Server rendered the full notebook panel — swap in-place
      var nbIsland = document.getElementById('nb-island');
      window._fileEditorView = null;  // Clear file editor ref on tab switch
      if (nbIsland && data.nb_html) {
        nbIsland.outerHTML = data.nb_html;
        // Re-init CM editors (handles both cell and file editors)
        window._sessionsInitNewCells && window._sessionsInitNewCells();
        // Re-hydrate WASM islands (CellToggle eye toggles, etc.)
        if (window.__hydrateTherapyIslands) {
          var newNb = document.getElementById('nb-island');
          if (newNb) window.__hydrateTherapyIslands(newNb);
        }
      } else if (!data.nb_html) {
        setTimeout(function(){ window.location.reload(); }, 200);
      }
    }

    else if (data.event === 'tabs_changed') {
      // Legacy fallback — reload
      setTimeout(function(){ window.location.reload(); }, 200);
    }

    else if (data.event === 'saved') {
      markSaved();
    }

    else if (data.event === 'stale_update') {
      // Show/hide Run Stale button
      var btn = document.getElementById('run-stale-btn');
      var label = document.getElementById('run-stale-label');
      if (btn) {
        if (data.count > 0) {
          btn.style.display = '';
          if (label) label.textContent = ' Run Stale (' + data.count + ')';
        } else {
          btn.style.display = 'none';
        }
      }
      // Toggle stale class on cell accent bars
      var staleSet = new Set(data.stale_ids || []);
      document.querySelectorAll('.code-cell').forEach(function(el) {
        var wrap = el.closest('.cell-wrap');
        var cid = wrap ? wrap.dataset.cellId : null;
        if (cid && staleSet.has(cid)) {
          el.classList.add('stale');
        } else {
          el.classList.remove('stale');
        }
      });
    }

    else if (data.event === 'run_progress') {
      var el = document.getElementById('run-progress');
      if (el) {
        if (data.running_index > 0 && data.total > 0) {
          el.textContent = 'Running ' + data.running_index + '/' + data.total + '...';
          el.style.display = '';
        } else {
          el.textContent = '';
          el.style.display = 'none';
        }
      }
      // Toggle Run All / Stop button visibility
      var runAllBtn = document.getElementById('run-all-btn');
      var stopBtn = document.getElementById('stop-btn');
      if (runAllBtn && stopBtn) {
        if (data.running_index > 0 && data.total > 0) {
          runAllBtn.style.display = 'none';
          stopBtn.style.display = '';
        } else {
          runAllBtn.style.display = '';
          stopBtn.style.display = 'none';
        }
      }
    }

    else if (data.event === 'interrupted') {
      var el = document.getElementById('run-progress');
      if (el) {
        el.textContent = 'Interrupted';
        el.style.display = '';
        el.style.color = '#e06b65';
        setTimeout(function() {
          el.textContent = '';
          el.style.display = 'none';
          el.style.color = '#56d4a0';
        }, 2000);
      }
      // Restore Run All button
      var runAllBtn = document.getElementById('run-all-btn');
      var stopBtn = document.getElementById('stop-btn');
      if (runAllBtn && stopBtn) {
        runAllBtn.style.display = '';
        stopBtn.style.display = 'none';
      }
    }

    else if (data.event === 'full_state') {
      console.log('[Sessions] Full state:', data.cells ? data.cells.length : 0, 'cells');
      var needsHydration = false;
      if (data.cells) {
        data.cells.forEach(function(cell) {
          var el = cellEls(cell.cell_id);
          if (!el) return;
          setCellState(el, cell.state);
          if (cell.output_html && el.out && !el.out.innerHTML) {
            el.out.innerHTML = cell.output_html;
            el.out.style.display = '';
            el.out.style.padding = '6px 0 10px';
            // Execute inline scripts (JS bridge for WebSlider etc.)
            el.out.querySelectorAll('script').forEach(function(oldScript) {
              var newScript = document.createElement('script');
              newScript.textContent = oldScript.textContent;
              oldScript.parentNode.replaceChild(newScript, oldScript);
            });
            if (el.out.querySelector('therapy-island')) needsHydration = true;
          }
        });
      }
      // Re-hydrate any @island components inserted via full_state
      if (needsHydration && window.__hydrateTherapyIslands) {
        var nb = document.getElementById('nb');
        if (nb) window.__hydrateTherapyIslands(nb);
      }
    }
  });

  document.addEventListener('keydown', function(e) {
    if ((e.ctrlKey || e.metaKey) && e.key === 's') {
      e.preventDefault();
      window._sessionsSave && window._sessionsSave();
    }
    // Ctrl+Z undo deleted cell (only when not focused in an editor)
    if ((e.ctrlKey || e.metaKey) && e.key === 'z' && window._recentlyDeleted) {
      var active = document.activeElement;
      var inEditor = active && (active.closest('.cm-editor') || active.tagName === 'INPUT' || active.tagName === 'TEXTAREA');
      if (!inEditor) {
        e.preventDefault();
        var del = window._recentlyDeleted;
        window._recentlyDeleted = null;
        var toast = document.getElementById('undo-toast');
        if (toast) toast.classList.remove('show');
        if (window._undoToastTimer) clearTimeout(window._undoToastTimer);
        if (window.TherapyWS && TherapyWS.sendMessage) {
          TherapyWS.sendMessage('notebook', {action: 'add_cell', after_cell_id: del.prev_cell_id, code: del.code});
        }
      }
    }
  });

  // ── Shared cell action dropdown (fixed position, escapes all overflow) ──
  var _cellMenu = document.createElement('div');
  _cellMenu.style.cssText = 'display:none;position:fixed;z-index:9999;background:#1a2332;border:1px solid #2a3a4f;border-radius:8px;min-width:130px;box-shadow:0 8px 24px rgba(0,0,0,.5);overflow:hidden;';
  var _menuItemStyle = 'display:flex;align-items:center;gap:8px;padding:6px 12px;font-size:12px;cursor:pointer;color:#9baabd;transition:background .1s,color .1s;';
  _cellMenu.innerHTML =
    '<div class="cell-menu-up" style="' + _menuItemStyle + '"><svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M8 3v10M4 7l4-4 4 4"/></svg>Move up</div>' +
    '<div class="cell-menu-down" style="' + _menuItemStyle + '"><svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M8 13V3M4 9l4 4 4-4"/></svg>Move down</div>' +
    '<div style="height:1px;background:#2a3a4f;margin:2px 8px;"></div>' +
    '<div class="cell-menu-format" style="' + _menuItemStyle + '"><svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"><path d="M2 3h12M2 6h8M2 9h10M2 12h6"/></svg>Format cell</div>' +
    '<div style="height:1px;background:#2a3a4f;margin:2px 8px;"></div>' +
    '<div class="cell-menu-delete" style="' + _menuItemStyle + '"><svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M2 4h12M5 4V3a1 1 0 011-1h4a1 1 0 011 1v1M6 7v5M10 7v5"/><path d="M3 4l1 9a1 1 0 001 1h6a1 1 0 001-1l1-9"/></svg>Delete cell</div>';
  document.body.appendChild(_cellMenu);
  var _menuCellId = '';

  // Hover effects for all menu items
  _cellMenu.querySelectorAll('[class^="cell-menu-"]').forEach(function(item) {
    var isDelete = item.classList.contains('cell-menu-delete');
    item.addEventListener('mouseenter', function(){
      this.style.background = isDelete ? 'rgba(224,107,101,.12)' : 'rgba(86,212,160,.08)';
      this.style.color = isDelete ? '#e06b65' : '#d4dce8';
    });
    item.addEventListener('mouseleave', function(){ this.style.background=''; this.style.color='#9baabd'; });
  });

  // Move up action
  _cellMenu.querySelector('.cell-menu-up').addEventListener('click', function(){
    _cellMenu.style.display = 'none';
    if (_menuCellId) TherapyWS.sendMessage('notebook', {action: 'move_cell', cell_id: _menuCellId, direction: 'up'});
  });

  // Move down action
  _cellMenu.querySelector('.cell-menu-down').addEventListener('click', function(){
    _cellMenu.style.display = 'none';
    if (_menuCellId) TherapyWS.sendMessage('notebook', {action: 'move_cell', cell_id: _menuCellId, direction: 'down'});
  });

  // Format cell action
  _cellMenu.querySelector('.cell-menu-format').addEventListener('click', function(){
    _cellMenu.style.display = 'none';
    if (_menuCellId) TherapyWS.sendMessage('notebook', {action: 'format_cell', cell_id: _menuCellId});
  });

  // Delete action (no confirm — undo available via Ctrl+Z)
  _cellMenu.querySelector('.cell-menu-delete').addEventListener('click', function(){
    _cellMenu.style.display = 'none';
    if (_menuCellId) {
      TherapyWS.sendMessage('notebook', {action: 'delete_cell', cell_id: _menuCellId});
    }
  });

  // Show dropdown next to a menu button (flip above if near bottom of viewport)
  window._sessionsShowCellMenu = function(btn, cellId) {
    _menuCellId = cellId;
    var r = btn.getBoundingClientRect();
    _cellMenu.style.display = 'block';
    var menuH = _cellMenu.offsetHeight || 150;
    if (window.innerHeight - r.bottom < menuH + 8) {
      _cellMenu.style.top = (r.top - menuH - 4) + 'px';
    } else {
      _cellMenu.style.top = (r.bottom + 4) + 'px';
    }
    _cellMenu.style.left = (r.right - 130) + 'px';
  };

  // Close on click outside
  document.addEventListener('click', function(e) {
    if (!e.target.closest('.menu-btn') && _cellMenu.style.display !== 'none') {
      _cellMenu.style.display = 'none';
    }
  });
})();
</script>""")
end
