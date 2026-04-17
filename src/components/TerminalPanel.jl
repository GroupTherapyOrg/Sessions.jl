# TerminalPanel.jl — @island wrapper for the REPL/terminal panel
#
# Mirror of SidebarPanel — owns the terminal's visibility from
# `terminal_open_signal`. See SidebarPanel.jl for the rationale on
# effect-driven display:none vs Show() and the no-kwargs constraint.

@island function TerminalPanel(children...)
    terminal_open, _ = terminal_open_signal

    create_effect(() -> begin
        v = terminal_open()
        js("""
            var el=island.querySelector('[data-panel-root]');
            if(el)el.style.display=\$1?'':'none';
        """, v)
    end)

    Div(:id => "repl-panel",
        Symbol("data-panel-root") => "1",
        :style => "display:none;flex-shrink:0;",
        children...)
end
