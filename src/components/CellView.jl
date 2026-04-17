# CellView.jl — per-cell @island (WASM-compiled)
#
# Owns ALL reactive chrome state for one cell — eye toggle
# (fold/unfold), state classes (queued/running/etc.), .stale class,
# runtime badge text. CodeMirror is passed as the `children` slot and
# lives as a child DOM node that CM manages itself.
#
# Therapy compiler limitation: `:class => () -> "..."` and reactive
# text-node bare callables ARE NOT WASM-managed for arbitrary string
# expressions — they render once at SSR and never update. The
# canonical Therapy reactive-DOM pattern (used by DarkModeToggle, etc.)
# is `create_effect(() -> ... js("...", value))`. The if/else logic
# lives in JULIA inside the effect; the js() block is a single line
# that just writes the result to the DOM. Logic is reactive (effect
# re-runs on signal change). NOT JS soup — one effect per visual
# concern, all derivation in Julia.
#
# Per-cell signals are PRIVATE (not shared) — the WS bridge writes
# them by selecting `therapy-island[data-cell-id=...]` and poking
# `signal_N.value` directly (the documented HMR pattern).
#
# Loaded by Therapy.load_app! from src/components/. render_cell()
# looks this up at SSR via Main.CellView.

using Therapy

# Cell state codes — must match the JS WS bridge encoding.
const CV_STATE_IDLE     = 0
const CV_STATE_QUEUED   = 1
const CV_STATE_RUNNING  = 2
const CV_STATE_DONE     = 3
const CV_STATE_ERRORED  = 4
const CV_STATE_SKIPPED  = 5

# Compute the .code-cell class string from state + stale (pure Julia,
# runs in WASM). Used both for SSR initial render and inside the
# reactive effect.
function _cv_class_str(s::Int, stale::Int)::String
    cls = "code-cell relative overflow-hidden"
    s == CV_STATE_QUEUED   && (cls *= " cv-queued executing")
    s == CV_STATE_RUNNING  && (cls *= " cv-running executing")
    s == CV_STATE_ERRORED  && (cls *= " cv-errored")
    s == CV_STATE_SKIPPED  && (cls *= " cv-skipped")
    stale == 1             && (cls *= " stale")
    cls
end

# Format an Int nanosecond duration → human runtime badge string.
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

@island function CellView(children...;
                          cell_id::String="",
                          initial_state::Int=CV_STATE_IDLE,
                          initial_stale::Int=0,
                          initial_runtime_ns::Int=0,
                          initial_open::Int=1,
                          run_handler::String="",
                          menu_handler::String="")
    # ── Signal layout (KEEP THIS ORDER — JS WS bridge indexes by it) ──
    state, set_state         = create_signal(initial_state)
    is_stale, set_stale      = create_signal(initial_stale)
    runtime_ns, set_runtime  = create_signal(initial_runtime_ns)
    is_open, set_open        = create_signal(initial_open)

    # ── Effect: state + stale → .code-cell className ──
    # Subscribes to BOTH signals. Builds class string in Julia, writes
    # via single js() call. Re-runs whenever state or is_stale changes.
    create_effect(() -> begin
        cls = _cv_class_str(state(), is_stale())
        js("var el=island.querySelector('.code-cell');if(el)el.className=\$1;", cls)
    end)

    # ── Effect: runtime_ns → .rt-badge text ──
    create_effect(() -> begin
        txt = _cv_fmt_runtime(runtime_ns())
        js("var b=island.querySelector('.rt-badge');if(b)b.textContent=\$1;", txt)
    end)

    # ── Effect: is_open → .cell-code-wrap visibility ──
    create_effect(() -> begin
        v = is_open()
        js("var c=island.querySelector('.cell-code-wrap');if(c)c.style.display=\$1?'':'none';", v)
    end)

    # SSR initial values so first paint matches state before effects run.
    initial_class = _cv_class_str(initial_state, initial_stale)
    initial_badge = _cv_fmt_runtime(initial_runtime_ns)
    initial_wrap_style = initial_open == 1 ? "" : "display:none"

    Div(:class => "cell-island",
        # Eye toggle — clicks flip is_open AND dispatch WS toggle_fold.
        Div(:class => "cell-eye",
            :on_click => () -> begin
                new_open = 1 - is_open()
                set_open(new_open)
                # Browser API: WebSocket dispatch — must be js().
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
        Div(:class => "cell-code-wrap", :style => initial_wrap_style,
            Div(:class => initial_class,
                Div(:class => "cell-ctrls absolute top-1 right-1.5 flex items-center z-10",
                    Span(:class => "rt-badge", initial_badge),
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
