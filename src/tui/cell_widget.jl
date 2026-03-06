# TUI: Cell editor widget — wraps CodeEditor with cell state indicators

"""A cell widget combining a CodeEditor with state/output display."""
mutable struct CellWidget
    cell::Cell
    editor::Tachikoma.CodeEditor
    focused::Bool
    collapsed::Bool  # Whether output is collapsed
end

function CellWidget(cell::Cell; focused::Bool=false)
    editor = Tachikoma.CodeEditor()
    Tachikoma.set_text!(editor, cell.code)
    CellWidget(cell, editor, focused, false)
end

"""Sync editor text back to cell."""
function sync_to_cell!(cw::CellWidget)
    cw.cell.code = Tachikoma.text(cw.editor)
end

"""Sync cell code to editor (after external change)."""
function sync_from_cell!(cw::CellWidget)
    Tachikoma.set_text!(cw.editor, cw.cell.code)
end

"""State indicator character and style for a cell.
- ◌ (dotted): never executed
- ○ (hollow, yellow): stale (source changed since last execution)
- ● (solid, green): executed and clean
- ● (solid, red): errored
- ● (solid, blue): currently running
- ◌ (orange): queued
- ✗ (red): errored (alternative when stale check isn't primary)
"""
function state_indicator(cell::Cell)
    # Disabled cells always show dim indicator
    if cell.disabled
        return "⊘", Tachikoma.Style(; fg=Tachikoma.Color256(240))  # dim gray circle-slash
    end
    # Priority: active states first, then error, then stale/never-run, then done
    if cell.state == cell_running
        return "●", Tachikoma.Style(; fg=Tachikoma.Color256(33))  # blue
    elseif cell.state == cell_queued
        return "◌", Tachikoma.Style(; fg=Tachikoma.Color256(214))  # orange
    elseif cell.state == cell_errored
        return "✗", Tachikoma.Style(; fg=Tachikoma.Color256(196))  # red
    elseif is_stale(cell)
        return "○", Tachikoma.Style(; fg=Tachikoma.Color256(214))  # yellow/warning
    elseif is_never_run(cell)
        return "◌", Tachikoma.Style(; fg=Tachikoma.Color256(245))  # dim gray
    elseif cell.state == cell_done
        return "●", Tachikoma.Style(; fg=Tachikoma.Color256(34))   # green
    else
        return "○", Tachikoma.Style(; fg=Tachikoma.Color256(245))  # default dim
    end
end

"""Height needed to render this cell widget (editor only, output separate)."""
function cell_height(cw::CellWidget)
    if cw.cell.folded || cw.cell.disabled
        return 3  # block border (2) + 1 line of collapsed preview
    end
    n_lines = count(==('\n'), cw.cell.code) + 1
    n_lines + 2  # +2 for block border
end

Tachikoma.focusable(::CellWidget) = true

function Tachikoma.render(cw::CellWidget, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    char, style = state_indicator(cw.cell)
    border_style = cw.focused ? Tachikoma.tstyle(:accent) : Tachikoma.Style()

    # Build title suffix
    suffix = cw.cell.disabled ? " [disabled]" : cw.cell.folded ? " [folded]" : ""
    title = "$(char) Cell$(suffix)"

    if cw.cell.folded || cw.cell.disabled
        first_line = first(split(cw.cell.code, '\n'; limit=2))
        preview = isempty(first_line) ? "…" : first_line * " …"
        dim_style = Tachikoma.Style(; fg=Tachikoma.Color256(240))
        block = Tachikoma.Block(; title, border_style=cw.cell.disabled ? dim_style : border_style)
        Tachikoma.render(block, rect, buf)
        inner = Tachikoma.Rect(rect.x + 1, rect.y + 1, max(rect.width - 2, 1), max(rect.height - 2, 1))
        para = Tachikoma.Paragraph([Tachikoma.Span(preview, dim_style)])
        Tachikoma.render(para, inner, buf)
    else
        block = Tachikoma.Block(; title, border_style)
        Tachikoma.render(block, rect, buf)
        inner = Tachikoma.Rect(rect.x + 1, rect.y + 1, max(rect.width - 2, 1), max(rect.height - 2, 1))
        Tachikoma.render(cw.editor, inner, buf)
    end
end

function Tachikoma.handle_key!(cw::CellWidget, evt)
    handled = Tachikoma.handle_key!(cw.editor, evt)
    if handled
        sync_to_cell!(cw)
    end
    handled
end
