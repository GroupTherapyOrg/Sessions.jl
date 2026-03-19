# SessionsApp.jl — @island: Top-level three-panel layout with shared signals
#
# Creates reactive signals for panel visibility (sidebar, REPL).
# Child @island components (ActivityBar) consume these via context.
# Show() blocks handle panel show/hide reactively in WASM.

@island function SessionsApp(children...)
    # Panel visibility signals (Int32: 0=closed, 1=open)
    sidebar_open, set_sidebar_open = create_signal(Int32(1))
    repl_open, set_repl_open = create_signal(Int32(0))

    # Share signals with child islands via context
    provide_context(:sidebar, (sidebar_open, set_sidebar_open))
    provide_context(:repl, (repl_open, set_repl_open))

    # Full-screen flex layout
    Div(:class => "flex h-full",
        # Left: Activity bar (always visible)
        ActivityBar(),

        # Left: Sidebar panel (collapsible)
        Show(sidebar_open) do
            Div(:class => "sidebar-panel panel-transition",
                Div(:class => "sidebar-header",
                    Span("Explorer")),
                FileExplorer())
        end,

        # Center + Bottom: Main area
        Div(:class => "flex-1 flex flex-col min-w-0",
            # Center: Notebook area (always visible, takes remaining space)
            Div(:class => "flex-1 overflow-y-auto",
                children...),

            # Bottom: REPL panel (collapsible)
            Show(repl_open) do
                Div(:class => "bottom-panel panel-transition",
                    Div(:class => "bottom-panel-header",
                        Span("REPL"),
                        Therapy.Button(:class => "text-warm-400 hover:text-warm-600 dark:hover:text-warm-300 cursor-pointer text-xs",
                            :on_click => () -> set_repl_open(Int32(0)),
                            "×")),
                    ReplPanel())
            end))
end
