# islands.jl — WASM-compiled @island components for live notebook UI
#
# CellToggle: code visibility toggle (fold/unfold)
# WebSlider: interactive @bind slider
# BoundValue: live WASM display for bound variable

using Therapy

@island function CellToggle(children...; initial_open::Int=1)
    is_open, set_is_open = create_signal(Int32(initial_open))

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
                if is_open() == Int32(1)
                    set_is_open(Int32(0))
                else
                    set_is_open(Int32(1))
                end
            end,
            Div(:style => "position:relative;width:14px;height:14px;",
                RawHtml("""<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19M1 1l22 22"/></svg>"""),
                Show(is_open) do
                    Div(:style => "position:absolute;inset:0;background:var(--panel-bg);",
                        RawHtml("""<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>"""))
                end)),

        Div(:class => "cell-code-wrap", children...))
end

@island function WebSlider(; min_val::Int=0, max_val::Int=100, value::Int=50, step_val::Int=1, var_name::String="x")
    current, set_current = create_signal(Int32(value))

    Div(:style => "display:flex;align-items:center;gap:12px;padding:8px 0;",
        Span(:style => "font-size:13px;font-family:'JetBrains Mono',ui-monospace,monospace;color:#6b7d93;",
            string(var_name), " = "),
        Input(:type => "range",
            :min => string(min_val),
            :max => string(max_val),
            :step => string(step_val),
            :value => string(value),
            :style => "flex:1;max-width:300px;accent-color:#56d4a0;cursor:pointer;",
            :on_input => () -> set_current(unsafe_trunc(Int32, get_target_value_f64()))),
        Span(:style => "font-size:13px;font-family:'JetBrains Mono',ui-monospace,monospace;color:#56d4a0;min-width:2em;text-align:right;",
            current))
end

@island function BoundValue(; value::Int=0)
    current, set_current = create_signal(Int32(value))

    Div(:class => "inline-flex items-baseline",
        Input(:type => "hidden", :value => string(value),
            :on_input => () -> set_current(unsafe_trunc(Int32, get_target_value_f64()))),
        Span(:class => "text-sm font-mono text-warm-600 dark:text-warm-500",
            current))
end
