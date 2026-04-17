# Notebooks Gallery — Sessions.jl
#
# Lists every notebook the docs site has auto-discovered from
# docs/notebooks/extracted/. Each card links to /notebooks/<slug>/.
# Discovery + route registration is set up in docs/app.jl; this page
# only renders the directory.

function NotebooksIndex()
    extracted = _extracted_notebooks()
    slugs = _ordered_notebook_slugs(keys(extracted))

    cards = map(slugs) do slug
        title = _notebook_display_title(slug)
        A(:href => "./notebooks/$(slug)/",
          :class => "block group",
          Card(class = "transition-colors hover:border-accent-400 dark:hover:border-accent-600",
              CardHeader(
                  CardTitle(title),
                  CardDescription("Auto-extracted Therapy component")),
              CardContent(
                  Div(:class => "flex gap-2",
                      Badge(variant="outline", "Julia"),
                      Badge(variant="outline", "Extracted")))))
    end

    NotebooksLayout(
        PageHeader(
            "Notebooks",
            "Sessions notebooks extracted into Therapy components — drop the .jl into any Therapy project to host them anywhere."),
        if !isempty(cards)
            Div(:class => "grid gap-6 sm:grid-cols-2", cards...)
        else
            Div(:class => "py-12",
                Card(class = "bg-warm-100/50 dark:bg-warm-900/50",
                    CardHeader(CardTitle("No Notebooks Yet")),
                    CardContent(
                        P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed",
                            "Extract a notebook from the Sessions IDE (or run ",
                            Code(:class => "text-accent-500", "Sessions.extract_notebook"),
                            ") to ", Code(:class => "text-accent-500", "docs/notebooks/extracted/"),
                            " and rebuild this site to see it here."))))
        end
    )
end

NotebooksIndex
