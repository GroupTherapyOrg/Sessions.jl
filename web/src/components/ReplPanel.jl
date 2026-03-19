# ReplPanel.jl — REPL panel content (placeholder for Phase 1)
#
# Shows a static placeholder for the REPL area.
# Server-backed terminal (PTY integration) comes in Phase 7.

function ReplPanel()
    Div(:class => "p-4 font-mono text-sm",
        Div(:class => "flex items-center gap-2 text-warm-500 dark:text-warm-400",
            Span(:class => "text-accent-500", "julia>"),
            Span(:class => "text-warm-400 dark:text-warm-600 animate-pulse", "▊")),
        Div(:class => "mt-3 text-xs text-warm-400 dark:text-warm-600",
            "REPL panel — server-backed terminal coming in a future phase."))
end
