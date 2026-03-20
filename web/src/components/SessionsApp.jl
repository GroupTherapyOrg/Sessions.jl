# SessionsApp.jl — @island: Top-level IDE layout with panel toggle signals
#
# Two signals: sidebar_open (file explorer), repl_open (REPL panel).
# Activity bar buttons toggle signals via pure WASM on_click handlers.
# Show() reactively hides/shows panels.
# BindBool maps signal state to data-state attribute for active highlighting.

# Julia three-circles SVG (small, for activity bar + status bar)
const _JULIA_LOGO_SVG = """<svg width="16" height="14" viewBox="0 0 40 34" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="20" cy="6" r="5.5" fill="#56d4a0"/><circle cx="10" cy="28" r="5.5" fill="#e06b65"/><circle cx="30" cy="28" r="5.5" fill="#b08fd8"/></svg>"""

# Activity bar button base style (inactive state)
const _AB_BTN_STYLE = "width:32px;height:32px;display:flex;align-items:center;justify-content:center;border-radius:6px;border:none;background:none;cursor:pointer;color:#3d5068;transition:all .15s;"

@island function SessionsApp(children...; initial_sidebar=1, initial_repl=1)
    # Panel visibility signals (Int32: 0=closed, 1=open)
    sidebar_open, set_sidebar_open = create_signal(Int32(initial_sidebar))
    repl_open, set_repl_open = create_signal(Int32(initial_repl))

    # Get notebook state for status bar (server-side only, not compiled to WASM)
    cell_count = if isdefined(Main, :WEB_STATE) && Main.WEB_STATE[] !== nothing
        length(Main.Sessions.ordered_cells(Main.WEB_STATE[].nb))
    else
        0
    end

    Div(:class => "flex-1 flex flex-col min-h-0",
        # ── Workspace: activity bar + explorer + editor ──
        Div(:id => "workspace", :class => "flex-1 flex gap-2.5 p-2.5 min-h-0 overflow-hidden",

            # ── Activity Bar ──
            Div(:class => "flex flex-col items-center gap-1 py-2 w-[42px] shrink-0 self-start rounded-xl bg-surf border border-b1 shadow-lg shadow-black/25",
                # Julia logo at top
                Div(:class => "flex items-center justify-center w-8 h-8 mb-2",
                    RawHtml(_JULIA_LOGO_SVG)),

                # File explorer toggle — active highlight via BindBool → data-state
                Button(:class => "ab-btn",
                    :style => _AB_BTN_STYLE,
                    :title => "Toggle Explorer (Ctrl+B)",
                    Symbol("data-state") => BindBool(sidebar_open, "off", "on"),
                    :on_click => () -> begin
                        if sidebar_open() == Int32(1)
                            set_sidebar_open(Int32(0))
                        else
                            set_sidebar_open(Int32(1))
                        end
                    end,
                    RawHtml("""<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"/></svg>""")),

                # JET diagnostics button (static for now)
                Button(:class => "ab-btn",
                    :style => _AB_BTN_STYLE,
                    :title => "Diagnostics",
                    RawHtml("""<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"/></svg>""")),

                # Terminal toggle — active highlight via BindBool → data-state
                Button(:class => "ab-btn",
                    :style => _AB_BTN_STYLE,
                    :title => "Toggle REPL (Ctrl+`)",
                    Symbol("data-state") => BindBool(repl_open, "off", "on"),
                    :on_click => () -> begin
                        if repl_open() == Int32(1)
                            set_repl_open(Int32(0))
                        else
                            set_repl_open(Int32(1))
                        end
                    end,
                    RawHtml("""<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>"""))),

            # ── File Explorer Panel (shown/hidden by sidebar_open signal) ──
            Show(sidebar_open) do
                Div(:id => "fpanel",
                    :class => "rounded-xl bg-surf border border-b1 flex flex-col overflow-hidden shrink-0 shadow-lg shadow-black/25",
                    :style => "width:234px; max-height:100%;",
                    # Header
                    Div(:class => "flex items-center justify-between px-3 py-2.5 border-b border-b1 shrink-0",
                        Span(:class => "text-[10px] font-semibold uppercase tracking-wider text-t3", "Explorer"),
                        Span(:class => "text-[9px] text-t4 font-mono", "⌘B")),
                    # Content (filesystem tree with inline JS folder toggles)
                    FileExplorer())
            end,

            # ── Editor Area ──
            Div(:class => "flex-1 flex flex-col gap-2 min-w-0 min-h-0 overflow-hidden",
                # Notebook island
                children...,
                # REPL island (shown/hidden by repl_open signal)
                Show(repl_open) do
                    ReplPanel()
                end)),

        # ── Status Bar ──
        Div(:class => "h-[26px] flex items-center px-4 gap-4 text-[10px] font-mono text-t4 bg-deep border-t border-b1 shrink-0",
            Span(:class => "flex items-center gap-1.5",
                RawHtml(_JULIA_LOGO_SVG),
                "Sessions.jl"),
            Span("$(cell_count) cells"),
            Span(:class => "flex-1"),
            Span(:class => "text-jg", "● connected")))
end
