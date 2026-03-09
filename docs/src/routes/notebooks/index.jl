# Notebooks Gallery — Sessions.jl
#
# Dynamic listing of executed notebooks from Main.EXECUTED_NOTEBOOKS.

function NotebooksIndex()
    # Build notebook cards from executed notebooks
    cards = []
    if isdefined(Main, :EXECUTED_NOTEBOOKS) && !isempty(Main.EXECUTED_NOTEBOOKS)
        for slug in sort(collect(keys(Main.EXECUTED_NOTEBOOKS)))
            nb = Main.EXECUTED_NOTEBOOKS[slug]
            title = _extract_notebook_title(nb)
            code_count = _count_code_cells(nb)
            prose_count = _count_prose_sections(nb)

            push!(cards,
                A(:href => "./notebooks/$(slug)/", :class => "block group",
                    Main.Card(class="transition-colors hover:border-accent-400 dark:hover:border-accent-600",
                        Main.CardHeader(
                            Main.CardTitle(title),
                            Main.CardDescription("$(code_count) code cells, $(prose_count) prose sections"),
                        ),
                        Main.CardContent(
                            Div(:class => "flex gap-2",
                                Main.Badge(variant="outline", "Julia"),
                                Main.Badge(variant="outline", "$(length(nb)) cells"),
                            ),
                        ),
                    )
                )
            )
        end
    end

    Fragment(
        PageHeader("Notebooks", "Interactive notebook gallery — export and share your Sessions.jl notebooks on the web."),

        if !isempty(cards)
            Div(:class => "max-w-4xl mx-auto py-8 grid gap-6 sm:grid-cols-2",
                cards...
            )
        else
            Div(:class => "max-w-2xl mx-auto py-12",
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
