# islands.jl — WASM-compiled @island components for live notebook UI
#
# CellToggle: code visibility toggle (fold/unfold)
#
# WebSlider + BoundValue (predecessors of SessionsUI's BoundSlider)
# were removed when bonds switched to the SessionsUI MIME"text/html"
# pipeline. The canonical interactive widget is now
# `<bond def="x">…SessionsUI widget HTML…</bond>` plus BOND_BRIDGE_JS
# (in dev mode) or a per-widget Therapy @island (in publish mode,
# Phase 3).

using Therapy

@island function CellToggle(children...; initial_open::Int=1)
    is_open, set_is_open = create_signal(initial_open)

    create_effect(() -> begin
        v = is_open()
        js("""
            var c=island.querySelector('.cell-code-wrap');
            if(c)c.style.display=\$1?'':'none';
            if(!island._foldInit){island._foldInit=true;return;}
            var wrap=island.closest('.cell-wrap');
            var cid=wrap?wrap.dataset.cellId:'';
            if(cid&&window.TherapyWS&&TherapyWS.sendMessage){
                TherapyWS.sendMessage('notebook',{action:'toggle_fold',cell_id:cid,folded:!\$1});
            }
        """, v)
    end)

    Div(:class => "cell-island",
        Div(:class => "cell-eye",
            :on_click => () -> begin
                set_is_open(1 - is_open())
            end,
            Div(:style => "position:relative;width:14px;height:14px;",
                RawHtml("""<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19M1 1l22 22"/></svg>"""),
                Show(is_open) do
                    Div(:style => "position:absolute;inset:0;background:var(--panel-bg);",
                        RawHtml("""<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>"""))
                end)),

        Div(:class => "cell-code-wrap", children...))
end
