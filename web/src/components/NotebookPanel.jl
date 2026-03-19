# NotebookPanel.jl — Renders all notebook cells (SSR)
#
# Iterates ordered_cells(nb), renders each with CellView.
# Includes header with notebook filename, save indicator, and toolbar.
# Scrollable container with cell gaps for adding new cells.
#
# Note: Components are included in Therapy's module context by load_app!,
# so we access Sessions via Main.Sessions and state via Main.WEB_STATE.

function NotebookPanel()
    state = if isdefined(Main, :WEB_STATE) && Main.WEB_STATE[] !== nothing
        Main.WEB_STATE[]
    else
        nothing
    end

    nb = state !== nothing ? state.nb : nothing

    if nb === nothing
        return Div(:class => "flex items-center justify-center h-full text-warm-400 dark:text-warm-600",
            "No notebook loaded")
    end

    _Sess = Main.Sessions
    cells = _Sess.ordered_cells(nb)
    nb_name = basename(nb.path)
    cell_count = length(cells)
    done_count = count(c -> c.state == _Sess.cell_done, cells)

    # --- Header toolbar ---
    header = Div(:class => "sticky top-0 z-10 bg-warm-50/95 dark:bg-warm-950/95 backdrop-blur-sm border-b border-warm-200 dark:border-warm-700",
        Div(:class => "flex items-center gap-3 px-4 py-2",
            # Notebook name
            Div(:class => "flex items-center gap-2",
                Span(:class => "font-medium text-sm text-warm-700 dark:text-warm-300", nb_name),
                Span(:class => "text-[10px] text-warm-400 dark:text-warm-600 font-mono",
                    "$(done_count)/$(cell_count) cells")),
            # Spacer
            Div(:class => "flex-1"),
            # Toolbar buttons
            Div(:class => "flex items-center gap-2",
                # Run All
                Therapy.Button(:class => "text-xs font-medium text-warm-500 hover:text-accent-600 dark:hover:text-accent-400 cursor-pointer px-2 py-1 rounded hover:bg-warm-100 dark:hover:bg-warm-800 transition-colors",
                    :on_click => "TherapyWS.sendMessage('notebook', {action: 'run_all'})",
                    "▶ Run All"),
                # Save
                Therapy.Button(:class => "text-xs font-medium text-warm-500 hover:text-accent-600 dark:hover:text-accent-400 cursor-pointer px-2 py-1 rounded hover:bg-warm-100 dark:hover:bg-warm-800 transition-colors",
                    :on_click => "TherapyWS.sendMessage('notebook', {action: 'save'})",
                    "Save"))))

    # --- Cell list ---
    rendered_cells = Any[]
    cell_index = 0

    # Initial "+" gap before first cell
    push!(rendered_cells, CellGap(after_cell_id=""))

    for cell in cells
        isempty(strip(cell.code)) && cell.state == _Sess.cell_idle && continue
        cell_index += 1
        view = CellView(cell; index=cell_index)
        view === nothing && continue
        push!(rendered_cells, view)
        # "+" gap after each cell
        push!(rendered_cells, CellGap(after_cell_id=string(cell.id)))
    end

    Div(:id => "notebook-container",
        header,
        Div(:class => "px-2 py-4 space-y-1 max-w-5xl mx-auto", rendered_cells...))
end
