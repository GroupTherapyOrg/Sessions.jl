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
.cell-collapsed .cm-cell,.cell-collapsed .cell-out{display:none;}
.cell-collapsed .md-inner{display:none;}
.cell-collapsed::before{opacity:.15!important;}
.cell-collapsed{border-style:dashed!important;opacity:.6;}
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
</style>"""),

        # --- Editor bundle (inlined — Therapy dev server has no static file handler) ---
        RawHtml(string("<script>", _EDITOR_BUNDLE_JS, "</script>")),

        # --- Body wrapper with children ---
        Div(:class => "bg-base text-t1 font-sans h-screen w-screen flex flex-col",
            children...),

        # --- Notebook channel handler ---
        _notebook_channel_script(),

        # --- CM initialization + eye toggle (after children so DOM exists) ---
        RawHtml("""<script>
(function() {
  if (typeof C === 'undefined' || !C.EditorView) return;

  // Initialize CM editors
  document.querySelectorAll('.cm-cell').forEach(function(host) {
    if (host.querySelector('.cm-editor')) return;
    var src = host.dataset.src || '';
    new C.EditorView({
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
        C.julia(),
        C.syntaxHighlighting(C.HighlightStyle.define([
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
        ])),
        C.EditorView.theme({
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
        },{dark:true}),
      ],
      parent: host,
    });
  });

  // Eye toggle
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
      var output = document.querySelector('.cell-output[data-cell-id="' + data.cell_id + '"]');
      if (output) output.innerHTML = data.output_html || '';
      var badge = document.querySelector('[data-cell-state][data-cell-id="' + data.cell_id + '"]');
      if (badge && data.state) {
        badge.style.background = stateColors[data.state] || '#56d4a0';
        badge.dataset.cellState = data.state;
        badge.style.animation = 'none';
      }
    }

    else if (data.event === 'cell_added' || data.event === 'cell_deleted' || data.event === 'cell_order') {
      window.location.reload();
    }

    else if (data.event === 'saved') {
      var ind = document.getElementById('save-indicator');
      if (ind) { ind.textContent = 'Saved'; setTimeout(function(){ ind.textContent = 'Save'; }, 2000); }
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
            var output = document.querySelector('.cell-output[data-cell-id="' + cell.cell_id + '"]');
            if (output && output.innerHTML === '') output.innerHTML = cell.output_html;
          }
        });
      }
    }
  });

  document.addEventListener('keydown', function(e) {
    if ((e.ctrlKey || e.metaKey) && e.key === 's') {
      e.preventDefault();
      if (window.TherapyWS && TherapyWS.sendMessage) TherapyWS.sendMessage('notebook', {action: 'save'});
    }
  });
})();
</script>""")
end
