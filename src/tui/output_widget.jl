# TUI: Output rendering widget — Pluto-style seamless output below cells
# No border, no title — just text on canvas bg with a subtle left accent bar

"""Widget to display a cell's output (result, stdout, errors)."""
mutable struct OutputWidget
    cell::Cell
    collapsed::Bool
    hovered::Bool      # mouse is hovering over this bond widget
end

OutputWidget(cell::Cell) = OutputWidget(cell, false, false)

"""Format cell output as displayable lines.

Uses MIME\"text/plain\" with color enabled and controlled display size,
matching Pluto's `format_output_default` approach but adapted for TUI.
ANSI escape codes are parsed into Tachikoma styles during rendering.
"""
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
        # Render via text/plain with color enabled (Pluto parity: IOContext with displaysize)
        # ANSI codes are parsed into Tachikoma styles by _parse_ansi_line during rendering
        text = try
            sprint(; context=IOContext(devnull, :color => true, :limit => true, :displaysize => (40, 80))) do io
                Base.invokelatest(show, io, MIME"text/plain"(), out.result)
            end
        catch
            try
                sprint(; context=IOContext(devnull, :color => true, :limit => true)) do io
                    Base.invokelatest(show, io, out.result)
                end
            catch
                repr(out.result)
            end
        end
        # Split into individual lines (UnicodePlots, matrices, etc. produce multi-line output)
        for line in split(text, '\n')
            push!(lines, String(line))
        end
    elseif out.error === nothing && out.result === nothing && !isempty(out.text_representation)
        # Cached output from .session.toml — result not available, use text_representation
        for line in split(out.text_representation, '\n')
            push!(lines, String(line))
        end
    end

    lines
end

"""Strip ANSI escape codes from a string (safety net for color leaks)."""
function _strip_ansi(s::AbstractString)::String
    replace(s, r"\e\[[0-9;]*[A-Za-z]" => "")
end

# --- ANSI SGR → Tachikoma.Style parsing ---

const _ANSI_CSI_RE = r"\e\[([0-9;]*)([A-Za-z])"

"""Parse a line with ANSI escape codes into styled `MdSegment`s for rendering.

Supports SGR sequences (ESC[...m):
- Reset (0), bold (1), dim (2), italic (3), underline (4)
- Standard fg (30–37), bright fg (90–97)
- Standard bg (40–47), bright bg (100–107)
- 256-color (38;5;N / 48;5;N) and 24-bit RGB (38;2;R;G;B / 48;2;R;G;B)
- Default fg (39), default bg (49)
Non-SGR CSI sequences are silently consumed.
"""
function _parse_ansi_line(line::String, base_style::Tachikoma.Style)::MdLine
    # Fast path: no escape codes at all
    occursin('\e', line) || return [MdSegment(line, base_style)]

    segs = MdSegment[]
    parts = split(line, _ANSI_CSI_RE; keepempty=true)
    code_matches = collect(eachmatch(_ANSI_CSI_RE, line))

    # Current ANSI state — initialized from base style
    fg::Tachikoma.AbstractColor        = base_style.fg
    bg::Tachikoma.AbstractColor        = base_style.bg
    bold::Bool      = base_style.bold
    dim_flag::Bool  = base_style.dim
    italic::Bool    = base_style.italic
    ul::Bool        = base_style.underline

    for (i, part) in enumerate(parts)
        if !isempty(part)
            push!(segs, MdSegment(part,
                Tachikoma.Style(; fg, bg, bold, dim=dim_flag, italic, underline=ul)))
        end
        i > length(code_matches) && continue

        final_byte = code_matches[i].captures[2]
        final_byte == "m" || continue   # only process SGR

        params_str = something(code_matches[i].captures[1], "")
        params = _parse_sgr_params(params_str)
        j = 1
        while j <= length(params)
            c = params[j]
            if c == 0       # Reset
                fg = base_style.fg;  bg = base_style.bg
                bold = base_style.bold;  dim_flag = base_style.dim
                italic = base_style.italic;  ul = base_style.underline
            elseif c == 1;  bold = true
            elseif c == 2;  dim_flag = true
            elseif c == 3;  italic = true
            elseif c == 4;  ul = true
            elseif c == 22; bold = false; dim_flag = false
            elseif c == 23; italic = false
            elseif c == 24; ul = false
            elseif 30 <= c <= 37
                fg = Tachikoma.Color256(c - 30)
            elseif c == 38  # Extended fg
                if j+1 <= length(params) && params[j+1] == 5 && j+2 <= length(params)
                    fg = Tachikoma.Color256(params[j+2]);  j += 2
                elseif j+1 <= length(params) && params[j+1] == 2 && j+4 <= length(params)
                    fg = Tachikoma.ColorRGB(UInt8(clamp(params[j+2],0,255)),
                                            UInt8(clamp(params[j+3],0,255)),
                                            UInt8(clamp(params[j+4],0,255)));  j += 4
                end
            elseif c == 39; fg = base_style.fg
            elseif 40 <= c <= 47
                bg = Tachikoma.Color256(c - 40)
            elseif c == 48  # Extended bg
                if j+1 <= length(params) && params[j+1] == 5 && j+2 <= length(params)
                    bg = Tachikoma.Color256(params[j+2]);  j += 2
                elseif j+1 <= length(params) && params[j+1] == 2 && j+4 <= length(params)
                    bg = Tachikoma.ColorRGB(UInt8(clamp(params[j+2],0,255)),
                                            UInt8(clamp(params[j+3],0,255)),
                                            UInt8(clamp(params[j+4],0,255)));  j += 4
                end
            elseif c == 49; bg = base_style.bg
            elseif 90 <= c <= 97;   fg = Tachikoma.Color256(c - 90 + 8)
            elseif 100 <= c <= 107; bg = Tachikoma.Color256(c - 100 + 8)
            end
            j += 1
        end
    end

    isempty(segs) && push!(segs, MdSegment("", base_style))
    segs
end

"""Parse semicolon-separated SGR parameter string into integers."""
function _parse_sgr_params(s::AbstractString)::Vector{Int}
    isempty(s) && return Int[0]   # bare ESC[m = reset
    codes = Int[]
    for part in split(s, ';')
        n = tryparse(Int, part)
        n !== nothing && push!(codes, n)
    end
    codes
end

"""Height needed for output display (borderless — just the lines + 1 for top padding)."""
function output_height(ow::OutputWidget)
    if ow.collapsed || ow.cell.state == cell_idle
        return 0
    end
    otype = ow.cell.output.output_type
    if otype == :bond
        return _bond_height(ow.cell)
    elseif otype == :dataframe
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

    # Interactive output: Bond widget (Slider, etc.)
    if otype == :bond && ow.cell.output.result isa Bond && !stale
        _render_bond(ow.cell, rect, buf, ow.hovered)
        return
    end

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
        # Parse ANSI escape codes into styled segments
        styled_segs = _parse_ansi_line(line, text_style)
        x = text_x
        max_x = text_x + max_width - 1
        for seg in styled_segs
            remaining = max_x - x + 1
            remaining <= 0 && break
            text = first(seg.text, remaining)
            Tachikoma.set_string!(buf, x, row, text, seg.style)
            x += length(text)
        end
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

# --- Bond / interactive widget rendering ---

"""Height for bond output (widget + optional value display)."""
function _bond_height(cell::Cell)
    result = cell.output.result
    result isa Bond || return 0
    el = result.element
    if el isa Slider
        return 1  # single-line slider track
    elseif el isa CheckBox
        return 1  # [✓] or [  ]
    elseif el isa Button || el isa CounterButton
        return 1  # [ Button Label ]
    elseif el isa Select
        return 1  # dropdown: ▸ selected_value
    elseif el isa NumberField
        return 1  # number: [  value  ]
    elseif el isa TextField
        return 1  # text: [  value  ]
    end
    1  # fallback: single line
end

"""Render a Bond widget in the output area."""
function _render_bond(cell::Cell, rect::Tachikoma.Rect, buf::Tachikoma.Buffer, hovered::Bool=false)
    bond = cell.output.result
    bond isa Bond || return

    el = bond.element
    if el isa Slider
        _render_slider_widget(bond, rect, buf, hovered)
    elseif el isa CheckBox
        _render_checkbox_widget(bond, rect, buf, hovered)
    elseif el isa Button || el isa CounterButton
        _render_button_widget(bond, rect, buf, hovered)
    elseif el isa Select
        _render_select_widget(bond, rect, buf, hovered)
    else
        # Fallback: show bond info as text
        text = "$(bond.defines) = $(_bond_current_value(bond))"
        Tachikoma.set_string!(buf, rect.x + 2, rect.y, text,
            Tachikoma.Style(; fg=Theme.FG, bg=Theme.CANVAS_BG))
    end
end

"""Get current value of a bond from the registry."""
function _bond_current_value(bond::Bond)
    haskey(_BOND_REGISTRY, bond.defines) || return initial_value(bond.element)
    _BOND_REGISTRY[bond.defines][2]
end

"""Render a TUI slider: ◄═══●═══► value"""
function _render_slider_widget(bond::Bond, rect::Tachikoma.Rect, buf::Tachikoma.Buffer, hovered::Bool=false)
    slider = bond.element::Slider
    current_val = _bond_current_value(bond)
    idx = _slider_index(slider, current_val)
    total = length(slider.values)

    # Format value string
    val_str = slider.show_value ? " $(current_val)" : ""
    label = "$(bond.defines) "

    # Track dimensions
    label_width = length(label)
    val_width = length(val_str)
    avail = rect.width - 4 - label_width - val_width  # 4 = left pad + ◄ + ► + space
    track_width = clamp(avail, 5, 50)

    # Compute knob position
    frac = total <= 1 ? 0.0 : (idx - 1) / (total - 1)
    knob_pos = round(Int, frac * (track_width - 1))

    x = rect.x + 2  # left padding
    y = rect.y

    # Style — hover brightens the interactive elements
    label_s = Tachikoma.Style(; fg=Theme.FG_DIM, bg=Theme.CANVAS_BG)
    track_s = Tachikoma.Style(; fg=hovered ? Theme.ACCENT_DIM : Theme.FG_MUTED, bg=Theme.CANVAS_BG)
    knob_s = Tachikoma.Style(; fg=hovered ? Theme.ACCENT_GLOW : Theme.ACCENT, bg=Theme.CANVAS_BG, bold=true)
    filled_s = Tachikoma.Style(; fg=hovered ? Theme.ACCENT : Theme.ACCENT_DIM, bg=Theme.CANVAS_BG)
    val_s = Tachikoma.Style(; fg=Theme.FG, bg=Theme.CANVAS_BG, bold=true)

    # Draw label
    Tachikoma.set_string!(buf, x, y, label, label_s)
    x += label_width

    # Draw left endpoint
    Tachikoma.set_char!(buf, x, y, '◄', track_s)
    x += 1

    # Draw track with knob
    for i in 0:track_width-1
        if i == knob_pos
            Tachikoma.set_char!(buf, x + i, y, '●', knob_s)
        elseif i < knob_pos
            Tachikoma.set_char!(buf, x + i, y, '━', filled_s)
        else
            Tachikoma.set_char!(buf, x + i, y, '─', track_s)
        end
    end
    x += track_width

    # Draw right endpoint
    Tachikoma.set_char!(buf, x, y, '►', track_s)
    x += 1

    # Draw value
    if slider.show_value
        Tachikoma.set_string!(buf, x, y, val_str, val_s)
    end
end

"""Render a TUI checkbox: [✓] label  or  [ ] label"""
function _render_checkbox_widget(bond::Bond, rect::Tachikoma.Rect, buf::Tachikoma.Buffer, hovered::Bool=false)
    val = _bond_current_value(bond)
    checked = val === true

    x = rect.x + 2
    y = rect.y
    label = "$(bond.defines) "

    label_s = Tachikoma.Style(; fg=Theme.FG_DIM, bg=Theme.CANVAS_BG)
    box_s = Tachikoma.Style(; fg=hovered ? Theme.ACCENT_GLOW : Theme.ACCENT, bg=Theme.CANVAS_BG, bold=true)

    Tachikoma.set_string!(buf, x, y, label, label_s)
    x += length(label)

    box_text = checked ? "[✓]" : "[ ]"
    Tachikoma.set_string!(buf, x, y, box_text, box_s)
end

"""Render a TUI button: [ Label ]"""
function _render_button_widget(bond::Bond, rect::Tachikoma.Rect, buf::Tachikoma.Buffer, hovered::Bool=false)
    el = bond.element
    label = el isa Button ? el.label : (el isa CounterButton ? el.label : "Click")
    val = _bond_current_value(bond)

    x = rect.x + 2
    y = rect.y

    name_s = Tachikoma.Style(; fg=Theme.FG_DIM, bg=Theme.CANVAS_BG)
    btn_s = Tachikoma.Style(; fg=hovered ? Theme.ACCENT_GLOW : Theme.ACCENT, bg=Theme.CANVAS_BG, bold=true)
    val_s = Tachikoma.Style(; fg=Theme.FG, bg=Theme.CANVAS_BG)

    Tachikoma.set_string!(buf, x, y, "$(bond.defines) ", name_s)
    x += length("$(bond.defines) ")

    Tachikoma.set_string!(buf, x, y, "[ $(label) ]", btn_s)
    x += length("[ $(label) ]")

    if el isa CounterButton
        Tachikoma.set_string!(buf, x, y, " = $(val)", val_s)
    end
end

"""Render a TUI select: label ▸ selected_value"""
function _render_select_widget(bond::Bond, rect::Tachikoma.Rect, buf::Tachikoma.Buffer, hovered::Bool=false)
    sel = bond.element::Select
    val = _bond_current_value(bond)

    # Find display label for current value
    display_label = string(val)
    for opt in sel.options
        if opt.first == val
            display_label = string(opt.second)
            break
        end
    end

    x = rect.x + 2
    y = rect.y

    name_s = Tachikoma.Style(; fg=Theme.FG_DIM, bg=Theme.CANVAS_BG)
    arrow_s = Tachikoma.Style(; fg=hovered ? Theme.ACCENT_GLOW : Theme.ACCENT, bg=Theme.CANVAS_BG)
    val_s = Tachikoma.Style(; fg=Theme.FG, bg=Theme.CANVAS_BG, bold=true)

    Tachikoma.set_string!(buf, x, y, "$(bond.defines) ", name_s)
    x += length("$(bond.defines) ")
    Tachikoma.set_string!(buf, x, y, "▸ ", arrow_s)
    x += 2
    Tachikoma.set_string!(buf, x, y, display_label, val_s)
end
