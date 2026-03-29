# Notebook.jl — Notebook cell rendering component
#
# Phase A: Renders cells server-side via Sessions.render_cell() + Sessions.CellGap().
# The CM init and WS channel handler scripts remain in Layout.jl for now
# (they work globally and moving them is a separate cleanup step).
#
# Phase B (future): Becomes a true @island with cell signals, For(),
# and optimistic updates for one-click publishing.

"""
    NotebookContent(state) -> VNode

Render the notebook content area: cell list with gaps.
Called by NotebookPanel for notebook tabs (not file tabs).
"""
function NotebookContent(state)
    _Sess = Main.Sessions
    nb = _Sess.active_nb(state)
    cells = _Sess.ordered_cells(nb)

    rendered = Any[]
    cell_index = 0
    push!(rendered, _Sess.CellGap(after_cell_id=""))
    for cell in cells
        cell_index += 1
        view = _Sess.render_cell(cell; mode=:live, index=cell_index)
        view === nothing && continue
        push!(rendered, view)
        push!(rendered, _Sess.CellGap(after_cell_id=string(cell.id)))
    end

    Div(:class => "flex-1 overflow-y-auto px-5 pt-3 pb-8", :id => "nb",
        Div(:style => "max-width:900px;margin:0 auto;padding-left:28px;",
            rendered...))
end
