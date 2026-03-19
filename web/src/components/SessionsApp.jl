# SessionsApp.jl — Static SSR: Top-level three-panel IDE layout
#
# Plain function (NOT @island). Renders the full workspace:
# activity bar | file explorer | editor area (notebook + REPL) | status bar.
# Uses Tailwind classes with the custom color palette defined in Layout.jl.

# Julia three-circles SVG (small, for activity bar + status bar)
const _JULIA_LOGO_SVG = """<svg width="16" height="14" viewBox="0 0 40 34" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="20" cy="6" r="5.5" fill="#56d4a0"/><circle cx="10" cy="28" r="5.5" fill="#e06b65"/><circle cx="30" cy="28" r="5.5" fill="#b08fd8"/></svg>"""

# Activity bar button inline style
const _AB_BTN_STYLE = "width:32px;height:32px;display:flex;align-items:center;justify-content:center;border-radius:6px;border:none;background:none;cursor:pointer;color:#3d5068;transition:all .15s;"

function SessionsApp(children...)
    # Get notebook state for status bar cell count
    state = if isdefined(Main, :WEB_STATE) && Main.WEB_STATE[] !== nothing
        Main.WEB_STATE[]
    else
        nothing
    end
    cell_count = if state !== nothing
        length(Main.Sessions.ordered_cells(state.nb))
    else
        0
    end

    Div(:class => "flex-1 flex flex-col min-h-0",
        # ── Workspace: activity bar + explorer + editor ──
        Div(:id => "workspace", :class => "flex-1 flex gap-2.5 p-2.5 min-h-0",
            # ── Activity Bar ──
            _activity_bar(),

            # ── File Explorer Panel ──
            Div(:id => "fpanel",
                :class => "rounded-xl bg-surf border border-b1 flex flex-col overflow-hidden shrink-0",
                :style => "width:234px;",
                # Header
                Div(:class => "flex items-center px-3 h-9 text-[11px] font-semibold uppercase tracking-wider text-t3 border-b border-b1 shrink-0",
                    "Explorer"),
                # Content
                FileExplorer()),

            # ── Editor Area ──
            Div(:class => "flex-1 flex flex-col gap-2 min-w-0 min-h-0",
                # Notebook island (NotebookPanel renders its own rounded-xl wrapper)
                children...,
                # REPL island
                ReplPanel())),

        # ── Status Bar ──
        Div(:class => "h-[26px] flex items-center px-4 gap-4 text-[10px] font-mono text-t4 bg-deep border-t border-b1 shrink-0",
            # Julia logo + name
            Span(:class => "flex items-center gap-1.5",
                RawHtml(_JULIA_LOGO_SVG),
                "Sessions.jl"),
            # Cell count
            Span("$(cell_count) cells"),
            # Spacer
            Span(:class => "flex-1"),
            # Connection status
            Span(:class => "text-jg", "\u25cf connected")))
end

# ── Activity Bar (inline, not a separate component) ──

function _activity_bar()
    Div(:class => "flex flex-col items-center gap-1 py-2 w-[42px] shrink-0 rounded-xl bg-surf border border-b1",
        # Julia logo at top
        Div(:class => "flex items-center justify-center w-8 h-8 mb-2",
            RawHtml(_JULIA_LOGO_SVG)),

        # File explorer toggle
        Therapy.Button(:class => "ab",
            :style => _AB_BTN_STYLE,
            :title => "Toggle Explorer (Ctrl+B)",
            :on_click => "var fp=document.getElementById('fpanel');if(fp)fp.classList.toggle('hide');",
            RawHtml("""<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"/></svg>""")),

        # JET diagnostics button
        Therapy.Button(:class => "ab",
            :style => _AB_BTN_STYLE,
            :title => "Diagnostics",
            RawHtml("""<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z"/></svg>""")),

        # Terminal button
        Therapy.Button(:class => "ab",
            :style => _AB_BTN_STYLE,
            :title => "Toggle REPL (Ctrl+`)",
            RawHtml("""<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>""")))
end
