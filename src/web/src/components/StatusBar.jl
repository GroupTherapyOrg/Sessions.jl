# StatusBar.jl — @island: theme toggle, connection status, cell count
#
# Destructures shared signal tuples from SharedSignals.jl.
# Theme toggle follows DarkModeToggle pattern exactly:
# local signal + handler captures it + js() for DOM/localStorage.

@island function StatusBar(; initial_cells::Int = 0)
    # Destructure shared signal tuples
    cc, set_cc = cellcount_signal
    cs, set_cs = connection_signal

    # Local signal for theme state (DarkModeToggle pattern)
    is_dark, set_dark = create_signal(0)

    # Sync theme signal with actual DOM state on hydration
    js("if(document.documentElement.classList.contains('dark'))\$1(1)", set_dark)

    # on_mount: WS connection polling + notebook event listener
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
        :style => "height:28px;flex-shrink:0;display:flex;align-items:center;padding:0 16px;gap:16px;font-size:10px;font-family:'JetBrains Mono',monospace;color:var(--text-3);background:var(--workspace-bg);box-shadow:var(--statusbar-shadow);border-top:1px solid var(--divider);",

        Span(:style => "color:var(--accent);", "\u25CF"),
        Span("Sessions.jl"),
        Span("\u00B7"),
        Span(cc, " cells"),
        Span(:style => "flex:1;"),
        Span(:style => "color:var(--status-done);", "\u25CF connected"),

        # Theme toggle — captures is_dark/set_dark so handler compiles
        Button(:id => "theme-toggle-btn",
            :style => "padding:2px 10px;border-radius:9999px;border:1px solid var(--accent);background:var(--accent-dim);color:var(--accent);font-size:10px;font-family:'JetBrains Mono',monospace;cursor:pointer;transition:all .15s;",
            :on_click => () -> begin
                set_dark(1 - is_dark())
                js("localStorage.setItem('sessions-theme',document.documentElement.classList.contains('dark')?'light':'dark')")
                js("window.location.reload()")
            end,
            :title => "Toggle light/dark mode",
            "\u25D0 Toggle")
    )
end
