# FileExplorer.jl — File tree panel (placeholder for Phase 1)
#
# Shows notebook filename and a static placeholder.
# Server-populated file listing comes in Phase 7.

function FileExplorer()
    nb_name = if isdefined(Main, :WEB_STATE) && Main.WEB_STATE[] !== nothing
        basename(Main.WEB_STATE[].nb.path)
    else
        "Untitled.jl"
    end

    Div(:class => "p-3",
        # Current notebook
        Div(:class => "mb-4",
            Div(:class => "flex items-center gap-2 px-2 py-1.5 rounded-md bg-warm-100 dark:bg-warm-900",
                Svg(:class => "w-4 h-4 text-accent-500 shrink-0", :fill => "none", :viewBox => "0 0 24 24",
                    :stroke => "currentColor", :stroke_width => "1.5",
                    Path(:stroke_linecap => "round", :stroke_linejoin => "round",
                        :d => "M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z")),
                Span(:class => "text-sm text-warm-700 dark:text-warm-300 truncate", nb_name))),

        # Placeholder tree
        Div(:class => "mt-2 space-y-1",
            Span(:class => "text-xs text-warm-400 dark:text-warm-600 px-2", "No file browser yet")))
end
