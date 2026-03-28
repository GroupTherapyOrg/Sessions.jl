# NotebookPanel.jl — Renders the full notebook panel (SSR)
#
# Structure: tab bar (38px) + scrollable cell list
# Contains: tab with .jl wordmark, Run All / Save toolbar, render_cell + CellGap pairs
#
# Color palette:
#   deep=#0a0e14 base=#0f1419 surf=#151c25 island=#1a2332 hov=#1f2b3d
#   b1=#1c2736 b2=#2a3a4f
#   t1=#d4dce8 t2=#9baabd t3=#6b7d93 t4=#3d5068 tout=#7ca0bf
#   accent/jg=#56d4a0 jr=#e06b65 jp=#b08fd8

# .jl wordmark SVG (three-dot Julia logo)
const _SVG_JL_WORDMARK = """<svg width="12" height="12" viewBox="0 0 20 20"><circle cx="10" cy="6" r="2.8" fill="#e06b65"/><circle cx="5.5" cy="14" r="2.8" fill="#56d4a0"/><circle cx="14.5" cy="14" r="2.8" fill="#b08fd8"/></svg>"""

# Run button SVG (small play triangle)
const _SVG_RUN_SMALL = """<svg width="9" height="9" viewBox="0 0 16 16" fill="currentColor" class="text-jg"><path d="M4 2.5v11l10-5.5z"/></svg>"""

function NotebookPanel()
    state = if isdefined(Main, :WEB_STATE) && Main.WEB_STATE[] !== nothing
        Main.WEB_STATE[]
    else
        nothing
    end

    _Sess = Main.Sessions
    tab = state !== nothing ? _Sess.active_tab(state) : nothing

    if tab === nothing
        return Div(:id => "nb-island",
            :class => "flex-1 flex flex-col rounded-xl overflow-hidden min-h-0",
            :style => "background:var(--panel-bg);border:1px solid var(--cell-border);box-shadow:var(--panel-shadow);",
            Div(:class => "flex-1 flex items-center text-sm",
                :style => "justify-content:center;color:var(--text-3);",
                "No file loaded"))
    end

    is_file_tab = tab.tab_type == :file
    nb = is_file_tab ? nothing : _Sess.active_nb(state)
    cells = is_file_tab ? _Sess.Cell[] : _Sess.ordered_cells(nb)

    # ===================================================================
    # Tab bar (38px) — render ALL tabs
    # ===================================================================
    tab_items = Any[]
    for (i, tab) in enumerate(state.tabs)
        is_active = (i == state.active_tab_idx)
        tab_name = tab.label
        is_jl = endswith(tab_name, ".jl")

        # Icon: Julia three-dot for .jl files, generic file icon otherwise
        icon_svg = is_jl ? _SVG_JL_WORDMARK : """<svg width="12" height="12" viewBox="0 0 20 20" fill="none"><path d="M5 2h7l4 4v12a1 1 0 01-1 1H5a1 1 0 01-1-1V3a1 1 0 011-1z" stroke="#4a6178" stroke-width="1.2"/><path d="M12 2v4h4" stroke="#4a6178" stroke-width="1.2"/></svg>"""

        if is_active
            push!(tab_items, Div(
                :class => "tab active relative flex items-center gap-1.5 px-3.5 font-mono text-xs cursor-pointer",
                :style => "color:var(--text-1);background:var(--chrome-active);border-right:1px solid var(--divider);",
                :on_click => "TherapyWS.sendMessage('notebook',{action:'switch_tab',tab_idx:$(i)})",
                RawHtml(icon_svg),
                tab_name,
                Span(:style => "width:5px;height:5px;border-radius:50%;background:var(--accent);"),
                Span(:style => "font-size:14px;color:var(--text-3);margin-left:2px;cursor:pointer;",
                    :on_click => "event.stopPropagation();if(confirm('Close notebook?'))TherapyWS.sendMessage('notebook',{action:'close_tab',tab_idx:$(i)})",
                    "\u00d7")))
        else
            push!(tab_items, Div(
                :class => "tab relative flex items-center gap-1.5 px-3.5 font-mono text-xs cursor-pointer",
                :style => "color:var(--text-3);border-right:1px solid var(--divider);",
                :on_click => "TherapyWS.sendMessage('notebook',{action:'switch_tab',tab_idx:$(i)})",
                RawHtml(icon_svg),
                tab_name,
                Span(:style => "font-size:14px;color:var(--text-3);margin-left:2px;cursor:pointer;",
                    :on_click => "event.stopPropagation();if(confirm('Close notebook?'))TherapyWS.sendMessage('notebook',{action:'close_tab',tab_idx:$(i)})",
                    "\u00d7")))
        end
    end

    # Spacer + Toolbar
    push!(tab_items, Span(:class => "flex-1"))
    toolbar_items = Any[]
    if !is_file_tab
        # Notebook-only buttons: Run Stale, Run All
        sc = nb !== nothing ? _Sess.stale_cells(nb) : _Sess.Cell[]
        n = length(sc)
        push!(toolbar_items,
            Button(:id => "run-stale-btn",
                :class => "tb-btn stale",
                :style => n == 0 ? "display:none;" : "",
                :on_click => "window._sessionsRunStale()",
                :title => "Run stale cells (Ctrl+Shift+Enter)",
                RawHtml("""<svg width="9" height="9" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2.5v11l10-5.5z"/></svg>"""),
                Span(:id => "run-stale-label", n > 0 ? " Run Stale ($n)" : " Run Stale")))
        push!(toolbar_items,
            Button(:id => "run-all-btn",
                :class => "tb-btn",
                :on_click => "window._sessionsRunAll()",
                :title => "Run all cells (Shift+R)",
                RawHtml(_SVG_RUN_SMALL),
                " Run All"))
        push!(toolbar_items,
            Button(:id => "stop-btn",
                :class => "tb-btn stop",
                :style => "display:none;",
                :on_click => "if(window.TherapyWS&&TherapyWS.sendMessage)TherapyWS.sendMessage('notebook',{action:'interrupt'})",
                :title => "Interrupt execution",
                RawHtml("""<svg width="9" height="9" viewBox="0 0 16 16" fill="currentColor"><rect x="3" y="3" width="10" height="10" rx="1"/></svg>"""),
                " Stop"))
        push!(toolbar_items,
            RawHtml("""<span id="run-progress" style="display:none;font-size:11px;color:var(--status-done);font-family:'JetBrains Mono',monospace;"></span>"""))
        push!(toolbar_items, RawHtml("""<span class="toolbar-sep"></span>"""))
    end
    push!(toolbar_items,
        Button(:id => "save-indicator",
            :class => "tb-btn",
            :on_click => "window._sessionsSave()",
            :title => "Save (Ctrl+S)",
            "Save"))
    if !is_file_tab
        push!(toolbar_items,
            Button(Symbol("data-format-btn") => "1",
                :class => "tb-btn",
                :on_click => "if(window.TherapyWS&&TherapyWS.sendMessage)TherapyWS.sendMessage('notebook',{action:'format_all'})",
                :title => "Format all cells (Runic.jl)",
                "Format"))
    end
    push!(tab_items, Div(:class => "flex items-center gap-2 px-2 ml-auto flex-shrink-0", toolbar_items...))

    tab_bar = Div(:class => "h-[38px] flex items-stretch shrink-0",
        :style => "background:var(--chrome-bg);border-bottom:1px solid var(--divider);border-radius:12px 12px 0 0;",
        tab_items...)

    # ===================================================================
    # Content: file editor OR cell list
    # ===================================================================
    content_area = if is_file_tab
        # Plain file editor — single large CodeMirror instance
        Div(:class => "flex-1 overflow-y-auto", :id => "nb",
            Div(:class => "file-editor-wrap",
                :style => "height:100%;",
                Div(:class => "cm-cell cm-file-editor",
                    :data_file_path => tab.path,
                    :data_src => tab.file_content,
                    :style => "height:100%;overflow:auto;")))
    else
        # Notebook cell list
        rendered_cells = Any[]
        cell_index = 0
        push!(rendered_cells, Main.Sessions.CellGap(after_cell_id=""))
        for cell in cells
            cell_index += 1
            view = Main.Sessions.render_cell(cell; mode=:live, index=cell_index)
            view === nothing && continue
            push!(rendered_cells, view)
            push!(rendered_cells, Main.Sessions.CellGap(after_cell_id=string(cell.id)))
        end
        Div(:class => "flex-1 overflow-y-auto px-5 pt-3 pb-8", :id => "nb",
            Div(:style => "max-width:900px;margin:0 auto;padding-left:28px;",
                rendered_cells...))
    end

    # ===================================================================
    # Assemble
    # ===================================================================
    Div(:id => "nb-island",
        :class => "flex-1 flex flex-col rounded-xl overflow-hidden min-h-0",
            :style => "background:var(--panel-bg);border:1px solid var(--cell-border);box-shadow:var(--panel-shadow);",
        tab_bar,
        content_area)
end
