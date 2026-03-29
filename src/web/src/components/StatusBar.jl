# StatusBar.jl — @island: theme toggle, connection status, cell count
#
# Destructures shared signal tuples from SharedSignals.jl.
# Follows DarkModeToggle pattern for proper signal compilation.

@island function StatusBar(; initial_cells::Int = 0)
    # Destructure shared signal tuples
    cc, set_cc = cellcount_signal
    cs, set_cs = connection_signal

    # on_mount: WS connection polling + notebook event listener
    # Uses __t.shared() directly since on_mount can't compile $1 substitution for setters
    on_mount(() -> js("""
        var cs = __t.shared('cs', 1);
        var cc = __t.shared('cc', 0);
        setInterval(function(){
            var ok = window.TherapyWS && TherapyWS._ws && TherapyWS._ws.readyState === 1;
            cs[1](ok ? 1 : 0);
        }, 2000);
        window.addEventListener('therapy:ws:open', function(){ cs[1](1); });
        window.addEventListener('therapy:ws:close', function(){ cs[1](0); });
        window.addEventListener('therapy:channel:notebook', function(e){
            var d = e.detail;
            if (!d) return;
            if (d.total_cells !== undefined) { cc[1](d.total_cells); }
            else if (d.event === 'cell_added' || d.event === 'cell_deleted') {
                setTimeout(function(){ cc[1](document.querySelectorAll('.cell-wrap').length); }, 50);
            } else if (d.event === 'nb_replaced' || d.event === 'full_state') {
                setTimeout(function(){ cc[1](document.querySelectorAll('.cell-wrap').length); }, 200);
            }
        });
    """))

    return Div(:id => "status-bar",
        :style => "height:28px;flex-shrink:0;display:flex;align-items:center;padding:0 16px;gap:16px;font-size:10px;font-family:'JetBrains Mono',monospace;color:var(--text-3);background:var(--workspace-bg);box-shadow:0 -2px 8px rgba(0,0,0,.06);",

        # Rose dot
        Span(:style => "color:var(--accent);", "\u25CF"),
        Span("Sessions.jl"),
        Span("\u00B7"),

        # Cell count (reactive)
        Span(cc, " cells"),

        # Spacer
        Span(:style => "flex:1;"),

        # Connection indicator (reactive)
        Span(:style => "color:var(--status-done);", "\u25CF connected"),

        # Theme toggle
        Button(:id => "theme-toggle-btn",
            :style => "padding:2px 10px;border-radius:9999px;border:1px solid var(--accent);background:var(--accent-dim);color:var(--accent);font-size:10px;font-family:'JetBrains Mono',monospace;cursor:pointer;transition:all .15s;",
            :on_click => () -> js("var h=document.documentElement;var d=h.classList.contains('dark');if(d){h.classList.remove('dark','sl-theme-dark');h.classList.add('sl-theme-light');localStorage.setItem('sessions-theme','light');}else{h.classList.add('dark','sl-theme-dark');h.classList.remove('sl-theme-light');localStorage.setItem('sessions-theme','dark');}"),
            :title => "Toggle light/dark mode",
            "\u25D0 Toggle")
    )
end
