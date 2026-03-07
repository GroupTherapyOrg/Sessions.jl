# TUI: Diagnostics panel — JET analysis results display
# Shows errors/warnings from JET.jl static analysis
# Togglable via activity bar ⚠ button

mutable struct DiagnosticsPanel
    entries::Vector{Tuple{UUID, Diagnostic}}  # (cell_id, diagnostic) pairs
    cursor_idx::Int
    scroll_offset::Int
    hovered_idx::Int
    viewport::Tachikoma.Rect
end

DiagnosticsPanel() = DiagnosticsPanel(Tuple{UUID, Diagnostic}[], 1, 0, 0, Tachikoma.Rect())

"""Update panel entries from a diagnostics dictionary."""
function update_entries!(dp::DiagnosticsPanel, diags::Dict{UUID, CellDiagnostics}, nb::Notebook)
    dp.entries = Tuple{UUID, Diagnostic}[]
    for id in nb.cell_order
        cd = get(diags, id, nothing)
        cd === nothing && continue
        for d in cd.diagnostics
            push!(dp.entries, (id, d))
        end
    end
    dp.cursor_idx = clamp(dp.cursor_idx, 1, max(length(dp.entries), 1))
end

"""Map screen y to entry index."""
function diag_entry_at_y(dp::DiagnosticsPanel, screen_y::Int)
    vp = dp.viewport
    vp.width == 0 && return nothing
    vi = Theme.CELL_V_INSET
    content_start_y = vp.y + vi + 3  # border + header + divider
    entry_y = screen_y - content_start_y + dp.scroll_offset
    (entry_y < 0 || entry_y >= length(dp.entries)) && return nothing
    return entry_y + 1
end

"""Severity icon."""
function _severity_icon(sev::Symbol)
    sev == :error   && return "●"
    sev == :warning && return "▲"
    return "○"
end

"""Severity color."""
function _severity_color(sev::Symbol)
    sev == :error   && return Theme.RED
    sev == :warning && return Theme.ORANGE
    return Theme.CYAN
end

function Tachikoma.render(dp::DiagnosticsPanel, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    dp.viewport = rect
    rect.width < 6 && return
    rect.height < 4 && return

    hi = Theme.CELL_H_INSET
    vi = Theme.CELL_V_INSET
    border_style = Tachikoma.Style(; fg=Theme.SIDEBAR_BORDER_FG, bg=Theme.SIDEBAR_BG)

    # Fill with sidebar bg
    for fy in rect.y:(rect.y + rect.height - 1)
        Tachikoma.set_string!(buf, rect.x, fy, " " ^ rect.width,
            Tachikoma.Style(; bg=Theme.SIDEBAR_BG))
    end

    bx = rect.x + hi
    by = rect.y + vi
    bw = max(rect.width - 2 * hi, 3)
    bh = max(rect.height - 2 * vi, 3)

    # Rounded border
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

    inner_x = bx + 1
    inner_w = bw - 2
    inner_w < 2 && return

    # Header
    header_y = by + 1
    n_entries = length(dp.entries)
    header_text = n_entries == 0 ? "No issues" : "$(n_entries) issue$(n_entries == 1 ? "" : "s")"
    Tachikoma.set_string!(buf, inner_x + 1, header_y, "⚠ ",
        Tachikoma.Style(; fg=Theme.ORANGE, bg=Theme.SIDEBAR_BG))
    Tachikoma.set_string!(buf, inner_x + 3, header_y, first(header_text, inner_w - 4),
        Tachikoma.Style(; fg=Theme.ACCENT, bg=Theme.SIDEBAR_BG))

    # Divider
    div_y = by + 2
    Tachikoma.set_char!(buf, bx, div_y, '├', border_style)
    Tachikoma.set_char!(buf, bx + bw - 1, div_y, '┤', border_style)
    for cx in (bx + 1):(bx + bw - 2)
        Tachikoma.set_char!(buf, cx, div_y, '─', border_style)
    end

    # Entries
    entries_start_y = by + 3
    entries_height = bh - 4
    entries_height < 1 && return

    # Auto-scroll
    if dp.cursor_idx - 1 < dp.scroll_offset
        dp.scroll_offset = dp.cursor_idx - 1
    end
    if dp.cursor_idx - 1 >= dp.scroll_offset + entries_height
        dp.scroll_offset = dp.cursor_idx - entries_height
    end
    dp.scroll_offset = clamp(dp.scroll_offset, 0, max(0, n_entries - entries_height))

    max_msg_w = inner_w - 4  # icon(1) + space(1) + pad(2)

    for vi_idx in 0:(entries_height - 1)
        ei = dp.scroll_offset + vi_idx + 1
        ei > n_entries && break
        _, diag = dp.entries[ei]
        row = entries_start_y + vi_idx
        is_cursor = (ei == dp.cursor_idx)
        is_hovered = (ei == dp.hovered_idx)

        # Severity icon
        icon = _severity_icon(diag.severity)
        ic = _severity_color(diag.severity)
        Tachikoma.set_string!(buf, inner_x + 1, row, icon,
            Tachikoma.Style(; fg=ic, bg=Theme.SIDEBAR_BG))

        # Message — truncated
        msg = first(diag.message, max_msg_w)
        msg_fg = (is_cursor || is_hovered) ? Theme.FG : Theme.FG_DIM
        Tachikoma.set_string!(buf, inner_x + 3, row, msg,
            Tachikoma.Style(; fg=msg_fg, bg=Theme.SIDEBAR_BG))
    end

    # Bottom count
    if n_entries > 0
        pos_text = "$(dp.cursor_idx)/$(n_entries)"
        pos_x = bx + bw - length(pos_text) - 2
        if pos_x > bx + 1
            Tachikoma.set_char!(buf, pos_x - 1, by + bh - 1, '┤', border_style)
            Tachikoma.set_string!(buf, pos_x, by + bh - 1, pos_text,
                Tachikoma.Style(; fg=Theme.FG_DIM, bg=Theme.SIDEBAR_BG))
            Tachikoma.set_char!(buf, pos_x + length(pos_text), by + bh - 1, '├', border_style)
        end
    end
end
