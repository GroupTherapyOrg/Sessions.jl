# ReplPanel.jl — REPL panel content (placeholder)
#
# Matches the TUI REPL aesthetic: dark terminal area with julia> prompt.

function ReplPanel()
    Div(:style => "flex: 1; padding: 12px 16px; font-family: 'JuliaMono', 'Fira Code', monospace; font-size: 13px; overflow-y: auto;",
        # Tab bar
        Div(:style => "display: flex; align-items: center; gap: 12px; margin-bottom: 12px; padding-bottom: 8px; border-bottom: 1px solid #2b2d30;",
            Span(:style => "display: flex; align-items: center; gap: 6px; color: #bcbec4; font-size: 12px;",
                Span(:style => "color: #389826;", "⊳"),
                "Julia 1",
                Span(:style => "color: #4e5157; cursor: pointer; margin-left: 4px;", "×")),
            Span(:style => "color: #4e5157; cursor: pointer; font-size: 14px;", "+")),
        # Prompt
        Div(:style => "display: flex; align-items: center; gap: 4px;",
            Span(:style => "color: #389826; font-weight: 600;", "julia>"),
            Span(:style => "color: #4e5157; animation: pulse 1.5s infinite;", "▊")))
end
