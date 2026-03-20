# SessionsApp.jl — Top-level IDE layout
#
# Panel toggles use JS onclick that:
#   1. Toggles display on the panel
#   2. Toggles data-state on the button (for CSS highlight)
#   3. Saves to localStorage immediately
#
# On page load: panels start hidden (SSR). JS reads localStorage
# and shows panels that should be open. Simple, no WASM signal issues.

const _JULIA_LOGO_SVG = """<svg width="16" height="14" viewBox="0 0 40 34" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="20" cy="6" r="5.5" fill="#56d4a0"/><circle cx="10" cy="28" r="5.5" fill="#e06b65"/><circle cx="30" cy="28" r="5.5" fill="#b08fd8"/></svg>"""

const _AB_BTN_STYLE = "width:32px;height:32px;display:flex;align-items:center;justify-content:center;border-radius:6px;border:none;background:none;cursor:pointer;color:#3d5068;transition:all .15s;"

function SessionsApp(children...)
    cell_count = if isdefined(Main, :WEB_STATE) && Main.WEB_STATE[] !== nothing
        length(Main.Sessions.ordered_cells(Main.Sessions.active_nb(Main.WEB_STATE[])))
    else
        0
    end

    # JS toggle function: toggles panel display + button state + saves localStorage
    toggle_js = """
    window._togglePanel = function(panelId, storageKey, btn) {
        var panel = document.getElementById(panelId);
        if (!panel) { console.log('[Panels] panel not found: ' + panelId); return; }
        var isOpen = panel.style.display !== 'none';
        panel.style.display = isOpen ? 'none' : '';
        btn.setAttribute('data-state', isOpen ? 'off' : 'on');
        localStorage.setItem(storageKey, isOpen ? '0' : '1');
        console.log('[Panels] toggle ' + storageKey + ' → ' + (isOpen ? 'closed' : 'open'));
    };
    """

    # JS restore function: reads localStorage and shows panels
    restore_js = """
    (function() {
        var sb = localStorage.getItem('sessions-sidebar');
        var rp = localStorage.getItem('sessions-repl');
        console.log('[Panels] restore: sidebar=' + sb + ' repl=' + rp);

        var fp = document.getElementById('fpanel');
        var repl = document.getElementById('repl-panel');
        var btns = document.querySelectorAll('.ab-btn');

        if (fp) {
            var showSidebar = sb === '1';
            fp.style.display = showSidebar ? '' : 'none';
            if (btns[0]) btns[0].setAttribute('data-state', showSidebar ? 'on' : 'off');
            console.log('[Panels] sidebar → ' + (showSidebar ? 'open' : 'closed'));
        }
        if (repl) {
            var showRepl = rp === '1';
            repl.style.display = showRepl ? '' : 'none';
            if (btns[2]) btns[2].setAttribute('data-state', showRepl ? 'on' : 'off');
            console.log('[Panels] repl → ' + (showRepl ? 'open' : 'closed'));
        }
    })();
    """

    Div(:class => "flex-1 flex flex-col min-h-0",
        # Toggle + restore scripts
        RawHtml("<script>$(toggle_js)</script>"),

        # ── Workspace ──
        Div(:id => "workspace", :class => "flex-1 flex gap-2.5 p-2.5 min-h-0 overflow-hidden",

            # ── Activity Bar ──
            Div(:class => "flex flex-col items-center gap-1 py-2 w-[42px] shrink-0 self-start rounded-xl bg-surf border border-b1 shadow-lg shadow-black/25",
                Div(:class => "flex items-center justify-center w-8 h-8 mb-2",
                    RawHtml(_JULIA_LOGO_SVG)),

                # File explorer toggle
                Button(:class => "ab-btn",
                    :style => _AB_BTN_STYLE,
                    :title => "Toggle Explorer (Ctrl+B)",
                    Symbol("data-state") => "off",
                    :on_click => "_togglePanel('fpanel','sessions-sidebar',this)",
                    RawHtml("""<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"/></svg>""")),

                # JET diagnostics (static)
                Button(:class => "ab-btn",
                    :style => _AB_BTN_STYLE,
                    :title => "Diagnostics",
                    RawHtml("""<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"/></svg>""")),

                # Terminal toggle
                Button(:class => "ab-btn",
                    :style => _AB_BTN_STYLE,
                    :title => "Toggle REPL (Ctrl+`)",
                    Symbol("data-state") => "off",
                    :on_click => "_togglePanel('repl-panel','sessions-repl',this)",
                    RawHtml("""<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>"""))),

            # ── File Explorer Panel (starts hidden, restored by JS) ──
            Div(:id => "fpanel",
                :class => "rounded-xl bg-surf border border-b1 flex flex-col overflow-hidden shrink-0 shadow-lg shadow-black/25",
                :style => "width:234px; max-height:100%; display:none;",
                Div(:class => "flex items-center justify-between px-3 py-2.5 border-b border-b1 shrink-0",
                    Span(:class => "text-[10px] font-semibold uppercase tracking-wider text-t3", "Explorer"),
                    Span(:class => "text-[9px] text-t4 font-mono", "⌘B")),
                FileExplorer()),

            # ── Editor Area ──
            Div(:class => "flex-1 flex flex-col gap-2 min-w-0 min-h-0 overflow-hidden",
                children...,
                # REPL (starts hidden, restored by JS)
                Div(:id => "repl-panel", :style => "display:none;",
                    ReplPanel()))),

        # Restore panels from localStorage (runs after DOM is ready)
        RawHtml("<script>$(restore_js)</script>"),

        # ── Status Bar ──
        Div(:class => "h-[26px] flex items-center px-4 gap-4 text-[10px] font-mono text-t4 bg-deep border-t border-b1 shrink-0",
            Span(:class => "flex items-center gap-1.5",
                RawHtml(_JULIA_LOGO_SVG),
                "Sessions.jl"),
            Span("$(cell_count) cells"),
            Span(:class => "flex-1"),
            Span(:class => "text-jg", "● connected")))
end
