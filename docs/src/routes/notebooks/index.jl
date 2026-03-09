# Notebooks — Sessions.jl
#
# Placeholder page for future wasm-exported notebook viewer.

function NotebooksIndex()
    Fragment(
        PageHeader("Notebooks", "Interactive notebook gallery — export and share your Sessions.jl notebooks on the web."),

        Div(:class => "max-w-2xl mx-auto py-12",
            # Coming Soon card
            Main.Card(class="bg-warm-100/50 dark:bg-warm-900/50",
                Main.CardHeader(
                    Div(:class => "flex items-center gap-3",
                        Div(:class => "w-10 h-10 bg-accent-100 dark:bg-accent-900/30 rounded-lg flex items-center justify-center",
                            Svg(:class => "w-5 h-5 text-accent-600 dark:text-accent-400", :fill => "none", :viewBox => "0 0 24 24", :stroke => "currentColor", :stroke_width => "1.5",
                                Path(:stroke_linecap => "round", :stroke_linejoin => "round",
                                     :d => "M12 6.042A8.967 8.967 0 006 3.75c-1.052 0-2.062.18-3 .512v14.25A8.987 8.987 0 016 18c2.305 0 4.408.867 6 2.292m0-14.25a8.966 8.966 0 016-2.292c1.052 0 2.062.18 3 .512v14.25A8.987 8.987 0 0018 18a8.967 8.967 0 00-6 2.292m0-14.25v14.25")
                            )
                        ),
                        Main.CardTitle("Coming Soon"),
                    ),
                ),
                Main.CardContent(
                    P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                        "Sessions.jl notebooks will be exportable to interactive web pages. Write your notebook in the terminal, then share it as a static site with live widgets powered by WebAssembly."
                    ),
                    P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                        "The notebook export pipeline will compile your @bind widgets to Wasm, render cell outputs to HTML, and produce a self-contained page that anyone can view in a browser."
                    ),
                    # Future vision bullets
                    Div(:class => "mt-6 space-y-3",
                        _VisionItem("Export notebooks to static HTML + Wasm"),
                        _VisionItem("Interactive @bind widgets in the browser"),
                        _VisionItem("Shareable notebook gallery"),
                        _VisionItem("Embeddable notebook snippets"),
                    ),
                ),
            ),
        )
    )
end

function _VisionItem(text)
    Div(:class => "flex items-center gap-3",
        Div(:class => "w-1.5 h-1.5 rounded-full bg-accent-500"),
        Span(:class => "text-sm text-warm-600 dark:text-warm-400", text),
    )
end

NotebooksIndex
