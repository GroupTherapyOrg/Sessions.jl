# Layout.jl - Sessions.jl documentation layout
#
# Uses Suite.jl components: Sheet (mobile), SiteFooter, Separator, ThemeToggle.
# Uses Sessions.jl green accent and blue-gray neutrals.

# --- Shared SVGs ---

const _GITHUB_SVG = Svg(:class => "h-5 w-5", :fill => "currentColor", :viewBox => "0 0 24 24",
    Path(:d => "M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z")
)

const _HAMBURGER_SVG = Svg(:class => "h-5 w-5", :fill => "none", :viewBox => "0 0 24 24",
    :stroke => "currentColor", :stroke_width => "2",
    Path(:stroke_linecap => "round", :stroke_linejoin => "round",
         :d => "M4 6h16M4 12h16M4 18h16")
)

# --- Logo ---

function SessionsLogo()
    A(:href => "./", :class => "flex items-center",
        Span(:class => "text-2xl font-bold text-warm-800 dark:text-warm-300", "Sessions"),
        Span(:class => "text-2xl font-light",
            Span(:style => "color: var(--jl-dot)", "."),
            Span(:style => "color: var(--jl-j)", "j"),
            Span(:style => "color: var(--jl-l)", "l")
        )
    )
end

# --- Desktop Nav (flat links) ---

const _NAV_LINK_CLASS = "text-sm font-medium transition-colors"
const _NAV_LINK_ACTIVE = "text-accent-700 dark:text-accent-400 font-semibold"
const _NAV_LINK_INACTIVE = "text-warm-600 dark:text-warm-400 hover:text-accent-600 dark:hover:text-accent-400"

function DesktopNav()
    Nav(:class => "flex items-center gap-6",
        NavLink("./getting-started/", "Getting Started",
            class=_NAV_LINK_CLASS, active_class=_NAV_LINK_ACTIVE, inactive_class=_NAV_LINK_INACTIVE),
        NavLink("./notebooks/", "Notebooks",
            class=_NAV_LINK_CLASS, active_class=_NAV_LINK_ACTIVE, inactive_class=_NAV_LINK_INACTIVE),
    )
end

# --- Mobile Sheet ---

function MobileNav()
    Main.Sheet(
        Main.SheetTrigger(
            :class => "text-warm-600 dark:text-warm-400 hover:text-warm-800 dark:hover:text-warm-200",
            :aria_label => "Open menu",
            _HAMBURGER_SVG
        ),
        Main.SheetContent(side="left",
            Main.SheetHeader(
                Main.SheetTitle("Sessions.jl"),
                Main.SheetDescription("Navigation"),
            ),
            Nav(:class => "flex flex-col gap-2 mt-4",
                _MobileLink("Home", "./"),
                Div(:class => "mt-2",
                    Span(:class => "text-xs font-semibold text-warm-500 dark:text-warm-500 uppercase tracking-wider", "Docs"),
                ),
                _MobileLink("Getting Started", "./getting-started/"),
                _MobileLink("Notebooks", "./notebooks/"),
                # Separator + utilities
                Main.Separator(class="my-4"),
                Div(:class => "flex items-center gap-4",
                    A(:href => "https://github.com/GroupTherapyOrg/Sessions.jl",
                      :class => "text-warm-600 hover:text-warm-800 dark:text-warm-400 dark:hover:text-warm-200 transition-colors",
                      :target => "_blank",
                      _GITHUB_SVG
                    ),
                    Main.ThemeToggle(),
                ),
            ),
        ),
    )
end

function _MobileLink(text, href)
    A(:href => href,
      :class => "text-sm text-warm-700 dark:text-warm-300 hover:text-accent-600 dark:hover:text-accent-400 py-1.5 px-2 rounded-md hover:bg-warm-100 dark:hover:bg-warm-800 transition-colors",
      text)
end

# --- Main Layout ---

function Layout(children...; title="Sessions.jl")
    Div(:class => "min-h-screen flex flex-col bg-warm-50 dark:bg-warm-950 transition-colors duration-200",
        # Plotly.js CDN (interactive plots)
        RawHtml("""<script src="https://cdn.plot.ly/plotly-basic-2.35.2.min.js"></script>"""),
        # Navigation bar
        Header(:class => "bg-warm-100 dark:bg-warm-900 border-b border-warm-200 dark:border-warm-700 transition-colors duration-200",
            Div(:class => "max-w-7xl mx-auto px-4 sm:px-6 lg:px-8",
                Div(:class => "flex items-center justify-between h-16",
                    # Logo
                    Div(:class => "flex items-center",
                        SessionsLogo(),
                    ),

                    # Desktop: Nav + utilities
                    Div(:class => "hidden md:flex md:items-center md:gap-2",
                        DesktopNav(),
                        # GitHub + Theme toggle
                        Div(:class => "flex items-center gap-2 ml-4",
                            A(:href => "https://github.com/GroupTherapyOrg/Sessions.jl",
                              :class => "text-warm-600 hover:text-warm-800 dark:text-warm-400 dark:hover:text-warm-200 transition-colors h-9 w-9 inline-flex items-center justify-center",
                              :target => "_blank",
                              _GITHUB_SVG
                            ),
                            Main.ThemeToggle(),
                        ),
                    ),

                    # Mobile: Hamburger Sheet
                    Div(:class => "flex items-center md:hidden",
                        MobileNav(),
                    ),
                )
            )
        ),

        # Main Content
        MainEl(:id => "page-content", :class => "flex-1 w-full max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8",
            children...
        ),

        # Footer separator
        Main.Separator(),

        # Footer
        Main.SiteFooter(
            Main.FooterBrand(
                Span(:class => "text-sm font-medium text-warm-800 dark:text-warm-300", "GroupTherapyOrg"),
            ),
            Main.FooterLinks(
                Main.FooterLink("Therapy.jl", href="https://github.com/GroupTherapyOrg/Therapy.jl"),
                Main.FooterLink("Suite.jl", href="https://github.com/GroupTherapyOrg/Suite.jl"),
                Main.FooterLink("Sessions.jl", href="https://github.com/GroupTherapyOrg/Sessions.jl"),
            ),
            Main.FooterTagline("Built with Therapy.jl — A reactive web framework for Julia"),
        ),

        # Toast notification container
        Main.Toaster()
    )
end
