# ActivityBar.jl — @island: Vertical icon sidebar for panel toggles
#
# Narrow dark strip with icons matching the TUI: file explorer, terminal, diagnostics.
# Uses inline styles for reliability.

# Shared icon button style
const _ICON_BTN = "display: flex; align-items: center; justify-content: center; width: 40px; height: 40px; border-radius: 6px; border: none; background: none; cursor: pointer; transition: background 0.15s;"

@island function ActivityBar()
    sidebar_open, set_sidebar_open = use_context_signal(:sidebar, Int32(1))
    repl_open, set_repl_open = use_context_signal(:repl, Int32(0))

    Div(:style => "display: flex; flex-direction: column; align-items: center; gap: 4px; padding: 8px 0; width: 48px; flex-shrink: 0; background: #181a1d; border-right: 1px solid #2b2d30;",
        # File explorer toggle
        Therapy.Button(
            :style => _ICON_BTN * " color: #9a9ea5;",
            :title => "Toggle Explorer (Ctrl+B)",
            :on_click => () -> begin
                if sidebar_open() == Int32(1)
                    set_sidebar_open(Int32(0))
                else
                    set_sidebar_open(Int32(1))
                end
            end,
            # File icon (⊟)
            RawHtml("""<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M2.25 12.75V12A2.25 2.25 0 014.5 9.75h15A2.25 2.25 0 0121.75 12v.75m-8.69-6.44l-2.12-2.12a1.5 1.5 0 00-1.061-.44H4.5A2.25 2.25 0 002.25 6v12a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9a2.25 2.25 0 00-2.25-2.25h-5.379a1.5 1.5 0 01-1.06-.44z"/></svg>""")),

        # Terminal toggle
        Therapy.Button(
            :style => _ICON_BTN * " color: #9a9ea5;",
            :title => "Toggle REPL (Ctrl+`)",
            :on_click => () -> begin
                if repl_open() == Int32(1)
                    set_repl_open(Int32(0))
                else
                    set_repl_open(Int32(1))
                end
            end,
            # Terminal icon (⊳)
            RawHtml("""<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M6.75 7.5l3 2.25-3 2.25m4.5 0h3m-9 8.25h13.5A2.25 2.25 0 0021.75 18V6a2.25 2.25 0 00-2.25-2.25H4.5A2.25 2.25 0 002.25 6v12a2.25 2.25 0 002.25 2.25z"/></svg>""")),

        # Diagnostics icon (static for now)
        Div(:style => _ICON_BTN * " color: #4e5157;",
            :title => "Diagnostics (coming soon)",
            RawHtml("""<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z"/></svg>""")))
end
