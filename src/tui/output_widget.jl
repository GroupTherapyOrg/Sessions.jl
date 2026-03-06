# TUI: Output rendering widget — Pluto-style seamless output below cells
# No border, no title — just text on canvas bg with a subtle left accent bar

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

"""Height needed for output display (borderless — just the lines + 1 for top padding)."""
function output_height(ow::OutputWidget)
    if ow.collapsed || ow.cell.state == cell_idle
        return 0
    end
    otype = ow.cell.output.output_type
    if otype == :dataframe
        return _datatable_height(ow.cell)
    elseif otype == :markdown
        return _markdown_height(ow.cell)
    end
    lines = output_lines(ow.cell)
    isempty(lines) ? 0 : length(lines)
end

function Tachikoma.render(ow::OutputWidget, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    if ow.collapsed || ow.cell.state == cell_idle
        return
    end

    stale = is_stale(ow.cell)
    otype = ow.cell.output.output_type

    # Rich output: DataTable for tabular data
    if otype == :dataframe && ow.cell.output.result !== nothing && !stale
        _render_datatable(ow.cell, rect, buf)
        return
    end

    # Rich output: MarkdownPane for markdown
    if otype == :markdown && ow.cell.output.result !== nothing && !stale
        _render_markdown(ow.cell, rect, buf)
        return
    end

    # Rich output: PixelImage placeholder for images
    if otype == :image_png && !stale
        _render_image_placeholder(ow.cell, rect, buf)
        return
    end

    # Default: Pluto-style borderless output on canvas bg
    lines = output_lines(ow.cell)
    isempty(lines) && return

    errored = ow.cell.state == cell_errored
    bar_color = Theme.output_bar_color(errored, stale)
    text_style = Theme.output_text_style(errored, stale)
    bar_style = Tachikoma.Style(; fg=bar_color, bg=Theme.CANVAS_BG)

    text_x = rect.x + 3  # indent: 1 for bar + 2 for padding
    max_width = max(rect.width - 4, 1)

    for (i, line) in enumerate(lines)
        row = rect.y + i - 1
        row > rect.y + rect.height - 1 && break
        Tachikoma.set_char!(buf, rect.x, row, '│', bar_style)
        Tachikoma.set_string!(buf, text_x, row, first(line, max_width), text_style)
    end
end

# --- DataTable rendering ---

"""Height for DataTable output: header + rows + border."""
function _datatable_height(cell::Cell)
    result = cell.output.result
    result === nothing && return 0
    nrows = _table_nrows(result)
    min(nrows + 3, 20)  # header + rows + 2 for border, cap at 20
end

"""Get row count from a table-like object."""
function _table_nrows(value)
    if value isa AbstractVector
        return length(value)
    end
    try
        return length(collect(value))
    catch
        return 0
    end
end

"""Render a DataTable for tabular output."""
function _render_datatable(cell::Cell, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    result = cell.output.result
    result === nothing && return

    # Build DataTable from data
    dt = _make_datatable(result)
    dt === nothing && return

    Tachikoma.render(dt, rect, buf)
end

"""Create a Tachikoma DataTable from a table-like value."""
function _make_datatable(value)
    # Handle Vector{<:NamedTuple} directly
    if value isa AbstractVector{<:NamedTuple} && !isempty(value)
        headers = String[string(k) for k in keys(first(value))]
        data = [Any[row[k] for row in value] for k in keys(first(value))]
        return Tachikoma.DataTable(headers, data;
            block=Tachikoma.Block(; title="Table"))
    end

    # Try Tables.jl interface via loaded modules
    tables_mod = get(Base.loaded_modules,
        Base.PkgId(Base.UUID("bd369af6-aec1-5ad0-b16a-f7cc5008161c"), "Tables"), nothing)
    if tables_mod !== nothing
        try
            cols = tables_mod.columns(value)
            names = tables_mod.columnnames(cols)
            headers = String[string(n) for n in names]
            data = [Any[v for v in tables_mod.getcolumn(cols, n)] for n in names]
            return Tachikoma.DataTable(headers, data;
                block=Tachikoma.Block(; title="Table"))
        catch
        end
    end

    nothing
end

# --- Markdown rendering ---

"""Height for markdown output."""
function _markdown_height(cell::Cell)
    result = cell.output.result
    result === nothing && return 0
    md_str = _markdown_string(result)
    n_lines = count(==('\n'), md_str) + 1
    min(n_lines, 15)
end

"""Convert a Markdown.MD to string for rendering."""
function _markdown_string(value)
    try
        sprint(show, MIME"text/markdown"(), value)
    catch
        sprint(show, value)
    end
end

"""Render markdown output via MarkdownPane."""
function _render_markdown(cell::Cell, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    result = cell.output.result
    result === nothing && return

    md_str = _markdown_string(result)
    mp = Tachikoma.MarkdownPane(md_str;
        width=max(rect.width - 2, 1),
        block=Tachikoma.Block(; title="Markdown"))
    Tachikoma.render(mp, rect, buf)
end

# --- Image placeholder rendering ---

"""Render a placeholder for image output (Kitty/sixel requires Frame, not Buffer)."""
function _render_image_placeholder(cell::Cell, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    block = Tachikoma.Block(; title="Image",
        border_style=Tachikoma.Style(; fg=Theme.FG_MUTED))
    Tachikoma.render(block, rect, buf)

    inner_y = rect.y + 1
    inner_x = rect.x + 2
    Tachikoma.set_string!(buf, inner_x, inner_y,
        "[Image: use graphical terminal for pixel rendering]",
        Tachikoma.Style(; fg=Theme.FG_MUTED))
end
