# SidebarPanel.jl — @island wrapper for the file explorer panel
#
# Owns the panel's visibility (display:none toggle) reactively from
# `sidebar_open_signal`. Replaces the cross-island reach-out where
# ActivityBar's effect did `document.getElementById('fpanel').style.display = …`.
#
# Why effect-driven display:none and not Show()?
#   Show() actually mounts/unmounts DOM, so FileExplorer's hydrated
#   state (Shoelace tree expansion, scroll position, selected file)
#   would be lost on every toggle. display:none keeps the DOM and
#   just hides it — toggle is cheap and stateful.
#
# Why no kwargs?
#   Same reason as NotebookToolbar / StatusBar: kwargs would collide
#   with the shared signal slot in Therapy's prop-init loop. The
#   page-level IIFE in SessionsApp.jl pre-seeds the shared signal
#   via `window.__therapy.set('sidebar_open', …)` BEFORE hydration,
#   so the first effect run picks up the localStorage-restored value.

@island function SidebarPanel(children...)
    sidebar_open, _ = sidebar_open_signal

    create_effect(() -> begin
        v = sidebar_open()
        js("""
            var el=island.querySelector('[data-panel-root]');
            if(el)el.style.display=\$1?'':'none';
        """, v)
    end)

    Div(:id => "fpanel",
        Symbol("data-panel-root") => "1",
        :class => "rounded-xl flex flex-col overflow-hidden shrink-0",
        :style => "width:234px;max-height:100%;display:none;background:var(--panel-bg);border:1px solid var(--cell-border);",
        children...)
end
