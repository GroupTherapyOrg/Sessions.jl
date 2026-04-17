# NotebookToolbar.jl — top-of-tab pill (Run all / Run stale / progress / Save / Format)
#
# THERAPY PATTERN (from Therapy.jl/docs/.../DarkModeToggle.jl):
#   Shared-signal islands have NO kwargs. Every kwarg becomes a signal
#   slot that collides with shared-signal slots by index. So for islands
#   that read shared signals, drop kwargs and route every dynamic value
#   through a shared signal updated by the WS bridge.
#
# THERAPY COMPILER LIMITATION:
#   js() args MUST be DIRECT signal-getter results — anything computed
#   by a Julia helper resolves to literal `undefined`. So every effect
#   binds the getter into a local and inlines all branching INSIDE the
#   JS string. (See header of CellView.jl for the longer write-up.)

using Therapy

const _SVG_RUN_TOOLBAR = """<svg width="9" height="9" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2.5v11l10-5.5z"/></svg>"""
const _SVG_STOP_TOOLBAR = """<svg width="9" height="9" viewBox="0 0 16 16" fill="currentColor"><rect x="3" y="3" width="10" height="10" rx="1"/></svg>"""

@island function NotebookToolbar()
    # Shared signals — closure field name = WS bridge key for window.__therapy.set.
    # All 8 read-only here; the WS bridge owns the writes.
    is_executing, _            = is_executing_signal
    is_unsaved, _              = is_unsaved_signal
    run_progress_current, _    = run_progress_current_signal
    run_progress_total, _      = run_progress_total_signal
    stale_count, _             = stale_count_signal
    is_formatting, _           = is_formatting_signal
    active_is_file, _          = active_is_file_signal
    active_can_format, _       = active_can_format_signal

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
        js("""
            var btn=island.querySelector('[data-run-stale]');
            if(btn)btn.className=\$1>0?'pill-btn pill-stale':'pill-btn pill-stale tb-disabled';
            var bd=island.querySelector('[data-stale-badge]');
            if(bd){bd.textContent=String(\$1);bd.style.display=\$1>0?'':'none';}
        """, n)
    end)

    # ── Effect: progress total → wrapper visibility ──
    create_effect(() -> begin
        tot = run_progress_total()
        js("""
            var sep=island.querySelector('[data-pill-sep]');
            var zone=island.querySelector('[data-pill-status]');
            var show=\$1>0;
            if(sep)sep.style.display=show?'':'none';
            if(zone)zone.style.display=show?'':'none';
        """, tot)
    end)

    # ── Effect: progress current → "N / M" label + bar fill ──
    create_effect(() -> begin
        cur = run_progress_current()
        js("""
            var zone=island.querySelector('[data-pill-status]');
            if(!zone||zone.style.display==='none')return;
            var totEl=zone.querySelector('.pill-count');
            var totMatch=totEl?(totEl.textContent.split('/')[1]||'0').trim():'0';
            var tot=parseInt(totMatch,10)||0;
            var cur=\$1;
            var pct=tot>0?Math.max(0,Math.min(100,Math.round(cur*100/tot))):0;
            zone.innerHTML='<span class="pill-dot"></span><span class="pill-count">'+cur+' / '+tot+'</span><div class="pill-bar"><div class="pill-bar-fill" style="width:'+pct+'%"></div></div>';
        """, cur)
    end)

    # ── Effect: save indicator text + class ──
    create_effect(() -> begin
        u = is_unsaved()
        js("""
            var btn=island.querySelector('[data-save-indicator]');
            if(!btn)return;
            btn.textContent=\$1?'\\u25CF Save':'Save';
            btn.className=\$1?'pill-btn pill-ghost pill-unsaved':'pill-btn pill-ghost';
        """, u)
    end)

    # ── Effect: format button text from formatting flag ──
    create_effect(() -> begin
        formatting = is_formatting()
        js("""
            var btn=island.querySelector('[data-format-btn]');
            if(!btn)return;
            btn.textContent=\$1?'Formatting...':'Format';
        """, formatting)
    end)

    # ── Effect: notebook-controls visibility from active-tab type ──
    create_effect(() -> begin
        is_file = active_is_file()
        js("""
            var nc=island.querySelector('[data-notebook-controls]');
            if(nc)nc.style.display=\$1?'none':'';
        """, is_file)
    end)

    # ── Effect: format button enabled state from can_format ──
    create_effect(() -> begin
        cf = active_can_format()
        js("""
            var btn=island.querySelector('[data-format-btn]');
            if(!btn)return;
            if(\$1)btn.classList.remove('tb-disabled');
            else btn.classList.add('tb-disabled');
        """, cf)
    end)

    # ── DOM (initial state — effects update on signal changes) ──
    # Always render every control; effects gate visibility/enabled-state.
    notebook_controls = Div(:class => "nb-toolbar-group",
        Symbol("data-notebook-controls") => "1",
        :style => "display:flex;gap:6px;align-items:center;",
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
            :class => "pill-btn pill-ghost",
            :on_click => "TherapyWS.sendMessage('notebook',{action:'format_active'})",
            :title => "Format",
            "Format"))

    Div(:class => "nb-pill", notebook_controls, save_format)
end
