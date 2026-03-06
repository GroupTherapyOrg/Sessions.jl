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

"""State indicator character and style for a cell."""
function state_indicator(cell::Cell)
    if cell.state == cell_idle
        return "○", Tachikoma.Style(; fg=Tachikoma.Color256(245))
    elseif cell.state == cell_queued
        return "◌", Tachikoma.Style(; fg=Tachikoma.Color256(214))
    elseif cell.state == cell_running
        return "●", Tachikoma.Style(; fg=Tachikoma.Color256(33))
    elseif cell.state == cell_done
        return "●", Tachikoma.Style(; fg=Tachikoma.Color256(34))
    elseif cell.state == cell_errored
        return "●", Tachikoma.Style(; fg=Tachikoma.Color256(196))
    end
end

"""Height needed to render this cell widget (editor only, output separate)."""
function cell_height(cw::CellWidget)
    n_lines = count(==('\n'), cw.cell.code) + 1
    n_lines + 2  # +2 for block border
end

Tachikoma.focusable(::CellWidget) = true

function Tachikoma.render(cw::CellWidget, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    char, style = state_indicator(cw.cell)
    title = "$(char) Cell"
    border_style = cw.focused ? Tachikoma.tstyle(:accent) : Tachikoma.Style()

    block = Tachikoma.Block(; title, border_style)
    Tachikoma.render(block, rect, buf)

    # Render editor inside block (inset by 1 for border)
    inner = Tachikoma.Rect(rect.x + 1, rect.y + 1, max(rect.width - 2, 1), max(rect.height - 2, 1))
    Tachikoma.render(cw.editor, inner, buf)
end

function Tachikoma.handle_key!(cw::CellWidget, evt)
    handled = Tachikoma.handle_key!(cw.editor, evt)
    if handled
        sync_to_cell!(cw)
    end
    handled
end
