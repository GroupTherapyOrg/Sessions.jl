# ActivityBar.jl — @island: sidebar/terminal panel toggles
#
# Destructures shared signal tuples from SharedSignals.jl.

const _SESSIONS_LOGO_SVG = """<svg width="20" height="20" viewBox="0 0 80 80" fill="none"><path d="M22 20C22 20 31 20 40 33C49 20 58 20 58 20" stroke="#d4759a" stroke-width="6" stroke-linecap="round"/><path d="M22 38C22 38 31 38 40 51C49 38 58 38 58 38" stroke="#d4759a" stroke-width="6" stroke-linecap="round" opacity="0.55"/><path d="M22 56C22 56 31 56 40 69C49 56 58 56 58 56" stroke="#d4759a" stroke-width="6" stroke-linecap="round" opacity="0.22"/></svg>"""
const _FOLDER_SVG = """<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"/></svg>"""
const _TERMINAL_SVG = """<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>"""
const _JET_SVG = """<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"/></svg>"""

@island function ActivityBar()
    sidebar_open, set_sidebar_open = sidebar_signal
    terminal_open, set_terminal_open = terminal_signal

    js("if(localStorage.getItem('sessions-sidebar')==='1')\$1(1)", set_sidebar_open)
    js("if(localStorage.getItem('sessions-repl')==='1')\$1(1)", set_terminal_open)

    create_effect(() -> begin
        v = sidebar_open()
        js("var fp=document.getElementById('fpanel');if(fp)fp.style.display=\$1?'':'none';var b=document.querySelectorAll('.ab-btn')[0];if(b)b.setAttribute('data-state',\$1?'on':'off')", v)
    end)

    create_effect(() -> begin
        v = terminal_open()
        js("var rp=document.getElementById('repl-panel');if(rp)rp.style.display=\$1?'':'none';var b=document.querySelectorAll('.ab-btn')[2];if(b)b.setAttribute('data-state',\$1?'on':'off')", v)
    end)

    return Div(:class => "flex flex-col items-center gap-1 py-2 w-[42px] shrink-0 self-start rounded-xl",
        :style => "background:var(--panel-bg);border:1px solid var(--cell-border);",

        Div(:class => "flex items-center justify-center w-8 h-8 mb-2",
            RawHtml(_SESSIONS_LOGO_SVG)),

        Button(:class => "ab-btn",
            :style => "width:28px;height:28px;display:flex;align-items:center;justify-content:center;border-radius:6px;border:none;background:none;cursor:pointer;color:var(--text-3);transition:all .15s;",
            :title => "Toggle Explorer (Ctrl+B)",
            :on_click => () -> begin
                nv = 1 - sidebar_open()
                set_sidebar_open(nv)
                js("localStorage.setItem('sessions-sidebar',\$1?'1':'0')", nv)
            end,
            RawHtml(_FOLDER_SVG)),

        Button(:class => "ab-btn",
            :style => "width:28px;height:28px;display:flex;align-items:center;justify-content:center;border-radius:6px;border:none;background:none;color:var(--text-3);opacity:0.3;cursor:default;",
            :title => "JETLS diagnostics — coming soon",
            :disabled => "true",
            RawHtml(_JET_SVG)),

        Button(:class => "ab-btn",
            :style => "width:28px;height:28px;display:flex;align-items:center;justify-content:center;border-radius:6px;border:none;background:none;cursor:pointer;color:var(--text-3);transition:all .15s;",
            :title => "Toggle Terminal (Ctrl+`)",
            :on_click => () -> begin
                nv = 1 - terminal_open()
                set_terminal_open(nv)
                js("localStorage.setItem('sessions-repl',\$1?'1':'0')", nv)
            end,
            RawHtml(_TERMINAL_SVG)))
end
