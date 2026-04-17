// Sessions.jl published-notebook bootstrap — read-only port of the
// live IDE's CodeMirror setup (Sessions.jl/src/components/Notebook.jl
// lines 66–122). Every visual knob is copied verbatim so published
// notebooks match the IDE's editor 1-to-1; only the editable flag
// flips.
//
// Bundled into render_published_notebook output so any Therapy app
// that drops in a Sessions-extracted .jl notebook gets working
// read-only CodeMirror editors + dark-mode re-theming for free.
//
// This script is re-executed by Therapy's ClientRouter after every
// SPA content swap (it passes the `__therapy` marker check in
// ClientRouter.jl:162–170). On re-execution the `__SESSIONS_NB_BOOT`
// guard prevents double setup of the theme + observer, but the
// `__sessionsInitPublishedCM()` call ALWAYS fires so any freshly
// inserted .cm-cell-published host gets a CodeMirror editor.

(function () {
  if (typeof C === 'undefined' || !C.EditorView) return;

  // ── One-time setup (theme defs + global init fn + observers) ────
  if (!window.__SESSIONS_NB_BOOT) {
    window.__SESSIONS_NB_BOOT = true;

    // Syntax highlight — 1-to-1 port of Notebook.jl hlTheme. All
    // colors reference CSS custom properties the notebook-chrome.css
    // bundle defines for both :root and .dark, so light/dark is
    // purely a class flip on <html>.
    var hlTheme = C.HighlightStyle.define([
      { tag: C.t.keyword,             color: 'var(--cm-keyword)' },
      { tag: C.t.controlKeyword,      color: 'var(--cm-keyword)' },
      { tag: C.t.operatorKeyword,     color: 'var(--cm-keyword)' },
      { tag: C.t.definitionKeyword,   color: 'var(--cm-keyword)' },
      { tag: C.t.moduleKeyword,       color: 'var(--cm-keyword)' },
      { tag: C.t.definitionOperator,  color: 'var(--cm-keyword)' },
      { tag: C.t.logicOperator,       color: 'var(--cm-keyword)' },
      { tag: C.t.controlOperator,     color: 'var(--cm-keyword)' },
      { tag: C.t.string,              color: 'var(--cm-string)'  },
      { tag: C.t.special(C.t.string), color: 'var(--cm-command)' },
      { tag: C.t.comment,             color: 'var(--cm-comment)', fontStyle: 'italic' },
      { tag: C.t.lineComment,         color: 'var(--cm-comment)', fontStyle: 'italic' },
      { tag: C.t.blockComment,        color: 'var(--cm-comment)', fontStyle: 'italic' },
      { tag: C.t.number,    color: 'var(--cm-literal)' },
      { tag: C.t.integer,   color: 'var(--cm-literal)' },
      { tag: C.t.float,     color: 'var(--cm-literal)' },
      { tag: C.t.bool,      color: 'var(--cm-literal)' },
      { tag: C.t.character, color: 'var(--cm-literal)' },
      { tag: C.t.literal,   color: 'var(--cm-literal)' },
      { tag: C.t.escape,    color: 'var(--cm-literal)' },
      { tag: C.t.variableName,                 color: 'var(--cm-variable)' },
      { tag: C.t.function(C.t.variableName),   color: 'var(--cm-function)' },
      { tag: C.t.definition(C.t.variableName), color: 'var(--cm-function)' },
      { tag: C.t.typeName,  color: 'var(--cm-variable)', opacity: '0.8' },
      { tag: C.t.className, color: 'var(--cm-variable)', opacity: '0.8' },
      { tag: C.t.atom,         color: 'var(--cm-symbol)' },
      { tag: C.t.propertyName, color: 'var(--cm-symbol)' },
      { tag: C.t.macroName, color: 'var(--cm-macro)', fontWeight: 'bold' },
      { tag: C.t.paren,         color: 'var(--cm-bracket)' },
      { tag: C.t.squareBracket, color: 'var(--cm-bracket)' },
      { tag: C.t.brace,         color: 'var(--cm-bracket)' },
      { tag: C.t.punctuation,   color: 'var(--cm-bracket)' },
      { tag: C.t.operator,           color: 'var(--cm-editor-text)' },
      { tag: C.t.arithmeticOperator, color: 'var(--cm-editor-text)' },
      { tag: C.t.compareOperator,    color: 'var(--cm-editor-text)' },
    ]);

    // Editor theme — 1-to-1 port of Notebook.jl _makeEdTheme.
    var accentColor = '#d4759a';
    function makeEdTheme() {
      var isDark = document.documentElement.classList.contains('dark');
      return C.EditorView.theme({
        '&':                                 { backgroundColor: 'transparent', color: 'var(--text-1)' },
        '.cm-gutters':                       { backgroundColor: 'transparent', color: 'var(--text-3)', border: 'none', minWidth: '38px' },
        '.cm-activeLine':                    { backgroundColor: 'transparent' },
        '&.cm-focused .cm-activeLine':       { backgroundColor: 'rgba(128,128,128,.04)' },
        '.cm-activeLineGutter':              { backgroundColor: 'transparent', color: 'var(--text-3)' },
        '&.cm-focused .cm-activeLineGutter': { backgroundColor: 'transparent', color: 'var(--text-2)' },
        '&.cm-focused .cm-cursor':           { borderLeftColor: accentColor },
        '&.cm-focused .cm-selectionBackground, .cm-selectionBackground': { backgroundColor: 'var(--selection-bg) !important' },
        '.cm-content':                       { caretColor: accentColor, fontFamily: "'JetBrains Mono',monospace", fontSize: '13px', lineHeight: '1.65', padding: '8px 0' },
        '.cm-scroller':                      { fontFamily: "'JetBrains Mono',monospace" },
        '.cm-matchingBracket':               { fontWeight: 'bold', backgroundColor: 'var(--cm-matching-bracket-bg)' },
        '.cm-line':                          { paddingLeft: '4px' },
      }, { dark: isDark });
    }

    // Exposed on window so every script re-execution reuses the
    // same function rather than re-defining it. Runs synchronously
    // if DOM is ready, otherwise on DOMContentLoaded — either way
    // it's a no-op for already-initialized hosts.
    window.__sessionsInitPublishedCM = function () {
      var edTheme = makeEdTheme();
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
        C.EditorState.readOnly.of(true),
        C.EditorView.editable.of(false),
      ];
      document.querySelectorAll('.cm-cell-published').forEach(function (host) {
        if (host.querySelector('.cm-editor')) return;
        new C.EditorView({
          state: C.EditorState.create({
            doc: host.dataset.src || '',
            extensions: exts,
          }),
          parent: host,
        });
      });
    };

    // Dark-mode toggle — rebuild every editor so the new theme applies.
    var lastDark = document.documentElement.classList.contains('dark');
    new MutationObserver(function () {
      var now = document.documentElement.classList.contains('dark');
      if (now !== lastDark) {
        lastDark = now;
        document.querySelectorAll('.cm-cell-published .cm-editor').forEach(function (ed) { ed.remove(); });
        window.__sessionsInitPublishedCM();
      }
    }).observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });
  }

  // ── Always-run: init editors on any .cm-cell-published hosts now
  // in the DOM. Runs on fresh page load and on every Therapy router
  // re-execution after a client-side page swap. Idempotent — skips
  // hosts that already have a .cm-editor child.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', window.__sessionsInitPublishedCM);
  } else {
    window.__sessionsInitPublishedCM();
  }
})();
