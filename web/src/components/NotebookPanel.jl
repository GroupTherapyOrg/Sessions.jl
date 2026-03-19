# NotebookPanel.jl — Renders all notebook cells (SSR)
#
# Matches the TUI notebook aesthetic: tab bar, cell list, toolbar.
# Uses inline styles for reliability.

function NotebookPanel()
    state = if isdefined(Main, :WEB_STATE) && Main.WEB_STATE[] !== nothing
        Main.WEB_STATE[]
    else
        nothing
    end

    nb = state !== nothing ? state.nb : nothing

    if nb === nothing
        return Div(:style => "display: flex; align-items: center; justify-content: center; height: 100%; color: #4e5157; font-size: 14px;",
            "No notebook loaded")
    end

    _Sess = Main.Sessions
    cells = _Sess.ordered_cells(nb)
    nb_name = basename(nb.path)
    cell_count = length(cells)
    done_count = count(c -> c.state == _Sess.cell_done, cells)

    # --- Tab bar ---
    tab_bar = Div(:style => "display: flex; align-items: center; background: #181a1d; border-bottom: 1px solid #2b2d30; padding: 0; height: 36px; flex-shrink: 0;",
        # Active tab
        Div(:style => "display: flex; align-items: center; gap: 6px; padding: 0 16px; height: 100%; background: #121216; border-right: 1px solid #2b2d30; font-size: 12px; color: #bcbec4;",
            Span(:style => "color: #389826;", "◆"),
            Span(nb_name),
            Span(:style => "color: #4e5157; cursor: pointer; margin-left: 8px; font-size: 10px;", "×")),
        # Spacer
        Div(:style => "flex: 1;"),
        # Status + toolbar
        Div(:style => "display: flex; align-items: center; gap: 12px; padding-right: 12px; font-size: 12px;",
            # Cell counter
            Span(:style => "color: #7a7e85; font-family: 'JuliaMono', monospace; font-size: 11px;",
                "$(done_count)/$(cell_count)"),
            # Save button
            Therapy.Button(:style => "background: none; border: none; color: #7a7e85; cursor: pointer; font-size: 12px; padding: 4px 8px; border-radius: 4px;",
                :id => "save-indicator",
                :on_click => "TherapyWS.sendMessage('notebook', {action: 'save'})",
                "Save")))

    # --- Cell list ---
    rendered_cells = Any[]
    cell_index = 0

    # Initial add-cell gap
    push!(rendered_cells, CellGap(after_cell_id=""))

    for cell in cells
        isempty(strip(cell.code)) && cell.state == _Sess.cell_idle && continue
        cell_index += 1
        view = CellView(cell; index=cell_index)
        view === nothing && continue
        push!(rendered_cells, view)
        push!(rendered_cells, CellGap(after_cell_id=string(cell.id)))
    end

    # Run All button at bottom
    push!(rendered_cells,
        Div(:style => "display: flex; justify-content: flex-end; padding: 8px 24px 24px;",
            Therapy.Button(:style => "background: none; border: none; color: #389826; cursor: pointer; font-size: 12px; font-weight: 600; padding: 6px 12px; border-radius: 4px; display: flex; align-items: center; gap: 4px;",
                :on_click => "TherapyWS.sendMessage('notebook', {action: 'run_all'})",
                "▶ Run All")))

    Div(:id => "notebook-container", :style => "display: flex; flex-direction: column; height: 100%;",
        tab_bar,
        Div(:style => "flex: 1; overflow-y: auto; padding: 0;", rendered_cells...))
end
