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
        t1:'#d4dce8', t2:'#9baabd', t3:'#6b7d93', t4:'#3d5068', tout:'#7ca0bf',
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
/* Full height chain: html → body → #therapy-content → #page-content → therapy-island → app.
   Every wrapper in the chain must pass through height and flex constraints. */
#therapy-content{display:flex;flex-direction:column;height:100%;overflow:hidden;}
#page-content{display:flex;flex-direction:column;flex:1;min-height:0;overflow:hidden;}
therapy-island{display:flex;flex-direction:column;flex:1;min-height:0;overflow:hidden;}
#workspace>div{min-height:0;}
/* Activity bar button: active highlight when panel is open.
   !important needed to override inline style from _AB_BTN_STYLE */
.ab-btn[data-state="on"]{background:rgba(86,212,160,.08) !important;color:#56d4a0 !important;}
.ab-btn:hover{background:rgba(86,212,160,.06) !important;color:#9baabd !important;}
.cell-ctrls{opacity:0;transform:translateY(-3px);transition:opacity .15s,transform .15s;pointer-events:none;}
.code-cell:hover .cell-ctrls{opacity:1;transform:translateY(0);pointer-events:auto;}
.code-cell::before{content:'';position:absolute;left:0;top:0;bottom:0;width:2px;background:#56d4a0;opacity:.4;transition:opacity .2s;border-radius:2px 0 0 2px;}
.code-cell:hover::before{opacity:.7;}
.code-cell.idle::before{background:#3d5068;opacity:.2;}
.md-cell::before{content:'';position:absolute;left:0;top:0;bottom:0;width:2px;background:#b08fd8;opacity:.4;border-radius:2px 0 0 2px;}
.cell-eye{position:absolute;left:-28px;top:0;bottom:0;width:24px;display:flex;align-items:center;justify-content:center;opacity:0;transition:opacity .15s;cursor:pointer;z-index:5;}
.cell-wrap:hover .cell-eye{opacity:1;}
.cell-eye svg{color:#3d5068;transition:color .15s;}
.cell-eye:hover svg{color:#56d4a0;}
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
.cm-cell .cm-editor{background:transparent!important;}
.cm-cell .cm-scroller{overflow-x:auto;}
.cm-cell .cm-focused{outline:none!important;}
@keyframes pulse{0%,100%{opacity:1;}50%{opacity:0.4;}}
.code-cell.stale::before{background:#d4a056;opacity:.5;}
/* Shoelace dark theme overrides — match Sessions.jl palette */
:root{--sl-color-neutral-0:#0a0e14;--sl-color-neutral-50:#0f1419;--sl-color-neutral-100:#151c25;--sl-color-neutral-200:#1a2332;--sl-color-neutral-300:#1c2736;--sl-color-neutral-400:#2a3a4f;--sl-color-neutral-500:#3d5068;--sl-color-neutral-600:#6b7d93;--sl-color-neutral-700:#9baabd;--sl-color-neutral-800:#d4dce8;--sl-color-neutral-900:#d4dce8;--sl-color-neutral-1000:#ffffff;--sl-color-primary-600:#56d4a0;--sl-font-sans:'DM Sans',system-ui,sans-serif;--sl-font-mono:'JetBrains Mono',monospace;--sl-font-size-small:12px;}
sl-tree{--indent-size:14px;--indent-guide-width:1px;--indent-guide-color:#1c2736;}
sl-tree-item::part(label){font-size:12px;font-family:'JetBrains Mono',monospace;color:#6b7d93;display:flex;align-items:center;gap:6px;}
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
.tree-breadcrumb button{background:none;border:none;color:#6b7d93;cursor:pointer;padding:2px 4px;border-radius:3px;display:flex;align-items:center;transition:color .12s,background .12s;}
.tree-breadcrumb button:hover{color:#d4dce8;background:rgba(255,255,255,.05);}
.tree-breadcrumb .crumb{color:#6b7d93;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:140px;}
/* xterm.js overrides */
.xterm{height:100%;}
.xterm .xterm-viewport{overflow-y:auto!important;}
.xterm .xterm-viewport::-webkit-scrollbar{width:5px;}
.xterm .xterm-viewport::-webkit-scrollbar-track{background:transparent;}
.xterm .xterm-viewport::-webkit-scrollbar-thumb{background:#2a3a4f;border-radius:3px;}
.term-tab{display:flex;align-items:center;gap:4px;padding:3px 10px;font-size:11px;font-family:'JetBrains Mono',monospace;color:#6b7d93;cursor:pointer;border-radius:4px 4px 0 0;transition:color .12s,background .12s;white-space:nowrap;user-select:none;}
.term-tab:hover{color:#9baabd;background:rgba(255,255,255,.03);}
.term-tab.active{color:#d4dce8;background:#0a0e14;border-bottom:2px solid #56d4a0;}
.term-tab .close-x{opacity:0;font-size:9px;padding:1px 3px;border-radius:3px;transition:opacity .1s,background .1s;}
.term-tab:hover .close-x,.term-tab.active .close-x{opacity:.6;}
.term-tab .close-x:hover{opacity:1;background:rgba(224,107,101,.2);color:#e06b65;}
/* Markdown prose — Pluto-style notebook text */
.md-prose{font-family:'DM Sans',system-ui,sans-serif;color:#9baabd;line-height:1.7;font-size:14px;}
.md-prose h1{font-family:'Fraunces',Georgia,serif;font-size:1.8em;font-weight:600;color:#d4dce8;margin:0.3em 0 0.6em;letter-spacing:-0.01em;}
.md-prose h2{font-family:'Fraunces',Georgia,serif;font-size:1.4em;font-weight:600;color:#d4dce8;margin:1.2em 0 0.4em;padding-bottom:0.3em;border-bottom:1px solid #1c2736;}
.md-prose h3{font-family:'Fraunces',Georgia,serif;font-size:1.15em;font-weight:600;color:#d4dce8;margin:1em 0 0.3em;}
.md-prose p{margin:0 0 0.8em;color:#9baabd;}
.md-prose ul,.md-prose ol{margin:0 0 0.8em;padding-left:1.5em;color:#9baabd;}
.md-prose li{margin:0.2em 0;}
.md-prose blockquote{border-left:3px solid #b08fd8;padding:0.2em 0 0.2em 1em;margin:0.8em 0;color:#6b7d93;font-style:italic;}
.md-prose code{font-family:'JetBrains Mono',monospace;font-size:0.85em;background:#0a0e14;padding:0.15em 0.4em;border-radius:4px;color:#7bb8e8;}
.md-prose pre{background:#0a0e14;border-radius:6px;padding:0.8em 1em;margin:0.8em 0;overflow-x:auto;}
.md-prose pre code{background:none;padding:0;font-size:0.85em;color:#d4dce8;}
.md-prose strong{color:#d4dce8;font-weight:600;}
.md-prose em{font-style:italic;}
.md-prose a{color:#56d4a0;text-decoration:none;}
.md-prose a:hover{text-decoration:underline;}
.md-prose hr{border:none;border-top:1px solid #1c2736;margin:1.2em 0;}
.md-prose img{max-width:100%;border-radius:6px;}
/* Sessions Table (sst-*) — Pluto-style table viewer for any Tables.jl type */
.sst-wrap{font-family:'JetBrains Mono','Fira Code',monospace;font-size:13px;overflow-x:auto;max-width:100%;}
.sst-table{border-collapse:separate;border-spacing:0;width:auto;min-width:50%;border:1px solid #2a3a4f;border-radius:8px;overflow:hidden;}
.sst-th{padding:8px 16px;color:#56d4a0;font-weight:600;font-size:13px;text-align:left;border-bottom:1px solid #2a3a4f;background:#151c25;white-space:nowrap;position:sticky;top:0;z-index:1;}
.sst-type-row .sst-type-th{padding:2px 16px 6px;color:#3d5068;font-weight:400;font-size:11px;font-style:italic;text-align:left;border-bottom:2px solid #2a3a4f;background:#151c25;opacity:0;transition:opacity .15s;}
.sst-table thead:hover .sst-type-row .sst-type-th{opacity:1;}
.sst-row-label{color:#3d5068 !important;font-weight:600;font-size:12px;text-align:right !important;padding:6px 12px 6px 8px !important;border-right:1px solid #2a3a4f;width:1%;white-space:nowrap;position:sticky;left:0;background:#0f1419;z-index:1;}
.sst-td{padding:6px 16px;color:#d4dce8;border-bottom:1px solid rgba(42,58,79,.4);text-align:left;white-space:nowrap;max-width:300px;overflow:auto;}
.sst-row:hover .sst-td,.sst-row:hover .sst-row-label{background:rgba(86,212,160,.04);}
.sst-row:nth-child(even) .sst-td,.sst-row:nth-child(even) .sst-row-label{background:rgba(255,255,255,.015);}
.sst-more{padding:8px 16px;color:#56d4a0;font-size:12px;text-align:center;cursor:pointer;background:rgba(86,212,160,.03);border-bottom:1px solid #2a3a4f;transition:background .15s;}
.sst-more:hover{background:rgba(86,212,160,.08);}
</style>"""),

        # --- Editor bundle (inlined — Therapy dev server has no static file handler) ---
        RawHtml(string("<script>", _EDITOR_BUNDLE_JS, "</script>")),

        # --- Body wrapper with children ---
        Div(:class => "bg-base text-t1 font-sans h-screen w-screen flex flex-col",
            children...),

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

  // ── Registry: cell_id → CM EditorView ──
  var editors = {};

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
    {tag:C.t.punctuation,color:"#6b7d93"},{tag:C.t.paren,color:"#6b7d93"},
    {tag:C.t.squareBracket,color:"#6b7d93"},{tag:C.t.brace,color:"#6b7d93"},
    {tag:C.t.operator,color:"#d4dce8"},{tag:C.t.special(C.t.string),color:"#7bb8e8"},
    {tag:C.t.macroName,color:"#d4a056"},
  ]);

  var edTheme = C.EditorView.theme({
    "&":{backgroundColor:"transparent",color:"#d4dce8"},
    ".cm-gutters":{backgroundColor:"transparent",color:"#3d5068",border:"none",minWidth:"38px"},
    ".cm-activeLine":{backgroundColor:"transparent"},
    "&.cm-focused .cm-activeLine":{backgroundColor:"rgba(86,212,160,.03)"},
    ".cm-activeLineGutter":{backgroundColor:"transparent",color:"#3d5068"},
    "&.cm-focused .cm-activeLineGutter":{backgroundColor:"transparent",color:"#6b7d93"},
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
    if (window.TherapyWS && TherapyWS.sendMessage) {
      TherapyWS.sendMessage('notebook', {action: 'save', codes: _collectCodes()});
    }
  };

  // ── Debounced code sync: sends update_code to server on edit ──
  // Server updates cell.code, recomputes stale state, broadcasts stale_count.
  // This is the bridge that keeps server in sync with client edits —
  // same result as agent editing the .jl file (file watcher path).
  var _syncTimers = {};
  function syncCodeToServer(cellId) {
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
  function initCMEditors() {
    document.querySelectorAll('.cm-cell').forEach(function(host) {
      if (host.querySelector('.cm-editor')) return;
      var src = host.dataset.src || '';
      var cellId = host.dataset.cellId || '';

    var view = new C.EditorView({
      doc: src,
      extensions: [
        C.lineNumbers(), C.highlightActiveLineGutter(), C.highlightSpecialChars(),
        C.history(), C.drawSelection(),
        C.EditorState.allowMultipleSelections.of(true),
        C.indentOnInput(), C.bracketMatching(), C.closeBrackets(),
        C.rectangularSelection(), C.highlightActiveLine(), C.highlightSelectionMatches(),
        C.keymap.of([
          ...C.closeBracketsKeymap, ...C.defaultKeymap, ...C.searchKeymap,
          ...C.historyKeymap, ...C.completionKeymap, C.indentWithTab,
        ]),
        shiftEnterKeymap(cellId),
        editSyncExtension(cellId),
        C.julia(),
        C.syntaxHighlighting(hlTheme),
        edTheme,
      ],
      parent: host,
    });

    if (cellId) editors[cellId] = view;
    });
  }
  initCMEditors();
  window._sessionsInitNewCells = initCMEditors;

  // ── Fold persistence: watch CellIsland WASM toggle and sync to server ──
  // CellIsland @island handles the visual toggle via WASM signal + Show().
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
    cc.classList.remove('idle', 'stale');
    // Queued/running: add a pulsing border
    if (state === 'cell_queued' || state === 'cell_running') {
      cc.style.borderColor = state === 'cell_queued' ? '#d4a056' : '#7bb8e8';
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
      if (nbIsland && data.nb_html) {
        nbIsland.outerHTML = data.nb_html;
        // Re-init CM editors
        window._sessionsInitNewCells && window._sessionsInitNewCells();
        // Re-hydrate WASM islands (CellIsland eye toggles, etc.)
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
      var ind = document.getElementById('save-indicator');
      if (ind) { ind.textContent = 'Saved'; setTimeout(function(){ ind.textContent = 'Save'; }, 2000); }
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

    else if (data.event === 'full_state') {
      console.log('[Sessions] Full state:', data.cells ? data.cells.length : 0, 'cells');
      if (data.cells) {
        data.cells.forEach(function(cell) {
          var el = cellEls(cell.cell_id);
          if (!el) return;
          // Update cell state
          setCellState(el, cell.state);
          // Fill empty output containers with cached output
          if (cell.output_html && el.out && !el.out.innerHTML) {
            el.out.innerHTML = cell.output_html;
            el.out.style.display = '';
            el.out.style.padding = '6px 0 10px';
          }
        });
      }
    }
  });

  document.addEventListener('keydown', function(e) {
    if ((e.ctrlKey || e.metaKey) && e.key === 's') {
      e.preventDefault();
      window._sessionsSave && window._sessionsSave();
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

  // Delete action
  _cellMenu.querySelector('.cell-menu-delete').addEventListener('click', function(){
    _cellMenu.style.display = 'none';
    if (_menuCellId && confirm('Delete this cell?')) {
      TherapyWS.sendMessage('notebook', {action: 'delete_cell', cell_id: _menuCellId});
    }
  });

  // Show dropdown next to a menu button
  window._sessionsShowCellMenu = function(btn, cellId) {
    _menuCellId = cellId;
    var r = btn.getBoundingClientRect();
    _cellMenu.style.top = (r.bottom + 4) + 'px';
    _cellMenu.style.left = (r.right - 130) + 'px';
    _cellMenu.style.display = 'block';
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
