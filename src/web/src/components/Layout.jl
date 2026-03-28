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
        # --- Theme init: MUST be first — read localStorage, set .dark before any rendering ---
        RawHtml("""<script>
(function(){
  var t = localStorage.getItem('sessions-theme');
  if (!t) t = window.matchMedia('(prefers-color-scheme:dark)').matches ? 'dark' : 'light';
  if (t === 'dark') {
    document.documentElement.classList.add('dark', 'sl-theme-dark');
  } else {
    document.documentElement.classList.remove('dark', 'sl-theme-dark');
    document.documentElement.classList.add('sl-theme-light');
  }
})();
</script>"""),

        # --- Google Fonts ---
        RawHtml("""<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,100..1000;1,9..40,100..1000&family=JetBrains+Mono:ital,wght@0,100..800;1,100..800&family=Fraunces:ital,opsz,wght@0,9..144,100..900;1,9..144,100..900&display=swap" rel="stylesheet">"""),

        # --- Shoelace Web Components ---
        RawHtml("""<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/themes/light.css" />
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/themes/dark.css" />
<script type="module" src="https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/shoelace-autoloader.js"></script>"""),

        # --- xterm.js (terminal emulator) ---
        RawHtml("""<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/css/xterm.css" />
<script src="https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/lib/xterm.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/lib/addon-fit.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@xterm/addon-web-links@0.11.0/lib/addon-web-links.js"></script>"""),

        # --- Tailwind CDN + custom config (dual light/dark mode) ---
        RawHtml("""<script src="https://cdn.tailwindcss.com"></script>
<script>
tailwind.config = {
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        /* Dark mode palette (original Sessions colors, used via dark: prefix) */
        deep:'#0a0e14', base:'#0f1419', surf:'#151c25', island:'#1a2332', hov:'#1f2b3d',
        b1:'#1c2736', b2:'#2a3a4f',
        t1:'#d4dce8', t2:'#9baabd', t3:'#4a5568', t4:'#3d5068', tout:'#7ca0bf',
        /* Shared warm neutrals (Therapy.jl ecosystem) */
        'warm-50':'#f8f7f4', 'warm-100':'#f0ece4', 'warm-200':'#e8e3d9',
        'warm-300':'#d4d0c8', 'warm-400':'#9a9590', 'warm-500':'#8a8680',
        'warm-600':'#6b6560', 'warm-700':'#5a5855', 'warm-800':'#2a2520',
        /* Status + accent */
        accent:'#56d4a0', jr:'#e06b65', jg:'#56d4a0', jp:'#b08fd8',
        rose:'#d4759a',
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

        # --- Full CSS (dual light/dark via CSS custom properties) ---
        RawHtml("""<style>
/* ═══ CSS Custom Properties: Light/Dark ═══ */
:root {
  --workspace-bg: #f8f7f4;    /* warm-50 */
  --panel-bg: #ffffff;
  --cell-bg: #f8f7f4;         /* warm-50 = workspace */
  --cell-border: #e8e3d9;     /* warm-200 */
  --cell-border-hov: #d4d0c8; /* warm-300 */
  --chrome-bg: #f0ece4;       /* warm-100 */
  --chrome-active: #ffffff;
  --divider: #e8e3d9;
  --text-1: #2a2520;
  --text-2: #6b6560;
  --text-3: #9a9590;
  --output-text: #6b6560;
  --term-bg: #f0ece4;         /* warm-100, distinct from notebook */
  --term-border: #ffffff;
  --selection-bg: rgba(86,212,160,.15);
  --accent: #d4759a;          /* rose */
  --status-done: #56d4a0;
  --status-running: #d4a056;
  --status-error: #dc3545;
  --panel-shadow: 0 2px 12px rgba(0,0,0,.06);
  --scrollbar-thumb: #d4d0c8;
}
.dark {
  --workspace-bg: #1a2332;
  --panel-bg: #0f1419;
  --cell-bg: #1a2332;
  --cell-border: #1c2736;
  --cell-border-hov: #2a3a4f;
  --chrome-bg: #050709;       /* near-black — tab bar + terminal header */
  --chrome-active: #0f1419;   /* matches notebook bg for active tab */
  --divider: #1c2736;
  --text-1: #d4dce8;
  --text-2: #9baabd;
  --text-3: #6b7d93;
  --output-text: #7ca0bf;
  --term-bg: #050709;          /* matches chrome-bg — near black */
  --term-border: #2a3a4f;
  --selection-bg: rgba(86,212,160,.15);
  --panel-shadow: 0 4px 24px rgba(0,0,0,.3);
  --scrollbar-thumb: #2a3a4f;
}

/* ═══ Reset + Layout ═══ */
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0;}
html,body{height:100%;overflow:hidden;margin:0;padding:0;}
#sessions-root{display:flex;flex-direction:column;height:100vh;overflow:hidden;position:fixed;top:0;left:0;right:0;bottom:0;z-index:1;background:var(--workspace-bg);color:var(--text-1);transition:background .2s,color .2s;}
#workspace{flex:1 1 0%;display:flex;gap:12px;padding:12px;min-height:0;overflow:hidden;}
#workspace>div{min-height:0;}

/* ═══ Activity Bar ═══ */
.ab-btn[data-state="on"]{background:rgba(212,117,154,.1) !important;color:var(--accent) !important;}
.ab-btn:hover{background:rgba(128,128,128,.08) !important;color:var(--text-2) !important;}

/* ═══ Shared Notebook CSS ═══ */
$(Main.Sessions.NOTEBOOK_CSS)

/* ═══ Cell States ═══ */
.code-cell.idle::before{background:var(--text-3);opacity:.2;}
.code-cell.stale::before{background:var(--status-running);opacity:.5;}
.code-cell.executing::before{opacity:0 !important;}
.md-cell::before{content:'';position:absolute;left:0;top:0;bottom:0;width:2px;background:#b08fd8;opacity:.4;border-radius:2px 0 0 2px;}
.cell-collapsed .cm-cell{display:none;}
.cell-collapsed .cell-ctrls{display:none;}
.cell-collapsed::before{opacity:.15!important;}
.cell-collapsed{border-style:dashed!important;opacity:.4;max-height:8px;overflow:hidden;}

/* ═══ Tab Bar + Cell Gaps ═══ */
.cdiv:hover .cdiv-inner{opacity:1;}
.chv{transition:transform .12s ease;}
.chv.open{transform:rotate(90deg);}
.tab.active::after{content:'';position:absolute;bottom:0;left:0;right:0;height:2px;background:var(--accent);border-radius:2px 2px 0 0;}
#fpanel.hide{width:0!important;opacity:0;padding:0;border:none;overflow:hidden;pointer-events:none;}

/* ═══ Scrollbar ═══ */
::-webkit-scrollbar{width:5px;height:5px;}
::-webkit-scrollbar-track{background:transparent;}
::-webkit-scrollbar-thumb{background:var(--scrollbar-thumb);border-radius:3px;}
::selection{background:var(--selection-bg);}

/* ═══ Shoelace loading: hide tree until web components defined ═══ */
sl-tree:not(:defined),sl-tree-item:not(:defined){opacity:0;height:0;overflow:hidden;}
sl-tree:defined,sl-tree-item:defined{opacity:1;height:auto;transition:opacity .2s;}
/* File explorer loading placeholder */
.explorer-loading{display:flex;align-items:center;justify-content:center;flex:1;color:var(--text-3);font-size:11px;font-family:'JetBrains Mono',monospace;gap:6px;}
.explorer-loading .dot-pulse{width:4px;height:4px;border-radius:50%;background:var(--text-3);animation:pulse 1.2s ease-in-out infinite;}
.explorer-loading .dot-pulse:nth-child(2){animation-delay:.2s;}
.explorer-loading .dot-pulse:nth-child(3){animation-delay:.4s;}

/* ═══ Animations ═══ */
@keyframes blink{50%{opacity:0}}
.cblink{animation:blink 1s step-end infinite;}
@keyframes pulse{0%,100%{opacity:1;}50%{opacity:0.4;}}

/* ═══ Markdown Prose ═══ */
.md-prose h5,.md-prose h6{font-family:'Fraunces',Georgia,serif;font-size:1rem;font-weight:600;color:var(--text-1);margin:0.6em 0 0.2em;}

/* ═══ Shoelace Overrides (adapt to current mode) ═══ */
:root{--sl-color-primary-600:var(--accent);--sl-font-sans:'DM Sans',system-ui,sans-serif;--sl-font-mono:'JetBrains Mono',monospace;--sl-font-size-small:12px;}
sl-tree{--indent-size:14px;--indent-guide-width:1px;--indent-guide-color:var(--divider);}
sl-tree-item::part(label){font-size:12px;font-family:'JetBrains Mono',monospace;color:var(--text-3);display:flex;align-items:center;gap:6px;}
sl-tree-item::part(item){border-radius:4px;padding:1px 4px;transition:background .12s,color .12s;}
sl-tree-item::part(item--selected){background:rgba(212,117,154,.08);outline:none;}
sl-tree-item::part(expand-button){color:var(--text-3);padding-right:0;}
sl-tree-item[selected]::part(label){color:var(--text-1);}
sl-tree-item[selected]{border-left:2px solid var(--accent);}
sl-tree-item::part(item):hover{background:rgba(128,128,128,.06);}
.tree-label{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
.tree-rename-input{background:var(--cell-bg);border:1px solid var(--accent);border-radius:3px;color:var(--text-1);font-family:'JetBrains Mono',monospace;font-size:12px;padding:1px 4px;outline:none;width:100%;}
.file-ctx-menu{display:none;position:fixed;z-index:9999;background:var(--panel-bg);border:1px solid var(--cell-border-hov);border-radius:8px;min-width:160px;box-shadow:0 8px 24px rgba(0,0,0,.3);overflow:hidden;padding:4px 0;}
.file-ctx-item{display:flex;align-items:center;gap:8px;padding:6px 12px;font-size:12px;cursor:pointer;color:var(--text-2);font-family:'JetBrains Mono',monospace;transition:background .1s,color .1s;}
.file-ctx-item:hover{background:rgba(212,117,154,.08);color:var(--text-1);}
.file-ctx-item.danger:hover{background:rgba(220,53,69,.1);color:var(--status-error);}
.file-ctx-sep{height:1px;background:var(--divider);margin:4px 8px;}
.tree-breadcrumb{display:flex;align-items:center;gap:4px;padding:4px 8px;font-size:11px;font-family:'JetBrains Mono',monospace;color:var(--text-3);overflow:hidden;}
.tree-breadcrumb button{background:none;border:none;color:var(--text-3);cursor:pointer;padding:2px 4px;border-radius:3px;display:flex;align-items:center;transition:color .12s,background .12s;}
.tree-breadcrumb button:hover{color:var(--text-1);background:rgba(128,128,128,.06);}
.tree-breadcrumb .crumb{color:var(--text-3);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:140px;}

/* ═══ xterm.js ═══ */
.xterm{height:100%;}
.xterm .xterm-viewport{overflow-y:auto!important;}
.xterm .xterm-viewport::-webkit-scrollbar{width:5px;}
.xterm .xterm-viewport::-webkit-scrollbar-track{background:transparent;}
.xterm .xterm-viewport::-webkit-scrollbar-thumb{background:var(--scrollbar-thumb);border-radius:3px;}
.term-tab{display:flex;align-items:center;gap:4px;padding:3px 10px;font-size:11px;font-family:'JetBrains Mono',monospace;color:var(--text-3);cursor:pointer;border-radius:4px 4px 0 0;transition:color .12s,background .12s;white-space:nowrap;user-select:none;}
.term-tab:hover{color:var(--text-2);background:rgba(128,128,128,.06);}
.term-tab.active{color:var(--text-1);background:var(--term-bg);border-bottom:2px solid var(--accent);}
.term-tab .close-x{opacity:0;font-size:9px;padding:1px 3px;border-radius:3px;transition:opacity .1s,background .1s;}
.term-tab:hover .close-x,.term-tab.active .close-x{opacity:.6;}
.term-tab .close-x:hover{opacity:1;background:rgba(220,53,69,.15);color:var(--status-error);}

/* ═══ Undo Toast ═══ */
#undo-toast{position:fixed;bottom:20px;left:20px;z-index:9999;background:var(--panel-bg);border:1px solid var(--cell-border-hov);border-radius:8px;padding:10px 16px;font-size:12px;font-family:'JetBrains Mono',monospace;color:var(--text-2);box-shadow:0 8px 24px rgba(0,0,0,.3);opacity:0;transform:translateY(10px);transition:opacity .2s,transform .2s;pointer-events:none;}
#undo-toast.show{opacity:1;transform:translateY(0);pointer-events:auto;}
#undo-toast kbd{background:var(--chrome-bg);border:1px solid var(--cell-border);border-radius:3px;padding:1px 5px;font-size:11px;color:var(--accent);}

/* ═══ File Editor ═══ */
.file-editor-wrap{height:100%;display:flex;flex-direction:column;}
.cm-file-editor{flex:1;min-height:0;}
.cm-file-editor .cm-editor{height:100%;}

/* ═══ Ghost Toolbar Buttons ═══ */
.tb-btn{display:flex;align-items:center;gap:4px;padding:4px 8px;border-radius:5px;font-size:11px;font-family:-apple-system,sans-serif;border:none;background:transparent;color:var(--text-3);cursor:pointer;transition:all .12s;white-space:nowrap;}
.tb-btn:hover{color:var(--text-1);background:rgba(128,128,128,.1);}
.tb-btn:active{background:rgba(128,128,128,.15);}
.tb-btn.stale{color:var(--status-running);}
.tb-btn.stale:hover{background:rgba(212,160,86,.08);}
.tb-btn.stop{color:var(--status-error);}
.tb-btn.stop:hover{background:rgba(220,53,69,.08);}
.tb-btn svg{width:9px;height:9px;}
.toolbar-sep{width:1px;height:14px;background:var(--divider);margin:0 4px;}
</style>"""),

        # --- Editor bundle (inlined — Therapy dev server has no static file handler) ---
        RawHtml(string("<script>", _EDITOR_BUNDLE_JS, "</script>")),

        # --- Body: children render directly (no wrapper div — SessionsApp owns the layout) ---
        RawHtml("""<div id="app-root" class="font-sans" style="background:var(--workspace-bg);color:var(--text-1);">"""),
        children...,
        RawHtml("""</div>"""),

        # --- Undo toast (for deleted cells) ---
        RawHtml("""<div id="undo-toast">Cell deleted &mdash; <kbd>Ctrl+Z</kbd> to undo</div>"""),

        # --- Panel state: persist to localStorage ---
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

  // CM theme uses CSS vars so it adapts to light/dark automatically
  var isDark = document.documentElement.classList.contains('dark');
  var accentColor = getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() || '#d4759a';
  var edTheme = C.EditorView.theme({
    "&":{backgroundColor:"transparent",color:"var(--text-1)"},
    ".cm-gutters":{backgroundColor:"transparent",color:"var(--text-3)",border:"none",minWidth:"38px"},
    ".cm-activeLine":{backgroundColor:"transparent"},
    "&.cm-focused .cm-activeLine":{backgroundColor:"rgba(128,128,128,.04)"},
    ".cm-activeLineGutter":{backgroundColor:"transparent",color:"var(--text-3)"},
    "&.cm-focused .cm-activeLineGutter":{backgroundColor:"transparent",color:"var(--text-2)"},
    "&.cm-focused .cm-cursor":{borderLeftColor:accentColor},
    "&.cm-focused .cm-selectionBackground, .cm-selectionBackground":{backgroundColor:"var(--selection-bg) !important"},
    ".cm-content":{caretColor:accentColor,fontFamily:"'JetBrains Mono',monospace",fontSize:"13px",lineHeight:"1.65",padding:"8px 0"},
    ".cm-scroller":{fontFamily:"'JetBrains Mono',monospace"},
    ".cm-matchingBracket":{color:accentColor+" !important",backgroundColor:"rgba(212,117,154,.1)",outline:"1px solid rgba(212,117,154,.2)"},
    ".cm-line":{paddingLeft:"4px"},
  },{dark:isDark});

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
  if (!window._sessSuppressSync) window._sessSuppressSync = {};
  function syncCodeToServer(cellId) {
    if (window._sessSuppressSync[cellId]) { delete window._sessSuppressSync[cellId]; return; }
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
  // Uses DOM-level handler to guarantee capture — CM6 keymap dispatch
  // can miss Shift-Enter depending on extension ordering and platform.
  function shiftEnterKeymap(cellId) {
    return C.EditorView.domEventHandlers({
      keydown: function(event) {
        if (event.key === 'Enter' && event.shiftKey && !event.ctrlKey && !event.metaKey) {
          event.preventDefault();
          window._sessionsRunCell(cellId);
          return true;
        }
      }
    });
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

      // Shift+Enter must come BEFORE defaultKeymap — CM6 checks keymaps in
      // extension order, and defaultKeymap's Enter handler would swallow it.
      var cellKeymaps = (!isFileEditor && cellId) ? [shiftEnterKeymap(cellId)] : [];
      var exts = [
        ...cellKeymaps,
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
        // Debounced sync (Shift+Enter already added above)
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

  // ── Fold persistence: watch CellToggle @island toggle and sync to server ──
  // CellToggle @island handles the visual toggle via Therapy.jl signal + Show().
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
  function fmtSeconds(s) {
    return s < 1 ? s.toFixed(2) + 's' : s < 60 ? s.toFixed(1) + 's' : (s / 60).toFixed(1) + 'min';
  }

  // ── Live stopwatch for running cells ──
  var _cellTimers = {};  // cellId → {interval, startTime}

  function startCellTimer(cellId, el) {
    stopCellTimer(cellId);
    if (!el || !el.ctrls) return;
    var startTime = performance.now();
    // Create or reuse the badge
    var badge = el.ctrls.querySelector('.rt-badge');
    if (!badge) {
      badge = document.createElement('span');
      badge.className = 'rt-badge';
      el.ctrls.insertBefore(badge, el.ctrls.firstChild);
    }
    badge.style.cssText = 'font-size:10px;font-family:ui-monospace,monospace;padding:1px 7px;border-radius:9999px;color:#7bb8e8;opacity:.9;background:rgba(123,184,232,.08);border:1px solid rgba(123,184,232,.15);';
    badge.textContent = '0.0s';
    var interval = setInterval(function() {
      var elapsed = (performance.now() - startTime) / 1000;
      badge.textContent = fmtSeconds(elapsed);
    }, 100);
    _cellTimers[cellId] = {interval: interval, startTime: startTime};
  }

  function stopCellTimer(cellId) {
    var timer = _cellTimers[cellId];
    if (timer) {
      clearInterval(timer.interval);
      delete _cellTimers[cellId];
    }
  }

  // ── Helper: update cell CSS state (accent bar color) ──
  function setCellState(el, state, cellId) {
    if (!el) return;
    var cc = el.code;
    if (!cc) return;
    cc.classList.remove('idle', 'stale', 'executing');
    // Queued/running: colored border + hide the green/orange side accent bar
    if (state === 'cell_queued' || state === 'cell_running') {
      cc.style.borderColor = state === 'cell_queued' ? '#d4a056' : '#7bb8e8';
      cc.classList.add('executing');
      // Start live stopwatch when cell begins running
      if (state === 'cell_running' && cellId) {
        startCellTimer(cellId, el);
      }
    } else {
      if (cellId) stopCellTimer(cellId);
      if (state === 'cell_errored') {
        cc.style.borderColor = '#e06b65';
      } else {
        cc.style.borderColor = '';  // revert to CSS default
      }
    }
  }

  window.addEventListener('therapy:channel:notebook', function(e) {
    var data = e.detail;
    if (!data || !data.event) return;

    if (data.event === 'cell_state') {
      var el = cellEls(data.cell_id);
      setCellState(el, data.state, data.cell_id);
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
          window._sessSuppressSync[data.cell_id] = true;  // don't echo back to server
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
          window._sessSuppressSync[data.cell_id] = true;  // don't echo back to server
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

      // Update cell state (done/errored) — stops live timer
      setCellState(el, data.state, data.cell_id);

      // Update runtime badge with final server-measured time
      if (el.ctrls && data.runtime_ns && data.runtime_ns > 0) {
        var old = el.ctrls.querySelector('.rt-badge');
        if (old) old.remove();
        var badge = document.createElement('span');
        badge.className = 'rt-badge';
        var isErr = data.state === 'cell_errored';
        var c = isErr ? '#e06b65' : '#56d4a0';
        badge.style.cssText = 'font-size:10px;font-family:ui-monospace,monospace;padding:1px 7px;border-radius:9999px;opacity:.8;color:'+c+';background:rgba('+(isErr?'224,107,101':'86,212,160')+',.08);border:1px solid rgba('+(isErr?'224,107,101':'86,212,160')+',.12);';
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
      // Show/hide Run Stale button (but keep hidden during execution)
      var btn = document.getElementById('run-stale-btn');
      var label = document.getElementById('run-stale-label');
      if (btn) {
        if (data.count > 0 && !window._sessionsExecuting) {
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
      var isRunning = data.running_index > 0 && data.total > 0;
      window._sessionsExecuting = isRunning;
      var el = document.getElementById('run-progress');
      if (el) {
        if (isRunning) {
          el.textContent = 'Running ' + data.running_index + '/' + data.total + '...';
          el.style.display = '';
        } else {
          el.textContent = '';
          el.style.display = 'none';
        }
      }
      // Toggle Run All / Stop / Run Stale button visibility
      var runAllBtn = document.getElementById('run-all-btn');
      var stopBtn = document.getElementById('stop-btn');
      var runStaleBtn = document.getElementById('run-stale-btn');
      if (runAllBtn && stopBtn) {
        if (isRunning) {
          runAllBtn.style.display = 'none';
          stopBtn.style.display = '';
          if (runStaleBtn) runStaleBtn.style.display = 'none';
        } else {
          runAllBtn.style.display = '';
          stopBtn.style.display = 'none';
          // Run Stale restored by the stale_update event that follows
        }
      }
    }

    else if (data.event === 'interrupted') {
      window._sessionsExecuting = false;
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
      // Restore Run All + Run Stale buttons
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
          setCellState(el, cell.state, cell.cell_id);
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
