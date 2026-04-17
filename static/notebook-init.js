// Sessions.jl published-notebook bootstrap.
//
// Bundled into render_published_notebook output so any Therapy app
// that drops in a Sessions-extracted .jl notebook gets working
// read-only CodeMirror editors + dark-mode re-theming "for free".
//
// Runs inside an IIFE with `__SESSIONS_NB_BOOT` singleton guard so
// multiple notebooks on the same page (e.g. gallery view) share one
// boot without redundant work.

(function () {
  if (window.__SESSIONS_NB_BOOT) return;
  window.__SESSIONS_NB_BOOT = true;

  // editor.js exposes `window.C`. Abort if it's not available —
  // likely means the preceding <script> that inlined editor.js
  // failed to execute. Nothing downstream is recoverable.
  if (typeof C === 'undefined' || !C.EditorView) return;

  function isDark() {
    return document.documentElement.classList.contains('dark');
  }

  // Syntax highlighting themes — dark + light palettes matching the
  // live IDE's CSS-vars-driven theme (input.css exports --cm-*).
  var darkHL = C.HighlightStyle.define([
    { tag: C.t.keyword,           color: '#e07068' },
    { tag: C.t.controlKeyword,    color: '#e07068' },
    { tag: C.t.operatorKeyword,   color: '#e07068' },
    { tag: C.t.definitionKeyword, color: '#e07068' },
    { tag: C.t.moduleKeyword,     color: '#e07068' },
    { tag: C.t.string,    color: '#56d4a0' },
    { tag: C.t.character, color: '#56d4a0' },
    { tag: C.t.comment,   color: '#4a6178', fontStyle: 'italic' },
    { tag: C.t.number,  color: '#d4a056' },
    { tag: C.t.integer, color: '#d4a056' },
    { tag: C.t.float,   color: '#d4a056' },
    { tag: C.t.bool,    color: '#d4a056' },
    { tag: C.t.function(C.t.variableName),   color: '#7bb8e8' },
    { tag: C.t.definition(C.t.variableName), color: '#7bb8e8' },
    { tag: C.t.typeName,     color: '#b08fd8' },
    { tag: C.t.className,    color: '#b08fd8' },
    { tag: C.t.variableName, color: '#d4dce8' },
    { tag: C.t.punctuation, color: '#6b7d93' },
    { tag: C.t.operator,    color: '#d4dce8' },
    { tag: C.t.macroName,   color: '#d4a056' },
  ]);

  var lightHL = C.HighlightStyle.define([
    { tag: C.t.keyword,           color: '#c4352b' },
    { tag: C.t.controlKeyword,    color: '#c4352b' },
    { tag: C.t.operatorKeyword,   color: '#c4352b' },
    { tag: C.t.definitionKeyword, color: '#c4352b' },
    { tag: C.t.moduleKeyword,     color: '#c4352b' },
    { tag: C.t.string,    color: '#1e7855' },
    { tag: C.t.character, color: '#1e7855' },
    { tag: C.t.comment,   color: '#7b8a9e', fontStyle: 'italic' },
    { tag: C.t.number,  color: '#b5831b' },
    { tag: C.t.integer, color: '#b5831b' },
    { tag: C.t.float,   color: '#b5831b' },
    { tag: C.t.bool,    color: '#b5831b' },
    { tag: C.t.function(C.t.variableName),   color: '#2b6cb0' },
    { tag: C.t.definition(C.t.variableName), color: '#2b6cb0' },
    { tag: C.t.typeName,     color: '#7c3aed' },
    { tag: C.t.className,    color: '#7c3aed' },
    { tag: C.t.variableName, color: '#1a2332' },
    { tag: C.t.punctuation, color: '#7b8a9e' },
    { tag: C.t.operator,    color: '#1a2332' },
    { tag: C.t.macroName,   color: '#b5831b' },
  ]);

  var darkTheme = C.EditorView.theme({
    '&':               { backgroundColor: 'transparent', color: '#d4dce8' },
    '.cm-gutters':     { backgroundColor: 'transparent', color: '#3d5068', border: 'none', minWidth: '38px' },
    '.cm-activeLine':  { backgroundColor: 'transparent' },
    '.cm-content':     { fontFamily: "'JetBrains Mono',monospace", fontSize: '13px', lineHeight: '1.65', padding: '8px 0' },
    '.cm-scroller':    { fontFamily: "'JetBrains Mono',monospace" },
    '.cm-cursor':      { display: 'none' },
  }, { dark: true });

  var lightTheme = C.EditorView.theme({
    '&':               { backgroundColor: 'transparent', color: '#1a2332' },
    '.cm-gutters':     { backgroundColor: 'transparent', color: '#b0bac8', border: 'none', minWidth: '38px' },
    '.cm-activeLine':  { backgroundColor: 'transparent' },
    '.cm-content':     { fontFamily: "'JetBrains Mono',monospace", fontSize: '13px', lineHeight: '1.65', padding: '8px 0' },
    '.cm-scroller':    { fontFamily: "'JetBrains Mono',monospace" },
    '.cm-cursor':      { display: 'none' },
  }, { dark: false });

  function initCM() {
    var dark = isDark();
    document.querySelectorAll('.cm-cell-published').forEach(function (host) {
      if (host.querySelector('.cm-editor')) return;  // already initialized
      new C.EditorView({
        state: C.EditorState.create({
          doc: host.dataset.src || '',
          extensions: [
            C.lineNumbers(),
            C.highlightSpecialChars(),
            C.drawSelection(),
            C.bracketMatching(),
            C.julia(),
            C.syntaxHighlighting(dark ? darkHL : lightHL),
            dark ? darkTheme : lightTheme,
            C.EditorState.readOnly.of(true),
            C.EditorView.editable.of(false),
          ],
        }),
        parent: host,
      });
    });
  }

  function reinitCM() {
    document.querySelectorAll('.cm-cell-published .cm-editor').forEach(function (ed) { ed.remove(); });
    initCM();
  }

  // Defer first run until DOM has .cm-cell-published hosts. This <script>
  // is inlined inline and may run before parsing reaches the cells below.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initCM);
  } else {
    initCM();
  }

  // SPA navigation — Therapy dispatches `therapy:router:loaded` after
  // a client-side page swap. Re-init on new .cm-cell-published hosts.
  window.addEventListener('therapy:router:loaded', initCM);

  // Theme switch — reinit so the HighlightStyle and theme objects swap.
  var _lastDark = isDark();
  new MutationObserver(function () {
    var now = isDark();
    if (now !== _lastDark) { _lastDark = now; reinitCM(); }
  }).observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });
})();
