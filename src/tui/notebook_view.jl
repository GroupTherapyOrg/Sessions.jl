# TUI: Notebook view — renders all cells + outputs in a scrollable layout

"""
Renders the notebook as a vertical list of cell widgets + output widgets.
Manages scrolling and focus.
"""
mutable struct NotebookView
    nb::Notebook
    cell_widgets::Vector{CellWidget}
    output_widgets::Vector{OutputWidget}
    focused_idx::Int
    scroll_offset::Int
end

function NotebookView(nb::Notebook)
    cells = ordered_cells(nb)
    cell_widgets = [CellWidget(c; focused=(i == 1)) for (i, c) in enumerate(cells)]
    output_widgets = [OutputWidget(c) for c in cells]
    NotebookView(nb, cell_widgets, output_widgets, 1, 0)
end

"""Rebuild widgets when cells change."""
function rebuild_widgets!(nv::NotebookView)
    cells = ordered_cells(nv.nb)
    old_focused_id = if !isempty(nv.cell_widgets) && nv.focused_idx <= length(nv.cell_widgets)
        nv.cell_widgets[nv.focused_idx].cell.id
    else
        nothing
    end

    nv.cell_widgets = [CellWidget(c) for c in cells]
    nv.output_widgets = [OutputWidget(c) for c in cells]

    nv.focused_idx = 1
    if old_focused_id !== nothing
        for (i, cw) in enumerate(nv.cell_widgets)
            if cw.cell.id == old_focused_id
                nv.focused_idx = i
                break
            end
        end
    end
    update_focus!(nv)
end

"""Update which cell widget is focused."""
function update_focus!(nv::NotebookView)
    for (i, cw) in enumerate(nv.cell_widgets)
        cw.focused = (i == nv.focused_idx)
    end
end

"""Move focus to next cell."""
function focus_next!(nv::NotebookView)
    if nv.focused_idx < length(nv.cell_widgets)
        nv.focused_idx += 1
        update_focus!(nv)
    end
end

"""Move focus to previous cell."""
function focus_prev!(nv::NotebookView)
    if nv.focused_idx > 1
        nv.focused_idx -= 1
        update_focus!(nv)
    end
end

"""Get the currently focused cell widget."""
function focused_widget(nv::NotebookView)
    isempty(nv.cell_widgets) ? nothing : nv.cell_widgets[nv.focused_idx]
end

"""Get the currently focused cell."""
function focused_cell(nv::NotebookView)
    cw = focused_widget(nv)
    cw === nothing ? nothing : cw.cell
end

"""Add a new cell after the focused cell."""
function add_cell_after_focus!(nv::NotebookView)
    idx = nv.focused_idx + 1
    cell = Cell()
    insert_cell!(nv.nb, idx, cell)
    rebuild_widgets!(nv)
    nv.focused_idx = idx
    update_focus!(nv)
end

"""Delete the focused cell (if more than one cell exists)."""
function delete_focused_cell!(nv::NotebookView)
    length(nv.cell_widgets) <= 1 && return
    cell = focused_cell(nv)
    cell === nothing && return
    remove_cell!(nv.nb, cell.id)
    nv.focused_idx = min(nv.focused_idx, length(nv.nb))
    rebuild_widgets!(nv)
end

function Tachikoma.render(nv::NotebookView, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    isempty(nv.cell_widgets) && return

    y = rect.y - nv.scroll_offset
    visible_start = rect.y
    visible_end = rect.y + rect.height - 1

    for i in eachindex(nv.cell_widgets)
        cw = nv.cell_widgets[i]
        ow = nv.output_widgets[i]

        ch = cell_height(cw)
        oh = output_height(ow)

        if y + ch > visible_start && y <= visible_end
            cell_rect = Tachikoma.Rect(rect.x, max(y, visible_start), rect.width,
                            min(ch, visible_end - max(y, visible_start) + 1))
            Tachikoma.render(cw, cell_rect, buf)
        end
        y += ch

        if oh > 0
            if y + oh > visible_start && y <= visible_end
                out_rect = Tachikoma.Rect(rect.x, max(y, visible_start), rect.width,
                                min(oh, visible_end - max(y, visible_start) + 1))
                Tachikoma.render(ow, out_rect, buf)
            end
            y += oh
        end

        y += 1  # gap between cells
    end

    ensure_visible!(nv, rect)
end

"""Adjust scroll_offset so the focused cell is visible."""
function ensure_visible!(nv::NotebookView, rect::Tachikoma.Rect)
    isempty(nv.cell_widgets) && return

    y = 0
    for i in 1:nv.focused_idx-1
        y += cell_height(nv.cell_widgets[i])
        y += output_height(nv.output_widgets[i])
        y += 1
    end

    focused_h = cell_height(nv.cell_widgets[nv.focused_idx])

    if y < nv.scroll_offset
        nv.scroll_offset = y
    end

    if y + focused_h > nv.scroll_offset + rect.height
        nv.scroll_offset = y + focused_h - rect.height
    end
end
