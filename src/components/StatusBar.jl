# StatusBar.jl — footer strip: WS connection dot, cell count, theme toggle
#
# THERAPY PATTERN: shared-signal islands have NO kwargs (kwargs collide
# with shared signal slots in the prop-init loop). Cell count comes from
# the cellcount_signal which the WS bridge updates on full_state +
# cell_added / cell_deleted events.
#
# THERAPY COMPILER LIMITATION: js() args MUST be DIRECT signal-getter
# results — branching goes INSIDE the JS string.

@island function StatusBar()
    cellcount, _  = cellcount_signal
    connection, _ = connection_signal
    is_dark, set_dark = create_signal(0)

    # ── Effect: cell-count text ──
    create_effect(() -> begin
        n = cellcount()
        js("""
            var el=island.querySelector('[data-cell-count]');
            if(el)el.textContent=String(\$1)+' cells';
        """, n)
    end)

    # ── Effect: WS connection dot color + label ──
    create_effect(() -> begin
        c = connection()
        js("""
            var d=island.querySelector('[data-ws-dot]');
            if(d)d.style.color=\$1?'var(--status-done)':'var(--status-error)';
            var l=island.querySelector('[data-ws-label]');
            if(l)l.textContent=\$1?' connected':' disconnected';
        """, c)
    end)

    return Div(:id => "status-bar",
        :style => "height:28px;flex-shrink:0;display:flex;align-items:center;padding:0 16px;gap:16px;font-size:10px;font-family:'JetBrains Mono',monospace;color:var(--text-3);background:var(--workspace-bg);box-shadow:var(--statusbar-shadow);border-top:1px solid var(--divider);",

        Span(:style => "color:var(--accent);", "\u25CF"),
        Span("Sessions.jl"),
        Span(:id => "cell-count",
            Symbol("data-cell-count") => "1",
            :style => "color:var(--text-3);",
            "0 cells"),
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
