# TUI: Output rendering widget — Pluto-style seamless output below cells
# No border, no title — just text on canvas bg with a subtle left accent bar

"""Widget to display a cell's output (result, stdout, errors)."""
mutable struct OutputWidget
    cell::Cell
    collapsed::Bool
    hovered::Bool      # mouse is hovering over this bond widget
    current_frame::Union{Nothing, Tachikoma.Frame}  # set before render for image output
    # Image cache: avoid re-decoding PNG every frame
    _cached_image_hash::UInt64
    _cached_pixels::Union{Nothing, Matrix{Tachikoma.ColorRGB}}
    _cached_pixel_image::Union{Nothing, Tachikoma.PixelImage}
    # DataTable cache: persist interactive state (scroll, selection, sort) across frames
    _cached_datatable::Union{Nothing, Tachikoma.DataTable}
    _cached_datatable_id::UInt64  # objectid of the result that produced the cached table
    # Height cache: avoid recomputing sprint(show,...) and markdown parsing every frame
    _cached_height::Int
    _cached_height_output_id::UInt64  # objectid(cell.output) when height was cached
    _cached_height_state::CellState
    _cached_height_collapsed::Bool
    # Text output cache: avoid re-calling sprint(show,...) every frame
    _cached_output_lines::Union{Nothing, Vector{String}}
    _cached_output_lines_id::UInt64  # objectid(cell.output) when lines were cached
    # Encoded raster cache: avoid re-encoding sixel/kitty bytes every frame
    _cached_encoded_data::Union{Nothing, Vector{UInt8}}     # pre-encoded sixel/kitty bytes
    _cached_encoded_rect::Tachikoma.Rect                    # rect used for encoding
    _cached_encoded_image_hash::UInt64                      # objectid(image_data) when encoded
    _cached_encoded_protocol::Tachikoma.GraphicsProtocol    # protocol used for encoding
    _cached_kitty_id::UInt32                                 # Kitty image ID for re-placement (0 = none)
    # Layout hints: set by NotebookView before prefix sum rebuild
    available_cols::Int    # actual cell content width (columns)
    viewport_rows::Int     # viewport height (rows) for max image cap
    # Async image decode: background task for expensive PNG/JPEG decode + raster encode
    _decode_task::Union{Nothing, Task}       # background decode task (nothing = idle)
    _decode_target_hash::UInt64              # objectid of image_data being decoded
    # Image interaction: viewport transform (pan/zoom)
    _img_offset_x::Int
    _img_offset_y::Int
    _img_zoom::Float64
    # Structured error interaction state
    _error_show_all::Bool       # toggle to show hidden/dim frames
    _error_focused_frame::Int   # keyboard-focused frame index (0 = none)
    _error_scroll_offset::Int   # scroll offset for long traces
    # Output truncation state
    _output_expanded::Bool      # true = show all lines (no truncation)
    # Output text selection (drag-to-copy)
    _sel_active::Bool           # selection in progress
    _sel_anchor_row::Int        # anchor line (1-based into output lines)
    _sel_anchor_col::Int        # anchor column (0-based)
    _sel_cursor_row::Int        # current end of selection (1-based)
    _sel_cursor_col::Int        # current end column (0-based)
end

OutputWidget(cell::Cell) = OutputWidget(cell, false, false, nothing, UInt64(0), nothing, nothing, nothing, UInt64(0), -1, UInt64(0), cell_idle, false, nothing, UInt64(0), nothing, Tachikoma.Rect(), UInt64(0), Tachikoma.gfx_none, UInt32(0), 80, 40, nothing, UInt64(0), 0, 0, 1.0, false, 0, 0, false, false, 1, 0, 1, 0)

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
        if out.structured_error !== nothing
            # Use structured error's plain text for cached lines (clipboard, fallback)
            for line in split(out.structured_error.plain_text, '\n')
                push!(lines, String(line))
            end
        else
            push!(lines, "ERROR: $(out.error.ex)")
        end
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
        # Cached output from .sessions.toml — result not available, use text_representation
        for line in split(out.text_representation, '\n')
            push!(lines, String(line))
        end
    end

    lines
end

"""Cached version of output_lines() — avoids re-calling sprint(show,...) every frame.

Invalidated when objectid(cell.output) changes (new execution result).
"""
function cached_output_lines(ow::OutputWidget)::Vector{String}
    out_id = objectid(ow.cell.output)
    if ow._cached_output_lines !== nothing && ow._cached_output_lines_id == out_id
        return ow._cached_output_lines
    end
    # Output changed — clear stale selection
    _clear_output_selection!(ow)
    lines = output_lines(ow.cell)
    ow._cached_output_lines = lines
    ow._cached_output_lines_id = out_id
    lines
end

"""Strip ANSI escape codes from a string (safety net for color leaks)."""
function _strip_ansi(s::AbstractString)::String
    replace(s, r"\e\[[0-9;]*[A-Za-z]" => "")
end

"""Count how many visual rows a single output line needs at the given width."""
function _wrapped_line_count(line::String, max_width::Int)::Int
    max_width <= 0 && return 1
    w = length(_strip_ansi(line))
    w <= max_width && return 1
    cld(w, max_width)  # ceiling division
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

"""Default image output height in terminal rows (used when dimensions can't be read)."""
const _IMAGE_OUTPUT_HEIGHT = 12
const _IMAGE_HEIGHT_DEFAULT = 12
const _IMAGE_HEIGHT_MIN = 4
const _IMAGE_HEIGHT_HARD_MAX = 60   # absolute ceiling (safety)
const _IMAGE_HEIGHT_MAX = 16        # legacy constant (kept for test compat)
const _CELL_ASPECT_RATIO = 2.0      # terminal chars are ~2× taller than wide
const _SVG_HEIGHT_MAX = 30          # max lines for SVG source display
const _ASYNC_DECODE_THRESHOLD = 50_000  # bytes — images ≥50KB decoded in background thread

"""Effective max image rows — never exceeds 75% of viewport or hard max."""
function _effective_image_max(viewport_rows::Int)
    clamp(div(viewport_rows * 3, 4), _IMAGE_HEIGHT_MIN, _IMAGE_HEIGHT_HARD_MAX)
end

"""Compute image output height from pixel dimensions and available terminal width.

Terminal cells are approximately twice as tall as wide, so a square image
needs half as many rows as columns. Formula:
  rows = (img_height / img_width) * available_cols / cell_aspect_ratio
Clamped to [_IMAGE_HEIGHT_MIN, effective_max].

The `max_rows` parameter defaults to `_IMAGE_HEIGHT_HARD_MAX` but callers
should pass `_effective_image_max(viewport_rows)` for viewport-aware sizing.
"""
function image_output_height(img_width::Int, img_height::Int, available_cols::Int;
                             max_rows::Int=_IMAGE_HEIGHT_HARD_MAX)
    (img_width <= 0 || img_height <= 0 || available_cols <= 0) && return _IMAGE_HEIGHT_MIN
    aspect = img_height / img_width
    rows = round(Int, aspect * available_cols / _CELL_ASPECT_RATIO)
    clamp(rows, _IMAGE_HEIGHT_MIN, max_rows)
end

"""Height needed for output display (borderless — just the lines + 1 for top padding).

Cached to avoid recomputing expensive operations (sprint, markdown parsing)
on every frame. Invalidated when output object, cell state, or collapsed flag changes.
"""
function output_height(ow::OutputWidget)
    out_id = objectid(ow.cell.output)
    state = ow.cell.state
    collapsed = ow.collapsed
    # Return cached value if nothing changed (including layout dimensions)
    if ow._cached_height >= 0 &&
       ow._cached_height_output_id == out_id &&
       ow._cached_height_state == state &&
       ow._cached_height_collapsed == collapsed
        return ow._cached_height
    end
    h = _compute_output_height(ow)
    ow._cached_height = h
    ow._cached_height_output_id = out_id
    ow._cached_height_state = state
    ow._cached_height_collapsed = collapsed
    h
end

"""Max visible lines before truncation (click/key to expand)."""
const _OUTPUT_TRUNCATE_LINES = 25

"""Max visible frames before truncation in structured error."""
const _ERROR_MAX_VISIBLE_FRAMES = 15

"""Compute output height (uncached)."""
function _compute_output_height(ow::OutputWidget)
    if ow.collapsed || ow.cell.state == cell_idle
        return 0
    end
    otype = ow.cell.output.output_type

    # Structured error: compute from frames
    if otype == :error && ow.cell.output.structured_error !== nothing
        return _structured_error_height(ow)
    end

    if otype == :bond
        return _bond_height(ow.cell)
    elseif otype == :dataframe
        return _datatable_height(ow.cell)
    elseif otype == :markdown
        return _markdown_height(ow.cell)
    elseif otype == :image_png && ow.cell.output.image_data !== nothing
        dims = decode_png_dimensions(ow.cell.output.image_data)
        if dims !== nothing
            max_r = _effective_image_max(ow.viewport_rows)
            return image_output_height(dims[1], dims[2], ow.available_cols; max_rows=max_r)
        end
        return _IMAGE_HEIGHT_DEFAULT
    elseif otype == :image_jpeg && ow.cell.output.image_data !== nothing
        dims = decode_jpeg_dimensions(ow.cell.output.image_data)
        if dims !== nothing
            max_r = _effective_image_max(ow.viewport_rows)
            return image_output_height(dims[1], dims[2], ow.available_cols; max_rows=max_r)
        end
        return _IMAGE_HEIGHT_DEFAULT
    elseif otype == :image_svg
        return _svg_height(ow.cell)
    end
    lines = output_lines(ow.cell)
    nlines = length(lines)
    if nlines == 0
        return 0
    end
    # Compute visual (wrapped) line count
    max_w = max(ow.available_cols - 3, 1)
    visual_lines = sum(l -> _wrapped_line_count(l, max_w), lines; init=0)
    # Truncation: cap at _OUTPUT_TRUNCATE_LINES visual lines unless expanded
    if !ow._output_expanded && visual_lines > _OUTPUT_TRUNCATE_LINES
        return _OUTPUT_TRUNCATE_LINES + 1  # +1 for "N more lines" indicator
    end
    visual_lines
end

"""Compute height for structured error display."""
function _structured_error_height(ow::OutputWidget)::Int
    se = ow.cell.output.structured_error
    se === nothing && return 0
    max_w = max(ow.available_cols - 3, 1)
    # Header: type_name (1) + message (wrapped) + blank (1) + "Stacktrace:" (1)
    msg_rows = _wrapped_line_count(se.message, max_w)
    h = 1 + msg_rows + 2
    visible_frames = if ow._error_show_all
        se.frames
    else
        [f for f in se.frames if f.importance != :dim]
    end
    nf = length(visible_frames)
    h += min(nf, _ERROR_MAX_VISIBLE_FRAMES)
    # "show more" / "collapse" line
    hidden = length(se.frames) - length(visible_frames)
    dim_count = length(se.frames) - length([f for f in se.frames if f.importance != :dim])
    if hidden > 0 && !ow._error_show_all
        h += 1
    elseif ow._error_show_all && dim_count > 0
        h += 1  # "Click to collapse" line
    end
    h
end

function Tachikoma.render(ow::OutputWidget, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    if ow.collapsed || ow.cell.state == cell_idle
        return
    end

    stale = is_stale(ow.cell)
    otype = ow.cell.output.output_type

    # Structured error display (Pluto-style)
    if otype == :error && ow.cell.output.structured_error !== nothing
        _render_structured_error!(ow, rect, buf)
        return
    end

    # Interactive output: Bond widget (Slider, etc.)
    if otype == :bond && ow.cell.output.result isa Bond && !stale
        _render_bond(ow.cell, rect, buf, ow.hovered)
        return
    end

    # Rich output: DataTable for tabular data
    if otype == :dataframe && ow.cell.output.result !== nothing && !stale
        _render_datatable(ow, rect, buf)
        return
    end

    # Rich output: MarkdownPane for markdown
    if otype == :markdown && ow.cell.output.result !== nothing && !stale
        _render_markdown(ow.cell, rect, buf)
        return
    end

    # Rich output: SVG source text
    if otype == :image_svg && !stale
        _render_svg_output!(ow, rect, buf)
        return
    end

    # Rich output: PixelImage for images (PNG or JPEG)
    # Only render when cell is done (not running/queued) to avoid escape sequence corruption
    if (otype == :image_png || otype == :image_jpeg) && !stale &&
       ow.cell.output.image_data !== nothing && ow.cell.state == cell_done
        _render_image_output!(ow, rect, buf)
        return
    end

    # Log why image rendering was skipped (once per state change)
    if (otype == :image_png || otype == :image_jpeg)
        dlog("image", "render SKIPPED"; otype=otype, stale=stale,
            has_data=ow.cell.output.image_data !== nothing, state=ow.cell.state)
    end

    # Default: Pluto-style borderless output on canvas bg (cached to avoid per-frame sprint)
    lines = cached_output_lines(ow)
    isempty(lines) && return

    errored = ow.cell.state == cell_errored
    bar_color = Theme.output_bar_color(errored, stale)
    text_style = Theme.output_text_style(errored, stale)
    bar_style = Tachikoma.Style(; fg=bar_color, bg=Theme.CANVAS_BG)

    text_x = rect.x + 3  # indent: 1 for bar + 2 for padding
    max_width = max(rect.width - 3, 1)  # clamp to rect right edge

    # Determine if stdout and result coexist — render stdout dimmed above result
    has_stdout = !isempty(ow.cell.output.stdout)
    has_result = !errored && ow.cell.output.result !== nothing
    stdout_lines = has_stdout ? split(ow.cell.output.stdout, '\n') : String[]
    # Remove trailing empty line from stdout (println adds trailing \n)
    if !isempty(stdout_lines) && isempty(last(stdout_lines))
        pop!(stdout_lines)
    end

    # Output truncation (based on visual/wrapped lines)
    total_lines = length(lines)
    max_x = text_x + max_width - 1
    total_visual = sum(l -> _wrapped_line_count(l, max_width), lines; init=0)
    truncated = !ow._output_expanded && total_visual > _OUTPUT_TRUNCATE_LINES
    max_visual_rows = truncated ? _OUTPUT_TRUNCATE_LINES : total_visual

    visual_row = 0
    for (i, line) in enumerate(lines)
        visual_row >= max_visual_rows && break
        row = rect.y + visual_row
        row > rect.y + rect.height - 1 && break
        Tachikoma.set_char!(buf, rect.x, row, '│', bar_style)

        # Dim stdout lines when both stdout and result exist
        line_style = text_style
        if has_stdout && has_result && i <= length(stdout_lines)
            line_style = Tachikoma.Style(; fg=Theme.FG_MUTED, bg=Theme.CANVAS_BG, italic=true)
        end

        # Parse ANSI escape codes into styled segments, render char-by-char with wrapping
        styled_segs = _parse_ansi_line(line, line_style)
        x = text_x
        for seg in styled_segs
            for ch in seg.text
                if x > max_x
                    # Wrap: advance to next visual row
                    visual_row += 1
                    visual_row >= max_visual_rows && @goto done_lines
                    row = rect.y + visual_row
                    row > rect.y + rect.height - 1 && @goto done_lines
                    Tachikoma.set_char!(buf, rect.x, row, '│', bar_style)
                    x = text_x
                end
                Tachikoma.set_char!(buf, x, row, ch, seg.style)
                x += 1
            end
        end
        visual_row += 1
    end
    @label done_lines

    # Truncation indicator
    if truncated
        row = rect.y + max_visual_rows
        if row <= rect.y + rect.height - 1
            hidden_visual = total_visual - _OUTPUT_TRUNCATE_LINES
            indicator = "··· $hidden_visual more lines ···"
            Tachikoma.set_char!(buf, rect.x, row, '│', bar_style)
            Tachikoma.set_string!(buf, text_x, row, indicator, Theme.S_ERROR_SHOW)
        end
    end

    # Overlay selection highlighting
    _render_output_selection!(ow, rect, buf)
end

"""Build the visual text lines for a structured error (matches what _render_structured_error! draws).
Used for selection text extraction — must stay in sync with the renderer."""
function _structured_error_visual_lines(ow::OutputWidget)::Vector{String}
    se = ow.cell.output.structured_error
    se === nothing && return String[]

    lines = String[]

    # Line 1: type name
    push!(lines, se.type_name)
    # Line 2: message
    push!(lines, se.message)
    # Line 3: blank
    push!(lines, "")
    # Line 4: Stacktrace header
    push!(lines, "Stacktrace:")

    # Frames
    visible_frames = if ow._error_show_all
        se.frames
    else
        [f for f in se.frames if f.importance != :dim]
    end
    nf = length(visible_frames)
    display_count = min(nf, _ERROR_MAX_VISIBLE_FRAMES)

    for (i, frame) in enumerate(visible_frames)
        i > display_count && break
        dot = (frame.from_user || frame.importance == :important) ? '●' : '○'
        loc = "  at $(frame.file_short):$(frame.line)"
        if frame.from_user
            loc *= "  ←"
        end
        push!(lines, " [$i] $dot $(frame.func_short)$loc")
    end

    # Expand/collapse indicator
    hidden = length(se.frames) - length(visible_frames)
    dim_count = length(se.frames) - length([f for f in se.frames if f.importance != :dim])
    if hidden > 0 && !ow._error_show_all
        push!(lines, "     ··· $hidden more frames (Click to expand) ···")
    elseif ow._error_show_all && dim_count > 0
        push!(lines, "     ··· (Click to collapse) ···")
    end

    lines
end

# --- Structured error rendering (Pluto-style) ---

"""Render a structured error with per-frame metadata, importance styling, and navigation."""
function _render_structured_error!(ow::OutputWidget, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    se = ow.cell.output.structured_error
    se === nothing && return

    bar_style = Tachikoma.Style(; fg=Theme.RED, bg=Theme.CANVAS_BG)
    text_x = rect.x + 3
    max_width = max(rect.width - 3, 1)
    row = rect.y

    # Line 1: Error type name + Copy button
    Tachikoma.set_char!(buf, rect.x, row, '│', bar_style)
    Tachikoma.set_string!(buf, text_x, row, se.type_name, Theme.S_ERROR_TYPE)
    # Copy button at far right
    copy_text = "⎘ Copy"
    copy_x = rect.x + rect.width - length(copy_text) - 1
    if copy_x > text_x + length(se.type_name) + 2
        Tachikoma.set_string!(buf, copy_x, row, copy_text, Theme.S_ERROR_COPY)
    end
    row += 1

    # Line 2+: Error message (with wrapping)
    msg_chars = collect(se.message)
    msg_idx = 1
    while msg_idx <= length(msg_chars) && row <= rect.y + rect.height - 1
        Tachikoma.set_char!(buf, rect.x, row, '│', bar_style)
        x = text_x
        while msg_idx <= length(msg_chars) && x <= text_x + max_width - 1
            Tachikoma.set_char!(buf, x, row, msg_chars[msg_idx], Theme.S_ERROR_MSG)
            x += 1
            msg_idx += 1
        end
        row += 1
    end

    # Line 3: blank separator
    if row <= rect.y + rect.height - 1
        Tachikoma.set_char!(buf, rect.x, row, '│', bar_style)
        row += 1
    end

    # Line 4: "Stacktrace:" header
    if row <= rect.y + rect.height - 1 && !isempty(se.frames)
        Tachikoma.set_char!(buf, rect.x, row, '│', bar_style)
        Tachikoma.set_string!(buf, text_x, row, "Stacktrace:", Theme.S_ERROR_FRAME)
        row += 1
    end

    # Frames
    visible_frames = if ow._error_show_all
        se.frames
    else
        [f for f in se.frames if f.importance != :dim]
    end

    nf = length(visible_frames)
    display_count = min(nf, _ERROR_MAX_VISIBLE_FRAMES)

    for (i, frame) in enumerate(visible_frames)
        i > display_count && break
        row > rect.y + rect.height - 1 && break

        Tachikoma.set_char!(buf, rect.x, row, '│', bar_style)

        # Determine frame style based on importance and focus
        is_focused = (i == ow._error_focused_frame)
        frame_style, dot_char = if is_focused
            Theme.S_ERROR_FOCUS, '●'
        elseif frame.from_user
            Theme.S_ERROR_USER_BG, '●'
        elseif frame.importance == :important
            Theme.S_ERROR_USER, '●'
        elseif frame.importance == :dim
            Theme.S_ERROR_DIM, '○'
        else
            Theme.S_ERROR_FRAME, '○'
        end

        # Format: [N] ●/○ func_short  at file:line
        idx_str = " [$i] "
        Tachikoma.set_string!(buf, text_x, row, idx_str, frame_style)
        x = text_x + length(idx_str)

        # Dot indicator
        if x <= rect.x + rect.width - 1
            Tachikoma.set_char!(buf, x, row, dot_char, frame_style)
            x += 2
        end

        # Function name
        func_display = first(frame.func_short, max(max_width - 30, 10))
        if x + length(func_display) <= rect.x + rect.width
            Tachikoma.set_string!(buf, x, row, func_display, frame_style)
            x += length(func_display)
        end

        # File:line location (right-aligned or after padding)
        loc = "  at $(frame.file_short):$(frame.line)"
        if frame.from_user
            loc *= "  ←"
        end
        loc = first(loc, max(max_width - (x - text_x), 1))
        if x + length(loc) <= rect.x + rect.width
            file_style = is_focused ? Theme.S_ERROR_FOCUS : Theme.S_ERROR_FILE
            Tachikoma.set_string!(buf, x, row, loc, file_style)
        end

        row += 1
    end

    # "Show more" / "Collapse" indicator
    hidden = length(se.frames) - length(visible_frames)
    if hidden > 0 && !ow._error_show_all
        if row <= rect.y + rect.height - 1
            Tachikoma.set_char!(buf, rect.x, row, '│', bar_style)
            indicator = "     ··· $hidden more frames (Click to expand) ···"
            Tachikoma.set_string!(buf, text_x, row, first(indicator, max_width), Theme.S_ERROR_SHOW)
        end
    elseif ow._error_show_all && length(se.frames) > length([f for f in se.frames if f.importance != :dim])
        if row <= rect.y + rect.height - 1
            Tachikoma.set_char!(buf, rect.x, row, '│', bar_style)
            indicator = "     ··· (Click to collapse) ···"
            Tachikoma.set_string!(buf, text_x, row, first(indicator, max_width), Theme.S_ERROR_SHOW)
        end
    end

    # Overlay selection highlighting
    _render_output_selection!(ow, rect, buf)
end

# --- Output text selection (drag-to-copy) ---

"""Get the visual lines for output selection — structured errors use their own layout,
everything else uses cached_output_lines."""
function _selectable_output_lines(ow::OutputWidget)::Vector{String}
    if ow.cell.output.output_type == :error && ow.cell.output.structured_error !== nothing
        return _structured_error_visual_lines(ow)
    end
    cached_output_lines(ow)
end

"""Map screen coordinates to output text (row, col) given the output rect.

Output text starts at rect.x + 3 (bar + padding). Row/col are clamped
to the visible output lines."""
function _output_click_to_pos(ow::OutputWidget, rect::Tachikoma.Rect,
                               click_x::Int, click_y::Int)
    lines = _selectable_output_lines(ow)
    nlines = length(lines)
    nlines == 0 && return (1, 0)

    text_x = rect.x + 3  # bar(1) + pad(2)
    row = click_y - rect.y + 1
    row = clamp(row, 1, nlines)

    col = click_x - text_x
    col = max(col, 0)

    # Clamp col to stripped line length
    stripped = _strip_ansi(lines[row])
    col = min(col, length(stripped))

    (row, col)
end

"""Return normalized (start_row, start_col, end_row, end_col) for output selection."""
function _output_selection_range(ow::OutputWidget)
    ar, ac = ow._sel_anchor_row, ow._sel_anchor_col
    cr, cc = ow._sel_cursor_row, ow._sel_cursor_col
    if ar < cr || (ar == cr && ac <= cc)
        return (ar, ac, cr, cc)
    else
        return (cr, cc, ar, ac)
    end
end

"""Extract the selected output text as a String."""
function _output_selected_text(ow::OutputWidget)::String
    !ow._sel_active && return ""
    lines = _selectable_output_lines(ow)
    isempty(lines) && return ""

    sr, sc, er, ec = _output_selection_range(ow)
    sr = clamp(sr, 1, length(lines))
    er = clamp(er, 1, length(lines))

    # Collect chars for safe positional indexing (handles multi-byte UTF-8 like ● ○)
    char_lines = [collect(_strip_ansi(l)) for l in lines]

    if sr == er
        chars = char_lines[sr]
        from = sc + 1  # 1-based
        to = min(ec, length(chars))
        from > to && return ""
        return String(chars[from:to])
    else
        parts = String[]
        push!(parts, String(char_lines[sr][sc+1:end]))
        for r in sr+1:er-1
            push!(parts, String(char_lines[r]))
        end
        push!(parts, String(char_lines[er][1:min(ec, length(char_lines[er]))]))
        return join(parts, '\n')
    end
end

"""Clear output selection state."""
function _clear_output_selection!(ow::OutputWidget)
    ow._sel_active = false
    ow._sel_anchor_row = 1
    ow._sel_anchor_col = 0
    ow._sel_cursor_row = 1
    ow._sel_cursor_col = 0
end

"""Render selection highlight over output text lines."""
function _render_output_selection!(ow::OutputWidget, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    !ow._sel_active && return

    lines = _selectable_output_lines(ow)
    isempty(lines) && return

    sr, sc, er, ec = _output_selection_range(ow)
    text_x = rect.x + 3
    max_width = max(rect.width - 3, 1)

    # Determine visual row limit (truncation based on visual lines)
    total_visual = sum(l -> _wrapped_line_count(l, max_width), lines; init=0)
    truncated = !ow._output_expanded && total_visual > _OUTPUT_TRUNCATE_LINES
    max_visual_rows = truncated ? _OUTPUT_TRUNCATE_LINES : total_visual

    sel_style = Tachikoma.Style(; fg=Theme.FG, bg=Theme.SELECTION_BG)

    visual_row = 0
    for i in eachindex(lines)
        (i < sr || i > er) && begin
            visual_row += _wrapped_line_count(lines[i], max_width)
            continue
        end

        # Collect chars for safe positional indexing (handles multi-byte UTF-8 like ● ○)
        chars = collect(_strip_ansi(lines[i]))
        line_len = length(chars)

        # Selection range on this line (1-based char indices)
        line_sel_start = i == sr ? sc + 1 : 1
        line_sel_end = i == er ? ec : line_len

        # Render selection across all visual rows this logical line occupies
        for ci in 1:line_len
            visual_col = ((ci - 1) % max_width)
            vr = visual_row + div(ci - 1, max_width)
            vr >= max_visual_rows && @goto done_sel
            row = rect.y + vr
            row > rect.y + rect.height - 1 && @goto done_sel
            x = text_x + visual_col

            (ci < line_sel_start || ci > line_sel_end) && continue

            ch = chars[ci]
            Tachikoma.set_char!(buf, x, row, ch, sel_style)
        end

        visual_row += _wrapped_line_count(lines[i], max_width)
    end
    @label done_sel
end

# --- SVG text fallback rendering ---

"""Height for SVG source display: 1 header + source lines, clamped."""
function _svg_height(cell::Cell)
    src = cell.output.text_representation
    isempty(src) && return 1  # header only
    nlines = count('\n', src) + 1
    min(1 + nlines, _SVG_HEIGHT_MAX)
end

"""Render SVG source text with a header label."""
function _render_svg_output!(ow::OutputWidget, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    src = ow.cell.output.text_representation
    header_style = Tachikoma.Style(; fg=Tachikoma.ColorRGB(0xB4, 0xB4, 0xDC), bg=Theme.CANVAS_BG)
    bar_style = Tachikoma.Style(; fg=Theme.output_bar_color(false, false), bg=Theme.CANVAS_BG)
    text_style = Theme.output_text_style(false, false)

    text_x = rect.x + 3
    max_width = max(rect.width - 3, 1)
    row = rect.y

    # Header line
    Tachikoma.set_char!(buf, rect.x, row, '│', bar_style)
    Tachikoma.set_string!(buf, text_x, row, first("SVG image (source)", max_width), header_style)
    row += 1

    # Source lines
    if !isempty(src)
        for line in split(src, '\n')
            row > rect.y + rect.height - 1 && break
            Tachikoma.set_char!(buf, rect.x, row, '│', bar_style)
            display_line = first(string(line), max_width)
            Tachikoma.set_string!(buf, text_x, row, display_line, text_style)
            row += 1
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

"""Render a DataTable for tabular output (uses OutputWidget for state caching)."""
function _render_datatable(ow::OutputWidget, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    result = ow.cell.output.result
    result === nothing && return

    # Cache DataTable so interactive state (scroll, selection, sort) persists across frames
    result_id = objectid(result)
    if ow._cached_datatable === nothing || ow._cached_datatable_id != result_id
        dt = _make_datatable(result)
        dt === nothing && return
        ow._cached_datatable = dt
        ow._cached_datatable_id = result_id
    end

    Tachikoma.render(ow._cached_datatable, rect, buf)
end

"""Create a Tachikoma DataTable from a table-like value."""
function _make_datatable(value)
    nrows = _table_nrows(value)
    title = "Table ($nrows rows)"

    # Handle Vector{<:NamedTuple} directly
    if value isa AbstractVector{<:NamedTuple} && !isempty(value)
        headers = String[string(k) for k in keys(first(value))]
        data = [Any[row[k] for row in value] for k in keys(first(value))]
        return Tachikoma.DataTable(headers, data;
            selected=1, show_scrollbar=true,
            detail_fn=Tachikoma.datatable_detail,
            block=Tachikoma.Block(; title=title))
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
                selected=1, show_scrollbar=true,
                detail_fn=Tachikoma.datatable_detail,
                block=Tachikoma.Block(; title=title))
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

# --- Image interaction: viewport transform (pan/zoom) ---

const _ZOOM_MIN = 1.0
const _ZOOM_MAX = 8.0
const _ZOOM_STEP = 0.5
const _PAN_STEP = 4  # pixels per arrow key press

"""Zoom in on the image."""
function _zoom_in!(ow::OutputWidget)
    ow._img_zoom = min(ow._img_zoom + _ZOOM_STEP, _ZOOM_MAX)
    _invalidate_image_caches!(ow)
end

"""Zoom out on the image."""
function _zoom_out!(ow::OutputWidget)
    ow._img_zoom = max(ow._img_zoom - _ZOOM_STEP, _ZOOM_MIN)
    if ow._img_zoom == _ZOOM_MIN
        ow._img_offset_x = 0
        ow._img_offset_y = 0
    end
    _invalidate_image_caches!(ow)
end

"""Pan the image by (dx, dy) pixels."""
function _pan!(ow::OutputWidget, dx::Int, dy::Int)
    ow._img_offset_x += dx
    ow._img_offset_y += dy
    _invalidate_image_caches!(ow)
end

"""Reset viewport to default (no zoom, no pan)."""
function _reset_viewport!(ow::OutputWidget)
    ow._img_offset_x = 0
    ow._img_offset_y = 0
    ow._img_zoom = 1.0
    _invalidate_image_caches!(ow)
end

"""Invalidate PixelImage and encoded caches (needed after zoom/pan change)."""
function _invalidate_image_caches!(ow::OutputWidget)
    ow._cached_pixel_image = nothing
    ow._cached_encoded_data = nothing
    ow._cached_kitty_id = UInt32(0)
end

"""Check if a cell has an image output."""
function _is_image_cell(cell::Cell)
    (cell.output.output_type == :image_png || cell.output.output_type == :image_jpeg) &&
    cell.output.image_data !== nothing
end

"""Apply viewport transform (zoom/pan) to a pixel matrix.

Returns a cropped sub-matrix representing the visible region at the current zoom level.
At zoom=1.0 with no offset, returns the original matrix unchanged.
"""
function _apply_viewport_transform(pixels::Matrix{Tachikoma.ColorRGB},
                                    offset_x::Int, offset_y::Int, zoom::Float64)
    zoom ≈ 1.0 && offset_x == 0 && offset_y == 0 && return pixels

    src_h, src_w = size(pixels)
    # Visible region size at current zoom
    vis_w = max(1, round(Int, src_w / zoom))
    vis_h = max(1, round(Int, src_h / zoom))

    # Center point + offset
    cx = src_w ÷ 2 + offset_x
    cy = src_h ÷ 2 + offset_y

    # Compute crop bounds
    x1 = cx - vis_w ÷ 2
    y1 = cy - vis_h ÷ 2

    # Clamp to image bounds
    x1 = clamp(x1, 1, max(1, src_w - vis_w + 1))
    y1 = clamp(y1, 1, max(1, src_h - vis_h + 1))
    x2 = min(x1 + vis_w - 1, src_w)
    y2 = min(y1 + vis_h - 1, src_h)

    pixels[y1:y2, x1:x2]
end

# --- Kitty image ID helpers (transmit once, re-place cheaply) ---

# Monotonic counter for Kitty image IDs (unique per session)
const _KITTY_ID_COUNTER = Ref(UInt32(0))
_next_kitty_id() = (_KITTY_ID_COUNTER[] += UInt32(1))

"""Inject `i=<id>` into a Kitty APC escape returned by encode_kitty.

encode_kitty output starts with `\\e_Ga=T,...` — we insert `i=<id>,` right
after the `G` so the terminal stores the image data under that ID.
"""
function _inject_kitty_id(data::Vector{UInt8}, id::UInt32)
    # Find \e_G (0x1b 0x5f 0x47) and insert after position of 'G'
    id_bytes = Vector{UInt8}(codeunits("i=$(id),"))
    for i in 1:length(data)-2
        if data[i] == 0x1b && data[i+1] == UInt8('_') && data[i+2] == UInt8('G')
            return vcat(view(data, 1:i+2), id_bytes, view(data, i+3:length(data)))
        end
    end
    data  # fallback: return unmodified
end

"""Build a tiny Kitty re-placement escape: `a=p` references a previously
transmitted image by ID. ~50 bytes vs ~535KB for a full SHM transmission."""
function _kitty_placement_bytes(id::UInt32, cols::Int, rows::Int)
    io = IOBuffer(; sizehint=64)
    write(io, "\e_Ga=p,i=", string(id), ",c=", string(cols), ",r=", string(rows), ",q=2\e\\")
    take!(io)
end

# --- Image rendering (PixelImage with decode cache) ---

"""Render image output via PixelImage (sixel/kitty raster or braille fallback).

Caching strategy (three layers):
1. Pixel decode cache: _cached_pixels (invalidated on image_data objectid change)
2. PixelImage cache: _cached_pixel_image (invalidated on rect size change)
3. Encoded raster cache: _cached_encoded_data (encode once, reuse across frames)
On the hot path, we call render_graphics! directly with cached bytes — no per-frame encoding.
"""
function _render_image_output!(ow::OutputWidget, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    img_data = ow.cell.output.image_data
    if img_data === nothing || isempty(img_data)
        dlog("image", "render: no image_data")
        _render_image_fallback(rect, buf)
        return
    end

    # Layer 1: Pixel decode cache — only re-decode if image_data is a different object
    img_id = objectid(img_data)
    pixels_changed = img_id != ow._cached_image_hash || ow._cached_pixels === nothing

    if pixels_changed
        dlog("image", "decode start"; bytes=length(img_data), rect_w=rect.width, rect_h=rect.height)
        # Small images (<50KB): decode synchronously (fast, avoids async overhead for tests)
        # Large images (≥50KB): decode in background to avoid blocking the render loop
        if length(img_data) < _ASYNC_DECODE_THRESHOLD
            pixels = decode_png(img_data)
            if pixels === nothing
                pixels = decode_jpeg(img_data)
            end
            if pixels === nothing
                dlog("image", "decode FAILED — neither PNG nor JPEG")
                _render_image_fallback(rect, buf)
                return
            end
            dlog("image", "decoded"; px_w=size(pixels, 2), px_h=size(pixels, 1))
            ow._cached_pixels = pixels
            ow._cached_image_hash = img_id
            ow._cached_pixel_image = nothing
            ow._cached_encoded_data = nothing
            ow._cached_kitty_id = UInt32(0)
        elseif ow._decode_task !== nothing && ow._decode_target_hash == img_id
            # Background decode already running for this image
            if istaskdone(ow._decode_task)
                result = try fetch(ow._decode_task) catch; nothing end
                ow._decode_task = nothing
                ow._decode_target_hash = UInt64(0)
                if result !== nothing
                    ow._cached_pixels = result
                    ow._cached_image_hash = img_id
                    ow._cached_pixel_image = nothing
                    ow._cached_encoded_data = nothing
                    ow._cached_kitty_id = UInt32(0)
                    pixels_changed = false
                else
                    _render_image_fallback(rect, buf)
                    return
                end
            else
                # Still decoding — show braille from stale cache or placeholder
                _render_image_stale_or_placeholder(ow, rect, buf)
                return
            end
        else
            # Start background decode for large image
            ow._decode_task = nothing
            data_copy = img_data
            ow._decode_target_hash = img_id
            ow._decode_task = Threads.@spawn begin
                pixels = decode_png(data_copy)
                if pixels === nothing
                    pixels = decode_jpeg(data_copy)
                end
                pixels
            end
            _render_image_stale_or_placeholder(ow, rect, buf)
            return
        end
    end

    # Layer 2: PixelImage cache — rebuild when rect dimensions change
    pi = ow._cached_pixel_image
    needs_rebuild = pi === nothing || pi.cells_w != rect.width || pi.cells_h != rect.height
    if needs_rebuild
        pi = Tachikoma.PixelImage(rect.width, rect.height)
        ow._cached_pixel_image = pi
        ow._cached_encoded_data = nothing  # force re-encode on size change
        ow._cached_kitty_id = UInt32(0)    # invalidate Kitty image ID
    end

    # Only reload pixels when data changed or PixelImage was rebuilt
    if pixels_changed || needs_rebuild
        visible = _apply_viewport_transform(ow._cached_pixels,
                                             ow._img_offset_x, ow._img_offset_y, ow._img_zoom)
        Tachikoma.load_pixels!(pi, visible)
        ow._cached_encoded_data = nothing  # force re-encode after pixel reload
        ow._cached_kitty_id = UInt32(0)
    end

    # Render: prefer Frame (raster) when available, else Buffer (braille).
    frame = ow.current_frame
    gfx = Tachikoma.GRAPHICS_PROTOCOL[]
    if frame !== nothing && gfx != Tachikoma.gfx_none
        if gfx == Tachikoma.gfx_kitty
            needs_fresh = ow._cached_kitty_id == UInt32(0) ||
                          ow._cached_encoded_data === nothing ||
                          ow._cached_encoded_rect.width != rect.width ||
                          ow._cached_encoded_rect.height != rect.height
            if needs_fresh
                data = Tachikoma.encode_kitty(pi.pixels; decay=pi.decay,
                            cols=rect.width, rows=rect.height)
                if !isempty(data)
                    kid = _next_kitty_id()
                    data = _inject_kitty_id(data, kid)
                    ow._cached_kitty_id = kid
                    ow._cached_encoded_rect = rect
                    ow._cached_encoded_data = _kitty_placement_bytes(kid, rect.width, rect.height)
                    ow._cached_encoded_protocol = Tachikoma.gfx_kitty
                    Tachikoma.render_graphics!(frame, data, rect; pixels=pi.pixels, format=Tachikoma.gfx_fmt_kitty)
                    _force_gfx_blank!(frame.buffer, rect)
                end
            else
                Tachikoma.render_graphics!(frame, ow._cached_encoded_data, rect;
                    pixels=pi.pixels, format=Tachikoma.gfx_fmt_kitty)
                _force_gfx_blank!(frame.buffer, rect)
            end
        else
            if ow._cached_encoded_data === nothing || ow._cached_encoded_protocol != gfx
                data = Tachikoma.encode_sixel(pi.pixels; decay=pi.decay)
                ow._cached_encoded_data = data
                ow._cached_encoded_protocol = Tachikoma.gfx_sixel
            end
            data = ow._cached_encoded_data
            if !isempty(data)
                Tachikoma.render_graphics!(frame, data, rect; pixels=pi.pixels, format=Tachikoma.gfx_fmt_sixel)
                _force_gfx_blank!(frame.buffer, rect)
            end
        end
    else
        Tachikoma.render(pi, rect, buf)
    end
end

"""Force cells in a graphics region to _GFX_BLANK = Cell(' ', RESET).

Tachikoma's set_char! preserves existing bg when new style has NoColor bg.
render_graphics! uses RESET (NoColor bg), so the canvas background leaks
through and _filter_visible_gfx rejects the region. This bypasses set_char!
and writes _GFX_BLANK directly to the buffer array.
"""
function _force_gfx_blank!(buf::Tachikoma.Buffer, area::Tachikoma.Rect)
    blank = Tachikoma.Cell(' ', Tachikoma.Style())
    for row in area.y:(area.y + area.height - 1)
        for col in area.x:(area.x + area.width - 1)
            x_ok = col >= buf.area.x && col <= buf.area.x + buf.area.width - 1
            y_ok = row >= buf.area.y && row <= buf.area.y + buf.area.height - 1
            (x_ok && y_ok) || continue
            @inbounds buf.content[(row - buf.area.y) * buf.area.width + (col - buf.area.x) + 1] = blank
        end
    end
end

"""Show stale cached braille image or placeholder while background decode runs."""
function _render_image_stale_or_placeholder(ow::OutputWidget, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    # If we have stale pixels from a previous image, show them as braille
    if ow._cached_pixel_image !== nothing
        Tachikoma.render(ow._cached_pixel_image, rect, buf)
    else
        Tachikoma.set_string!(buf, rect.x + 2, rect.y,
            "[Decoding image...]",
            Tachikoma.Style(; fg=Theme.FG_MUTED))
    end
end

"""Fallback text when image cannot be decoded."""
function _render_image_fallback(rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    Tachikoma.set_string!(buf, rect.x + 2, rect.y,
        "[Image: unable to decode image data]",
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

