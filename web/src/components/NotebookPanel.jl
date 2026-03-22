# NotebookPanel.jl — Renders the full notebook panel (SSR)
#
# Structure: tab bar (38px) + scrollable cell list
# Contains: tab with .jl wordmark, Run All / Save toolbar, CellGap + CellView pairs
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

    nb = state !== nothing ? Main.Sessions.active_nb(state) : nothing

    if nb === nothing
        return Div(:id => "nb-island",
            :class => "flex-1 flex flex-col bg-surf border border-b1 rounded-xl overflow-hidden min-h-0 shadow-lg shadow-black/25",
            Div(:class => "flex-1 flex items-center justify-content-center text-t3 text-sm",
                :style => "justify-content:center",
                "No notebook loaded"))
    end

    _Sess = Main.Sessions
    cells = _Sess.ordered_cells(nb)

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
                :class => "tab active relative flex items-center gap-1.5 px-3.5 font-mono text-xs text-t1 bg-surf border-r border-b1 cursor-pointer",
                :on_click => "TherapyWS.sendMessage('notebook',{action:'switch_tab',tab_idx:$(i)})",
                RawHtml(icon_svg),
                tab_name,
                # Modified dot (accent green)
                Span(:class => "w-[5px] h-[5px] rounded-full bg-accent"),
                # Close button
                Span(:class => "text-sm text-t4 ml-0.5 leading-none hover:text-t2 cursor-pointer",
                    :on_click => "event.stopPropagation();if(confirm('Close notebook?'))TherapyWS.sendMessage('notebook',{action:'close_tab',tab_idx:$(i)})",
                    "\u00d7")))  # x
        else
            push!(tab_items, Div(
                :class => "tab relative flex items-center gap-1.5 px-3.5 font-mono text-xs text-t3 border-r border-b1 cursor-pointer hover:text-t2",
                :on_click => "TherapyWS.sendMessage('notebook',{action:'switch_tab',tab_idx:$(i)})",
                RawHtml(icon_svg),
                tab_name,
                # Close button
                Span(:class => "text-sm text-t4 ml-0.5 leading-none hover:text-t2 cursor-pointer",
                    :on_click => "event.stopPropagation();if(confirm('Close notebook?'))TherapyWS.sendMessage('notebook',{action:'close_tab',tab_idx:$(i)})",
                    "\u00d7")))  # x
        end
    end

    # Spacer + Toolbar
    push!(tab_items, Span(:class => "flex-1"))
    push!(tab_items, Div(:class => "flex items-center gap-2 px-3.5",
        # Run Stale button — always in DOM, hidden when no stale cells.
        # Server broadcasts stale_count after execution to show/hide.
        let sc = _Sess.stale_cells(nb), n = length(sc)
            Button(:id => "run-stale-btn",
                :class => "flex items-center gap-1.5 bg-island border border-b2 rounded px-2.5 py-[3px] text-[11px] font-sans cursor-pointer hover:bg-hov transition-colors",
                :style => "color:#d4a056;" * (n == 0 ? "display:none;" : ""),
                :on_click => "window._sessionsRunStale()",
                :title => "Run stale cells (Ctrl+Shift+Enter)",
                RawHtml("""<svg width="9" height="9" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2.5v11l10-5.5z"/></svg>"""),
                Span(:id => "run-stale-label", n > 0 ? " Run Stale ($n)" : " Run Stale"))
        end,
        # Run All button
        Button(:class => "flex items-center gap-1.5 bg-island border border-b2 rounded px-2.5 py-[3px] text-[11px] text-t2 font-sans cursor-pointer hover:bg-hov hover:text-t1 transition-colors",
            :on_click => "window._sessionsRunAll()",
            :title => "Run all cells (Shift+R)",
            RawHtml(_SVG_RUN_SMALL),
            " Run All"),
        # Save button
        Button(:id => "save-indicator",
            :class => "bg-island border border-b2 rounded px-3 py-[3px] text-[11px] text-t2 font-sans cursor-pointer hover:bg-hov hover:text-t1 transition-colors",
            :on_click => "window._sessionsSave()",
            :title => "Save (Ctrl+S)",
            "Save")))

    tab_bar = Div(:class => "h-[38px] flex items-stretch bg-deep border-b border-b1 shrink-0",
        tab_items...)

    # ===================================================================
    # Cell list
    # ===================================================================
    rendered_cells = Any[]
    cell_index = 0

    # Initial gap
    push!(rendered_cells, CellGap(after_cell_id=""))

    for cell in cells
        cell_index += 1
        view = CellView(cell; index=cell_index)
        view === nothing && continue
        push!(rendered_cells, view)
        push!(rendered_cells, CellGap(after_cell_id=string(cell.id)))
    end

    # ===================================================================
    # Assemble
    # ===================================================================
    Div(:id => "nb-island",
        :class => "flex-1 flex flex-col bg-surf border border-b1 rounded-xl overflow-hidden min-h-0 shadow-lg shadow-black/25",
        tab_bar,
        Div(:class => "flex-1 overflow-y-auto px-5 pt-3 pb-8", :id => "nb",
            Div(:style => "max-width:900px;margin:0 auto;padding-left:28px;",
                rendered_cells...)))
end
