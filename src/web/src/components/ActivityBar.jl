# ActivityBar.jl — @island: sidebar/terminal panel toggles
#
# Destructures shared signal tuples from SharedSignals.jl.
# Follows DarkModeToggle pattern: module-level tuple → destructure inside @island.

const _JULIA_LOGO_SVG = """<svg width="16" height="14" viewBox="0 0 40 34" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="20" cy="6" r="5.5" fill="#56d4a0"/><circle cx="10" cy="28" r="5.5" fill="#e06b65"/><circle cx="30" cy="28" r="5.5" fill="#b08fd8"/></svg>"""
const _FOLDER_SVG = """<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"/></svg>"""
const _TERMINAL_SVG = """<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>"""
const _JET_SVG = """<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"/></svg>"""

@island function ActivityBar()
    # Destructure shared signal tuples (compiles to __t.shared())
    sidebar_open, set_sidebar_open = sidebar_signal
    terminal_open, set_terminal_open = terminal_signal

    # Restore panel state from localStorage on mount
    # Note: js() with $1/$2 substitution for signal setters compiled correctly
    # in handlers but not in on_mount (gets Julia repr). Use __t.shared() directly.
    on_mount(() -> js("""
        if(localStorage.getItem('sessions-sidebar')==='1'){
            __t.shared('sidebar_open',0)[1](1);
        }
        if(localStorage.getItem('sessions-repl')==='1'){
            __t.shared('terminal_open',0)[1](1);
        }
    """))

    # Effect: sync sidebar visibility to DOM
    create_effect(() -> begin
        v = sidebar_open()
        js("var fp=document.getElementById('fpanel');if(fp)fp.style.display=\$1?'':'none'", v)
    end)

    # Effect: sync terminal visibility to DOM
    create_effect(() -> begin
        v = terminal_open()
        js("var rp=document.getElementById('repl-panel');if(rp)rp.style.display=\$1?'':'none'", v)
    end)

    return Div(:class => "flex flex-col items-center gap-1 py-2 w-[42px] shrink-0 self-start rounded-xl",
        :style => "background:var(--panel-bg);border:1px solid var(--cell-border);",

        Div(:class => "flex items-center justify-center w-8 h-8 mb-2",
            RawHtml(_JULIA_LOGO_SVG)),

        # Sidebar toggle
        Button(:class => "ab-btn",
            :style => "width:28px;height:28px;display:flex;align-items:center;justify-content:center;border-radius:6px;border:none;background:none;cursor:pointer;color:var(--text-3);transition:all .15s;",
            :title => "Toggle Explorer (Ctrl+B)",
            :on_click => () -> begin
                set_sidebar_open(1 - sidebar_open())
                js("localStorage.setItem('sessions-sidebar',\$1?'1':'0')", sidebar_open())
            end,
            RawHtml(_FOLDER_SVG)),

        # JET (disabled)
        Button(:class => "ab-btn",
            :style => "width:28px;height:28px;display:flex;align-items:center;justify-content:center;border-radius:6px;border:none;background:none;color:var(--text-3);opacity:0.3;cursor:default;",
            :title => "JETLS diagnostics — coming soon",
            :disabled => "true",
            RawHtml(_JET_SVG)),

        # Terminal toggle
        Button(:class => "ab-btn",
            :style => "width:28px;height:28px;display:flex;align-items:center;justify-content:center;border-radius:6px;border:none;background:none;cursor:pointer;color:var(--text-3);transition:all .15s;",
            :title => "Toggle Terminal (Ctrl+`)",
            :on_click => () -> begin
                set_terminal_open(1 - terminal_open())
                js("localStorage.setItem('sessions-repl',\$1?'1':'0')", terminal_open())
            end,
            RawHtml(_TERMINAL_SVG)))
end
