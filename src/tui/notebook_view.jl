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
    user_scrolling::Bool       # true when user is manually scrolling (suppress auto-scroll)
    hovered_control::Symbol    # :none, :plus_gap, :eye, :ellipsis, :run
    hovered_control_idx::Int   # which cell index the hovered control belongs to
    hovered_bond_idx::Int      # cell index where mouse hovers over a bond widget (0 = none)
    run_all_rect::Tachikoma.Rect   # clickable "▶ Run All" button in bottom border
    run_all_hovered::Bool          # mouse hovering over run-all button
    save_rect::Tachikoma.Rect      # clickable "Save" button in top border
    save_hovered::Bool             # mouse hovering over save button
    dirty::Bool                    # notebook has unsaved changes
    cell_diags::Dict{UUID, Vector{Diagnostic}}  # JET/LSP diagnostics per cell
    lsp_status::LspStatus          # LSP server status for indicator
    current_frame::Union{Nothing, Tachikoma.Frame}  # set before render for image output
    last_scroll_time::Float64  # time() of last scroll event — skip image rendering during active scroll
    _last_viewport_size::Tuple{Int, Int}  # (width, height) for resize detection
end

function NotebookView(nb::Notebook)
    cells = ordered_cells(nb)
    cell_widgets = [CellWidget(c; focused=(i == 1)) for (i, c) in enumerate(cells)]
    output_widgets = [OutputWidget(c) for c in cells]
    NotebookView(nb, cell_widgets, output_widgets, 1, 0, 0, Tachikoma.Rect(), false, :none, 0, 0, Tachikoma.Rect(), false, Tachikoma.Rect(), false, false, Dict{UUID, Vector{Diagnostic}}(), lsp_off, nothing, 0.0, (0, 0))
end

"""Flush image-related caches on all OutputWidgets (encoded data, PixelImage, height).

Called on terminal resize. Preserves text output caches and pixel decode caches
(decode is dimension-independent; PixelImage and encoding are dimension-dependent).
"""
function flush_image_caches!(nv::NotebookView)
    for ow in nv.output_widgets
        ow._cached_encoded_data = nothing
        ow._cached_pixel_image = nothing
        # Invalidate height cache for image cells (dimensions may change with new width)
        if ow.cell.output.output_type == :image_png || ow.cell.output.output_type == :image_jpeg
            ow._cached_height = -1
        end
    end
end

"""Detect viewport resize and flush image caches if size changed.

Called at the start of each render cycle. First call initializes the size
without flushing (no previous data to invalidate).
"""
function detect_viewport_resize!(nv::NotebookView, width::Int, height::Int)
    old_w, old_h = nv._last_viewport_size
    nv._last_viewport_size = (width, height)
    # Only flush if we had a previous size and it changed
    if old_w > 0 && old_h > 0 && (old_w != width || old_h != height)
        flush_image_caches!(nv)
    end
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

    # Account for border inset (inner area starts at vp.y + vi + 1)
    vi = Theme.CELL_V_INSET
    content_y = screen_y - (vp.y + vi + 1) + nv.scroll_offset - Theme.TOP_MARGIN

    y = 0
    for i in eachindex(nv.cell_widgets)
        oh = output_height(nv.output_widgets[i])
        ch = cell_height(nv.cell_widgets[i]; has_output=oh > 0)
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

    vi = Theme.CELL_V_INSET
    screen_y < vp.y + vi + 1 && return nothing

    content_y = screen_y - (vp.y + vi + 1) + nv.scroll_offset - Theme.TOP_MARGIN

    y = 0
    for i in eachindex(nv.cell_widgets)
        oh = output_height(nv.output_widgets[i])
        ch = cell_height(nv.cell_widgets[i]; has_output=oh > 0)

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
    nv.user_scrolling = false  # auto-scroll to show newly focused cell
    update_focus!(nv)
    # Scroll to show focused cell if viewport is known
    if nv.viewport.width > 0
        ensure_visible!(nv, nv.viewport)
    end
end

# Layout constants are in Theme — referenced as Theme.CELL_PAD_FRACTION etc.
# Re-export for backward compatibility with tests that use Sessions.CELL_PAD_FRACTION
const CELL_PAD_FRACTION = Theme.CELL_PAD_FRACTION
const MARGIN_CTRL_WIDTH = Theme.MARGIN_CTRL_WIDTH

function Tachikoma.render(nv::NotebookView, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    nv.viewport = rect
    detect_viewport_resize!(nv, rect.width, rect.height)
    rect.width < 4 && return
    rect.height < 4 && return

    # ── Rounded border for notebook pane (inset to match cell island style) ──
    hi = Theme.CELL_H_INSET
    vi = Theme.CELL_V_INSET
    border_fg = nv.dirty ? Theme.DIRTY_BORDER_FG : Theme.BORDER_DIM
    border_style = Tachikoma.Style(; fg=border_fg, bg=Theme.CANVAS_BG)

    # Fill entire rect with canvas bg (overflow visible around border)
    for fy in rect.y:(rect.y + rect.height - 1)
        Tachikoma.set_string!(buf, rect.x, fy, " " ^ rect.width, Theme.S_CANVAS)
    end

    # Border drawn inset from fill edges
    bx = rect.x + hi
    by = rect.y + vi
    bw = max(rect.width - 2 * hi, 3)
    bh = max(rect.height - 2 * vi, 3)

    # Rounded corners
    Tachikoma.set_char!(buf, bx, by, '╭', border_style)
    Tachikoma.set_char!(buf, bx + bw - 1, by, '╮', border_style)
    Tachikoma.set_char!(buf, bx, by + bh - 1, '╰', border_style)
    Tachikoma.set_char!(buf, bx + bw - 1, by + bh - 1, '╯', border_style)

    for cx in (bx + 1):(bx + bw - 2)
        Tachikoma.set_char!(buf, cx, by, '─', border_style)
        Tachikoma.set_char!(buf, cx, by + bh - 1, '─', border_style)
    end

    for fy in (by + 1):(by + bh - 2)
        Tachikoma.set_char!(buf, bx, fy, '│', border_style)
        Tachikoma.set_char!(buf, bx + bw - 1, fy, '│', border_style)
    end

    # Inner content area (inside border)
    inner_x = bx + 1
    inner_y = by + 1
    inner_w = bw - 2
    inner_h = bh - 2
    inner_w < 2 && return
    inner_h < 2 && return

    isempty(nv.cell_widgets) && return

    pad = max(1, round(Int, inner_w * Theme.CELL_PAD_FRACTION))
    pad = min(pad, max(0, div(inner_w - 10, 2)))
    cx = inner_x + pad
    cw_width = max(1, inner_w - 2 * pad)

    y = inner_y + Theme.TOP_MARGIN - nv.scroll_offset
    visible_start = inner_y
    visible_end = inner_y + inner_h - 1
    # Clamp margin_x to stay inside the notebook inner area
    margin_x = max(cx - Theme.MARGIN_CTRL_WIDTH, inner_x)
    margin_s = Theme.margin_style()
    # Right boundary for any content (inside right border)
    content_right = inner_x + inner_w - 1

    n_cells = length(nv.cell_widgets)
    gap_mid = div(Theme.CELL_GAP, 2)  # center row offset within gap

    for i in eachindex(nv.cell_widgets)
        cw = nv.cell_widgets[i]
        ow = nv.output_widgets[i]

        # Sync diagnostics into cell widget for inline rendering
        cw.diagnostics = get(nv.cell_diags, cw.cell.id, Diagnostic[])

        oh = output_height(ow)
        ch = cell_height(cw; has_output=oh > 0)
        is_focused = (i == nv.focused_idx)
        is_hovered = (i == nv.hovered_idx)
        show_controls = is_focused || is_hovered

        cw.hovered = is_hovered && !is_focused

        # --- Horizontal separator rule in gap above cell ---
        if i > 1
            rule_y = y - Theme.CELL_GAP + gap_mid
            if rule_y >= visible_start && rule_y <= visible_end
                rule_style = Tachikoma.Style(; fg=Theme.FG_FAINT, bg=Theme.CANVAS_BG)
                for rx in cx:(cx + cw_width - 1)
                    Tachikoma.set_char!(buf, rx, rule_y, '─', rule_style)
                end
            end
        end

        # --- Gap ABOVE this cell: + button (and ▲ for active cell) ---
        # + shown when this cell or the previous cell shows controls.
        # ▲ only shown on the active cell's top gap (to move it up).
        prev_shows = i > 1 && (i - 1 == nv.focused_idx || i - 1 == nv.hovered_idx)
        if show_controls || prev_shows
            gap_center_y = y - Theme.CELL_GAP + gap_mid
            if i == 1
                gap_center_y = y - 1
            end
            if gap_center_y >= visible_start && gap_center_y <= visible_end
                # + (add cell) — leftmost
                plus_hover = nv.hovered_control == :plus_gap && nv.hovered_control_idx == i
                plus_fg = plus_hover ? Theme.GREEN : Theme.FG_MUTED
                Tachikoma.set_string!(buf, margin_x, gap_center_y, " + ",
                    Tachikoma.Style(; fg=plus_fg, bg=Theme.MARGIN_BG))

                # ▲ to the right of + , only on active cell's top gap
                if show_controls && i > 1
                    up_hover = nv.hovered_control == :move_up && nv.hovered_control_idx == i
                    up_fg = up_hover ? Theme.ORANGE : Theme.FG_MUTED
                    Tachikoma.set_string!(buf, margin_x + 3, gap_center_y, " ▲",
                        Tachikoma.Style(; fg=up_fg, bg=Theme.MARGIN_BG))
                end
            end
        end

        # --- Cell rendering ---
        # Pass full virtual rect so CellWidget draws its border/code at the
        # correct virtual position.  Buffer in_bounds silently clips writes
        # outside the terminal.  The notebook border re-draw after this loop
        # seals any overflow into the inset/border area.
        if y + ch > visible_start && y <= visible_end
            cell_rect = Tachikoma.Rect(cx, max(y, rect.y), cw_width,
                            ch - max(0, rect.y - y))
            Tachikoma.render(cw, cell_rect, buf)

            # --- Diagnostic gutter markers (colored dots on lines with issues) ---
            diags = get(nv.cell_diags, cw.cell.id, Diagnostic[])
            if !isempty(diags)
                # Mark lines with diagnostic dots in the left margin
                for d in diags
                    diag_y = y + d.line  # line is 1-based, y is the cell top (border row)
                    if diag_y >= visible_start && diag_y <= visible_end
                        marker_fg = d.severity == :error ? Theme.RED :
                                    d.severity == :warning ? Theme.ORANGE : Theme.CYAN
                        Tachikoma.set_string!(buf, margin_x, diag_y, "●",
                            Tachikoma.Style(; fg=marker_fg, bg=Theme.MARGIN_BG))
                    end
                end
            end
        end

        # --- Eye button (left margin, vertically centered) ---
        if show_controls
            eye_y = y + div(ch, 2)
            if eye_y >= visible_start && eye_y <= visible_end
                eye_hover = nv.hovered_control == :eye && nv.hovered_control_idx == i
                echar = Theme.eye_char(cw.cell.folded)
                efg = eye_hover ? Theme.ACCENT : Theme.eye_fg(cw.cell.folded)
                Tachikoma.set_string!(buf, margin_x, eye_y, " $echar ",
                    Tachikoma.Style(; fg=efg, bg=Theme.MARGIN_BG))
            end
        end

        y += ch

        # --- Output rendering ---
        if oh > 0
            ow.hovered = (i == nv.hovered_bond_idx)
            ow.current_frame = nv.current_frame  # thread Frame for image rendering
            if y + oh > visible_start && y <= visible_end
                # Full virtual rect — buffer in_bounds clips, overpaint seals border
                out_rect = Tachikoma.Rect(cx, y, cw_width, oh)
                Tachikoma.render(ow, out_rect, buf)
            end
            y += oh
        end

        # --- Run button + ▼ (immediately below cell/output, in gap) ---
        if show_controls
            run_y = y  # row 0 of gap — directly adjacent to cell
            if run_y >= visible_start && run_y <= visible_end
                run_text = run_button_text(cw.cell)
                run_hover = nv.hovered_control == :run && nv.hovered_control_idx == i
                run_style = if run_hover
                    Tachikoma.Style(; fg=Theme.GREEN_BRIGHT, bg=Theme.RUN_BG, bold=true)
                else
                    run_button_style(cw.cell, Theme.tick())
                end
                run_x = cx + cw_width - length(run_text)
                if run_x >= cx && run_x + length(run_text) - 1 <= content_right
                    Tachikoma.set_string!(buf, run_x, run_y, run_text, run_style)
                end
            end

            # ▼ to the right of the bottom + (at gap_mid row), only if cell can move down
            if i < n_cells
                dn_y = y + gap_mid  # same row as the + below
                if dn_y >= visible_start && dn_y <= visible_end
                    dn_hover = nv.hovered_control == :move_down && nv.hovered_control_idx == i
                    dn_fg = dn_hover ? Theme.ORANGE : Theme.FG_MUTED
                    Tachikoma.set_string!(buf, margin_x + 3, dn_y, " ▼",
                        Tachikoma.Style(; fg=dn_fg, bg=Theme.MARGIN_BG))
                end
            end
        end

        # --- Gap AFTER last cell: + (and ▼ for active cell) ---
        if i == n_cells && show_controls
            bot_y = y + gap_mid
            if bot_y >= visible_start && bot_y <= visible_end
                plus_hover = nv.hovered_control == :plus_gap && nv.hovered_control_idx == n_cells + 1
                plus_fg = plus_hover ? Theme.GREEN : Theme.FG_MUTED
                Tachikoma.set_string!(buf, margin_x, bot_y, " + ",
                    Tachikoma.Style(; fg=plus_fg, bg=Theme.MARGIN_BG))
            end
        end

        y += Theme.CELL_GAP
    end

    clamp_scroll!(nv, rect)

    # ── Overpaint inset + border areas to seal any cell overflow ──
    # Cells render at full virtual rect, so they may write into border/inset zones.
    # Top inset area (rect.y to by-1)
    for fy in rect.y:(by - 1)
        Tachikoma.set_string!(buf, rect.x, fy, " " ^ rect.width, Theme.S_CANVAS)
    end
    # Bottom inset area (by+bh to rect.y+rect.height-1)
    for fy in (by + bh):(rect.y + rect.height - 1)
        Tachikoma.set_string!(buf, rect.x, fy, " " ^ rect.width, Theme.S_CANVAS)
    end
    # Re-draw border
    Tachikoma.set_char!(buf, bx, by, '╭', border_style)
    Tachikoma.set_char!(buf, bx + bw - 1, by, '╮', border_style)
    Tachikoma.set_char!(buf, bx, by + bh - 1, '╰', border_style)
    Tachikoma.set_char!(buf, bx + bw - 1, by + bh - 1, '╯', border_style)
    for cx_b in (bx + 1):(bx + bw - 2)
        Tachikoma.set_char!(buf, cx_b, by, '─', border_style)
        Tachikoma.set_char!(buf, cx_b, by + bh - 1, '─', border_style)
    end
    for fy in (by + 1):(by + bh - 2)
        Tachikoma.set_char!(buf, bx, fy, '│', border_style)
        Tachikoma.set_char!(buf, bx + bw - 1, fy, '│', border_style)
    end

    # ── "▶ Run All" button in bottom-right border (after re-draw so it's not overwritten) ──
    run_label = " ▶ Run All "
    run_len = length(run_label)
    run_x = bx + bw - 1 - run_len - 1  # 1 char inside right border
    bot_border_y = by + bh - 1          # bottom border row
    if run_x > bx + 2
        is_busy = any(c -> c.state == cell_running || c.state == cell_queued, values(nv.nb.cells))
        run_fg = if is_busy
            Theme.ORANGE
        elseif nv.run_all_hovered
            Theme.GREEN_BRIGHT
        else
            Theme.GREEN
        end
        run_s = Tachikoma.Style(; fg=run_fg, bg=Theme.CANVAS_BG, bold=nv.run_all_hovered)
        Tachikoma.set_string!(buf, run_x, bot_border_y, run_label, run_s)
        nv.run_all_rect = Tachikoma.Rect(run_x, bot_border_y, run_len, 1)
    else
        nv.run_all_rect = Tachikoma.Rect()
    end

    # ── "Save" button in top-right border ──
    save_label = nv.dirty ? " ● Save " : " Save "
    save_len = length(save_label)
    save_x = bx + bw - 1 - save_len - 1
    top_border_y = by
    if save_x > bx + 2
        save_fg = if nv.dirty && nv.save_hovered
            Theme.ORANGE
        elseif nv.dirty
            Theme.DIRTY_BORDER_FG
        elseif nv.save_hovered
            Theme.ACCENT
        else
            Theme.FG_MUTED
        end
        save_s = Tachikoma.Style(; fg=save_fg, bg=Theme.CANVAS_BG, bold=nv.save_hovered)
        Tachikoma.set_string!(buf, save_x, top_border_y, save_label, save_s)
        nv.save_rect = Tachikoma.Rect(save_x, top_border_y, save_len, 1)
    else
        nv.save_rect = Tachikoma.Rect()
    end

    # ── LSP status indicator in top-left border ──
    lsp_label, lsp_fg = if nv.lsp_status == lsp_ready
        n_diags = sum(length(ds) for ds in values(nv.cell_diags); init=0)
        if n_diags > 0
            (" ⚠ $(n_diags) ", Theme.ORANGE)
        else
            (" ✓ JET ", Theme.GREEN)
        end
    elseif nv.lsp_status == lsp_starting
        (" ◌ JET ", Theme.FG_MUTED)
    elseif nv.lsp_status == lsp_error
        (" ✕ JET ", Theme.RED)
    else
        ("", Theme.FG_MUTED)
    end
    if !isempty(lsp_label)
        lsp_x = bx + 2
        if lsp_x + length(lsp_label) < save_x
            Tachikoma.set_string!(buf, lsp_x, top_border_y, lsp_label,
                Tachikoma.Style(; fg=lsp_fg, bg=Theme.CANVAS_BG))
        end
    end
end

"""Lightweight placeholder for image output during scroll/clip — just blank space."""
function _render_image_scroll_placeholder(rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    style = Tachikoma.Style(; fg=Theme.FG_MUTED, bg=Theme.CANVAS_BG)
    for row in 0:(rect.height - 1)
        ry = rect.y + row
        for col in 0:(rect.width - 1)
            Tachikoma.set_char!(buf, rect.x + col, ry, ' ', style)
        end
    end
end

"""Total content height including all cells, outputs, gaps, and margins."""
function content_height(nv::NotebookView)
    isempty(nv.cell_widgets) && return 0
    h = Theme.TOP_MARGIN
    for i in eachindex(nv.cell_widgets)
        oh = output_height(nv.output_widgets[i])
        h += cell_height(nv.cell_widgets[i]; has_output=oh > 0)
        h += oh
        h += Theme.CELL_GAP
    end
    h
end

"""Clamp scroll_offset to valid range."""
function clamp_scroll!(nv::NotebookView, rect::Tachikoma.Rect)
    isempty(nv.cell_widgets) && return
    vi = Theme.CELL_V_INSET
    inner_h = max(1, rect.height - 2 * vi - 2)  # subtract inset + border
    max_scroll = max(0, content_height(nv) - inner_h)
    nv.scroll_offset = clamp(nv.scroll_offset, 0, max_scroll)
end

"""Scroll to make the focused cell visible. Called on focus change, not every frame."""
function ensure_visible!(nv::NotebookView, rect::Tachikoma.Rect)
    isempty(nv.cell_widgets) && return
    vi = Theme.CELL_V_INSET
    inner_h = max(1, rect.height - 2 * vi - 2)  # subtract inset + border

    y = Theme.TOP_MARGIN
    for i in 1:nv.focused_idx-1
        oh = output_height(nv.output_widgets[i])
        y += cell_height(nv.cell_widgets[i]; has_output=oh > 0)
        y += oh
        y += Theme.CELL_GAP
    end

    focused_oh = output_height(nv.output_widgets[nv.focused_idx])
    focused_h = cell_height(nv.cell_widgets[nv.focused_idx]; has_output=focused_oh > 0)
    # Include output height so scrolling doesn't clip the output area
    total_focused_h = focused_h + focused_oh

    # Scroll up if cell code is above viewport
    if y < nv.scroll_offset
        nv.scroll_offset = y
    end

    # Scroll down if cell+output extends below viewport
    if y + total_focused_h > nv.scroll_offset + inner_h
        # But don't scroll so far that the cell code disappears off the top
        nv.scroll_offset = min(y + total_focused_h - inner_h, y)
    end
end
