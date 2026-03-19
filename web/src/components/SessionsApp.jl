# SessionsApp.jl — @island: Top-level three-panel IDE layout
#
# Matches the TUI aesthetic: dark activity bar | file explorer | notebook | REPL.
# Uses inline styles for reliability (no dependency on Tailwind custom tokens).

@island function SessionsApp(children...)
    sidebar_open, set_sidebar_open = create_signal(Int32(1))
    repl_open, set_repl_open = create_signal(Int32(0))

    provide_context(:sidebar, (sidebar_open, set_sidebar_open))
    provide_context(:repl, (repl_open, set_repl_open))

    # Three-panel IDE layout
    Div(:style => "display: flex; height: 100%; overflow: hidden;",
        # Activity bar (narrow icon strip, always visible)
        ActivityBar(),

        # Sidebar panel (collapsible file explorer)
        Show(sidebar_open) do
            Div(:style => "width: 240px; flex-shrink: 0; overflow-y: auto; background: #161619; border-right: 1px solid #2b2d30; display: flex; flex-direction: column;",
                # Header
                Div(:style => "padding: 8px 12px; font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; color: #7a7e85; border-bottom: 1px solid #2b2d30;",
                    "Explorer"),
                # Content
                FileExplorer())
        end,

        # Main area (notebook + bottom panel)
        Div(:style => "flex: 1; display: flex; flex-direction: column; min-width: 0; overflow: hidden;",
            # Notebook (takes remaining space)
            Div(:style => "flex: 1; overflow-y: auto; overflow-x: hidden;",
                children...),

            # REPL panel (collapsible)
            Show(repl_open) do
                Div(:style => "height: 200px; flex-shrink: 0; background: #0e0e12; border-top: 1px solid #2b2d30; display: flex; flex-direction: column;",
                    # Header
                    Div(:style => "display: flex; align-items: center; justify-content: space-between; padding: 4px 12px; font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; color: #7a7e85; border-bottom: 1px solid #2b2d30;",
                        Span("REPL"),
                        Therapy.Button(:style => "background: none; border: none; color: #4e5157; cursor: pointer; font-size: 14px; padding: 2px 6px;",
                            :on_click => () -> set_repl_open(Int32(0)),
                            "×")),
                    ReplPanel())
            end))
end
