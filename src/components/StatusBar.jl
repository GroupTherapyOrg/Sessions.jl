# StatusBar.jl — footer strip: WS connection dot, cell count, theme toggle
#
# Fully signal-driven: `cellcount` and `connection` come from
# SharedSignals.jl via window.__therapy.set (see Notebook.jl WS
# bridge); `is_dark` is a local click-flip signal. No imperative DOM
# mutation — all dynamic text / color comes from Therapy reactive
# bindings (:style => ..., text-node callback, :class => ...).
#
# The js() calls left in the click handler are BROWSER-API plumbing
# only (document.documentElement.classList toggle, localStorage,
# CodeMirror editor rebuild). None of them mutate UI state — all
# visible state flows through signals.

@island function StatusBar(; initial_cells::Int = 0)
    # Destructure shared signals. Closure-field names (bare) become
    # the cross-island signal names the WS bridge writes with
    # window.__therapy.set('cellcount', N).
    cellcount, _  = cellcount_signal
    connection, _ = connection_signal

    is_dark, set_dark = create_signal(0)

    return Div(:id => "status-bar",
        :style => "height:28px;flex-shrink:0;display:flex;align-items:center;padding:0 16px;gap:16px;font-size:10px;font-family:'JetBrains Mono',monospace;color:var(--text-3);background:var(--workspace-bg);box-shadow:var(--statusbar-shadow);border-top:1px solid var(--divider);",

        Span(:style => "color:var(--accent);", "\u25CF"),
        Span("Sessions.jl"),
        # Cell count: reactive text node — rebuilds when cellcount() changes.
        Span(:id => "cell-count", :style => "color:var(--text-3);",
            () -> string(cellcount(), " cells")),
        Span(:style => "flex:1;"),
        # WS status dot: color driven by connection signal.
        # 1 = connected (green), 0 = disconnected (red).
        Span(:id => "ws-dot",
            :style => () -> connection() == 1 ?
                "color:var(--status-done);" : "color:var(--status-error);",
            "\u25CF"),
        # Label: "connected" vs "disconnected" — same signal
        Span(() -> connection() == 1 ? " connected" : " disconnected"),

        Button(:id => "theme-toggle-btn",
            :style => "padding:2px 10px;border-radius:9999px;border:1px solid var(--accent);background:var(--accent-dim);color:var(--accent);font-size:10px;font-family:'JetBrains Mono',monospace;cursor:pointer;transition:all .15s;",
            :on_click => () -> begin
                set_dark(1 - is_dark())
                # Browser-API plumbing below — HAS to be js():
                #   • documentElement.classList toggle (DOM mutation of <html>)
                #   • localStorage write (browser API)
                #   • CodeMirror editor rebuild (3rd-party JS library)
                # The visual "dark vs light" state lives in CSS via the
                # .dark root class, NOT in this signal — is_dark is kept
                # only to re-read inside the click handler if needed.
                js("document.documentElement.classList.toggle('dark')")
                js("localStorage.setItem('sessions-theme',document.documentElement.classList.contains('dark')?'dark':'light')")
                js("if(window._sessionsThemeSwitch)_sessionsThemeSwitch()")
            end,
            :title => "Toggle light/dark mode",
            "\u25D0 Toggle")
    )
end
