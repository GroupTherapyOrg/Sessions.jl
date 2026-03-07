# Layer 1: Kernel — Cell execution with workspace isolation and output capture

using Markdown: Markdown

# --- MIME-based output classification (Pluto parity) ---
# Follows Pluto's `allmimes` priority list, adapted for TUI rendering.
# Pluto order: table > divelement > text/html > images > tree > text/latex > text/plain
# TUI adaptation: when a graphics protocol is available (Kitty/Sixel), images are
# promoted ABOVE text/plain (like Pluto's browser). When no graphics protocol,
# text/plain wins (UnicodePlots renders as text).
# We use invokelatest for all showable checks (world age safety).

"""Image MIME types in preference order (matches Pluto's imagemimes)."""
const _IMAGE_MIMES = MIME[
    MIME"image/svg+xml"(),
    MIME"image/png"(),
    MIME"image/jpg"(),
    MIME"image/jpeg"(),
    MIME"image/bmp"(),
    MIME"image/gif"(),
]

"""
    _tui_showable(mime, value) -> Bool

World-age-safe check for whether `value` can be shown as `mime`.
Equivalent to Pluto's `pluto_showable` — uses `invokelatest` to avoid
MethodError from packages loaded in newer world ages.
"""
function _tui_showable(m::MIME, @nospecialize(value))::Bool
    try
        Base.invokelatest(showable, m, value)::Bool
    catch
        false
    end
end

"""
    _has_graphics_protocol() -> Bool

Check if the terminal supports a graphics protocol (Kitty or Sixel).
Uses Tachikoma's detected protocol (set at TUI startup).
"""
_has_graphics_protocol() = Tachikoma.GRAPHICS_PROTOCOL[] != Tachikoma.gfx_none

"""
    classify_output(value) -> Symbol

Classify a cell's return value using MIME dispatch (Pluto parity, adapted for TUI).
Tries MIME types in priority order and returns a Symbol for TUI rendering:
:nothing, :bond, :dataframe, :markdown, :text, or :image_png.

TUI priority depends on graphics capability:
- With Kitty/Sixel: images promoted above text/plain (like Pluto browser)
- Without graphics: text/plain promoted above images (UnicodePlots path)
"""
function classify_output(value)::Symbol
    value === nothing && return :nothing

    # 1. Bond (Sessions-specific, like Pluto's divelement)
    value isa Bond && return :bond

    # 2. Table (Pluto: application/vnd.pluto.table+object)
    if _is_table_value(value)
        return :dataframe
    end

    # 3. Markdown (Pluto renders text/html from Markdown.MD; we render natively)
    value isa Markdown.MD && return :markdown

    # 4. When graphics protocol available: check images BEFORE text/plain
    if _has_graphics_protocol()
        if _tui_showable(MIME"image/png"(), value)
            return :image_png
        end
        if _tui_showable(MIME"image/jpeg"(), value)
            return :image_jpeg
        end
    end

    # 5. SVG — text fallback (no rasterization needed, works without graphics protocol)
    if _tui_showable(MIME"image/svg+xml"(), value)
        return :image_svg
    end

    # 6. text/plain — terminal-native output (UnicodePlots, etc.)
    if _tui_showable(MIME"text/plain"(), value)
        return :text
    end

    # 7. Images — fallback for values with only image output (no text/plain)
    for m in _IMAGE_MIMES
        if _tui_showable(m, value)
            return :image_png
        end
    end

    return :text
end

"""Check if a value is Tables.jl-compatible tabular data (Pluto parity)."""
function _is_table_value(@nospecialize(value))::Bool
    # Direct duck typing for common types (fast path)
    value isa AbstractVector{<:NamedTuple} && return true
    # Check Tables.jl via loaded modules (like Pluto's integration)
    tables_mod = get(Base.loaded_modules,
        Base.PkgId(Base.UUID("bd369af6-aec1-5ad0-b16a-f7cc5008161c"), "Tables"), nothing)
    if tables_mod !== nothing
        try
            return Base.invokelatest(tables_mod.istable, value)::Bool
        catch; end
    end
    false
end

"""Generate a text representation of any value for fallback display.

Uses Pluto's IOContext pattern: color disabled, display size limited, :limit => true.
This ensures clean text for session caching and TUI rendering.
"""
function text_representation(value)::String
    value === nothing && return ""
    try
        sprint(; context=IOContext(devnull, :color => false, :limit => true, :displaysize => (40, 80))) do io
            Base.invokelatest(show, io, MIME"text/plain"(), value)
        end
    catch
        try
            sprint(; context=IOContext(devnull, :color => false, :limit => true)) do io
                Base.invokelatest(show, io, value)
            end
        catch
            repr(value)
        end
    end
end

"""Capture PNG bytes from a value that supports MIME"image/png"."""
function _capture_png_bytes(@nospecialize(value))::Union{Nothing, Vector{UInt8}}
    try
        io = IOBuffer()
        Base.invokelatest(show, io, MIME"image/png"(), value)
        take!(io)
    catch
        nothing
    end
end

"""Capture SVG source text from a value that supports MIME"image/svg+xml"."""
function _capture_svg_source(@nospecialize(value))::Union{Nothing, String}
    try
        io = IOBuffer()
        Base.invokelatest(show, io, MIME"image/svg+xml"(), value)
        String(take!(io))
    catch
        nothing
    end
end

"""Capture JPEG bytes from a value that supports MIME"image/jpeg"."""
function _capture_jpeg_bytes(@nospecialize(value))::Union{Nothing, Vector{UInt8}}
    try
        io = IOBuffer()
        Base.invokelatest(show, io, MIME"image/jpeg"(), value)
        take!(io)
    catch
        nothing
    end
end

# --- Error formatting ---

"""Format an exception with a clean, filtered stacktrace for display."""
function format_error(ex::Exception, bt)::String
    lines = String[]

    # Error message
    push!(lines, _format_error_message(ex))

    # Convert bt to StackFrames depending on format
    raw_frames = _to_stackframes(bt)
    frames = _filter_frames(raw_frames)
    if !isempty(frames)
        push!(lines, "Stacktrace:")
        for (i, frame) in enumerate(frames)
            file = string(frame.file)
            line_no = frame.line
            func = frame.func
            push!(lines, " [$i] $func at $file:$line_no")
        end
    end

    join(lines, '\n')
end

"""Format a user-friendly error message for specific exception types."""
function _format_error_message(ex::Exception)::String
    if ex isa UndefVarError
        return "UndefVarError: `$(ex.var)` is not defined"
    elseif ex isa MethodError
        f = ex.f
        args = ex.args
        types = join([string(typeof(a)) for a in args], ", ")
        return "MethodError: no method matching $(f)($(types))"
    elseif ex isa BoundsError
        if isdefined(ex, :i)
            return "BoundsError: attempt to access at index $(ex.i)"
        else
            return "BoundsError: attempt to access out of bounds"
        end
    elseif ex isa StackOverflowError
        return "StackOverflowError: infinite recursion detected"
    elseif ex isa InterruptException
        return "Execution interrupted"
    elseif ex isa Meta.ParseError
        return "ParseError: $(ex.msg)"
    elseif ex isa ErrorException
        return string(ex.msg)
    else
        return sprint(showerror, ex)
    end
end

"""Convert various backtrace formats to Vector{StackFrame}."""
function _to_stackframes(bt)::Vector{Base.StackTraces.StackFrame}
    # Already processed: Vector{Tuple{StackFrame, Int}} from CapturedException
    if bt isa Vector && !isempty(bt) && bt[1] isa Tuple
        return [frame for (frame, _) in bt]
    end
    # Raw backtrace (from catch_backtrace())
    try
        return stacktrace(bt)
    catch
        return Base.StackTraces.StackFrame[]
    end
end

"""Filter stackframes to remove internal frames (eval, Core, Base internals)."""
function _filter_frames(frames::Vector{Base.StackTraces.StackFrame})
    filter(frames) do frame
        file = string(frame.file)
        func = string(frame.func)
        # Skip internal Julia frames
        any(startswith(file, p) for p in ("./", "boot.jl", "loading.jl", "essentials.jl")) && return false
        func in ("eval", "top-level scope", "include", "macro expansion") && return false
        startswith(func, "#") && return false  # generated function names
        contains(file, "Base") && return false
        contains(file, "Core") && return false
        true
    end
end

"""Format a cell error from a CellOutput for TUI display."""
function format_cell_error(output::CellOutput)::String
    output.error === nothing && return ""
    ce = output.error
    # CapturedException has .processed_bt, not .bt
    bt = hasproperty(ce, :processed_bt) ? ce.processed_bt : backtrace()
    format_error(ce.ex, bt)
end

"""
The Workspace holds all cell-evaluated state in a dedicated module.
Each notebook gets its own workspace module so variables don't leak.
"""
mutable struct Workspace
    mod::Module
    ns::Symbol
end

let workspace_counter = Ref(0)
    global function Workspace()
        workspace_counter[] += 1
        ns = Symbol("SessionsWorkspace_", workspace_counter[])
        mod = Module(ns)
        # Pre-populate the workspace with Base
        Core.eval(mod, :(using Base))
        # Inject @bind and widget types so cells can use them directly
        Core.eval(mod, :(import Sessions: @bind, Slider, TextField, CheckBox, Select, NumberField, Button, CounterButton))
        Workspace(mod, ns)
    end
end

"""Execute a single cell in the workspace, capturing output and timing."""
function execute_cell!(workspace::Workspace, cell::Cell)
    cell.state = cell_running
    # Keep old output visible during execution (Pluto behavior) — replaced at the end

    # Set current cell ID so @bind knows which cell it's in
    _EXECUTING_CELL_ID[] = cell.id

    result = nothing
    err = nothing
    captured_stdout = ""
    t_start = time_ns()

    try
        expr = Meta.parse("begin\n$(cell.code)\nend")
        # Use a Pipe for stdout capture (IOBuffer doesn't work with redirect_stdout)
        old_stdout = stdout
        rd, wr = redirect_stdout()
        try
            result = Base.eval(workspace.mod, expr)
        finally
            redirect_stdout(old_stdout)
            close(wr)
        end
        captured_stdout = String(read(rd))
    catch e
        err = CapturedException(e, catch_backtrace())
    end

    t_end = time_ns()

    # Replace output atomically — old output was visible during execution
    out = CellOutput()
    out.result = err === nothing ? result : nothing
    out.stdout = captured_stdout
    out.error = err
    out.runtime_ns = t_end - t_start

    if err === nothing
        out.output_type = classify_output(result)
        out.text_representation = text_representation(result)
        if out.output_type == :image_png
            out.image_data = _capture_png_bytes(result)
        elseif out.output_type == :image_jpeg
            out.image_data = _capture_jpeg_bytes(result)
        elseif out.output_type == :image_svg
            svg_src = _capture_svg_source(result)
            if svg_src !== nothing
                out.text_representation = svg_src
            end
        end
        cell.output = out
        cell.state = cell_done
        mark_executed!(cell)
    else
        out.output_type = :error
        out.text_representation = sprint(showerror, err.ex)
        cell.output = out
        cell.state = cell_errored
        mark_executed!(cell)  # errors are also execution results — needed for session caching
    end
    cell.output
end

"""
Execute a notebook reactively: analyze dependencies, sort topologically, run in order.
Returns the notebook with all cells updated.
"""
function execute_notebook!(nb::Notebook; workspace::Workspace=Workspace())
    order = execution_order(nb)

    # Mark errable cells
    for (cell, err) in order.errable
        cell.state = cell_errored
        cell.output = CellOutput()
        cell.output.error = CapturedException(
            ErrorException("Reactivity error: $(typeof(err))"),
            backtrace()
        )
    end

    # Mark all runnable cells as queued so TUI can show them waiting
    for cell in order.runnable
        cell.disabled && continue
        cell.state = cell_queued
    end

    # Execute runnable cells in topological order (skip disabled)
    for cell in order.runnable
        cell.disabled && continue
        yield()  # let render loop draw queued/running states
        execute_cell!(workspace, cell)
    end

    nb
end

"""
Re-execute only the cells affected by changes to `changed_cells`.
"""
function execute_changed!(nb::Notebook, changed_cells::Vector{Cell}; workspace::Workspace=Workspace())
    order = execution_order(nb, changed_cells)

    for (cell, err) in order.errable
        cell.state = cell_errored
        cell.output = CellOutput()
        cell.output.error = CapturedException(
            ErrorException("Reactivity error: $(typeof(err))"),
            backtrace()
        )
    end

    # Mark all runnable cells as queued so TUI can show them waiting
    for cell in order.runnable
        cell.disabled && continue
        cell.state = cell_queued
    end

    for cell in order.runnable
        cell.disabled && continue
        yield()  # let render loop draw queued/running states
        execute_cell!(workspace, cell)
    end

    nb
end
