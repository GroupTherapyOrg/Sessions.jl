# PageComponents.jl - Shared page helpers for Sessions.jl docs

"""
Render a page header with title and description.
"""
function PageHeader(title::String, description::String)
    Div(:class => "py-8 border-b border-warm-200 dark:border-warm-700 mb-10",
        H1(:class => "text-4xl font-serif font-semibold text-warm-800 dark:text-warm-300 mb-3", title),
        P(:class => "text-lg text-warm-600 dark:text-warm-300", description)
    )
end

"""
Render a section H2 heading.
"""
function SectionH2(text::String)
    H2(:class => "text-2xl font-serif font-semibold text-warm-800 dark:text-warm-300 mb-4", text)
end

"""
Render a section H3 heading.
"""
function SectionH3(text::String)
    H3(:class => "text-xl font-serif font-semibold text-warm-800 dark:text-warm-300 mb-3", text)
end

"""
Render a keyboard interactions table with title.
"""
function KeyboardTable(title::String, rows...)
    Div(:class => "mt-8 space-y-4",
        SectionH3(title),
        Div(:class => "overflow-x-auto",
            Main.Table(
                Main.TableHeader(Main.TableRow(
                    Main.TableHead("Key"),
                    Main.TableHead("Action"),
                )),
                Main.TableBody(rows...)
            )
        )
    )
end

"""
Render a keyboard shortcut row with Kbd component.
"""
function KeyRow(key, action)
    Main.TableRow(
        Main.TableCell(Main.Kbd(key)),
        Main.TableCell(action),
    )
end

# =============================================================================
# Notebooks Layout — sidebar + content (mirrors Suite.jl ComponentsLayout)
# =============================================================================

# Notebooks that contain interactive plots (sliders + CairoMakie/Plotly)
# are disabled for now — shown but not clickable.
const _INTERACTIVE_SLUGS = Set(["interactive-plots", "cairomakie-plots"])

# Preferred display order — unlisted slugs go at the end alphabetically
const _NOTEBOOK_ORDER = ["hello-sessions", "data-exploration", "interactive-plots", "cairomakie-plots"]

"""Order notebook slugs: preferred order first, then alphabetical remainder."""
function _ordered_notebook_slugs(slugs)
    ordered = String[]
    for s in _NOTEBOOK_ORDER
        s in slugs && push!(ordered, s)
    end
    for s in sort(collect(slugs))
        s in ordered || push!(ordered, s)
    end
    ordered
end

"""Sidebar for notebooks section — lists all executed notebooks."""
function NotebooksSidebar()
    items = if isdefined(Main, :EXECUTED_NOTEBOOKS) && !isempty(Main.EXECUTED_NOTEBOOKS)
        _ordered_notebook_slugs(keys(Main.EXECUTED_NOTEBOOKS))
    else
        String[]
    end

    Nav(:class => "py-4 px-2",
        H4(:class => "px-3 mb-2 text-xs font-semibold tracking-wider uppercase text-warm-600 dark:text-warm-400",
            "Notebooks"
        ),
        Div(:class => "space-y-0.5 mb-2",
            # Overview link
            NavLink("./notebooks/", "Overview";
                class = "block px-3 py-1.5 text-sm rounded transition-colors",
                active_class = "text-accent-700 dark:text-accent-400 bg-warm-100 dark:bg-warm-900 border-l-2 border-accent-600 -ml-0.5 pl-[calc(0.75rem+2px)]",
                inactive_class = "text-warm-600 dark:text-warm-400 hover:text-warm-800 dark:hover:text-white hover:bg-warm-50 dark:hover:bg-warm-900",
                exact = true
            ),
            # Each notebook — interactive ones are disabled (not clickable)
            map(items) do slug
                nb = Main.EXECUTED_NOTEBOOKS[slug]
                title = _extract_notebook_title(nb)
                is_interactive = slug in _INTERACTIVE_SLUGS
                if is_interactive
                    Span(:class => "block px-3 py-1.5 text-sm rounded text-warm-400 dark:text-warm-600 cursor-default",
                        title
                    )
                else
                    NavLink("./notebooks/$(slug)/", title;
                        class = "block px-3 py-1.5 text-sm rounded transition-colors",
                        active_class = "text-accent-700 dark:text-accent-400 bg-warm-100 dark:bg-warm-900 border-l-2 border-accent-600 -ml-0.5 pl-[calc(0.75rem+2px)]",
                        inactive_class = "text-warm-600 dark:text-warm-400 hover:text-warm-800 dark:hover:text-white hover:bg-warm-50 dark:hover:bg-warm-900",
                        exact = true
                    )
                end
            end...
        )
    )
end

"""Layout wrapper for notebook pages with sidebar."""
function NotebooksLayout(children...)
    Div(:class => "lg:grid lg:grid-cols-[16rem_minmax(0,1fr)] min-h-[calc(100vh-8rem)]",
        # Sidebar
        Aside(:class => "hidden lg:block shrink-0 border-r border-warm-200 dark:border-warm-700 bg-warm-100/50 dark:bg-warm-900/50 overflow-y-auto",
            :style => "position: sticky; top: 0; height: calc(100vh - 4rem);",
            NotebooksSidebar()
        ),
        # Main content area
        Div(:class => "w-full min-w-0 px-4 sm:px-6 lg:px-8 py-8 max-w-4xl",
            children...
        )
    )
end
