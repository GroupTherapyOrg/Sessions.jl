// Sessions.jl published-notebook bootstrap — read-only port of the
// live IDE's CodeMirror setup (Sessions.jl/src/components/Notebook.jl
// lines 66–122). Every visual knob is copied verbatim so published
// notebooks match the IDE's editor 1-to-1; only the editable flag
// flips.
//
// Bundled into render_published_notebook output so any Therapy app
// that drops in a Sessions-extracted .jl notebook gets working
// read-only CodeMirror editors + dark-mode re-theming for free.

(function () {
  if (window.__SESSIONS_NB_BOOT) return;
  window.__SESSIONS_NB_BOOT = true;
  if (typeof C === 'undefined' || !C.EditorView) return;

  // ── Syntax highlight — 1-to-1 port of Notebook.jl hlTheme ────────
  // All colors reference CSS custom properties the notebook-chrome.css
  // bundle defines for both :root and .dark, so light/dark is purely
  // a class flip on <html>.
  var hlTheme = C.HighlightStyle.define([
    // Keywords (function, if, end, for, using, etc.)
    { tag: C.t.keyword,             color: 'var(--cm-keyword)' },
    { tag: C.t.controlKeyword,      color: 'var(--cm-keyword)' },
    { tag: C.t.operatorKeyword,     color: 'var(--cm-keyword)' },
    { tag: C.t.definitionKeyword,   color: 'var(--cm-keyword)' },
    { tag: C.t.moduleKeyword,       color: 'var(--cm-keyword)' },
    { tag: C.t.definitionOperator,  color: 'var(--cm-keyword)' },
    { tag: C.t.logicOperator,       color: 'var(--cm-keyword)' },
    { tag: C.t.controlOperator,     color: 'var(--cm-keyword)' },
    // Strings
    { tag: C.t.string,              color: 'var(--cm-string)'  },
    { tag: C.t.special(C.t.string), color: 'var(--cm-command)' },
    // Comments (italic)
    { tag: C.t.comment,             color: 'var(--cm-comment)', fontStyle: 'italic' },
    { tag: C.t.lineComment,         color: 'var(--cm-comment)', fontStyle: 'italic' },
    { tag: C.t.blockComment,        color: 'var(--cm-comment)', fontStyle: 'italic' },
    // Literals (numbers, bools, chars)
    { tag: C.t.number,    color: 'var(--cm-literal)' },
    { tag: C.t.integer,   color: 'var(--cm-literal)' },
    { tag: C.t.float,     color: 'var(--cm-literal)' },
    { tag: C.t.bool,      color: 'var(--cm-literal)' },
    { tag: C.t.character, color: 'var(--cm-literal)' },
    { tag: C.t.literal,   color: 'var(--cm-literal)' },
    { tag: C.t.escape,    color: 'var(--cm-literal)' },
    // Variables
    { tag: C.t.variableName,                 color: 'var(--cm-variable)' },
    { tag: C.t.function(C.t.variableName),   color: 'var(--cm-function)' },
    { tag: C.t.definition(C.t.variableName), color: 'var(--cm-function)' },
    // Types
    { tag: C.t.typeName,  color: 'var(--cm-variable)', opacity: '0.8' },
    { tag: C.t.className, color: 'var(--cm-variable)', opacity: '0.8' },
    // Symbols & properties
    { tag: C.t.atom,         color: 'var(--cm-symbol)' },
    { tag: C.t.propertyName, color: 'var(--cm-symbol)' },
    // Macros
    { tag: C.t.macroName, color: 'var(--cm-macro)', fontWeight: 'bold' },
    // Brackets & punctuation
    { tag: C.t.paren,         color: 'var(--cm-bracket)' },
    { tag: C.t.squareBracket, color: 'var(--cm-bracket)' },
    { tag: C.t.brace,         color: 'var(--cm-bracket)' },
    { tag: C.t.punctuation,   color: 'var(--cm-bracket)' },
    // Operators
    { tag: C.t.operator,           color: 'var(--cm-editor-text)' },
    { tag: C.t.arithmeticOperator, color: 'var(--cm-editor-text)' },
    { tag: C.t.compareOperator,    color: 'var(--cm-editor-text)' },
  ]);

  // ── Editor theme — 1-to-1 port of Notebook.jl _makeEdTheme ───────
  // accentColor is the one hardcoded value in the IDE too.
  var accentColor = '#d4759a';
  function makeEdTheme() {
    var isDark = document.documentElement.classList.contains('dark');
    return C.EditorView.theme({
      '&':                                              { backgroundColor: 'transparent', color: 'var(--text-1)' },
      '.cm-gutters':                                    { backgroundColor: 'transparent', color: 'var(--text-3)', border: 'none', minWidth: '38px' },
      '.cm-activeLine':                                 { backgroundColor: 'transparent' },
      '&.cm-focused .cm-activeLine':                    { backgroundColor: 'rgba(128,128,128,.04)' },
      '.cm-activeLineGutter':                           { backgroundColor: 'transparent', color: 'var(--text-3)' },
      '&.cm-focused .cm-activeLineGutter':              { backgroundColor: 'transparent', color: 'var(--text-2)' },
      '&.cm-focused .cm-cursor':                        { borderLeftColor: accentColor },
      '&.cm-focused .cm-selectionBackground, .cm-selectionBackground':
                                                        { backgroundColor: 'var(--selection-bg) !important' },
      '.cm-content':                                    { caretColor: accentColor, fontFamily: "'JetBrains Mono',monospace", fontSize: '13px', lineHeight: '1.65', padding: '8px 0' },
      '.cm-scroller':                                   { fontFamily: "'JetBrains Mono',monospace" },
      '.cm-matchingBracket':                            { fontWeight: 'bold', backgroundColor: 'var(--cm-matching-bracket-bg)' },
      '.cm-line':                                       { paddingLeft: '4px' },
    }, { dark: isDark });
  }

  function initCM() {
    var edTheme = makeEdTheme();
    // Published notebooks use the same selector class as the IDE
    // (`.cm-cell`) plus `.cm-cell-published` so the CSS can narrow
    // chrome rules. The init targets only the published variant so
    // it never collides with a co-hosted live IDE.
    document.querySelectorAll('.cm-cell-published').forEach(function (host) {
      if (host.querySelector('.cm-editor')) return;  // already initialized
      // Extension list mirrors the IDE's exts (Notebook.jl line 151),
      // minus the edit-oriented pieces (history, closeBrackets,
      // indentOnInput, keymap with run handlers) that can't fire in
      // read-only mode. Visual knobs stay identical.
      var exts = [
        C.lineNumbers(),
        C.highlightSpecialChars(),
        C.drawSelection(),
        C.EditorState.allowMultipleSelections.of(true),
        C.bracketMatching(),
        C.rectangularSelection(),
        C.highlightSelectionMatches(),
        C.EditorState.tabSize.of(4),
        C.julia(),
        C.syntaxHighlighting(hlTheme),
        edTheme,
        // Read-only clamps — the two flips that distinguish published
        // from the live IDE editor. Everything upstream is identical.
        C.EditorState.readOnly.of(true),
        C.EditorView.editable.of(false),
      ];
      new C.EditorView({
        state: C.EditorState.create({
          doc: host.dataset.src || '',
          extensions: exts,
        }),
        parent: host,
      });
    });
  }

  function reinitCM() {
    document.querySelectorAll('.cm-cell-published .cm-editor').forEach(function (ed) { ed.remove(); });
    initCM();
  }

  // Defer first run until DOM has `.cm-cell-published` hosts.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initCM);
  } else {
    initCM();
  }
  // SPA navigation — Therapy dispatches after client-side page swaps.
  window.addEventListener('therapy:router:loaded', initCM);
  // Theme switch — rebuild so the ed-theme's `dark:isDark` reflects.
  var lastDark = document.documentElement.classList.contains('dark');
  new MutationObserver(function () {
    var now = document.documentElement.classList.contains('dark');
    if (now !== lastDark) { lastDark = now; reinitCM(); }
  }).observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });
})();
