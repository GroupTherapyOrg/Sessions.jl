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
    hovered_idx::Int   # which cell the mouse is hovering over (0 = none)
    scroll_offset::Int
    viewport::Tachikoma.Rect   # stored during render for mouse hit testing
end

function NotebookView(nb::Notebook)
    cells = ordered_cells(nb)
    cell_widgets = [CellWidget(c; focused=(i == 1)) for (i, c) in enumerate(cells)]
    output_widgets = [OutputWidget(c) for c in cells]
    NotebookView(nb, cell_widgets, output_widgets, 1, 0, 0, Tachikoma.Rect())
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

"""Add a new cell before the focused cell."""
function add_cell_before_focus!(nv::NotebookView)
    idx = nv.focused_idx
    cell = Cell()
    insert_cell!(nv.nb, idx, cell)
    rebuild_widgets!(nv)
    nv.focused_idx = idx
    update_focus!(nv)
end

"""Move the focused cell up (swap with previous). Focus follows the cell."""
function move_cell_up!(nv::NotebookView)
    swap_cell_up!(nv.nb, nv.focused_idx) || return
    rebuild_widgets!(nv)
end

"""Move the focused cell down (swap with next). Focus follows the cell."""
function move_cell_down!(nv::NotebookView)
    swap_cell_down!(nv.nb, nv.focused_idx) || return
    rebuild_widgets!(nv)
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
    vp.width == 0 && return nothing

    content_y = screen_y - vp.y + nv.scroll_offset - Theme.TOP_MARGIN

    y = 0
    for i in eachindex(nv.cell_widgets)
        ch = cell_height(nv.cell_widgets[i])
        oh = output_height(nv.output_widgets[i])
        slot_h = ch + oh + Theme.CELL_GAP

        if content_y < y + slot_h
            return i
        end
        y += slot_h
    end

    nothing
end

"""Map a screen y-coordinate to a gap insertion index, or nothing if inside a cell.
Returns the 1-based index where a new cell should be inserted."""
function gap_at_y(nv::NotebookView, screen_y::Int)
    isempty(nv.cell_widgets) && return nothing
    vp = nv.viewport
    vp.width == 0 && return nothing

    screen_y < vp.y && return nothing

    content_y = screen_y - vp.y + nv.scroll_offset - Theme.TOP_MARGIN

    y = 0
    for i in eachindex(nv.cell_widgets)
        ch = cell_height(nv.cell_widgets[i])
        oh = output_height(nv.output_widgets[i])

        if content_y < y + ch
            return nothing
        end
        y += ch

        if oh > 0 && content_y < y + oh
            return nothing
        end
        y += oh

        if content_y < y + Theme.CELL_GAP
            return nothing  # in the gap — not a clickable zone
        end
        y += Theme.CELL_GAP
    end

    return nothing
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

"""Select all cells."""
function select_all!(nv::NotebookView)
    for cw in nv.cell_widgets
        cw.selected = true
    end
end

"""Clear all cell selections."""
function clear_selection!(nv::NotebookView)
    for cw in nv.cell_widgets
        cw.selected = false
    end
end

"""Check if any cells are selected."""
function has_selection(nv::NotebookView)
    any(cw -> cw.selected, nv.cell_widgets)
end

"""Select range of cells from idx_a to idx_b (inclusive)."""
function select_range!(nv::NotebookView, from::Int, to::Int)
    lo, hi = minmax(from, to)
    for (i, cw) in enumerate(nv.cell_widgets)
        cw.selected = lo <= i <= hi
    end
end

"""Move all selected cells up by one position."""
function move_selected_up!(nv::NotebookView)
    isempty(nv.cell_widgets) && return
    selected_indices = [i for (i, cw) in enumerate(nv.cell_widgets) if cw.selected]
    isempty(selected_indices) && return
    first(selected_indices) <= 1 && return

    for i in selected_indices
        nb = nv.nb
        nb.cell_order[i], nb.cell_order[i-1] = nb.cell_order[i-1], nb.cell_order[i]
    end
    selected_ids = Set(nv.cell_widgets[i].cell.id for i in selected_indices)
    rebuild_widgets!(nv)
    for (i, cw) in enumerate(nv.cell_widgets)
        cw.selected = cw.cell.id in selected_ids
    end
end

"""Move all selected cells down by one position."""
function move_selected_down!(nv::NotebookView)
    isempty(nv.cell_widgets) && return
    selected_indices = [i for (i, cw) in enumerate(nv.cell_widgets) if cw.selected]
    isempty(selected_indices) && return
    last(selected_indices) >= length(nv.cell_widgets) && return

    for i in reverse(selected_indices)
        nb = nv.nb
        nb.cell_order[i], nb.cell_order[i+1] = nb.cell_order[i+1], nb.cell_order[i]
    end
    selected_ids = Set(nv.cell_widgets[i].cell.id for i in selected_indices)
    rebuild_widgets!(nv)
    for (i, cw) in enumerate(nv.cell_widgets)
        cw.selected = cw.cell.id in selected_ids
    end
end

"""Focus a cell by index directly (for mouse click)."""
function focus_cell!(nv::NotebookView, idx::Int)
    (idx < 1 || idx > length(nv.cell_widgets)) && return
    nv.focused_idx = idx
    update_focus!(nv)
end

# Layout constants are in Theme — referenced as Theme.CELL_PAD_FRACTION etc.
# Re-export for backward compatibility with tests that use Sessions.CELL_PAD_FRACTION
const CELL_PAD_FRACTION = Theme.CELL_PAD_FRACTION
const MARGIN_CTRL_WIDTH = Theme.MARGIN_CTRL_WIDTH

function Tachikoma.render(nv::NotebookView, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    nv.viewport = rect

    # Fill viewport with canvas bg
    for fy in rect.y:(rect.y + rect.height - 1)
        Tachikoma.set_string!(buf, rect.x, fy, " " ^ rect.width, Theme.S_CANVAS)
    end

    isempty(nv.cell_widgets) && return

    pad = max(1, round(Int, rect.width * Theme.CELL_PAD_FRACTION))
    pad = min(pad, max(0, div(rect.width - 10, 2)))
    cx = rect.x + pad
    cw_width = max(1, rect.width - 2 * pad)

    y = rect.y + Theme.TOP_MARGIN - nv.scroll_offset
    visible_start = rect.y
    visible_end = rect.y + rect.height - 1
    margin_x = cx - Theme.MARGIN_CTRL_WIDTH
    margin_s = Theme.margin_style()

    for i in eachindex(nv.cell_widgets)
        cw = nv.cell_widgets[i]
        ow = nv.output_widgets[i]

        ch = cell_height(cw)
        oh = output_height(ow)
        is_focused = (i == nv.focused_idx)
        is_hovered = (i == nv.hovered_idx)
        show_controls = is_focused || is_hovered

        cw.hovered = is_hovered && !is_focused

        # --- "+" add-above (in gap row above cell) ---
        if show_controls
            plus_above_y = y - 1
            if plus_above_y >= visible_start && plus_above_y <= visible_end && margin_x >= rect.x
                Tachikoma.set_string!(buf, margin_x, plus_above_y, " + ", margin_s)
            end
        end

        # --- Cell rendering ---
        if y + ch > visible_start && y <= visible_end
            cell_rect = Tachikoma.Rect(cx, max(y, visible_start), cw_width,
                            min(ch, visible_end - max(y, visible_start) + 1))
            Tachikoma.render(cw, cell_rect, buf)
        end

        # --- Eye button (left margin, vertically centered) ---
        if show_controls
            eye_y = y + div(ch, 2)
            if eye_y >= visible_start && eye_y <= visible_end && margin_x >= rect.x
                echar = Theme.eye_char(cw.cell.folded)
                efg = Theme.eye_fg(cw.cell.folded)
                Tachikoma.set_string!(buf, margin_x, eye_y, " $echar ",
                    Tachikoma.Style(; fg=efg, bg=Theme.MARGIN_BG))
            end
        end

        y += ch

        # --- Output rendering ---
        if oh > 0
            if y + oh > visible_start && y <= visible_end
                out_rect = Tachikoma.Rect(cx, max(y, visible_start), cw_width,
                                min(oh, visible_end - max(y, visible_start) + 1))
                Tachikoma.render(ow, out_rect, buf)
            end
            y += oh
        end

        # --- "+" add-below and "▶ Xms" run button (in gap below cell) ---
        if show_controls
            gap_y = y
            if gap_y >= visible_start && gap_y <= visible_end
                if margin_x >= rect.x
                    Tachikoma.set_string!(buf, margin_x, gap_y, " + ", margin_s)
                end
                run_text = run_button_text(cw.cell)
                run_style = run_button_style(cw.cell, Theme.tick())
                run_x = cx + cw_width - length(run_text)
                if run_x >= cx
                    Tachikoma.set_string!(buf, run_x, gap_y, run_text, run_style)
                end
            end
        end

        y += Theme.CELL_GAP
    end

    ensure_visible!(nv, rect)
end

"""Adjust scroll_offset so the focused cell is visible."""
function ensure_visible!(nv::NotebookView, rect::Tachikoma.Rect)
    isempty(nv.cell_widgets) && return

    y = Theme.TOP_MARGIN
    for i in 1:nv.focused_idx-1
        y += cell_height(nv.cell_widgets[i])
        y += output_height(nv.output_widgets[i])
        y += Theme.CELL_GAP
    end

    focused_h = cell_height(nv.cell_widgets[nv.focused_idx])

    if y < nv.scroll_offset
        nv.scroll_offset = y
    end

    if y + focused_h > nv.scroll_offset + rect.height
        nv.scroll_offset = y + focused_h - rect.height
    end
end
