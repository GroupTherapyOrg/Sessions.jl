# NotebookToolbar.jl — top-of-tab pill (Run all / Run stale / progress / Save / Format)
#
# Pure-declarative Therapy @island. NO js() blocks — every dynamic
# part of the UI is expressed with Therapy primitives:
#   • `Show(() -> cond)` for conditional groups (toolbar mode flip,
#     progress zone visibility, stale badge visibility)
#   • `:class => () -> ...` reactive class binding for button
#     enable/disable state
#   • `:style => () -> ...` reactive style binding for the progress bar
#     fill width
#   • `() -> "text"` reactive text-node binding for counts and labels
#
# The compiler turns each of these into a WASM effect that re-runs
# automatically when its signals change. State arrives from the page-
# level signals declared in NotebookSignals.jl; the WS bridge writes
# them via `window.__therapy.set('<name>', v)` — no per-island JS
# listeners, no manual flush.

using Therapy

const _SVG_RUN_TOOLBAR = """<svg width="9" height="9" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2.5v11l10-5.5z"/></svg>"""
const _SVG_STOP_TOOLBAR = """<svg width="9" height="9" viewBox="0 0 16 16" fill="currentColor"><rect x="3" y="3" width="10" height="10" rx="1"/></svg>"""

@island function NotebookToolbar(; is_file_tab::Int=0, can_format::Int=1)
    # ── Shared signal subscriptions ──
    # Names below MUST match what NotebookSignals.jl exports (after
    # destructuring) so window.__therapy.set('is_executing', …) etc.
    # actually wakes us up.
    is_executing, _            = is_executing_signal
    is_unsaved, _              = is_unsaved_signal
    run_progress_current, _    = run_progress_current_signal
    run_progress_total, _      = run_progress_total_signal
    stale_count, _             = stale_count_signal
    is_formatting, _           = is_formatting_signal

    # ── Notebook-tab-only group: run controls + progress ──
    notebook_controls = is_file_tab == 1 ? nothing : Fragment(
        # Idle mode: Run all + Run stale (with reactive enable + count badge)
        Show(() -> is_executing() == 0) do
            Div(:class => "pill-group",
                Therapy.Button(:class => "pill-btn pill-primary",
                    :on_click => "window._sessionsRunAll()",
                    :title => "Run all cells",
                    RawHtml(_SVG_RUN_TOOLBAR), " Run all"),
                Therapy.Button(
                    :class => () -> stale_count() > 0 ?
                        "pill-btn pill-stale" : "pill-btn pill-stale tb-disabled",
                    :on_click => "window._sessionsRunStale()",
                    :title => "Run stale cells",
                    RawHtml(_SVG_RUN_TOOLBAR), " Run stale",
                    Show(() -> stale_count() > 0) do
                        Span(:class => "pill-count-badge",
                            () -> string(stale_count()))
                    end))
        end,
        # Running mode: Stop button
        Show(() -> is_executing() == 1) do
            Div(:class => "pill-group",
                Therapy.Button(:class => "pill-btn pill-stop",
                    :on_click => "TherapyWS.sendMessage('notebook',{action:'interrupt'})",
                    :title => "Stop execution",
                    RawHtml(_SVG_STOP_TOOLBAR), " Stop"))
        end,
        # Progress zone — separator + status pill — visible whenever
        # there's an active total
        Show(() -> run_progress_total() > 0) do
            Fragment(
                RawHtml("""<span class="pill-sep"></span>"""),
                Div(:class => "pill-status",
                    Span(:class => "pill-dot"),
                    Span(:class => "pill-count",
                        () -> string(run_progress_current(), " / ",
                                     run_progress_total())),
                    Div(:class => "pill-bar",
                        Div(:class => "pill-bar-fill",
                            :style => () -> string("width:",
                                round(Int, run_progress_current() * 100 /
                                    max(1, run_progress_total())), "%")))))
        end,
        RawHtml("""<span class="pill-sep"></span>"""))

    # ── Save + Format (always present) ──
    save_format = Div(:class => "pill-group",
        Therapy.Button(
            :class => () -> is_unsaved() == 1 ?
                "pill-btn pill-ghost pill-unsaved" : "pill-btn pill-ghost",
            :on_click => "window._sessionsSave()",
            :title => "Save (Ctrl+S)",
            () -> is_unsaved() == 1 ? "● Save" : "Save"),
        Therapy.Button(Symbol("data-format-btn") => "1",
            :class => () -> begin
                base = "pill-btn pill-ghost"
                if can_format == 0 || is_formatting() == 1
                    base *= " tb-disabled"
                end
                base
            end,
            :on_click => is_file_tab == 1 ?
                "TherapyWS.sendMessage('notebook',{action:'format_file'})" :
                "TherapyWS.sendMessage('notebook',{action:'format_all'})",
            :title => is_file_tab == 1 ? "Format file" : "Format all cells",
            () -> is_formatting() == 1 ? "Formatting..." : "Format"))

    Div(:class => "nb-pill", notebook_controls, save_format)
end
