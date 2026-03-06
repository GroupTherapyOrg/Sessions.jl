# TUI: Output rendering widget — displays cell execution results

"""Widget to display a cell's output (result, stdout, errors)."""
mutable struct OutputWidget
    cell::Cell
    collapsed::Bool
end

OutputWidget(cell::Cell) = OutputWidget(cell, false)

"""Format cell output as displayable lines."""
function output_lines(cell::Cell)
    out = cell.output
    lines = String[]

    if !isempty(out.stdout)
        for line in split(out.stdout, '\n')
            push!(lines, String(line))
        end
    end

    if out.error !== nothing
        push!(lines, "ERROR: $(out.error.ex)")
    end

    if out.error === nothing && out.result !== nothing
        push!(lines, sprint(show, out.result))
    end

    lines
end

"""Height needed for output display."""
function output_height(ow::OutputWidget)
    if ow.collapsed || ow.cell.state == cell_idle
        return 0
    end
    lines = output_lines(ow.cell)
    isempty(lines) ? 0 : length(lines) + 2
end

function Tachikoma.render(ow::OutputWidget, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    if ow.collapsed || ow.cell.state == cell_idle
        return
    end

    lines = output_lines(ow.cell)
    isempty(lines) && return

    stale = is_stale(ow.cell)

    border_style = if ow.cell.state == cell_errored
        Tachikoma.Style(; fg=Tachikoma.Color256(196))
    elseif stale
        Tachikoma.Style(; fg=Tachikoma.Color256(240))  # dimmed border when stale
    else
        Tachikoma.Style(; fg=Tachikoma.Color256(245))
    end

    title = stale ? "Output (stale)" : "Output"
    block = Tachikoma.Block(; title, border_style)
    Tachikoma.render(block, rect, buf)

    inner_y = rect.y + 1
    inner_x = rect.x + 2
    max_width = max(rect.width - 4, 1)

    for (i, line) in enumerate(lines)
        row = inner_y + i - 1
        row > rect.y + rect.height - 2 && break
        text_style = if ow.cell.state == cell_errored
            Tachikoma.Style(; fg=Tachikoma.Color256(196))
        elseif stale
            Tachikoma.Style(; fg=Tachikoma.Color256(240))  # dimmed text when stale
        else
            Tachikoma.Style()
        end
        Tachikoma.set_string!(buf, inner_x, row, first(line, max_width), text_style)
    end
end
