# StatusBar.jl — @island: theme toggle, connection status, cell count
#
# Reads shared signals: cell_count, connection_status
# Handles: theme toggle (dark/light via localStorage + classList)
# Updates: connection indicator via WS polling

@island function StatusBar(; initial_cells::Int = 0)
    # Capture shared signals (compile to __t.shared())
    cc = cell_count
    cs = connection_status

    # on_mount: WS connection polling + notebook event listener
    on_mount(() -> begin
        # Poll WS connection status every 2 seconds
        js("""
            setInterval(function(){
                var ok = window.TherapyWS && TherapyWS._ws && TherapyWS._ws.readyState === 1;
                __t.shared('connection_status', 1)[1](ok ? 1 : 0);
            }, 2000);
            window.addEventListener('therapy:ws:open', function(){
                __t.shared('connection_status', 1)[1](1);
            });
            window.addEventListener('therapy:ws:close', function(){
                __t.shared('connection_status', 1)[1](0);
            });
        """)

        # Listen for notebook events that update cell count
        js("""
            window.addEventListener('therapy:channel:notebook', function(e){
                var d = e.detail;
                if (!d) return;
                if (d.total_cells !== undefined) {
                    __t.shared('cell_count', 0)[1](d.total_cells);
                } else if (d.event === 'cell_added' || d.event === 'cell_deleted') {
                    setTimeout(function(){
                        var n = document.querySelectorAll('.cell-wrap').length;
                        __t.shared('cell_count', 0)[1](n);
                    }, 50);
                } else if (d.event === 'nb_replaced' || d.event === 'full_state') {
                    setTimeout(function(){
                        var n = document.querySelectorAll('.cell-wrap').length;
                        __t.shared('cell_count', 0)[1](n);
                    }, 200);
                }
            });
        """)
    end)

    return Div(:id => "status-bar",
        :style => "height:28px;flex-shrink:0;display:flex;align-items:center;padding:0 16px;gap:16px;font-size:10px;font-family:'JetBrains Mono',monospace;color:var(--text-3);background:var(--workspace-bg);box-shadow:0 -2px 8px rgba(0,0,0,.06);",

        # Rose dot
        Span(:style => "color:var(--accent);", "\u25CF"),

        # App name
        Span("Sessions.jl"),

        Span("\u00B7"),

        # Cell count (reactive via shared signal)
        Span(cell_count, " cells"),

        # Spacer
        Span(:style => "flex:1;"),

        # Connection indicator (reactive)
        Span(:id => "status-connection",
            :style => "color:var(--status-done);",
            "\u25CF connected"),

        # Theme toggle (rose accent)
        Button(:id => "theme-toggle-btn",
            :style => "padding:2px 10px;border-radius:9999px;border:1px solid var(--accent);background:var(--accent-dim);color:var(--accent);font-size:10px;font-family:'JetBrains Mono',monospace;cursor:pointer;transition:all .15s;",
            :on_click => () -> begin
                js("var h=document.documentElement;var d=h.classList.contains('dark');if(d){h.classList.remove('dark','sl-theme-dark');h.classList.add('sl-theme-light');localStorage.setItem('sessions-theme','light');}else{h.classList.add('dark','sl-theme-dark');h.classList.remove('sl-theme-light');localStorage.setItem('sessions-theme','dark');}")
            end,
            :title => "Toggle light/dark mode",
            "\u25D0 Toggle")
    )
end
