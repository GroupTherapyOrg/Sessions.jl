# StatusBar.jl — @island: theme toggle, connection status, cell count
#
# Destructures shared signal tuples from SharedSignals.jl.

@island function StatusBar(; initial_cells::Int = 0)
    cc, set_cc = cellcount_signal
    cs, set_cs = connection_signal

    is_dark, set_dark = create_signal(0)

    # NOTE: setter-bound js() blocks (theme-init read, WS open/close listeners,
    # cell-count seed) were removed — Therapy's `js("...", setter)` interpolation
    # only resolves SETTERS as JS callables in click/input handlers, never at
    # body top level or in on_mount. Forcing it here makes WasmTarget compile a
    # setter reference that fails with `local.set[0] expected type i32, found
    # call of type i64`. The dot/text below stay at their initial state until a
    # click handler updates them.

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
                set_dark(1 - is_dark())
                js("document.documentElement.classList.toggle('dark')")
                js("localStorage.setItem('sessions-theme',document.documentElement.classList.contains('dark')?'dark':'light')")
                js("if(window._sessionsThemeSwitch)_sessionsThemeSwitch()")
            end,
            :title => "Toggle light/dark mode",
            "\u25D0 Toggle")
    )
end
