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

# Load theme CSS — read fresh each time (not const, so changes to theme.css
# are picked up without recompilation)
function _load_theme_css()
    p = joinpath(@__DIR__, "..", "..", "theme.css")
    isfile(p) ? read(p, String) : "/* theme.css not found */"
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

        # --- MathJax 3 (LaTeX rendering) ---
        let ds = '\$'  # dollar sign, escaped from Julia interpolation
            RawHtml("""<script>
window.MathJax={tex:{inlineMath:[['$(ds)','$(ds)'],['\\\\(','\\\\)']]},svg:{fontCache:'global'}};
</script>
<script id="MathJax-script" async src="https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/tex-svg-full.js"></script>""")
        end,

        # --- highlight.js (syntax highlighting for markdown code blocks, like Pluto) ---
        RawHtml("""<link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/styles/default.min.css" disabled>
<script src="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/highlight.min.js"></script>
<script src="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/languages/julia.min.js"></script>
<script>hljs.configure({cssSelector:'.md-prose pre code', ignoreUnescapedHTML:true});</script>"""),

        # --- xterm.js (terminal emulator) ---
        RawHtml("""<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/css/xterm.css" />
<script src="https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/lib/xterm.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/lib/addon-fit.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@xterm/addon-web-links@0.11.0/lib/addon-web-links.js"></script>"""),

        # --- Theme CSS (single source of truth for all colors) ---
        RawHtml(string("<style>", _load_theme_css(), "</style>")),

        # --- Tailwind CDN + config (references CSS vars from theme.css) ---
        RawHtml("""<script src="https://cdn.tailwindcss.com"></script>
<script>
tailwind.config = {
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        /* All colors reference CSS vars from theme.css */
        workspace: 'var(--workspace-bg)',
        panel: 'var(--panel-bg)',
        cell: 'var(--cell-bg)',
        chrome: 'var(--chrome-bg)',
        divider: 'var(--divider)',
        accent: 'var(--accent)',
        rose: 'var(--accent)',
        'status-done': 'var(--status-done)',
        'status-running': 'var(--status-running)',
        'status-error': 'var(--status-error)',
        /* Warm neutrals for Tailwind utility classes */
        'warm-50':'var(--warm-50)', 'warm-100':'var(--warm-100)', 'warm-200':'var(--warm-200)',
        'warm-300':'var(--warm-300)', 'warm-400':'var(--warm-400)', 'warm-500':'var(--warm-500)',
        'warm-600':'var(--warm-600)', 'warm-700':'var(--warm-700)', 'warm-800':'var(--warm-800)',
      },
      textColor: {
        1: 'var(--text-1)',
        2: 'var(--text-2)',
        3: 'var(--text-3)',
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
/* Colors defined in theme.css (inlined above) — do not duplicate here */

/* ═══ Reset + Layout ═══ */
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0;}
html,body{height:100%;overflow:hidden;margin:0;padding:0;}
#sessions-root{display:flex;flex-direction:column;height:100vh;overflow:hidden;position:fixed;top:0;left:0;right:0;bottom:0;z-index:1;background:var(--workspace-bg);color:var(--text-1);transition:background .2s,color .2s;}
#workspace{flex:1 1 0%;display:flex;gap:12px;padding:12px;min-height:0;overflow:hidden;}
/* Clip panel shadows at workspace boundary to prevent corner bleed */
#workspace>*{min-height:0;}
#workspace>div{min-height:0;}
/* NotebookIsland therapy-island must participate in #nb-island flex layout for scroll */
#nb-island>therapy-island{flex:1;display:flex;flex-direction:column;min-height:0;}
/* Clip cell-shoulder overflow so it doesn't bleed into sidebar/activity bar */
#nb{overflow-x:hidden;}

/* ═══ Activity Bar ═══ */
.ab-btn[data-state="on"]{background:rgba(212,117,154,.1) !important;color:var(--accent) !important;}
.ab-btn:hover{background:rgba(128,128,128,.08) !important;color:var(--text-2) !important;}

/* ═══ Notebook CSS (cell chrome, markdown prose, tables) ═══ */
$(Main.Sessions.NOTEBOOK_CSS)

/* ═══ Cell States ═══ */
/* Stale: traffic light bar turns amber */
.cell-wrap:has(.code-cell.stale)::before{background:var(--status-running) !important;opacity:.7 !important;}
.md-cell::before{content:'';position:absolute;left:0;top:0;bottom:0;width:2px;background:#b08fd8;opacity:.4;border-radius:2px 0 0 2px;}
.cell-collapsed .cm-cell{display:none;}
.cell-collapsed .cell-ctrls{display:none;}
.cell-collapsed::before{opacity:.15!important;}
.cell-collapsed{border-style:dashed!important;opacity:.4;max-height:8px;overflow:hidden;}
/* Cell execution state — border on .cell-wrap (visible even when code folded), suppress inner borders */
@property --border-angle{syntax:"<angle>";initial-value:0deg;inherits:false;}
/* Queued: amber border on wrap + suppress inner borders */
.cell-wrap.wrap-queued{border:2px solid var(--status-running);border-radius:8px;box-shadow:0 0 10px rgba(212,160,86,.12);}
.cell-wrap.wrap-queued .code-cell{border-color:transparent !important;}
.cell-wrap.wrap-queued .jl-error{border-color:transparent !important;}
/* Running: spinning border on wrap */
.cell-wrap.wrap-running{position:relative;border:2px solid transparent;border-radius:8px;box-shadow:0 0 12px rgba(123,184,232,.1);}
.cell-wrap.wrap-running .code-cell{border-color:transparent !important;}
.cell-wrap.wrap-running::after{content:'';position:absolute;inset:-2px;border-radius:10px;padding:2px;background:conic-gradient(from var(--border-angle),#7bb8e8 0%,transparent 30%,transparent 70%,#7bb8e8 100%);-webkit-mask:linear-gradient(#fff 0 0) content-box,linear-gradient(#fff 0 0);-webkit-mask-composite:xor;mask:linear-gradient(#fff 0 0) content-box,linear-gradient(#fff 0 0);mask-composite:exclude;animation:spin-border 2.5s linear infinite;pointer-events:none;z-index:60;}
/* Errored: red border on wrap + suppress inner borders */
.cell-wrap.wrap-errored{border:2px solid var(--status-error);border-radius:8px;}
.cell-wrap.wrap-errored .code-cell{border-color:transparent !important;}
.cell-wrap.wrap-errored .jl-error{border-color:transparent !important;border-top-left-radius:0;border-top-right-radius:0;}
@keyframes spin-border{to{--border-angle:360deg;}}

/* ═══ Tab Bar + Cell Gaps ═══ */
.cdiv{height:10px;display:flex;align-items:center;justify-content:center;position:relative;cursor:pointer;}
.cdiv-inner{opacity:0;transition:opacity .15s;display:flex;align-items:center;justify-content:center;position:absolute;z-index:5;}
.cdiv:hover .cdiv-inner{opacity:1;}
.cdiv-btn{width:20px;height:20px;display:flex;align-items:center;justify-content:center;border-radius:50%;border:1px solid var(--cell-border);background:var(--panel-bg);color:var(--text-3);cursor:pointer;font-size:12px;padding:0;transition:all .12s;}
.cdiv-btn:hover{border-color:var(--accent);color:var(--accent);background:var(--accent-dim);}
.chv{transition:transform .12s ease;}
.chv.open{transform:rotate(90deg);}
.tab.active::after{content:'';position:absolute;bottom:0;left:0;right:0;height:2px;background:var(--accent);border-radius:2px 2px 0 0;}
#fpanel.hide{width:0!important;opacity:0;padding:0;border:none;overflow:hidden;pointer-events:none;}

/* ═══ Scrollbar ═══ */
::-webkit-scrollbar{width:5px;height:5px;}
::-webkit-scrollbar-track{background:transparent;}
::-webkit-scrollbar-thumb{background:var(--scrollbar-thumb);border-radius:3px;}
::selection{background:var(--selection-bg);}

/* ═══ Resize Zones (on panel edges, no extra DOM elements) ═══ */
#fpanel{position:relative;}
#fpanel::after{content:'';position:absolute;top:0;bottom:0;right:-8px;width:12px;cursor:col-resize;z-index:10;}
#repl{position:relative;}
#repl::before{content:'';position:absolute;left:0;right:0;top:-8px;height:12px;cursor:row-resize;z-index:10;}
body.resizing-x *{cursor:col-resize!important;user-select:none!important;}
body.resizing-y *{cursor:row-resize!important;user-select:none!important;}

/* ═══ Shoelace loading: hide tree until web components defined ═══ */
sl-tree:not(:defined),sl-tree-item:not(:defined){opacity:0;height:0;overflow:hidden;}
sl-tree:defined,sl-tree-item:defined{opacity:1;height:auto;transition:opacity .2s;}
/* File explorer loading placeholder */
.explorer-loading{display:flex;align-items:center;justify-content:center;flex:1;color:var(--text-3);font-size:11px;font-family:'JetBrains Mono',monospace;gap:6px;}
.explorer-loading .dot-pulse{width:4px;height:4px;border-radius:50%;background:var(--text-3);animation:pulse 1.2s ease-in-out infinite;}
.explorer-loading .dot-pulse:nth-child(2){animation-delay:.2s;}
.explorer-loading .dot-pulse:nth-child(3){animation-delay:.4s;}

/* ═══ Notebook loading overlay ═══ */
.nb-loading{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;gap:6px;z-index:10;background:var(--panel-bg);transition:opacity .3s;pointer-events:none;}
.nb-loading.loaded{opacity:0;}
.nb-loading .dot-pulse{width:5px;height:5px;border-radius:50%;background:var(--accent);animation:pulse 1.2s ease-in-out infinite;}
.nb-loading .dot-pulse:nth-child(2){animation-delay:.2s;}
.nb-loading .dot-pulse:nth-child(3){animation-delay:.4s;}

/* ═══ Animations ═══ */
@keyframes blink{50%{opacity:0}}
.cblink{animation:blink 1s step-end infinite;}
@keyframes pulse{0%,100%{opacity:1;}50%{opacity:0.4;}}

/* Markdown prose defined in theme.css (single source of truth) */

/* ═══ Shoelace Overrides (adapt to current mode) ═══ */
:root{--sl-color-primary-600:var(--accent);--sl-font-sans:'DM Sans',system-ui,sans-serif;--sl-font-mono:'JetBrains Mono',monospace;--sl-font-size-small:12px;}
sl-tree{--indent-size:14px;--indent-guide-width:1px;--indent-guide-color:var(--divider);min-width:max-content;}
sl-tree-item::part(label){font-size:12px;font-family:'JetBrains Mono',monospace;color:var(--text-3);display:flex;align-items:center;gap:6px;}
sl-tree-item::part(item){border-radius:4px;padding:1px 4px;transition:background .12s,color .12s;}
sl-tree-item::part(item--selected){background:rgba(212,117,154,.1);outline:none;border-left:2px solid var(--accent);}
sl-tree-item::part(expand-button){color:var(--text-3);padding-right:0;}
sl-tree-item[selected]::part(label){color:var(--text-1);}
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
.tb-btn.tb-disabled{opacity:.3;pointer-events:none;}
.tb-btn svg{width:9px;height:9px;}
.toolbar-sep{width:1px;height:14px;background:var(--divider);margin:0 4px;}
/* Theme toggle button */
#theme-toggle-btn:hover{background:rgba(212,117,154,.18) !important;border-color:var(--accent) !important;}
</style>"""),

        # --- Editor bundle (inlined — Therapy dev server has no static file handler) ---
        RawHtml(string("<script>", _EDITOR_BUNDLE_JS, "</script>")),

        # --- Body: children render directly (no wrapper div — SessionsApp owns the layout) ---
        RawHtml("""<div id="app-root" class="font-sans" style="background:var(--workspace-bg);color:var(--text-1);">"""),
        children...,
        RawHtml("""</div>"""),

        # --- Sessions WS: channel-based messaging + dispatch ---
        RawHtml("""<script>
(function(){
  // 1. Extend TherapyWS with sendMessage(channel, data)
  //    TherapyWS.sendMessage('notebook', {action:'execute', cell_id:'...'})
  //    → sends {type:'action', channel:'notebook', action:'execute', cell_id:'...'}
  function _waitForWS() {
    if (window.TherapyWS && TherapyWS.send) {
      TherapyWS.sendMessage = function(channel, data) {
        var msg = Object.assign({type:'action', channel:channel}, data);
        TherapyWS.send(msg);
      };
    } else {
      setTimeout(_waitForWS, 100);
    }
  }
  _waitForWS();

  // 2. Dispatch incoming WS messages to channel-specific custom events
  //    Server sends: {channel:'notebook', event:'cell_output', ...}
  //    Client dispatches: therapy:channel:notebook CustomEvent with detail=msg
  window.addEventListener('therapy:ws:message', function(e) {
    var msg = e.detail;
    if (!msg) return;
    var channel = msg.channel;
    if (channel) {
      window.dispatchEvent(new CustomEvent('therapy:channel:' + channel, {detail: msg}));
    }
  });
})();
</script>"""),

        # --- Undo toast (for deleted cells) ---
        RawHtml("""<div id="undo-toast">Cell deleted &mdash; <kbd>Ctrl+Z</kbd> to undo</div>"""),

        # --- Notebook JS: global function definitions (must load before island hydration) ---
        RawHtml(string("<script>", _notebook_island_js(), "</script>")))
end

# _notebook_channel_script() moved to Notebook.jl
