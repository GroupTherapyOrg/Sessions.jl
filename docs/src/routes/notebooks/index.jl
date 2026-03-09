# Notebooks Gallery — Sessions.jl
#
# Dynamic listing of executed notebooks with sidebar layout.

function NotebooksIndex()
    cards = []
    if isdefined(Main, :EXECUTED_NOTEBOOKS) && !isempty(Main.EXECUTED_NOTEBOOKS)
        for slug in _ordered_notebook_slugs(keys(Main.EXECUTED_NOTEBOOKS))
            nb = Main.EXECUTED_NOTEBOOKS[slug]
            title = _extract_notebook_title(nb)
            code_count = _count_code_cells(nb)
            prose_count = _count_prose_sections(nb)
            is_interactive = slug in _INTERACTIVE_SLUGS

            card_content = Main.Card(
                class = is_interactive ? "opacity-50 cursor-default" : "transition-colors hover:border-accent-400 dark:hover:border-accent-600",
                Main.CardHeader(
                    Main.CardTitle(title),
                    Main.CardDescription("$(code_count) code cells, $(prose_count) prose sections"),
                ),
                Main.CardContent(
                    Div(:class => "flex gap-2",
                        Main.Badge(variant="outline", "Julia"),
                        Main.Badge(variant="outline", "$(length(nb)) cells"),
                        is_interactive ? Main.Badge(variant="outline", "Coming soon") : nothing,
                    ),
                ),
            )

            if is_interactive
                push!(cards, Div(:class => "block", card_content))
            else
                push!(cards, A(:href => "./notebooks/$(slug)/", :class => "block group", card_content))
            end
        end
    end

    NotebooksLayout(
        PageHeader("Notebooks", "Interactive notebook gallery — export and share your Sessions.jl notebooks on the web."),

        if !isempty(cards)
            Div(:class => "grid gap-6 sm:grid-cols-2",
                cards...
            )
        else
            Div(:class => "py-12",
                Main.Card(class="bg-warm-100/50 dark:bg-warm-900/50",
                    Main.CardHeader(
                        Main.CardTitle("No Notebooks Yet"),
                    ),
                    Main.CardContent(
                        P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed",
                            "Add .jl notebooks to the docs/notebooks/ directory and rebuild to see them here."
                        ),
                    ),
                ),
            )
        end
    )
end

NotebooksIndex
