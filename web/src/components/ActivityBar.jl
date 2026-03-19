# ActivityBar.jl — @island: Vertical icon sidebar for panel toggles
#
# Reads sidebar/repl signals from context (provided by SessionsApp).
# Click toggles corresponding panel. Active icon highlighted with accent color.

@island function ActivityBar()
    sidebar_open, set_sidebar_open = use_context_signal(:sidebar, Int32(1))
    repl_open, set_repl_open = use_context_signal(:repl, Int32(0))

    Div(:class => "activity-bar",
        # File explorer toggle
        Therapy.Button(
            :class => "activity-bar-icon",
            :title => "Toggle Explorer",
            :on_click => () -> begin
                if sidebar_open() == Int32(1)
                    set_sidebar_open(Int32(0))
                else
                    set_sidebar_open(Int32(1))
                end
            end,
            # File tree icon (⊟)
            Svg(:class => "w-5 h-5", :fill => "none", :viewBox => "0 0 24 24",
                :stroke => "currentColor", :stroke_width => "1.5",
                Path(:stroke_linecap => "round", :stroke_linejoin => "round",
                    :d => "M2.25 12.75V12A2.25 2.25 0 014.5 9.75h15A2.25 2.25 0 0121.75 12v.75m-8.69-6.44l-2.12-2.12a1.5 1.5 0 00-1.061-.44H4.5A2.25 2.25 0 002.25 6v12a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9a2.25 2.25 0 00-2.25-2.25h-5.379a1.5 1.5 0 01-1.06-.44z"))),

        # Terminal toggle
        Therapy.Button(
            :class => "activity-bar-icon",
            :title => "Toggle REPL",
            :on_click => () -> begin
                if repl_open() == Int32(1)
                    set_repl_open(Int32(0))
                else
                    set_repl_open(Int32(1))
                end
            end,
            # Terminal icon (⊳)
            Svg(:class => "w-5 h-5", :fill => "none", :viewBox => "0 0 24 24",
                :stroke => "currentColor", :stroke_width => "1.5",
                Path(:stroke_linecap => "round", :stroke_linejoin => "round",
                    :d => "M6.75 7.5l3 2.25-3 2.25m4.5 0h3m-9 8.25h13.5A2.25 2.25 0 0021.75 18V6a2.25 2.25 0 00-2.25-2.25H4.5A2.25 2.25 0 002.25 6v12a2.25 2.25 0 002.25 2.25z"))))
end
