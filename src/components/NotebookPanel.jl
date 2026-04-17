# NotebookPanel.jl — Notebook panel with tab bar + toolbar + cell list
#
# SSR component (not @island) — renders server-side notebook state.
# Tab switching and toolbar actions use direct WS calls via onclick.
# Cell rendering delegates to Sessions.render_cell() and Sessions.CellGap().
#
# All colors via CSS vars from theme.css. Toolbar is a single .nb-pill container.

# SVG icons
const _SVG_JL_WORDMARK = """<svg width="12" height="12" viewBox="0 0 20 20"><circle cx="10" cy="6" r="2.8" fill="#e06b65"/><circle cx="5.5" cy="14" r="2.8" fill="#56d4a0"/><circle cx="14.5" cy="14" r="2.8" fill="#b08fd8"/></svg>"""
const _SVG_RUN_SMALL = """<svg width="9" height="9" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2.5v11l10-5.5z"/></svg>"""
const _SVG_FILE_ICON = """<svg width="12" height="12" viewBox="0 0 20 20" fill="none"><path d="M5 2h7l4 4v12a1 1 0 01-1 1H5a1 1 0 01-1-1V3a1 1 0 011-1z" stroke="currentColor" stroke-width="1.2"/><path d="M12 2v4h4" stroke="currentColor" stroke-width="1.2"/></svg>"""
const _SVG_TAB_CLOSE = """<svg width="10" height="10" viewBox="0 0 10 10" fill="none"><path d="M2.5 2.5L7.5 7.5M7.5 2.5L2.5 7.5" stroke="currentColor" stroke-width="1" stroke-linecap="round"/></svg>"""

function NotebookPanel(state)
    _Sess = Main.Sessions

    tab = state !== nothing ? _Sess.active_tab(state) : nothing

    if tab === nothing
        return Div(:id => "nb-island",
            :class => "flex-1 flex flex-col rounded-xl overflow-hidden min-h-0",
            :style => "background:var(--panel-bg);border:1px solid var(--cell-border);",
            Div(:class => "flex-1 flex items-center text-sm",
                :style => "justify-content:center;color:var(--text-3);",
                "No file loaded"))
    end

    is_file_tab = tab.tab_type == :file
    nb = is_file_tab ? nothing : _Sess.active_nb(state)
    cells = is_file_tab ? _Sess.Cell[] : _Sess.ordered_cells(nb)

    # ═══════════════════════════════════════════════════════════
    # Tab bar: tabs (left, scrollable) + toolbar (right, always visible)
    # ═══════════════════════════════════════════════════════════
    tab_items = Any[]

    # Tabs area (max 55%, scrollable)
    tab_views = Any[]
    for (i, t) in enumerate(state.tabs)
        is_active = (i == state.active_tab_idx)
        tab_name = t.label
        is_jl = endswith(tab_name, ".jl")
        icon_svg = is_jl ? _SVG_JL_WORDMARK : _SVG_FILE_ICON

        close_btn = Span(:class => "tab-close",
            :on_click => "event.stopPropagation();if(confirm('Close?')){window._sessionsShowLoading&&_sessionsShowLoading();TherapyWS.sendMessage('notebook',{action:'close_tab',tab_idx:$(i)})}",
            RawHtml(_SVG_TAB_CLOSE))
        if is_active
            push!(tab_views, Div(
                :class => "tab active relative flex items-center gap-2 font-mono text-xs cursor-pointer",
                :style => "padding-left:16px;padding-right:16px;color:var(--text-1);background:var(--chrome-active);border-right:1px solid var(--divider);",
                :on_click => "TherapyWS.sendMessage('notebook',{action:'switch_tab',tab_idx:$(i)})",
                RawHtml(icon_svg), tab_name,
                Span(:style => "width:5px;height:5px;border-radius:50%;background:var(--accent);"),
                close_btn))
        else
            push!(tab_views, Div(
                :class => "tab relative flex items-center gap-2 font-mono text-xs cursor-pointer",
                :style => "padding-left:16px;padding-right:16px;color:var(--text-3);border-right:1px solid var(--divider);",
                :on_click => "window._sessionsShowLoading&&_sessionsShowLoading();TherapyWS.sendMessage('notebook',{action:'switch_tab',tab_idx:$(i)})",
                RawHtml(icon_svg), tab_name,
                close_btn))
        end
    end
    push!(tab_items, Div(:style => "display:flex;overflow-x:auto;max-width:55%;flex-shrink:1;min-width:0;",
        tab_views...))

    # Toolbar — a single pill container grouping execution + status + file actions.
    # Layout is: [exec group] | [status zone] | [file group].
    # The exec group swaps between an "idle" pair (Run all + Run stale) and a
    # "running" slot (Stop). The status zone is hidden when idle and fills with
    # dot/count/bar/jump-to-cell during run + a transient green-check on finish.
    # Toolbar pill is a kwarg-less Therapy @island (NotebookToolbar) —
    # every dynamic value comes through a shared signal updated by the
    # WS bridge (active_is_file_signal, active_can_format_signal, plus
    # is_executing/is_unsaved/run_progress_*/stale_count/is_formatting).
    # Initial tab-type values are seeded by send_full_state on connect.
    push!(tab_items, Div(:style => "margin-left:auto;padding:0 8px;flex-shrink:0;display:flex;align-items:center;",
        NotebookToolbar()))

    tab_bar = Div(:class => "h-[38px] flex items-stretch shrink-0",
        :style => "background:var(--chrome-bg);border-radius:12px 12px 0 0;",
        tab_items...)

    # ═══════════════════════════════════════════════════════════
    # Content: file editor OR notebook cells
    # ═══════════════════════════════════════════════════════════
    content_area = if is_file_tab
        Div(:class => "flex-1 overflow-y-auto", :id => "nb",
            Div(:class => "file-editor-wrap", :style => "height:100%;",
                Div(:class => "cm-cell cm-file-editor",
                    :data_file_path => tab.path,
                    :data_src => tab.file_content,
                    :style => "height:100%;overflow:auto;")))
    else
        # NotebookIsland @island: SSR'd cells as children, hydrated with signals
        rendered_cells = Any[]
        cell_index = 0
        push!(rendered_cells, _Sess.CellGap(after_cell_id=""))
        for cell in cells
            cell_index += 1
            view = _Sess.render_cell(cell; mode=:live, index=cell_index)
            view === nothing && continue
            push!(rendered_cells, view)
            push!(rendered_cells, _Sess.CellGap(after_cell_id=string(cell.id)))
        end
        NotebookIsland(rendered_cells...)
    end

    # ═══════════════════════════════════════════════════════════
    # Loading overlay — fades out once CM editors initialize
    # ═══════════════════════════════════════════════════════════
    loading_overlay = Div(:id => "nb-loading", :class => "nb-loading",
        Span(:class => "dot-pulse"),
        Span(:class => "dot-pulse"),
        Span(:class => "dot-pulse"))

    # ═══════════════════════════════════════════════════════════
    # Table of Contents (floating fixed panel — PlutoUI parity)
    # ═══════════════════════════════════════════════════════════
    toc_panel = RawHtml("""<nav id="toc-panel" class="sessions-toc aside indent hide">
        <header>
            <span class="toc-toggle open-toc"></span>
            <span class="toc-toggle closed-toc"></span>
            Contents
        </header>
        <section id="toc-content"></section>
    </nav>""")

    # ═══════════════════════════════════════════════════════════
    # Assemble
    # ═══════════════════════════════════════════════════════════
    Div(:id => "nb-island",
        :class => "flex-1 flex flex-col rounded-xl overflow-hidden min-h-0",
        :style => "background:var(--panel-bg);border:1px solid var(--cell-border);position:relative;",
        tab_bar,
        loading_overlay,
        content_area,
        toc_panel)
end
