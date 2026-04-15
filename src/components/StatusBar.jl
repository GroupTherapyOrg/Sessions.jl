# StatusBar.jl — @island: theme toggle, connection status, cell count
#
# Destructures shared signal tuples from SharedSignals.jl.

@island function StatusBar(; initial_cells::Int = 0)
    cc, set_cc = cellcount_signal
    cs, set_cs = connection_signal

    is_dark, set_dark = create_signal(Int32(0))

    js("if(document.documentElement.classList.contains('dark'))\$1(1)", set_dark)

    on_mount(() -> begin
        js("""
            window.addEventListener('therapy:ws:open',function(){\$1(1)});
            window.addEventListener('therapy:ws:close',function(){\$1(0)});
        """, set_cs)
        js("""
            var cells=document.querySelectorAll('.cell-wrap[data-cell-id]');
            \$1(cells.length);
        """, set_cc)
    end)

    create_effect(() -> begin
        v = cs()
        js("var d=document.getElementById('ws-dot');if(d){d.style.color=\$1?'var(--status-done)':'var(--status-error)';d.nextElementSibling.textContent=\$1?' connected':' disconnected'}", v)
    end)

    create_effect(() -> begin
        v = cc()
        js("var el=document.getElementById('cell-count');if(el)el.textContent=\$1+' cells'", v)
    end)

    return Div(:id => "status-bar",
        :style => "height:28px;flex-shrink:0;display:flex;align-items:center;padding:0 16px;gap:16px;font-size:10px;font-family:'JetBrains Mono',monospace;color:var(--text-3);background:var(--workspace-bg);box-shadow:var(--statusbar-shadow);border-top:1px solid var(--divider);",

        Span(:style => "color:var(--accent);", "\u25CF"),
        Span("Sessions.jl"),
        Span(:id => "cell-count", :style => "color:var(--text-3);", string(initial_cells, " cells")),
        Span(:style => "flex:1;"),
        Span(:id => "ws-dot", :style => "color:var(--status-done);", "\u25CF"),
        Span(" connected"),

        Button(:id => "theme-toggle-btn",
            :style => "padding:2px 10px;border-radius:9999px;border:1px solid var(--accent);background:var(--accent-dim);color:var(--accent);font-size:10px;font-family:'JetBrains Mono',monospace;cursor:pointer;transition:all .15s;",
            :on_click => () -> begin
                set_dark(Int32(1) - is_dark())
                js("document.documentElement.classList.toggle('dark')")
                js("localStorage.setItem('sessions-theme',document.documentElement.classList.contains('dark')?'dark':'light')")
                js("if(window._sessionsThemeSwitch)_sessionsThemeSwitch()")
            end,
            :title => "Toggle light/dark mode",
            "\u25D0 Toggle")
    )
end
