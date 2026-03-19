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
</style>"""),

        # --- Editor bundle (inlined — Therapy dev server has no static file handler) ---
        RawHtml(string("<script>", _EDITOR_BUNDLE_JS, "</script>")),

        # --- Body wrapper with children ---
        Div(:class => "bg-base text-t1 font-sans h-screen w-screen flex flex-col",
            children...),

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
    ".cm-activeLine":{backgroundColor:"rgba(86,212,160,.03)"},
    ".cm-activeLineGutter":{backgroundColor:"transparent",color:"#6b7d93"},
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

  // ── Initialize CM editors ──
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

  // ── Eye toggle ──
  document.querySelectorAll('.cell-eye').forEach(function(btn) {
    btn.addEventListener('click', function() {
      var wrap = btn.closest('.cell-wrap').querySelector('.code-cell, .md-cell');
      if (!wrap) return;
      var collapsed = wrap.classList.toggle('cell-collapsed');
      btn.innerHTML = collapsed
        ? '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19M1 1l22 22"/></svg>'
        : '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>';
      btn.title = collapsed ? 'Show cell' : 'Hide cell';
    });
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

  var stateColors = {
    'cell_idle':    '#3d5068',
    'cell_queued':  '#d4a056',
    'cell_running': '#7bb8e8',
    'cell_done':    '#56d4a0',
    'cell_errored': '#e06b65'
  };

  window.addEventListener('therapy:channel:notebook', function(e) {
    var data = e.detail;
    if (!data || !data.event) return;

    if (data.event === 'cell_state') {
      var badge = document.querySelector('[data-cell-state][data-cell-id="' + data.cell_id + '"]');
      if (badge) {
        badge.style.background = stateColors[data.state] || stateColors['cell_idle'];
        badge.dataset.cellState = data.state;
        badge.style.animation = (data.state === 'cell_queued' || data.state === 'cell_running') ? 'pulse 1.5s infinite' : 'none';
      }
    }

    else if (data.event === 'cell_output') {
      // Update output HTML
      var output = document.querySelector('.cell-out[data-cell-id="' + data.cell_id + '"]');
      if (output) {
        var html = data.output_html || '';
        if (html) {
          output.innerHTML = html;
          output.style.display = '';
          output.style.padding = '6px 0 10px';
        } else {
          output.innerHTML = '';
          output.style.display = 'none';
        }
      }
      // Update state badge
      var badge = document.querySelector('[data-cell-state][data-cell-id="' + data.cell_id + '"]');
      if (badge && data.state) {
        badge.style.background = stateColors[data.state] || '#56d4a0';
        badge.dataset.cellState = data.state;
        badge.style.animation = 'none';
      }
      // Update runtime badge
      if (data.runtime_ns && data.runtime_ns > 0) {
        var cell_wrap = document.querySelector('.cell-wrap[data-cell-id="' + data.cell_id + '"]');
        if (cell_wrap) {
          var ctrls = cell_wrap.querySelector('.cell-ctrls');
          if (ctrls) {
            // Remove old runtime badge if exists
            var old = ctrls.querySelector('.rt-badge');
            if (old) old.remove();
            // Format runtime
            var ms = data.runtime_ns / 1e6;
            var rt = ms < 1 ? (data.runtime_ns / 1e3).toFixed(1) + '\u00b5s' : ms < 1000 ? ms.toFixed(1) + 'ms' : (ms / 1000).toFixed(2) + 's';
            var badge_el = document.createElement('span');
            badge_el.className = 'rt-badge';
            badge_el.style.cssText = 'font-size:10px;font-family:ui-monospace,monospace;padding:1px 7px;border-radius:9999px;color:#56d4a0;opacity:.8;background:rgba(86,212,160,.08);border:1px solid rgba(86,212,160,.12);';
            badge_el.textContent = rt;
            ctrls.insertBefore(badge_el, ctrls.firstChild);
          }
          // Remove idle class
          var codeCell = cell_wrap.querySelector('.code-cell');
          if (codeCell) codeCell.classList.remove('idle');
        }
      }
    }

    else if (data.event === 'cell_added' || data.event === 'cell_deleted' || data.event === 'cell_order') {
      window.location.reload();
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
          var badge = document.querySelector('[data-cell-state][data-cell-id="' + cell.cell_id + '"]');
          if (badge) {
            badge.style.background = stateColors[cell.state] || stateColors['cell_idle'];
            badge.dataset.cellState = cell.state;
          }
          if (cell.output_html) {
            var output = document.querySelector('.cell-out[data-cell-id="' + cell.cell_id + '"]');
            if (output && !output.innerHTML) {
              output.innerHTML = cell.output_html;
              output.style.display = '';
              output.style.padding = '6px 0 10px';
            }
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
})();
</script>""")
end
