# NotebookToolbar.jl — top-of-tab pill (Run all / Run stale / progress / Save / Format)
#
# Pattern (same as CellView): static SSR for initial render +
# `create_effect(... js("...", value))` per visual concern. The
# if/else logic lives in JULIA inside each effect; the js() block is
# a single-line DOM write. Re-runs automatically when subscribed
# signals change. NOT JS soup — one focused effect per derived state.
#
# Therapy compiler limitation: `:class => () -> ...`, reactive
# text-node bare callables, and reactive `:style => () -> ...` for
# arbitrary string expressions are silently STATIC (audit-confirmed).
# So we can't write the toolbar in pure declarative form; the
# create_effect+js pattern is the working Therapy idiom. Logic in
# Julia, DOM write via single js() = clean.

using Therapy

const _SVG_RUN_TOOLBAR = """<svg width="9" height="9" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2.5v11l10-5.5z"/></svg>"""
const _SVG_STOP_TOOLBAR = """<svg width="9" height="9" viewBox="0 0 16 16" fill="currentColor"><rect x="3" y="3" width="10" height="10" rx="1"/></svg>"""

# ── Pure Julia helpers (run in WASM via the effects below) ──

function _tb_progress_html(cur::Int, tot::Int)::String
    tot <= 0 && return ""
    pct = max(0, min(100, round(Int, cur * 100 / max(1, tot))))
    string(
        """<span class="pill-dot"></span>""",
        """<span class="pill-count">""", cur, " / ", tot, "</span>",
        """<div class="pill-bar"><div class="pill-bar-fill" style="width:""", pct, """%"></div></div>""")
end

@island function NotebookToolbar(; is_file_tab::Int=0, can_format::Int=1)
    # Shared signals (closure field name = WS bridge key for __therapy.set)
    is_executing, _            = is_executing_signal
    is_unsaved, _              = is_unsaved_signal
    run_progress_current, _    = run_progress_current_signal
    run_progress_total, _      = run_progress_total_signal
    stale_count, _             = stale_count_signal
    is_formatting, _           = is_formatting_signal

    # ── Effect: pill-mode flip (idle group vs running group) ──
    create_effect(() -> begin
        running = is_executing()
        js("""
            var idle=island.querySelector('[data-pill-mode="idle"]');
            var run=island.querySelector('[data-pill-mode="running"]');
            if(idle)idle.style.display=\$1?'none':'';
            if(run) run.style.display =\$1?'':'none';
        """, running)
    end)

    # ── Effect: stale-count badge text + run-stale enable ──
    create_effect(() -> begin
        n = stale_count()
        # Build the class string + count string in Julia.
        run_stale_cls = n > 0 ? "pill-btn pill-stale" : "pill-btn pill-stale tb-disabled"
        badge_display = n > 0 ? "" : "none"
        # One js() that applies all of it.
        js("""
            var btn=island.querySelector('[data-run-stale]');
            if(btn)btn.className=\$1;
            var bd=island.querySelector('[data-stale-badge]');
            if(bd){bd.textContent=String(\$2);bd.style.display=\$3;}
        """, run_stale_cls, n, badge_display)
    end)

    # ── Effect: progress pill (innerHTML built in Julia, written in one js()) ──
    create_effect(() -> begin
        cur = run_progress_current()
        tot = run_progress_total()
        body = _tb_progress_html(cur, tot)
        # Toggle the wrapper visibility too (sep + status zone)
        show_display = tot > 0 ? "" : "none"
        js("""
            var sep=island.querySelector('[data-pill-sep]');
            var zone=island.querySelector('[data-pill-status]');
            if(sep)sep.style.display=\$1;
            if(zone){zone.style.display=\$1;zone.innerHTML=\$2;}
        """, show_display, body)
    end)

    # ── Effect: save indicator text + class ──
    create_effect(() -> begin
        u = is_unsaved()
        save_text = u == 1 ? "● Save" : "Save"
        save_cls  = u == 1 ? "pill-btn pill-ghost pill-unsaved" : "pill-btn pill-ghost"
        js("""
            var btn=island.querySelector('[data-save-indicator]');
            if(btn){btn.textContent=\$1;btn.className=\$2;}
        """, save_text, save_cls)
    end)

    # ── Effect: format button text + class ──
    create_effect(() -> begin
        formatting = is_formatting()
        fmt_text = formatting == 1 ? "Formatting..." : "Format"
        fmt_cls = if can_format == 0 || formatting == 1
            "pill-btn pill-ghost tb-disabled"
        else
            "pill-btn pill-ghost"
        end
        js("""
            var btn=island.querySelector('[data-format-btn]');
            if(btn){btn.textContent=\$1;btn.className=\$2;}
        """, fmt_text, fmt_cls)
    end)

    # ── DOM (initial state — effects update on signal changes) ──
    notebook_controls = is_file_tab == 1 ? nothing : Fragment(
        Div(:class => "pill-group", Symbol("data-pill-mode") => "idle",
            Therapy.Button(:id => "run-all-btn", :class => "pill-btn pill-primary",
                :on_click => "window._sessionsRunAll()",
                :title => "Run all cells",
                RawHtml(_SVG_RUN_TOOLBAR), " Run all"),
            Therapy.Button(:id => "run-stale-btn",
                :class => "pill-btn pill-stale tb-disabled",
                Symbol("data-run-stale") => "1",
                :on_click => "window._sessionsRunStale()",
                :title => "Run stale cells",
                RawHtml(_SVG_RUN_TOOLBAR), " Run stale",
                Span(:class => "pill-count-badge",
                    Symbol("data-stale-badge") => "1",
                    :style => "display:none", "0"))),
        Div(:class => "pill-group", Symbol("data-pill-mode") => "running",
            :style => "display:none",
            Therapy.Button(:id => "stop-btn", :class => "pill-btn pill-stop",
                :on_click => "TherapyWS.sendMessage('notebook',{action:'interrupt'})",
                :title => "Stop execution",
                RawHtml(_SVG_STOP_TOOLBAR), " Stop")),
        RawHtml("""<span class="pill-sep" data-pill-sep="1" style="display:none"></span><div class="pill-status" data-pill-status="1" style="display:none"></div>"""),
        RawHtml("""<span class="pill-sep"></span>"""))

    save_format = Div(:class => "pill-group",
        Therapy.Button(:id => "save-indicator", :class => "pill-btn pill-ghost",
            Symbol("data-save-indicator") => "1",
            :on_click => "window._sessionsSave()",
            :title => "Save (Ctrl+S)",
            "Save"),
        Therapy.Button(Symbol("data-format-btn") => "1",
            :class => can_format == 1 ? "pill-btn pill-ghost" : "pill-btn pill-ghost tb-disabled",
            :on_click => is_file_tab == 1 ?
                "TherapyWS.sendMessage('notebook',{action:'format_file'})" :
                "TherapyWS.sendMessage('notebook',{action:'format_all'})",
            :title => is_file_tab == 1 ? "Format file" : "Format all cells",
            "Format"))

    Div(:class => "nb-pill", notebook_controls, save_format)
end
