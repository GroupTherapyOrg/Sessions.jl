# Layout.jl — Sessions.jl documentation layout
#
# Matches Therapy.jl docs structure exactly: nav, content, footer.
# Rose accent instead of green. Same warm neutrals.

"""Sessions.jl wordmark with colored .jl suffix"""
function SessionsWordmark()
    NavLink("./",
        RawHtml("""Sessions<span style="color:var(--jl-dot)">.</span><span style="color:var(--jl-j)">j</span><span style="color:var(--jl-l)">l</span>""");
        class = "text-xl font-serif font-bold text-warm-900 dark:text-warm-100 hover:opacity-80 transition-opacity no-underline",
        active_class = ""
    )
end

# CodeMirror bundle for notebook rendering.
# Path walks up from docs/src/components/ → docs/src/ → docs/ → Sessions.jl/
# and then into static/. Fixed from a stale src/web/static/ path that
# pre-dates the rebuild PRD's directory restructure.
const _SESSIONS_EDITOR_JS = let
    p = joinpath(dirname(dirname(dirname(@__DIR__))), "static", "editor.js")
    isfile(p) ? read(p, String) : "/* editor.js not found */"
end

function Layout(content)
    Div(:class => "min-h-screen flex flex-col bg-warm-100 dark:bg-warm-950 text-warm-800 dark:text-warm-200 transition-colors",
        # Theme init (prevent FOUC)
        RawHtml("""<script>(function(){try{var bp=document.documentElement.getAttribute('data-base-path')||'';var sk=bp?'therapy-theme:'+bp:'therapy-theme';var t=localStorage.getItem(sk);if(t==='dark'||(!t&&window.matchMedia('(prefers-color-scheme: dark)').matches)){document.documentElement.classList.add('dark')}}catch(e){}})();</script>"""),
        # Plotly CDN
        RawHtml("""<script src="https://cdn.plot.ly/plotly-basic-2.35.2.min.js"></script>"""),
        # CodeMirror bundle + init
        RawHtml(string("<script>", _SESSIONS_EDITOR_JS, "</script>")),
        _cm_init_script(),
        # Nav
        Nav(:class => "border-b border-warm-200 dark:border-warm-800 px-6 py-4",
            Div(:class => "max-w-5xl mx-auto flex items-center justify-between",
                SessionsWordmark(),
                Div(:class => "flex items-center gap-6",
                    NavLink("./getting-started/", "Getting Started";
                        class = "text-sm transition-colors no-underline",
                        active_class = "text-accent-600 dark:text-accent-400 font-medium",
                        inactive_class = "text-warm-600 dark:text-warm-400 hover:text-accent-600 dark:hover:text-accent-400"
                    ),
                    NavLink("./notebooks/", "Notebooks";
                        class = "text-sm transition-colors no-underline",
                        active_class = "text-accent-600 dark:text-accent-400 font-medium",
                        inactive_class = "text-warm-600 dark:text-warm-400 hover:text-accent-600 dark:hover:text-accent-400"
                    ),
                    A(:href => "https://github.com/GroupTherapyOrg/Sessions.jl", :target => "_blank",
                        :class => "text-warm-600 dark:text-warm-400 hover:text-warm-700 dark:hover:text-warm-300 transition-colors",
                        RawHtml("""<svg class="w-5 h-5" viewBox="0 0 24 24" fill="currentColor"><path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/></svg>""")
                    ),
                    DarkModeToggle()
                )
            )
        ),
        # Main content
        MainEl(:id => "page-content", :class => "flex-1 w-full max-w-5xl mx-auto px-6 py-12",
            content
        ),
        # Footer
        Footer(:class => "border-t border-warm-200 dark:border-warm-800 px-6 py-6",
            Div(:class => "max-w-5xl mx-auto flex items-center justify-between",
                A(:href => "https://github.com/GroupTherapyOrg", :target => "_blank",
                    :class => "text-sm text-warm-600 dark:text-warm-400 hover:text-warm-700 dark:hover:text-warm-300 transition-colors no-underline",
                    "GroupTherapyOrg"
                ),
                Div(:class => "flex items-center gap-2 text-sm text-warm-500 dark:text-warm-500",
                    A(:href => "https://github.com/GroupTherapyOrg/Sessions.jl", :target => "_blank",
                        :class => "hover:text-warm-600 dark:hover:text-warm-300 transition-colors no-underline", "Sessions.jl"),
                    Span("/"),
                    A(:href => "https://github.com/GroupTherapyOrg/Therapy.jl", :target => "_blank",
                        :class => "hover:text-warm-600 dark:hover:text-warm-300 transition-colors no-underline", "Therapy.jl"),
                    Span("/"),
                    A(:href => "https://github.com/GroupTherapyOrg/JavaScriptTarget.jl", :target => "_blank",
                        :class => "hover:text-warm-600 dark:hover:text-warm-300 transition-colors no-underline", "JavaScriptTarget.jl")
                ),
                P(:class => "text-sm text-warm-500 dark:text-warm-500",
                    "Built with ",
                    RawHtml("""<span class="font-serif">Therapy<span style="color:var(--jl-dot)">.</span><span style="color:var(--jl-j)">j</span><span style="color:var(--jl-l)">l</span></span>""")
                )
            )
        )
    )
end

# CodeMirror initialization for notebook cells in docs
function _cm_init_script()
    RawHtml("""<script>
(function() {
  if (typeof C === 'undefined' || !C.EditorView) return;
  function isDark() { return document.documentElement.classList.contains('dark'); }

  var darkHL = C.HighlightStyle.define([
    {tag:C.t.keyword,color:"#e06b65"},{tag:C.t.controlKeyword,color:"#e06b65"},
    {tag:C.t.operatorKeyword,color:"#e06b65"},{tag:C.t.definitionKeyword,color:"#e06b65"},
    {tag:C.t.moduleKeyword,color:"#e06b65"},
    {tag:C.t.string,color:"#56d4a0"},{tag:C.t.character,color:"#56d4a0"},
    {tag:C.t.comment,color:"#4a6178",fontStyle:"italic"},
    {tag:C.t.number,color:"#d4a056"},{tag:C.t.integer,color:"#d4a056"},
    {tag:C.t.float,color:"#d4a056"},{tag:C.t.bool,color:"#d4a056"},
    {tag:C.t.function(C.t.variableName),color:"#7bb8e8"},
    {tag:C.t.definition(C.t.variableName),color:"#7bb8e8"},
    {tag:C.t.typeName,color:"#b08fd8"},{tag:C.t.className,color:"#b08fd8"},
    {tag:C.t.variableName,color:"#d4dce8"},
    {tag:C.t.punctuation,color:"#6b7d93"},
    {tag:C.t.operator,color:"#d4dce8"},{tag:C.t.macroName,color:"#d4a056"},
  ]);

  var lightHL = C.HighlightStyle.define([
    {tag:C.t.keyword,color:"#c4352b"},{tag:C.t.controlKeyword,color:"#c4352b"},
    {tag:C.t.operatorKeyword,color:"#c4352b"},{tag:C.t.definitionKeyword,color:"#c4352b"},
    {tag:C.t.moduleKeyword,color:"#c4352b"},
    {tag:C.t.string,color:"#1e7855"},{tag:C.t.character,color:"#1e7855"},
    {tag:C.t.comment,color:"#7b8a9e",fontStyle:"italic"},
    {tag:C.t.number,color:"#b5831b"},{tag:C.t.integer,color:"#b5831b"},
    {tag:C.t.float,color:"#b5831b"},{tag:C.t.bool,color:"#b5831b"},
    {tag:C.t.function(C.t.variableName),color:"#2b6cb0"},
    {tag:C.t.definition(C.t.variableName),color:"#2b6cb0"},
    {tag:C.t.typeName,color:"#7c3aed"},{tag:C.t.className,color:"#7c3aed"},
    {tag:C.t.variableName,color:"#1a2332"},
    {tag:C.t.punctuation,color:"#7b8a9e"},
    {tag:C.t.operator,color:"#1a2332"},{tag:C.t.macroName,color:"#b5831b"},
  ]);

  var darkTheme = C.EditorView.theme({
    "&":{backgroundColor:"transparent",color:"#d4dce8"},
    ".cm-gutters":{backgroundColor:"transparent",color:"#3d5068",border:"none",minWidth:"38px"},
    ".cm-activeLine":{backgroundColor:"transparent"},
    ".cm-content":{fontFamily:"'JetBrains Mono',monospace",fontSize:"13px",lineHeight:"1.65",padding:"8px 0"},
    ".cm-scroller":{fontFamily:"'JetBrains Mono',monospace"},
    ".cm-cursor":{display:"none"},
  },{dark:true});

  var lightTheme = C.EditorView.theme({
    "&":{backgroundColor:"transparent",color:"#1a2332"},
    ".cm-gutters":{backgroundColor:"transparent",color:"#b0bac8",border:"none",minWidth:"38px"},
    ".cm-activeLine":{backgroundColor:"transparent"},
    ".cm-content":{fontFamily:"'JetBrains Mono',monospace",fontSize:"13px",lineHeight:"1.65",padding:"8px 0"},
    ".cm-scroller":{fontFamily:"'JetBrains Mono',monospace"},
    ".cm-cursor":{display:"none"},
  },{dark:false});

  function initCM() {
    var dark = isDark();
    document.querySelectorAll('.cm-cell').forEach(function(host) {
      if (host.querySelector('.cm-editor')) return;
      new C.EditorView({
        state: C.EditorState.create({
          doc: host.dataset.src || '',
          extensions: [
            C.lineNumbers(), C.highlightSpecialChars(), C.drawSelection(),
            C.bracketMatching(), C.julia(),
            C.syntaxHighlighting(dark ? darkHL : lightHL),
            dark ? darkTheme : lightTheme,
            C.EditorState.readOnly.of(true), C.EditorView.editable.of(false),
          ]
        }),
        parent: host
      });
    });
  }

  function reinitCM() {
    document.querySelectorAll('.cm-cell .cm-editor').forEach(function(ed) { ed.remove(); });
    initCM();
  }

  // This <script> is inlined in <body> BEFORE the cell DOM, so `.cm-cell`
  // hosts don't exist yet when we fire. Defer until the parser has walked
  // past them. `therapy:router:loaded` covers SPA navigation afterward.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initCM);
  } else {
    initCM();
  }
  window.addEventListener('therapy:router:loaded', initCM);
  var _lastDark = isDark();
  new MutationObserver(function() {
    var now = isDark();
    if (now !== _lastDark) { _lastDark = now; reinitCM(); }
  }).observe(document.documentElement, {attributes:true, attributeFilter:['class']});
})();
</script>""")
end
