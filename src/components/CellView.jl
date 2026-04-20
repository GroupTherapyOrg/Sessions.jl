# CellView.jl — per-cell @island (WASM-compiled)
#
# Owns ALL reactive chrome state for one cell — eye toggle (fold/unfold),
# state classes (queued/running/etc.), .stale class, runtime badge text.
# CodeMirror is passed as the `children` slot and lives as a child DOM
# node that CM manages itself.
#
# THERAPY COMPILER LIMITATIONS (audit-confirmed):
#
# 1. js() args MUST be DIRECT signal-getter results — anything computed
#    by a Julia helper resolves to literal `undefined`. So every effect
#    is `v = sig(); js("…use \$1…", v)` and all branching lives INSIDE
#    the JS string.
#
# 2. Prop→signal init only fires when ALL kwargs are Integer-typed
#    (Compile.jl line 898: `all_props_are_int`). One String kwarg →
#    every signal silently stays at 0 on hydration. So this island
#    keeps every kwarg as Int. cell_id is discovered from the DOM at
#    click time inside the inline onclick handlers; run/menu actions
#    call global IDE helpers (window._sessionsRunCell etc.).
#
# Per-cell signals are PRIVATE (not shared) — the WS bridge writes
# them by selecting `therapy-island[data-cell-id=...]` and poking
# `signal_N.value` directly (the documented HMR pattern).
#
# Loaded by Therapy.load_app! from src/components/. render_cell() looks
# this up at SSR via Main.TherapyApp.CellView.

using Therapy

# Cell state codes — must match the JS WS bridge encoding.
const CV_STATE_IDLE     = 0
const CV_STATE_QUEUED   = 1
const CV_STATE_RUNNING  = 2
const CV_STATE_DONE     = 3
const CV_STATE_ERRORED  = 4
const CV_STATE_SKIPPED  = 5

# Inline onclick: discover cell_id from the DOM at click time so we
# don't need a String kwarg (which would break Therapy's prop-init).
const _CV_RUN_ONCLICK  = "window._sessionsRunCell(this.closest('.cell-wrap').dataset.cellId)"
const _CV_MENU_ONCLICK = "window._sessionsShowCellMenu(this,this.closest('.cell-wrap').dataset.cellId)"

@island function CellView(children...;
                          initial_state::Int=CV_STATE_IDLE,
                          initial_stale::Int=0,
                          initial_runtime_ns::Int=0,
                          initial_open::Int=1)
    # ── Signal layout (KEEP THIS ORDER — JS WS bridge indexes by it) ──
    state, set_state         = create_signal(initial_state)
    is_stale, set_stale      = create_signal(initial_stale)
    runtime_ns, set_runtime  = create_signal(initial_runtime_ns)
    is_open, set_open        = create_signal(initial_open)

    # ── Effect: (state, is_stale) → .code-cell className ──
    # Merged from two effects so we don't have one writing className
    # then the other reading classList to preserve stale across rebuilds.
    # Subscribes to both signals; rebuilds className from scratch on
    # either change.
    create_effect(() -> begin
        s = state()
        st = is_stale()
        js("""
            var el=island.querySelector('.code-cell');
            if(!el)return;
            var base='code-cell relative overflow-hidden';
            if(\$1===1)base+=' cv-queued executing';
            else if(\$1===2)base+=' cv-running executing';
            else if(\$1===4)base+=' cv-errored';
            else if(\$1===5)base+=' cv-skipped';
            if(\$2)base+=' stale';
            el.className=base;
        """, s, st)
    end)

    # ── Effect: runtime_ns → .rt-badge text (formatted in JS) ──
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

    # ── Effect: is_open → .cell-code-wrap visibility + .code-hidden class + WS ──
    # Single writer for fold state: inline style on .cell-code-wrap AND
    # .code-hidden on .cell-wrap. The class must move together with the
    # inline style — the CSS rule `.cell-wrap.code-hidden .cell-code-wrap
    # {display:none}` otherwise overrides a cleared inline style, leaving
    # the cell stuck hidden when re-opened. Init flag gates WS so hydration
    # doesn't fire a spurious toggle_fold.
    create_effect(() -> begin
        v = is_open()
        js("""
            var c=island.querySelector('.cell-code-wrap');
            if(c)c.style.display=\$1?'':'none';
            var wrap=island.closest('.cell-wrap');
            if(wrap){
                if(\$1) wrap.classList.remove('code-hidden');
                else wrap.classList.add('code-hidden');
            }
            if(!island._foldInit){island._foldInit=true;return;}
            var cid=wrap?wrap.dataset.cellId:'';
            if(cid&&window.TherapyWS&&TherapyWS.sendMessage){
                TherapyWS.sendMessage('notebook',{action:'toggle_fold',cell_id:cid,folded:!\$1});
            }
        """, v)
    end)

    # SSR initial values so first paint matches state before effects run.
    initial_class = "code-cell relative overflow-hidden"
    initial_state == CV_STATE_QUEUED  && (initial_class *= " cv-queued executing")
    initial_state == CV_STATE_RUNNING && (initial_class *= " cv-running executing")
    initial_state == CV_STATE_ERRORED && (initial_class *= " cv-errored")
    initial_state == CV_STATE_SKIPPED && (initial_class *= " cv-skipped")
    initial_stale == 1                && (initial_class *= " stale")
    initial_wrap_style = initial_open == 1 ? "" : "display:none"

    Div(:class => "cell-island",
        Div(:class => "cell-eye",
            :on_click => () -> set_open(1 - is_open()),
            Div(:style => "position:relative;width:14px;height:14px;",
                RawHtml("""<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19M1 1l22 22"/></svg>"""),
                Show(is_open) do
                    Div(:style => "position:absolute;inset:0;background:var(--panel-bg);",
                        RawHtml("""<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>"""))
                end)),
        Div(:class => "cell-code-wrap", :style => initial_wrap_style,
            Div(:class => initial_class,
                Div(:class => "cell-ctrls absolute top-1 right-1.5 flex items-center z-10",
                    Span(:class => "rt-badge", ""),
                    Therapy.Button(:class => "ctrl-btn run-btn",
                        :title => "Run cell (Shift+Enter)",
                        :on_click => _CV_RUN_ONCLICK,
                        RawHtml("""<svg width="10" height="10" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2.5v11l10-5.5z"/></svg>""")),
                    Therapy.Button(:class => "ctrl-btn menu-btn",
                        :title => "Cell actions",
                        :on_click => _CV_MENU_ONCLICK,
                        RawHtml("""<svg width="11" height="11" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="8" cy="3" r="1.2"/><circle cx="8" cy="8" r="1.2"/><circle cx="8" cy="13" r="1.2"/></svg>"""))),
                children...)))
end
