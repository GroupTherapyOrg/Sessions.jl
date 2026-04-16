# CellView.jl — per-cell @island (WASM-compiled)
#
# Owns ALL reactive chrome state for one cell — eye toggle
# (fold/unfold), state classes (queued/running/etc.), .stale class,
# runtime badge text, run + menu buttons. CodeMirror is passed as the
# `children` slot and lives as a child DOM node that CM manages itself.
#
# Loaded like every other @island by Therapy.load_app! at app startup.
# render_cell() (src/engine/web_rendering.jl) looks this up at SSR time
# via `Main.CellView` since the package layer doesn't depend on the
# component layer (one-way arrow: components → package, not the
# reverse).
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

# Format an Int nanosecond duration into a compact human string for
# the runtime badge. Pure Julia (runs in WASM via Therapy reactive
# text-node binding — no js() needed).
function _cv_fmt_runtime(ns::Int)::String
    ns <= 0 && return ""
    ms = ns / 1e6
    ms < 1     && return string(round(ns / 1e3; digits=1), "µs")
    ms < 1000  && return string(round(ms;       digits=1), "ms")
    s = ms / 1000
    s < 60     && return string(round(s;        digits=1), "s")
    m = s / 60
    m < 60     && return string(round(m;        digits=1), "min")
    return string(round(m / 60; digits=1), "hr")
end

# Map a state code to the `cv-X` modifier class CSS keys off via :has().
function _cv_state_class(s::Int)::String
    s == CV_STATE_QUEUED  && return " cv-queued"
    s == CV_STATE_RUNNING && return " cv-running"
    s == CV_STATE_ERRORED && return " cv-errored"
    s == CV_STATE_SKIPPED && return " cv-skipped"
    ""
end

@island function CellView(children...;
                          cell_id::String="",
                          initial_state::Int=CV_STATE_IDLE,
                          initial_stale::Int=0,
                          initial_runtime_ns::Int=0,
                          initial_open::Int=1,
                          run_handler::String="",
                          menu_handler::String="")
    # ── Signal layout (KEEP THIS ORDER — see header docstring) ──
    state, set_state         = create_signal(initial_state)
    is_stale, set_stale      = create_signal(initial_stale)
    runtime_ns, set_runtime  = create_signal(initial_runtime_ns)
    is_open, set_open        = create_signal(initial_open)

    # ── Render — pure declarative Therapy. No js() except in the eye
    #            click handler (WS dispatch — browser API, unavoidable).
    #            All visual state comes from reactive bindings:
    #              :class => () -> ...   reactive class string
    #              :style => () -> ...   reactive style
    #              () -> "text"          reactive text node
    #            Parent .cell-wrap styling is driven by CSS :has(...)
    #            against the .code-cell modifiers — see input.css.
    Div(:class => "cell-island",
        # Eye toggle — clicks flip is_open AND dispatch WS toggle_fold.
        Div(:class => "cell-eye",
            :on_click => () -> begin
                new_open = 1 - is_open()
                set_open(new_open)
                # The single js() in this @island: WS send is a browser
                # API call (TherapyWS), not state mutation. Cell id is
                # interpolated at SSR time via the kwarg.
                js("""if(window.TherapyWS&&TherapyWS.sendMessage){
                          TherapyWS.sendMessage('notebook',{action:'toggle_fold',cell_id:'""" * cell_id * """',folded:!\$1});
                      }""", new_open)
            end,
            Div(:style => "position:relative;width:14px;height:14px;",
                RawHtml("""<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19M1 1l22 22"/></svg>"""),
                Show(is_open) do
                    Div(:style => "position:absolute;inset:0;background:var(--panel-bg);",
                        RawHtml("""<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>"""))
                end)),
        # cell-code-wrap — visibility driven by reactive style binding
        # (NOT Show() — Show() unmounts/remounts and CodeMirror would
        # lose its DOM state every fold/unfold).
        Div(:class => "cell-code-wrap",
            :style => () -> is_open() == 1 ? "" : "display:none",
            # code-cell — class is reactive: state modifier (cv-running
            # etc.) + stale modifier. CSS :has() picks these up to
            # style the parent .cell-wrap (input.css).
            Div(:class => () -> string("code-cell relative overflow-hidden",
                                       _cv_state_class(state()),
                                       is_stale() == 1 ? " stale" : ""),
                # Hover controls — runtime badge + run + menu buttons.
                Div(:class => "cell-ctrls absolute top-1 right-1.5 flex items-center z-10",
                    # Reactive text-node — formatted on every runtime_ns change.
                    Span(:class => "rt-badge", () -> _cv_fmt_runtime(runtime_ns())),
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
