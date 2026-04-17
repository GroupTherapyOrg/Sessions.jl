# StatusBar.jl — footer strip: WS connection dot, cell count, theme toggle
#
# Same pattern as CellView / NotebookToolbar — the dynamic parts are
# driven by `create_effect(() -> ... js("...", value))`. Logic in
# Julia inside the effect, single js() write per concern.

@island function StatusBar(; initial_cells::Int = 0)
    cellcount, _  = cellcount_signal
    connection, _ = connection_signal
    is_dark, set_dark = create_signal(0)

    # ── Effect: cell-count text ──
    create_effect(() -> begin
        n = cellcount()
        txt = string(n, " cells")
        js("var el=island.querySelector('[data-cell-count]');if(el)el.textContent=\$1;", txt)
    end)

    # ── Effect: WS connection dot color + label ──
    create_effect(() -> begin
        c = connection()
        dot_color = c == 1 ? "color:var(--status-done);" : "color:var(--status-error);"
        label = c == 1 ? " connected" : " disconnected"
        js("""
            var d=island.querySelector('[data-ws-dot]');
            if(d)d.style.cssText=\$1;
            var l=island.querySelector('[data-ws-label]');
            if(l)l.textContent=\$2;
        """, dot_color, label)
    end)

    return Div(:id => "status-bar",
        :style => "height:28px;flex-shrink:0;display:flex;align-items:center;padding:0 16px;gap:16px;font-size:10px;font-family:'JetBrains Mono',monospace;color:var(--text-3);background:var(--workspace-bg);box-shadow:var(--statusbar-shadow);border-top:1px solid var(--divider);",

        Span(:style => "color:var(--accent);", "\u25CF"),
        Span("Sessions.jl"),
        Span(:id => "cell-count",
            Symbol("data-cell-count") => "1",
            :style => "color:var(--text-3);",
            string(initial_cells, " cells")),
        Span(:style => "flex:1;"),
        Span(:id => "ws-dot",
            Symbol("data-ws-dot") => "1",
            :style => "color:var(--status-done);",
            "\u25CF"),
        Span(Symbol("data-ws-label") => "1", " connected"),

        Button(:id => "theme-toggle-btn",
            :style => "padding:2px 10px;border-radius:9999px;border:1px solid var(--accent);background:var(--accent-dim);color:var(--accent);font-size:10px;font-family:'JetBrains Mono',monospace;cursor:pointer;transition:all .15s;",
            :on_click => () -> begin
                set_dark(1 - is_dark())
                # Browser-API plumbing — has to be js().
                js("document.documentElement.classList.toggle('dark')")
                js("localStorage.setItem('sessions-theme',document.documentElement.classList.contains('dark')?'dark':'light')")
                js("if(window._sessionsThemeSwitch)_sessionsThemeSwitch()")
            end,
            :title => "Toggle light/dark mode",
            "\u25D0 Toggle")
    )
end
