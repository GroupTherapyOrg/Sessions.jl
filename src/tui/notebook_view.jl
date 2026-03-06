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
    viewport::Tachikoma.Rect   # stored during render for mouse hit testing
end

function NotebookView(nb::Notebook)
    cells = ordered_cells(nb)
    cell_widgets = [CellWidget(c; focused=(i == 1)) for (i, c) in enumerate(cells)]
    output_widgets = [OutputWidget(c) for c in cells]
    NotebookView(nb, cell_widgets, output_widgets, 1, 0, Tachikoma.Rect())
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

"""Move the focused cell up (swap with previous). Focus follows the cell."""
function move_cell_up!(nv::NotebookView)
    swap_cell_up!(nv.nb, nv.focused_idx) || return
    rebuild_widgets!(nv)  # rebuild_widgets! tracks focused cell by ID
end

"""Move the focused cell down (swap with next). Focus follows the cell."""
function move_cell_down!(nv::NotebookView)
    swap_cell_down!(nv.nb, nv.focused_idx) || return
    rebuild_widgets!(nv)  # rebuild_widgets! tracks focused cell by ID
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

"""Map a screen y-coordinate to a cell index, or nothing if outside cells."""
function cell_at_y(nv::NotebookView, screen_y::Int)
    isempty(nv.cell_widgets) && return nothing
    vp = nv.viewport
    vp.width == 0 && return nothing  # viewport not yet established

    # Convert screen y to content-space y
    content_y = screen_y - vp.y + nv.scroll_offset

    y = 0
    for i in eachindex(nv.cell_widgets)
        ch = cell_height(nv.cell_widgets[i])
        oh = output_height(nv.output_widgets[i])
        slot_h = ch + oh + 1  # cell + output + gap

        if content_y < y + slot_h
            return i
        end
        y += slot_h
    end

    nothing  # clicked below all cells
end

"""Map a screen y-coordinate to a gap insertion index, or nothing if inside a cell.
Returns the 1-based index where a new cell should be inserted."""
function gap_at_y(nv::NotebookView, screen_y::Int)
    isempty(nv.cell_widgets) && return 1  # empty notebook → insert at 1
    vp = nv.viewport
    vp.width == 0 && return nothing

    # Clicks outside viewport are not gaps
    screen_y < vp.y && return nothing

    content_y = screen_y - vp.y + nv.scroll_offset

    y = 0
    for i in eachindex(nv.cell_widgets)
        ch = cell_height(nv.cell_widgets[i])
        oh = output_height(nv.output_widgets[i])

        # Cell body
        if content_y < y + ch
            return nothing  # inside cell, not gap
        end
        y += ch

        # Output body
        if oh > 0 && content_y < y + oh
            return nothing  # inside output, not gap
        end
        y += oh

        # Gap (1 pixel)
        if content_y < y + 1
            return i + 1  # gap after cell i → insert at i+1
        end
        y += 1
    end

    # Below all cells
    return length(nv.cell_widgets) + 1
end

"""Insert a new cell at a gap position and focus it."""
function add_cell_at_gap!(nv::NotebookView, pos::Int)
    cell = Cell()
    insert_cell!(nv.nb, pos, cell)
    rebuild_widgets!(nv)
    nv.focused_idx = pos
    update_focus!(nv)
end

"""Split the focused cell at the cursor position. Creates two cells."""
function split_cell_at_cursor!(nv::NotebookView)
    isempty(nv.cell_widgets) && return
    cw = nv.cell_widgets[nv.focused_idx]
    sync_to_cell!(cw)

    editor = cw.editor
    row = editor.cursor_row
    col = editor.cursor_col
    lines = editor.lines

    before_lines = String[]
    after_lines = String[]
    for i in eachindex(lines)
        line_str = String(lines[i])
        if i < row
            push!(before_lines, line_str)
        elseif i == row
            push!(before_lines, line_str[1:min(col, length(line_str))])
            push!(after_lines, line_str[min(col+1, length(line_str)+1):end])
        else
            push!(after_lines, line_str)
        end
    end

    cw.cell.code = join(before_lines, '\n')
    sync_from_cell!(cw)

    new_cell = Cell(join(after_lines, '\n'))
    pos = nv.focused_idx + 1
    insert_cell!(nv.nb, pos, new_cell)
    rebuild_widgets!(nv)
    nv.focused_idx = pos
    update_focus!(nv)
end

"""Merge the focused cell with the next cell."""
function merge_with_next!(nv::NotebookView)
    nv.focused_idx >= length(nv.cell_widgets) && return
    length(nv.cell_widgets) <= 1 && return

    cell = nv.cell_widgets[nv.focused_idx].cell
    next = nv.cell_widgets[nv.focused_idx + 1].cell
    sync_to_cell!(nv.cell_widgets[nv.focused_idx])
    sync_to_cell!(nv.cell_widgets[nv.focused_idx + 1])

    cell.code = cell.code * "\n" * next.code
    remove_cell!(nv.nb, next.id)
    rebuild_widgets!(nv)
end

"""Focus a cell by index directly (for mouse click)."""
function focus_cell!(nv::NotebookView, idx::Int)
    idx < 1 || idx > length(nv.cell_widgets) && return
    nv.focused_idx = idx
    update_focus!(nv)
end

function Tachikoma.render(nv::NotebookView, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    nv.viewport = rect  # store for mouse hit testing
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
