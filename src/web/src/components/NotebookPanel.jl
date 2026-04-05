# NotebookPanel.jl — Notebook panel with tab bar + toolbar + cell list
#
# SSR component (not @island) — renders server-side notebook state.
# Tab switching and toolbar actions use direct WS calls via onclick.
# Cell rendering delegates to Sessions.render_cell() and Sessions.CellGap().
#
# All colors via CSS vars from theme.css. Ghost toolbar buttons via .tb-btn class.

# SVG icons
const _SVG_JL_WORDMARK = """<svg width="12" height="12" viewBox="0 0 20 20"><circle cx="10" cy="6" r="2.8" fill="#e06b65"/><circle cx="5.5" cy="14" r="2.8" fill="#56d4a0"/><circle cx="14.5" cy="14" r="2.8" fill="#b08fd8"/></svg>"""
const _SVG_RUN_SMALL = """<svg width="9" height="9" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2.5v11l10-5.5z"/></svg>"""
const _SVG_FILE_ICON = """<svg width="12" height="12" viewBox="0 0 20 20" fill="none"><path d="M5 2h7l4 4v12a1 1 0 01-1 1H5a1 1 0 01-1-1V3a1 1 0 011-1z" stroke="currentColor" stroke-width="1.2"/><path d="M12 2v4h4" stroke="currentColor" stroke-width="1.2"/></svg>"""

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

        if is_active
            push!(tab_views, Div(
                :class => "tab active relative flex items-center gap-1.5 px-3.5 font-mono text-xs cursor-pointer",
                :style => "color:var(--text-1);background:var(--chrome-active);border-right:1px solid var(--divider);",
                :on_click => "TherapyWS.sendMessage('notebook',{action:'switch_tab',tab_idx:$(i)})",
                RawHtml(icon_svg), tab_name,
                Span(:style => "width:5px;height:5px;border-radius:50%;background:var(--accent);"),
                Span(:style => "font-size:14px;color:var(--text-3);margin-left:2px;cursor:pointer;",
                    :on_click => "event.stopPropagation();if(confirm('Close?'))TherapyWS.sendMessage('notebook',{action:'close_tab',tab_idx:$(i)})",
                    "\u00d7")))
        else
            push!(tab_views, Div(
                :class => "tab relative flex items-center gap-1.5 px-3.5 font-mono text-xs cursor-pointer",
                :style => "color:var(--text-3);border-right:1px solid var(--divider);",
                :on_click => "window._sessionsShowLoading&&_sessionsShowLoading();TherapyWS.sendMessage('notebook',{action:'switch_tab',tab_idx:$(i)})",
                RawHtml(icon_svg), tab_name,
                Span(:style => "font-size:14px;color:var(--text-3);margin-left:2px;cursor:pointer;",
                    :on_click => "event.stopPropagation();if(confirm('Close?'))TherapyWS.sendMessage('notebook',{action:'close_tab',tab_idx:$(i)})",
                    "\u00d7")))
        end
    end
    push!(tab_items, Div(:style => "display:flex;overflow-x:auto;max-width:55%;flex-shrink:1;min-width:0;",
        tab_views...))

    # Toolbar (right, always visible) — ghost buttons
    toolbar = Any[]
    if !is_file_tab
        sc = nb !== nothing ? _Sess.stale_cells(nb) : _Sess.Cell[]
        n = length(sc)
        push!(toolbar, Button(:id => "run-stale-btn", :class => n == 0 ? "tb-btn stale tb-disabled" : "tb-btn stale",
            :on_click => "window._sessionsRunStale()",
            :title => "Run stale cells",
            RawHtml(_SVG_RUN_SMALL),
            Span(:id => "run-stale-label", n > 0 ? " Run Stale ($n)" : " Run Stale")))
        push!(toolbar, Button(:id => "run-all-btn", :class => "tb-btn",
            :on_click => "window._sessionsRunAll()",
            :title => "Run all cells",
            RawHtml(_SVG_RUN_SMALL), " Run All"))
        push!(toolbar, Button(:id => "stop-btn", :class => "tb-btn stop tb-disabled",
            :on_click => "TherapyWS.sendMessage('notebook',{action:'interrupt'})",
            :title => "Stop execution",
            RawHtml("""<svg width="9" height="9" viewBox="0 0 16 16" fill="currentColor"><rect x="3" y="3" width="10" height="10" rx="1"/></svg>"""),
            " Stop"))
        push!(toolbar, RawHtml("""<span id="run-progress" style="font-size:11px;color:var(--status-done);font-family:'JetBrains Mono',monospace;"></span><button id="jump-running-btn" class="tb-btn tb-disabled" onclick="window._sessionsJumpToRunning&&_sessionsJumpToRunning()" title="Jump to running cell" style="padding:2px 6px;font-size:10px;"><svg width="10" height="10" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M8 3v10M4 9l4 4 4-4"/></svg></button>"""))
        push!(toolbar, RawHtml("""<span class="toolbar-sep"></span>"""))
    end
    push!(toolbar, Button(:id => "save-indicator", :class => "tb-btn",
        :on_click => "window._sessionsSave()",
        :title => "Save (Ctrl+S)", "Save"))
    is_jl_file = is_file_tab && endswith(tab.path, ".jl")
    can_format = !is_file_tab || is_jl_file  # notebooks always, files only .jl
    push!(toolbar, Button(Symbol("data-format-btn") => "1",
        :class => can_format ? "tb-btn" : "tb-btn tb-disabled",
        :on_click => is_file_tab ?
            "TherapyWS.sendMessage('notebook',{action:'format_file'})" :
            "TherapyWS.sendMessage('notebook',{action:'format_all'})",
        :title => is_file_tab ? "Format file" : "Format all cells", "Format"))
    if !is_file_tab
        push!(toolbar, RawHtml("""<span class="toolbar-sep"></span>"""))
        push!(toolbar, Button(:id => "toc-toggle-btn", :class => "tb-btn",
            :on_click => "window._sessionsToggleToc&&_sessionsToggleToc()",
            :title => "Table of Contents",
            RawHtml("""<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M2 3h12M2 8h8M2 13h10"/></svg>"""),
            " ToC"))
    end
    push!(tab_items, Div(:style => "display:flex;align-items:center;gap:2px;padding:0 8px;margin-left:auto;flex-shrink:0;",
        toolbar...))

    tab_bar = Div(:class => "h-[38px] flex items-stretch shrink-0",
        :style => "background:var(--chrome-bg);border-bottom:1px solid var(--divider);border-radius:12px 12px 0 0;",
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
    # Table of Contents panel (inside notebook, right sidebar)
    # ═══════════════════════════════════════════════════════════
    toc_panel = Div(:id => "toc-panel",
        :style => "display:none;width:220px;flex-shrink:0;overflow-y:auto;border-left:1px solid var(--divider);",
        Div(:style => "font-size:10px;font-weight:600;text-transform:uppercase;letter-spacing:.5px;color:var(--text-3);padding:10px 12px 6px;", "Contents"),
        Div(:id => "toc-content", :style => "padding:0 4px 8px;"))

    # ═══════════════════════════════════════════════════════════
    # Assemble — content + ToC in a flex-row
    # ═══════════════════════════════════════════════════════════
    content_with_toc = Div(:class => "flex flex-1 min-h-0 overflow-hidden",
        content_area,
        toc_panel)

    Div(:id => "nb-island",
        :class => "flex-1 flex flex-col rounded-xl overflow-hidden min-h-0",
        :style => "background:var(--panel-bg);border:1px solid var(--cell-border);position:relative;",
        tab_bar,
        loading_overlay,
        content_with_toc)
end
