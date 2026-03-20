# CellIsland.jl — @island: Full cell component with WASM signals
#
# Each notebook cell is a CellIsland instance with:
#   - is_open signal: fold/unfold code visibility (eye toggle)
#
# The cell body (CM editor, controls, output) is passed as children
# from the static CellView function. The island owns the reactive state.
#
# This is the SolidJS-style approach: one component, signals drive UI.

@island function CellIsland(children...; initial_open=1)
    is_open, set_is_open = create_signal(Int32(initial_open))

    Div(:class => "cell-island",
        # Eye toggle — stacked open/closed icons, WASM click handler
        Div(:class => "cell-eye",
            :on_click => () -> begin
                if is_open() == Int32(1)
                    set_is_open(Int32(0))
                else
                    set_is_open(Int32(1))
                end
            end,
            Div(:style => "position:relative;width:14px;height:14px;",
                # Closed eye (always in DOM)
                RawHtml("""<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19M1 1l22 22"/></svg>"""),
                # Open eye (layered on top, hidden when folded)
                Show(is_open) do
                    Div(:style => "position:absolute;inset:0;background:#151c25;",
                        RawHtml("""<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>"""))
                end)),

        # Code cell — shown/hidden by is_open signal
        Show(is_open) do
            children
        end)
end
