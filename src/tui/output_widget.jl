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
    elseif out.error === nothing && out.result === nothing && !isempty(out.text_representation)
        # Cached output from .session.toml — result not available, use text_representation
        for line in split(out.text_representation, '\n')
            push!(lines, String(line))
        end
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
    max_width = max(rect.width - 3, 1)  # clamp to rect right edge

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

# --- Markdown rendering (custom AST walker for Pluto-like output) ---

import Markdown

"""A styled text segment for rendering."""
struct MdSegment
    text::String
    style::Tachikoma.Style
end

"""A rendered line of styled segments."""
const MdLine = Vector{MdSegment}

# Style constructors — match Pluto: light text on dark canvas bg, no background highlights
_s_h1()    = Tachikoma.Style(; fg=Theme.FG, bg=Theme.CANVAS_BG, bold=true)
_s_h2()    = Tachikoma.Style(; fg=Theme.FG, bg=Theme.CANVAS_BG, bold=true)
_s_h3()    = Tachikoma.Style(; fg=Theme.FG, bg=Theme.CANVAS_BG, bold=true)
_s_text()  = Tachikoma.Style(; fg=Theme.FG, bg=Theme.CANVAS_BG)
_s_bold()  = Tachikoma.Style(; fg=Theme.FG, bg=Theme.CANVAS_BG, bold=true)
_s_ital()  = Tachikoma.Style(; fg=Theme.FG, bg=Theme.CANVAS_BG, italic=true)
_s_code()  = Tachikoma.Style(; fg=Theme.FG_DIM, bg=Theme.CANVAS_BG)
_s_link()  = Tachikoma.Style(; fg=Theme.FG, bg=Theme.CANVAS_BG, underline=true)
_s_quote() = Tachikoma.Style(; fg=Theme.FG_DIM, bg=Theme.CANVAS_BG, italic=true)
_s_hr()    = Tachikoma.Style(; fg=Theme.FG_MUTED, bg=Theme.CANVAS_BG)
_s_bullet() = Tachikoma.Style(; fg=Theme.FG, bg=Theme.CANVAS_BG)
_s_dim()   = Tachikoma.Style(; fg=Theme.FG_MUTED, bg=Theme.CANVAS_BG)

"""Walk a Markdown.MD AST and produce styled lines for TUI rendering."""
function _md_to_lines(md::Markdown.MD, width::Int)
    lines = MdLine[]
    for block in md.content
        _render_block!(lines, block, width, 0)
    end
    lines
end

"""Render a block-level markdown element into lines."""
function _render_block!(lines::Vector{MdLine}, block, width::Int, indent::Int)
    if block isa Markdown.Header{1}
        # H1: bold + double underline (═)
        push!(lines, MdLine())  # blank line before
        segs = MdSegment[]
        push!(segs, MdSegment(" " ^ indent, _s_text()))
        _inline_to_segs!(segs, block.text, _s_h1())
        push!(lines, segs)
        text_len = sum(length(s.text) for s in segs)
        rule_len = min(max(text_len, 20), width - indent)
        push!(lines, [MdSegment(" " ^ indent * "═" ^ rule_len, _s_hr())])
        push!(lines, MdLine())  # blank line after

    elseif block isa Markdown.Header{2}
        # H2: bold + dashed underline (─)
        push!(lines, MdLine())
        segs = MdSegment[]
        push!(segs, MdSegment(" " ^ indent, _s_text()))
        _inline_to_segs!(segs, block.text, _s_h2())
        push!(lines, segs)
        text_len = sum(length(s.text) for s in segs)
        rule_len = min(max(text_len, 20), width - indent)
        push!(lines, [MdSegment(" " ^ indent * "─" ^ rule_len, _s_hr())])
        push!(lines, MdLine())

    elseif block isa Markdown.Header
        # H3+: bold + dotted underline (·)
        push!(lines, MdLine())
        segs = MdSegment[]
        push!(segs, MdSegment(" " ^ indent, _s_text()))
        _inline_to_segs!(segs, block.text, _s_h3())
        push!(lines, segs)
        text_len = sum(length(s.text) for s in segs)
        rule_len = min(max(text_len, 20), width - indent)
        push!(lines, [MdSegment(" " ^ indent * "·" ^ rule_len, _s_hr())])
        push!(lines, MdLine())

    elseif block isa Markdown.Paragraph
        segs = MdSegment[]
        push!(segs, MdSegment(" " ^ indent, _s_text()))
        _inline_to_segs!(segs, block.content, _s_text())
        push!(lines, segs)
        push!(lines, MdLine())  # blank line after paragraph

    elseif block isa Markdown.List
        for (i, item) in enumerate(block.items)
            prefix = if block.ordered == -1
                "  • "
            else
                "  $(block.ordered + i - 1). "
            end
            first_line = true
            for sub in item
                if sub isa Markdown.Paragraph
                    segs = MdSegment[]
                    if first_line
                        push!(segs, MdSegment(" " ^ indent * prefix, _s_text()))
                        first_line = false
                    else
                        push!(segs, MdSegment(" " ^ (indent + length(prefix)), _s_text()))
                    end
                    _inline_to_segs!(segs, sub.content, _s_text())
                    push!(lines, segs)
                else
                    _render_block!(lines, sub, width, indent + length(prefix))
                end
            end
        end
        push!(lines, MdLine())  # blank line after list

    elseif block isa Markdown.BlockQuote
        for sub in block.content
            if sub isa Markdown.Paragraph
                segs = MdSegment[]
                push!(segs, MdSegment(" " ^ indent * "  │ ", _s_dim()))
                _inline_to_segs!(segs, sub.content, _s_quote())
                push!(lines, segs)
            else
                _render_block!(lines, sub, width, indent + 4)
            end
        end
        push!(lines, MdLine())

    elseif block isa Markdown.HorizontalRule
        push!(lines, [MdSegment(" " ^ indent * "─" ^ max(width - indent - 4, 10), _s_hr())])
        push!(lines, MdLine())

    elseif block isa Markdown.Code
        # Fenced code block
        for code_line in split(block.code, '\n')
            push!(lines, [MdSegment(" " ^ (indent + 2) * String(code_line), _s_code())])
        end
        push!(lines, MdLine())

    else
        # Fallback: show as text
        push!(lines, [MdSegment(" " ^ indent * sprint(show, block), _s_text())])
    end
end

"""Convert inline markdown elements to styled segments."""
function _inline_to_segs!(segs::Vector{MdSegment}, content, default_style::Tachikoma.Style)
    for item in content
        if item isa AbstractString
            push!(segs, MdSegment(item, default_style))
        elseif item isa Markdown.Bold
            _inline_to_segs!(segs, item.text, _s_bold())
        elseif item isa Markdown.Italic
            _inline_to_segs!(segs, item.text, _s_ital())
        elseif item isa Markdown.Code
            push!(segs, MdSegment(item.code, _s_code()))
        elseif item isa Markdown.Link
            _inline_to_segs!(segs, item.text, _s_link())
        elseif item isa Markdown.Image
            push!(segs, MdSegment("[$(item.alt)]", _s_dim()))
        elseif item isa Markdown.LineBreak
            # ignore, handled by line structure
        else
            push!(segs, MdSegment(sprint(show, "text/plain", item), default_style))
        end
    end
end

"""Height for markdown output."""
function _markdown_height(cell::Cell)
    result = cell.output.result
    result === nothing && return 0
    result isa Markdown.MD || return 0
    lines = _md_to_lines(result, 80)  # approximate width
    length(lines)
end

"""Render markdown output — Pluto-style document on canvas bg."""
function _render_markdown(cell::Cell, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    result = cell.output.result
    result === nothing && return
    result isa Markdown.MD || return

    lines = _md_to_lines(result, max(rect.width - 4, 20))
    text_x = rect.x + 2  # left padding
    max_x = rect.x + rect.width - 1  # right boundary

    for (i, line) in enumerate(lines)
        row = rect.y + i - 1
        row > rect.y + rect.height - 1 && break
        x = text_x
        for seg in line
            remaining = max_x - x + 1
            remaining <= 0 && break
            text = first(seg.text, remaining)
            Tachikoma.set_string!(buf, x, row, text, seg.style)
            x += length(seg.text)
        end
    end
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
