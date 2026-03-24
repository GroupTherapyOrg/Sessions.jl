# Layout.jl - Sessions.jl documentation layout
#
# Uses local components (PageComponents.jl): ThemeToggle, Separator, SiteFooter.
# Mobile nav is pure JS. No Suite.jl dependency.

# --- Shared SVGs ---

const _GITHUB_SVG = Svg(:class => "h-5 w-5", :fill => "currentColor", :viewBox => "0 0 24 24",
    Path(:d => "M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"))

const _HAMBURGER_SVG = Svg(:class => "h-5 w-5", :fill => "none", :viewBox => "0 0 24 24",
    :stroke => "currentColor", :stroke_width => "2",
    Path(:stroke_linecap => "round", :stroke_linejoin => "round",
         :d => "M4 6h16M4 12h16M4 18h16"))

# --- Logo ---

function SessionsLogo()
    A(:href => "./", :class => "flex items-center",
        Span(:class => "text-2xl font-bold text-warm-800 dark:text-warm-300", "Sessions"),
        Span(:class => "text-2xl font-light",
            Span(:style => "color:#b08fd8;", "."),
            Span(:class => "text-accent-600 dark:text-accent-400", "j"),
            Span(:class => "text-accent-secondary-600 dark:text-accent-secondary-400", "l")))
end

# --- Desktop Nav ---

const _NAV_LINK_CLASS = "text-sm font-medium transition-colors"
const _NAV_LINK_ACTIVE = "text-accent-700 dark:text-accent-400 font-semibold"
const _NAV_LINK_INACTIVE = "text-warm-600 dark:text-warm-400 hover:text-accent-600 dark:hover:text-accent-400"

function DesktopNav()
    Nav(:class => "flex items-center gap-6",
        NavLink("./getting-started/", "Getting Started",
            class=_NAV_LINK_CLASS, active_class=_NAV_LINK_ACTIVE, inactive_class=_NAV_LINK_INACTIVE),
        NavLink("./notebooks/", "Notebooks",
            class=_NAV_LINK_CLASS, active_class=_NAV_LINK_ACTIVE, inactive_class=_NAV_LINK_INACTIVE))
end

# --- Mobile Nav (JS-based slide panel) ---

function MobileNav()
    Fragment(
        Button(:class => "cursor-pointer text-warm-600 dark:text-warm-400 hover:text-warm-800 dark:hover:text-warm-200",
            :aria_label => "Open menu", :type => "button",
            :onclick => "document.getElementById('mobile-menu').classList.remove('hidden')",
            _HAMBURGER_SVG),
        Div(:id => "mobile-menu", :class => "hidden fixed inset-0 z-50",
            Div(:class => "fixed inset-0 bg-black/50",
                :onclick => "document.getElementById('mobile-menu').classList.add('hidden')"),
            Div(:class => "fixed top-0 left-0 w-72 h-full bg-warm-50 dark:bg-warm-900 border-r border-warm-200 dark:border-warm-700 p-6 overflow-y-auto",
                Div(:class => "flex justify-between items-center mb-6",
                    Span(:class => "text-lg font-semibold text-warm-800 dark:text-warm-300", "Sessions.jl"),
                    Button(:class => "cursor-pointer text-warm-500 hover:text-warm-800 dark:hover:text-warm-200",
                        :onclick => "document.getElementById('mobile-menu').classList.add('hidden')",
                        :type => "button",
                        RawHtml("""<svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12"/></svg>"""))),
                Nav(:class => "flex flex-col gap-2",
                    _MobileLink("Home", "./"),
                    Div(:class => "mt-2",
                        Span(:class => "text-xs font-semibold text-warm-500 uppercase tracking-wider", "Docs")),
                    _MobileLink("Getting Started", "./getting-started/"),
                    _MobileLink("Notebooks", "./notebooks/"),
                    Separator(class="my-4"),
                    Div(:class => "flex items-center gap-4",
                        A(:href => "https://github.com/GroupTherapyOrg/Sessions.jl",
                          :class => "text-warm-600 hover:text-warm-800 dark:text-warm-400 dark:hover:text-warm-200 transition-colors",
                          :target => "_blank", _GITHUB_SVG),
                        ThemeToggle())))))
end

function _MobileLink(text, href)
    A(:href => href,
      :class => "text-sm text-warm-700 dark:text-warm-300 hover:text-accent-600 dark:hover:text-accent-400 py-1.5 px-2 rounded-md hover:bg-warm-100 dark:hover:bg-warm-800 transition-colors",
      text)
end

# --- Main Layout ---

const _SESSIONS_EDITOR_JS = let
    p = joinpath(dirname(dirname(dirname(@__DIR__))), "src", "web", "static", "editor.js")
    isfile(p) ? read(p, String) : "/* editor.js not found */"
end

function Layout(children...; title="Sessions.jl")
    Div(:class => "min-h-screen flex flex-col bg-warm-50 dark:bg-warm-950 transition-colors duration-200",
        # FOUC prevention — apply saved theme before paint (matches Therapy.jl key format)
        RawHtml("""<script>(function(){try{var bp=document.documentElement.getAttribute('data-base-path')||'';var sk=bp?'therapy-theme:'+bp:'therapy-theme';var t=localStorage.getItem(sk);if(t==='dark'||(!t&&window.matchMedia('(prefers-color-scheme: dark)').matches)){document.documentElement.classList.add('dark')}}catch(e){}})();</script>"""),
        # Plotly.js CDN
        RawHtml("""<script src="https://cdn.plot.ly/plotly-basic-2.35.2.min.js"></script>"""),
        # CodeMirror bundle + init (always loaded so SPA nav to notebooks works)
        RawHtml(string("<script>", _SESSIONS_EDITOR_JS, "</script>")),
        RawHtml("""<script>
(function() {
  if (typeof C === 'undefined' || !C.EditorView) return;
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
    ".cm-activeLineGutter":{backgroundColor:"transparent",color:"#3d5068"},
    ".cm-content":{fontFamily:"'JetBrains Mono',monospace",fontSize:"13px",lineHeight:"1.65",padding:"8px 0"},
    ".cm-scroller":{fontFamily:"'JetBrains Mono',monospace"},
    ".cm-line":{paddingLeft:"4px"},
    ".cm-cursor":{display:"none"},
  },{dark:true});
  function initSessionsCM() {
    document.querySelectorAll('.cm-cell').forEach(function(host) {
      if (host.querySelector('.cm-editor')) return;
      var src = host.dataset.src || '';
      new C.EditorView({
        state: C.EditorState.create({
          doc: src,
          extensions: [
            C.lineNumbers(), C.highlightSpecialChars(), C.drawSelection(),
            C.bracketMatching(), C.julia(), C.syntaxHighlighting(hlTheme),
            edTheme, C.EditorState.readOnly.of(true), C.EditorView.editable.of(false),
          ]
        }),
        parent: host
      });
    });
  }
  initSessionsCM();
  window.addEventListener('therapy:router:loaded', initSessionsCM);
})();
</script>"""),
        # Navigation bar
        Header(:class => "bg-warm-100 dark:bg-warm-900 border-b border-warm-200 dark:border-warm-700 transition-colors duration-200",
            Div(:class => "max-w-7xl mx-auto px-4 sm:px-6 lg:px-8",
                Div(:class => "flex items-center justify-between h-16",
                    Div(:class => "flex items-center", SessionsLogo()),
                    Div(:class => "hidden md:flex md:items-center md:gap-2",
                        DesktopNav(),
                        Div(:class => "flex items-center gap-2 ml-4",
                            A(:href => "https://github.com/GroupTherapyOrg/Sessions.jl",
                              :class => "text-warm-600 hover:text-warm-800 dark:text-warm-400 dark:hover:text-warm-200 transition-colors",
                              :target => "_blank", _GITHUB_SVG),
                            ThemeToggle())),
                    Div(:class => "flex items-center md:hidden", MobileNav())))),
        # Content
        MainEl(:id => "page-content", :class => "flex-1 w-full max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8",
            children...),
        # Footer
        Separator(),
        SiteFooter())
end
