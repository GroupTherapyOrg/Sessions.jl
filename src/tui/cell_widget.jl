# TUI: Cell editor widget — Pluto-style cell with hover controls

"""A cell widget combining a CodeEditor with state/output display."""
mutable struct CellWidget
    cell::Cell
    editor::Tachikoma.CodeEditor
    focused::Bool
    hovered::Bool    # Mouse is hovering over this cell (shows controls)
    collapsed::Bool  # Whether output is collapsed
    selected::Bool   # Whether this cell is part of multi-cell selection
    ellipsis_hovered::Bool  # Mouse hovering over ⋯ button
end

function CellWidget(cell::Cell; focused::Bool=false)
    editor = Tachikoma.CodeEditor()
    Tachikoma.set_text!(editor, cell.code)
    editor.focused = false  # cursor hidden by default; app sets true only in insert mode
    CellWidget(cell, editor, focused, false, false, false, false)
end

"""Sync editor text back to cell."""
function sync_to_cell!(cw::CellWidget)
    cw.cell.code = Tachikoma.text(cw.editor)
end

"""Sync cell code to editor (after external change)."""
function sync_from_cell!(cw::CellWidget)
    Tachikoma.set_text!(cw.editor, cw.cell.code)
end

"""Check if editor text differs from cell code (unsaved edits)."""
is_dirty(cw::CellWidget) = Tachikoma.text(cw.editor) != cw.cell.code

"""State indicator character and style for a cell."""
function state_indicator(cell::Cell)
    if cell.disabled
        return "⊘", Theme.S_DISABLED
    end
    tick = Theme.tick()
    if cell.state == cell_running
        b = Tachikoma.breathe(tick; period=45)
        fg = Tachikoma.color_lerp(Theme.ACCENT_DIM, Theme.ACCENT_GLOW, b)
        return "●", Tachikoma.Style(; fg)
    elseif cell.state == cell_queued
        return "◌", Theme.S_QUEUED
    elseif cell.state == cell_errored
        return "✗", Theme.S_ERRORED
    elseif is_stale(cell)
        return "○", Theme.S_STALE
    elseif is_never_run(cell)
        return "◌", Theme.S_NEVER_RUN
    elseif cell.state == cell_done
        return "●", Theme.S_DONE
    else
        return "○", Theme.S_NEVER_RUN
    end
end

"""Format runtime_ns to a human-readable string."""
function format_runtime(ns::UInt64)
    ns == 0 && return ""
    if ns < 1_000
        return "$(ns)ns"
    elseif ns < 1_000_000
        return "$(round(ns / 1_000; digits=1))µs"
    elseif ns < 1_000_000_000
        return "$(round(ns / 1_000_000; digits=1))ms"
    else
        return "$(round(ns / 1_000_000_000; digits=2))s"
    end
end

"""Height needed to render this cell widget.
When `has_output` is true and the cell is folded, the cell collapses to 0
so only the output is visible."""
function cell_height(cw::CellWidget; has_output::Bool=false)
    if cw.cell.folded
        return has_output ? 0 : 1
    end
    vi = Theme.CELL_V_INSET
    if cw.cell.disabled
        return 3 + 2 * vi
    end
    n_lines = count(==('\n'), cw.cell.code) + 1
    n_lines + 2 + 2 * vi  # +2 for border, +2*vi for vertical padding
end

Tachikoma.focusable(::CellWidget) = true

"""Draw a dashed rounded border — rounded corners with dashed horizontal/vertical lines."""
function _draw_dashed_border!(buf::Tachikoma.Buffer, rect::Tachikoma.Rect,
                               border_fg, surface_bg)
    (rect.width < 2 || rect.height < 2) && return
    box = Theme.BOX
    s = Tachikoma.Style(; fg=border_fg, bg=surface_bg)

    rx = rect.x; ry = rect.y
    rx2 = Tachikoma.right(rect); ry2 = Tachikoma.bottom(rect)

    # Rounded corners
    Tachikoma.set_char!(buf, rx, ry, box.tl, s)
    Tachikoma.set_char!(buf, rx2, ry, box.tr, s)
    Tachikoma.set_char!(buf, rx, ry2, box.bl, s)
    Tachikoma.set_char!(buf, rx2, ry2, box.br, s)

    # Dashed horizontal lines (┄ = U+2504)
    for x in (rx + 1):(rx2 - 1)
        Tachikoma.set_char!(buf, x, ry, '┄', s)
        Tachikoma.set_char!(buf, x, ry2, '┄', s)
    end

    # Dashed vertical lines (┆ = U+2506)
    for y in (ry + 1):(ry2 - 1)
        Tachikoma.set_char!(buf, rx, y, '┆', s)
        Tachikoma.set_char!(buf, rx2, y, '┆', s)
    end
end

"""Draw a rounded border. All border chars use surface_bg so they match the cell fill exactly."""
function _draw_rounded_border!(buf::Tachikoma.Buffer, rect::Tachikoma.Rect,
                                border_fg, surface_bg)
    (rect.width < 2 || rect.height < 2) && return
    box = Theme.BOX
    s = Tachikoma.Style(; fg=border_fg, bg=surface_bg)

    rx = rect.x; ry = rect.y
    rx2 = Tachikoma.right(rect); ry2 = Tachikoma.bottom(rect)

    Tachikoma.set_char!(buf, rx, ry, box.tl, s)
    Tachikoma.set_char!(buf, rx2, ry, box.tr, s)
    Tachikoma.set_char!(buf, rx, ry2, box.bl, s)
    Tachikoma.set_char!(buf, rx2, ry2, box.br, s)

    for x in (rx + 1):(rx2 - 1)
        Tachikoma.set_char!(buf, x, ry, box.h, s)
        Tachikoma.set_char!(buf, x, ry2, box.h, s)
    end

    for y in (ry + 1):(ry2 - 1)
        Tachikoma.set_char!(buf, rx, y, box.v, s)
        Tachikoma.set_char!(buf, rx2, y, box.v, s)
    end
end

"""Draw a shimmer border. All border chars use surface_bg so they match the cell fill exactly."""
function _shimmer_border_with_bg!(buf::Tachikoma.Buffer, rect::Tachikoma.Rect,
                                   base_color, surface_bg, tick::Int;
                                   box=Theme.BOX, intensity::Float64=0.2)
    (rect.width < 2 || rect.height < 2) && return
    base_rgb = Tachikoma.to_rgb(base_color)

    function _style(x::Int, y::Int)
        if Tachikoma.animations_enabled()
            n = Tachikoma.fbm(x * 0.3 + tick * 0.04, y * 0.5 + tick * 0.02)
            adj = (n - 0.5) * 2.0 * intensity
            c = if adj > 0
                Tachikoma.brighten(base_rgb, adj)
            else
                Tachikoma.dim_color(base_rgb, -adj)
            end
            Tachikoma.Style(; fg=c, bg=surface_bg)
        else
            Tachikoma.Style(; fg=base_rgb, bg=surface_bg)
        end
    end

    rx = rect.x; ry = rect.y
    rx2 = Tachikoma.right(rect); ry2 = Tachikoma.bottom(rect)

    Tachikoma.set_char!(buf, rx, ry, box.tl, _style(rx, ry))
    Tachikoma.set_char!(buf, rx2, ry, box.tr, _style(rx2, ry))
    Tachikoma.set_char!(buf, rx, ry2, box.bl, _style(rx, ry2))
    Tachikoma.set_char!(buf, rx2, ry2, box.br, _style(rx2, ry2))

    for x in (rx + 1):(rx2 - 1)
        Tachikoma.set_char!(buf, x, ry, box.h, _style(x, ry))
        Tachikoma.set_char!(buf, x, ry2, box.h, _style(x, ry2))
    end

    for y in (ry + 1):(ry2 - 1)
        Tachikoma.set_char!(buf, rx, y, box.v, _style(rx, y))
        Tachikoma.set_char!(buf, rx2, y, box.v, _style(rx2, y))
    end
end

function Tachikoma.render(cw::CellWidget, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    tick = Theme.tick()

    # Folded cell: hidden code — just a thin canvas-bg row (or nothing if output visible)
    if cw.cell.folded
        rect.height < 1 && return  # height 0 means output is showing instead
        Tachikoma.set_string!(buf, rect.x, rect.y, " " ^ rect.width, Theme.S_CANVAS)
        if cw.focused || cw.hovered
            bar_style = Tachikoma.Style(; fg=Theme.FOLD_BAR_FG, bg=Theme.CANVAS_BG)
            Tachikoma.set_char!(buf, rect.x, rect.y, '│', bar_style)
        end
        return
    end

    surface_bg = Theme.cell_surface(cw.focused)

    # Fill the entire rect with surface_bg (gray cell island).
    fill_style = Tachikoma.Style(; bg=surface_bg)
    for fy in rect.y:(rect.y + rect.height - 1)
        Tachikoma.set_string!(buf, rect.x, fy, " " ^ rect.width, fill_style)
    end

    # Border is drawn INSET from the fill — horizontal padding visible on sides.
    # IMPORTANT: never exceed the given rect (cells are clipped at viewport edges).
    hi = Theme.CELL_H_INSET
    vi = Theme.CELL_V_INSET
    border_w = rect.width - 2 * hi
    border_h = rect.height - 2 * vi
    (border_w < 2 || border_h < 2) && return
    border_rect = Tachikoma.Rect(rect.x + hi, rect.y + vi, border_w, border_h)

    hp = Theme.CELL_H_PAD
    inner_w = border_w - 2 - 2 * hp
    inner_h = border_h - 2
    (inner_w < 1 || inner_h < 1) && return
    inner = Tachikoma.Rect(border_rect.x + 1 + hp, border_rect.y + 1, inner_w, inner_h)

    dirty = is_dirty(cw)

    if cw.focused && !cw.cell.disabled
        if cw.editor.focused
            # Insert mode: bright shimmer border (actively editing)
            border_color = dirty ? Theme.ORANGE : Theme.ACCENT
            _shimmer_border_with_bg!(buf, border_rect, border_color, surface_bg, tick;
                box=Theme.BOX, intensity=Theme.SHIMMER_INTENSITY)
        else
            # Normal mode: dim dashed accent border (focused but not editing)
            border_color = dirty ? Theme.DIRTY_BORDER_FG : Theme.ACCENT_DIM
            _draw_dashed_border!(buf, border_rect, border_color, surface_bg)
        end
        _render_code!(cw, inner, buf, surface_bg)
        _render_ellipsis_button!(border_rect, buf; hovered=cw.ellipsis_hovered)

    elseif cw.hovered && !cw.cell.disabled
        border_color = dirty ? Theme.DIRTY_BORDER_FG : Theme.BORDER_BRIGHT
        _draw_rounded_border!(buf, border_rect, border_color, surface_bg)
        _render_code!(cw, inner, buf, surface_bg)
        _render_ellipsis_button!(border_rect, buf; hovered=cw.ellipsis_hovered)

    elseif cw.cell.disabled
        _draw_rounded_border!(buf, border_rect, Theme.FG_MUTED, surface_bg)
        _render_folded_preview(cw, inner, buf, surface_bg)

    elseif cw.selected
        _draw_rounded_border!(buf, border_rect, Theme.CYAN, surface_bg)
        _render_code!(cw, inner, buf, surface_bg)

    elseif dirty
        _draw_rounded_border!(buf, border_rect, Theme.DIRTY_BORDER_FG, surface_bg)
        _render_code!(cw, inner, buf, surface_bg)

    else
        _draw_rounded_border!(buf, border_rect, Theme.BORDER_DIM, surface_bg)
        _render_code!(cw, inner, buf, surface_bg)
    end

    # Running/queued left border indicator (Pluto-style colored left edge)
    _render_run_indicator!(cw.cell, border_rect, buf, surface_bg, tick)

    # Thin bar cursor — only when cell is being edited
    if cw.editor.focused && !cw.cell.disabled
        _render_bar_cursor!(cw.editor, inner, buf, tick)
    end
end

"""Overlay the left border with a colored bar when cell is running or queued."""
function _render_run_indicator!(cell::Cell, border_rect::Tachikoma.Rect,
                                 buf::Tachikoma.Buffer, surface_bg, tick::Int)
    (cell.state != cell_running && cell.state != cell_queued) && return
    border_rect.height < 2 && return

    rx = border_rect.x
    ry = border_rect.y
    ry2 = Tachikoma.bottom(border_rect)

    if cell.state == cell_running
        # Breathing accent blue bar
        for y in ry:ry2
            b = Tachikoma.breathe(tick + (y - ry) * 3; period=45)
            fg = Tachikoma.color_lerp(Theme.ACCENT_DIM, Theme.ACCENT_GLOW, b)
            Tachikoma.set_char!(buf, rx, y, '▎', Tachikoma.Style(; fg, bg=surface_bg))
        end
    else  # cell_queued
        # Static orange bar
        style = Tachikoma.Style(; fg=Theme.ORANGE, bg=surface_bg)
        for y in ry:ry2
            Tachikoma.set_char!(buf, rx, y, '▎', style)
        end
    end
end

"""Render code editor (folded cells are handled before this is called)."""
function _render_code!(cw::CellWidget, inner::Tachikoma.Rect,
                        buf::Tachikoma.Buffer, surface_bg)
    # Always render from line 1 — the notebook passes the full virtual rect,
    # so inner.height == n_lines and auto-scroll won't trigger. Buffer
    # in_bounds silently clips lines outside the visible viewport.
    cw.editor.scroll_offset = 0

    if cw.focused
        # Suppress built-in block cursor; we draw thin bar cursor after
        was_focused = cw.editor.focused
        cw.editor.focused = false
        Tachikoma.render(cw.editor, inner, buf)
        cw.editor.focused = was_focused
    else
        Tachikoma.render(cw.editor, inner, buf)
    end
end

"""Render ⋯ pill button inside cell, top-right corner."""
function _render_ellipsis_button!(rect::Tachikoma.Rect, buf::Tachikoma.Buffer; hovered::Bool=false)
    rect.height < 3 && return
    ey = rect.y + 1
    ex = rect.x + rect.width - 4  # 3 chars + border
    ex < rect.x + 2 && return
    if hovered
        bracket = Tachikoma.Style(; fg=Theme.ACCENT, bg=Theme.BTN_BG)
        center  = Tachikoma.Style(; fg=Theme.ACCENT_GLOW, bg=Theme.BTN_BG)
    else
        bracket = Tachikoma.Style(; fg=Theme.BTN_BRACKET, bg=Theme.BTN_BG)
        center  = Tachikoma.Style(; fg=Theme.BTN_FG, bg=Theme.BTN_BG)
    end
    Tachikoma.set_char!(buf, ex, ey, '(', bracket)
    Tachikoma.set_char!(buf, ex + 1, ey, Theme.BTN_CHAR, center)
    Tachikoma.set_char!(buf, ex + 2, ey, ')', bracket)
end

"""Compute run button style for a cell (used by notebook_view for gap rendering)."""
function run_button_style(cell::Cell, tick::Int)
    bg = Theme.RUN_BG
    if cell.state == cell_running
        p = Tachikoma.pulse(tick; period=30, lo=0.4, hi=1.0)
        fg = Tachikoma.color_lerp(Theme.ACCENT_DIM, Theme.ACCENT_GLOW, p)
        Tachikoma.Style(; fg, bg, bold=true)
    elseif cell.state == cell_errored
        Tachikoma.Style(; fg=Theme.RUN_ERROR_FG, bg)
    elseif cell.state == cell_done
        Tachikoma.Style(; fg=Theme.RUN_DONE_FG, bg)
    else
        Tachikoma.Style(; fg=Theme.RUN_DEFAULT_FG, bg)
    end
end

"""Compute run button text for a cell."""
function run_button_text(cell::Cell)
    rt = format_runtime(cell.output.runtime_ns)
    rt_display = isempty(rt) ? "" : " $rt "
    cell.state == cell_running ? "▶ ..." : "▶" * rt_display
end

"""Draw a thin vertical bar cursor (▏) at the editor's cursor position."""
function _render_bar_cursor!(editor::Tachikoma.CodeEditor, area::Tachikoma.Rect,
                              buf::Tachikoma.Buffer, tick::Int)
    line_count = length(editor.lines)
    gw = editor.show_line_numbers ? ndigits(max(line_count, 1)) + 1 : 0

    vis_row = editor.cursor_row - editor.scroll_offset
    vis_row < 1 && return
    vis_row > area.height && return

    cy = area.y + vis_row - 1
    cx = area.x + gw + (editor.cursor_col - editor.h_scroll)

    cx < area.x + gw && return
    cx > area.x + area.width - 1 && return

    b = Tachikoma.breathe(tick; period=60)
    fg = Tachikoma.color_lerp(Theme.ACCENT, Theme.ACCENT_GLOW, b)
    bar_style = Tachikoma.Style(; fg, bg=Theme.ELEVATED_BG)

    Tachikoma.set_char!(buf, cx, cy, '▏', bar_style)
end

"""Render folded/disabled preview text."""
function _render_folded_preview(cw::CellWidget, inner::Tachikoma.Rect,
                                 buf::Tachikoma.Buffer, surface_bg)
    first_line = first(split(cw.cell.code, '\n'; limit=2))
    preview = isempty(first_line) ? "..." : first_line * " ..."
    para = Tachikoma.Paragraph([Tachikoma.Span(preview,
        Tachikoma.Style(; fg=Theme.FG_DIM, bg=surface_bg))])
    Tachikoma.render(para, inner, buf)
end

function Tachikoma.handle_key!(cw::CellWidget, evt)
    handled = Tachikoma.handle_key!(cw.editor, evt)
    if handled
        sync_to_cell!(cw)
    end
    handled
end
