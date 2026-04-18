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

function Layout(content)
    Div(:class => "min-h-screen flex flex-col bg-warm-100 dark:bg-warm-950 text-warm-800 dark:text-warm-200 transition-colors",
        # Theme init (prevent FOUC)
        RawHtml("""<script>(function(){try{var bp=document.documentElement.getAttribute('data-base-path')||'';var sk=bp?'therapy-theme:'+bp:'therapy-theme';var t=localStorage.getItem(sk);if(t==='dark'||(!t&&window.matchMedia('(prefers-color-scheme: dark)').matches)){document.documentElement.classList.add('dark')}}catch(e){}})();</script>"""),
        # NOTE: CodeMirror bundle + notebook CSS + read-only init are
        # now bundled into `Sessions.render_published_notebook` itself
        # (see Sessions.jl/static/notebook-*.{css,js}). Any extracted
        # notebook component carries its own styling + CM renderer, so
        # the Layout doesn't need to pre-wire them. Pages that don't
        # render a notebook incur zero cost.
        # Nav — sticky at the top of the viewport so the sidebars
        # have a fixed anchor they can slot beneath. Matches the
        # canonical docs layout (Astro Starlight / Vercel /
        # Supabase): top nav always visible, sidebars scroll
        # independently. `backdrop-blur` + translucent bg so content
        # scrolling behind stays faintly visible. `z-40` keeps it
        # above the sidebars' sticky content.
        Nav(:class => "sticky top-0 z-40 border-b border-warm-200 dark:border-warm-800 px-6 py-4 bg-warm-100/80 dark:bg-warm-950/80 backdrop-blur supports-[backdrop-filter]:bg-warm-100/60 supports-[backdrop-filter]:dark:bg-warm-950/60",
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
        # Main content. No max-width constraint at this level —
        # most pages want centered narrow content (hero / gallery /
        # getting-started: ~max-w-5xl) but notebook pages run a
        # three-column layout (sidebar + notebook + TOC) that needs
        # the full viewport. Each page wraps its own content with
        # the appropriate max-width.
        MainEl(:id => "page-content", :class => "flex-1 w-full",
            content
        ),
        # Footer — kept deliberately slim so it doesn't dominate
        # scroll at the bottom of a long notebook. `py-3` + smaller
        # text hits roughly the same height as a sidebar row. Not
        # sticky on purpose — docs sites almost never stick the
        # footer (would compete with the TOC rail) — so it just
        # slides in at the end of the document flow.
        Footer(:class => "border-t border-warm-200 dark:border-warm-800 px-6 py-3",
            Div(:class => "max-w-5xl mx-auto flex items-center justify-between text-xs text-warm-500 dark:text-warm-500",
                A(:href => "https://github.com/GroupTherapyOrg", :target => "_blank",
                    :class => "hover:text-warm-700 dark:hover:text-warm-300 transition-colors no-underline",
                    "GroupTherapyOrg"
                ),
                Div(:class => "flex items-center gap-1.5",
                    A(:href => "https://github.com/GroupTherapyOrg/Sessions.jl", :target => "_blank",
                        :class => "hover:text-warm-600 dark:hover:text-warm-300 transition-colors no-underline", "Sessions.jl"),
                    Span("·"),
                    A(:href => "https://github.com/GroupTherapyOrg/Therapy.jl", :target => "_blank",
                        :class => "hover:text-warm-600 dark:hover:text-warm-300 transition-colors no-underline", "Therapy.jl"),
                    Span("·"),
                    A(:href => "https://github.com/GroupTherapyOrg/JavaScriptTarget.jl", :target => "_blank",
                        :class => "hover:text-warm-600 dark:hover:text-warm-300 transition-colors no-underline", "JavaScriptTarget.jl")
                ),
                Span("Built with ",
                    RawHtml("""<span class="font-serif">Therapy<span style="color:var(--jl-dot)">.</span><span style="color:var(--jl-j)">j</span><span style="color:var(--jl-l)">l</span></span>""")
                )
            )
        )
    )
end

# Notebook CodeMirror init used to live here, but it now travels with
# each published notebook (bundled into `Sessions.render_published_notebook`),
# so the docs layout no longer needs to pre-wire it.
