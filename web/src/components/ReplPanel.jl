# ReplPanel.jl — REPL panel (SSR)
#
# Returns the complete REPL island div with border, rounded-xl, and shadow.
# Sits at the same level as the notebook island inside the editor area.
# Uses the Sessions.jl color palette: deep/base/surf/island/hov + b1/b2 + t1-t4 + accent.

"""
    ReplPanel()

Render the complete REPL panel: header with mode buttons, scrollable history area,
and input line with julia> prompt and blinking cursor.
"""
function ReplPanel()
    state = if isdefined(Main, :WEB_STATE) && Main.WEB_STATE[] !== nothing
        Main.WEB_STATE[]
    else
        nothing
    end

    # Build REPL history lines from workspace if available
    history_items = Any[]
    # For now, show a welcome line
    push!(history_items,
        Div(:style => "color:#3d5068;",
            "# Press Enter to evaluate"))

    # Mode button style (shared)
    mode_btn_style = "background:rgba(255,255,255,.04);"

    Div(:id => "repl",
        :class => "flex flex-col overflow-hidden shrink-0",
        :style => "height:168px; background:#0a0e14; border:1px solid #1c2736; border-radius:0.75rem; box-shadow:0 10px 15px -3px rgba(0,0,0,.25);",

        # --- Header ---
        Div(:class => "flex items-center gap-2.5 shrink-0",
            :style => "padding:7px 14px; border-bottom:1px solid #1c2736;",

            # Julia REPL label with green dot
            Span(:class => "flex items-center gap-1.5",
                :style => "font-size:11px; font-weight:600; font-family:ui-monospace,monospace; color:#56d4a0;",
                Span(:style => "font-size:7px;", "\u25CF"),
                "Julia REPL"),

            # Version badge
            Span(:style => "font-size:10px; font-family:ui-monospace,monospace; color:#3d5068;",
                "v1.12"),

            # Spacer
            Div(:class => "flex-1"),

            # Mode buttons
            Div(:class => "flex gap-1",
                Button(:class => "rounded cursor-pointer",
                    :style => "border:0; padding:1px 7px; font-size:9px; font-family:ui-monospace,monospace; color:#3d5068; $(mode_btn_style)",
                    "shell"),
                Button(:class => "rounded cursor-pointer",
                    :style => "border:0; padding:1px 7px; font-size:9px; font-family:ui-monospace,monospace; color:#3d5068; $(mode_btn_style)",
                    "pkg"),
                Button(:class => "rounded cursor-pointer",
                    :style => "border:0; padding:1px 7px; font-size:9px; font-family:ui-monospace,monospace; color:#3d5068; $(mode_btn_style)",
                    "help"))),

        # --- History area ---
        Div(:class => "flex-1 overflow-y-auto",
            :id => "rpl-hist",
            :style => "padding:8px 14px; font-family:ui-monospace,monospace; font-size:12px; line-height:1.625;",
            history_items...),

        # --- Input line ---
        Div(:class => "flex items-center gap-1.5 shrink-0",
            :style => "padding:6px 14px 10px;",

            # julia> prompt
            Span(:style => "color:#56d4a0; font-family:ui-monospace,monospace; font-size:12px;",
                "julia>"),

            # Text input
            Input(:type => "text",
                :class => "flex-1",
                :style => "background:transparent; border:0; outline:none; color:#d4dce8; font-family:ui-monospace,monospace; font-size:12px; caret-color:#56d4a0;"),

            # Blinking cursor block
            Span(:class => "cblink",
                :style => "width:7px; height:15px; background:#56d4a0; opacity:0.7;")))
end
