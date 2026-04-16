# islands.jl — WASM-compiled @island components for live notebook UI
#
# CellView: per-cell @island. Owns ALL reactive chrome state for one
# cell — eye toggle (fold/unfold), state classes (queued/running/etc.),
# .stale class, runtime badge text, run + menu buttons. CodeMirror is
# passed as the `children` slot and lives as a child DOM node that CM
# manages itself.
#
# Per-cell state signals are PRIVATE to each CellView instance (no
# cross-island sharing — each cell owns its own). The WS bridge
# (Notebook.jl) writes to a CellView by:
#
#     var island = document.querySelector(
#         'therapy-island[data-cell-id="<uuid>"]');
#     // Signal layout (DOCUMENTED + DETERMINISTIC — keep the order
#     // of create_signal() calls below stable!):
#     //   signal_0 = state       (Int: 0=idle 1=queued 2=running
#     //                                3=done  4=errored  5=skipped)
#     //   signal_1 = is_stale    (0/1)
#     //   signal_2 = runtime_ns  (Int)
#     //   signal_3 = is_open     (0/1 — eye toggle)
#     island._wasmExports.signal_0.value = BigInt(2);
#     island._wasmExports._rt_flush(island._wasmExports._rt_subs_0.value);
#
# This is exactly the pattern Therapy's HMR uses (Therapy.jl/src/
# Server/WebSocketClient.jl ~line 208) — the supported public way to
# poke an island's signal from outside its own runtime. NOT going
# through window.__therapy because per-cell state belongs to one
# island instance, not shared across islands.
#
# WebSlider + BoundValue (predecessors of SessionsUI's BoundSlider)
# were removed when bonds switched to the SessionsUI MIME"text/html"
# pipeline. The canonical interactive widget is now
# `<bond def="x">…SessionsUI widget HTML…</bond>` plus BOND_BRIDGE_JS
# (in dev mode) or a per-widget Therapy @island (in publish mode,
# Phase 3).

using Therapy

# Cell state codes — must match the order assumed by the JS WS bridge.
const CV_STATE_IDLE     = 0
const CV_STATE_QUEUED   = 1
const CV_STATE_RUNNING  = 2
const CV_STATE_DONE     = 3
const CV_STATE_ERRORED  = 4
const CV_STATE_SKIPPED  = 5

@island function CellView(children...;
                          initial_state::Int=CV_STATE_IDLE,
                          initial_stale::Int=0,
                          initial_runtime_ns::Int=0,
                          initial_open::Int=1,
                          run_handler::String="",
                          menu_handler::String="")
    # ── Signal layout (KEEP THIS ORDER — see header docstring) ──
    state, set_state = create_signal(initial_state)
    is_stale, set_stale = create_signal(initial_stale)
    runtime_ns, set_runtime = create_signal(initial_runtime_ns)
    is_open, set_open = create_signal(initial_open)

    # ── Eye toggle (fold/unfold + WS dispatch on user click) ──
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

    # ── State → classes on .code-cell + wrap-* on .cell-wrap ──
    create_effect(() -> begin
        s = state()
        js("""
            var cc=island.querySelector('.code-cell');
            if(cc){
                cc.classList.remove('idle','executing');
                if(\$1===1||\$1===2)cc.classList.add('executing');
            }
            var w=island.closest('.cell-wrap');
            if(w){
                w.classList.remove('wrap-queued','wrap-running','wrap-done','wrap-errored','wrap-skipped');
                if(\$1===1)w.classList.add('wrap-queued');
                else if(\$1===2)w.classList.add('wrap-running');
                else if(\$1===4)w.classList.add('wrap-errored');
                else if(\$1===5)w.classList.add('wrap-skipped');
            }
        """, s)
    end)

    # ── is_stale → .stale class on .code-cell ──
    create_effect(() -> begin
        v = is_stale()
        js("""
            var cc=island.querySelector('.code-cell');
            if(cc){if(\$1)cc.classList.add('stale');else cc.classList.remove('stale');}
        """, v)
    end)

    # ── runtime_ns → .rt-badge text ──
    # Format inline: ns < 1ms → µs, ms < 1000 → ms, etc.
    create_effect(() -> begin
        ns = runtime_ns()
        js("""
            var b=island.querySelector('.rt-badge');
            if(!b)return;
            var n=\$1;
            if(n<=0){b.textContent='';return;}
            var ms=n/1e6;
            if(ms<1){b.textContent=(n/1e3).toFixed(1)+'\\u00b5s';return;}
            if(ms<1000){b.textContent=ms.toFixed(1)+'ms';return;}
            var s=ms/1000;
            if(s<60){b.textContent=s.toFixed(1)+'s';return;}
            var m=s/60;
            if(m<60){b.textContent=m.toFixed(1)+'min';return;}
            b.textContent=(m/60).toFixed(1)+'hr';
        """, ns)
    end)

    # ── Render: cell-island > cell-eye + cell-code-wrap > code-cell ──
    Div(:class => "cell-island",
        # Eye toggle (click flips is_open signal)
        Div(:class => "cell-eye",
            :on_click => () -> set_open(1 - is_open()),
            Div(:style => "position:relative;width:14px;height:14px;",
                RawHtml("""<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19M1 1l22 22"/></svg>"""),
                Show(is_open) do
                    Div(:style => "position:absolute;inset:0;background:var(--panel-bg);",
                        RawHtml("""<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>"""))
                end)),
        Div(:class => "cell-code-wrap",
            Div(:class => "code-cell relative overflow-hidden",
                # Hover controls — runtime badge + run + menu buttons.
                # The badge text is updated by the runtime_ns effect above.
                # Buttons use string handlers (interpolated cell_id) since
                # they dispatch to global IDE JS and don't need per-island
                # WASM compilation of the click logic.
                Div(:class => "cell-ctrls absolute top-1 right-1.5 flex items-center z-10",
                    Span(:class => "rt-badge", ""),
                    isempty(run_handler) ? nothing :
                        Therapy.Button(:class => "ctrl-btn run-btn",
                            :title => "Run cell (Shift+Enter)",
                            :on_click => run_handler,
                            RawHtml("""<svg width="10" height="10" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2.5v11l10-5.5z"/></svg>""")),
                    isempty(menu_handler) ? nothing :
                        Therapy.Button(:class => "ctrl-btn menu-btn",
                            :title => "Cell actions",
                            :on_click => menu_handler,
                            RawHtml("""<svg width="11" height="11" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="8" cy="3" r="1.2"/><circle cx="8" cy="8" r="1.2"/><circle cx="8" cy="13" r="1.2"/></svg>"""))),
                children...)))
end
