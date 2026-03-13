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

    # 4. Images — always check BEFORE text/plain. With a graphics protocol
    #    (Kitty/Sixel) images render as sharp raster. Without one, images
    #    render as braille/unicode-block fallback — still far better than
    #    showing "Figure()" text. This ensures CairoMakie, Plots.jl, etc.
    #    always produce visual output.
    if _tui_showable(MIME"image/png"(), value)
        return :image_png
    end
    if _tui_showable(MIME"image/jpeg"(), value)
        return :image_jpeg
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
    elseif ex isa Base.Meta.ParseError
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

"""Symbols to inject into every workspace module.

Built once at load time from the already-loaded Sessions module, so workspace
creation never touches the package loader (immune to LOAD_PATH corruption from
notebook `Pkg.activate()` calls).
"""
const _SESSIONS_MODULE = @__MODULE__

const _WORKSPACE_INJECTIONS = Pair{Symbol,Any}[
    :Slider             => Slider,
    :TextField          => TextField,
    :CheckBox           => CheckBox,
    :Select             => Select,
    :NumberField        => NumberField,
    :Button             => Button,
    :CounterButton      => CounterButton,
]

"""
The Workspace holds all cell-evaluated state in a dedicated module.
Each notebook gets its own workspace module so variables don't leak.

When `notebook_path` is provided:
- `@__DIR__` resolves to the notebook's directory (via `include_string`)
- The nearest `Project.toml` environment is auto-activated in LOAD_PATH
"""
mutable struct Workspace
    mod::Module
    ns::Symbol
    notebook_path::String  # absolute path to notebook file (for @__DIR__)
end

"""Walk up from `path` to find the nearest directory containing Project.toml."""
function _find_workspace_project(path::String)::Union{String, Nothing}
    dir = isempty(path) ? pwd() : dirname(abspath(path))
    for _ in 1:20
        isfile(joinpath(dir, "Project.toml")) && return dir
        parent = dirname(dir)
        parent == dir && break
        dir = parent
    end
    nothing
end

let workspace_counter = Ref(0)
    global function Workspace(; notebook_path::String="")
        workspace_counter[] += 1
        ns = Symbol("SessionsWorkspace_", workspace_counter[])
        mod = Module(ns)
        nb_abspath = isempty(notebook_path) ? "" : abspath(notebook_path)

        # Pre-populate the workspace with Base
        Core.eval(mod, :(using Base))

        # Auto-activate nearest Project.toml environment so `using X` works
        # for any package in the notebook's project — like running a .jl file
        # from that project directory.
        project_dir = _find_workspace_project(notebook_path)
        if project_dir !== nothing
            lp = "$project_dir"
            if lp ∉ LOAD_PATH
                pushfirst!(LOAD_PATH, lp)
            end
        end

        # Pre-import Markdown (Pluto parity — md"..." strings need @md_str)
        Core.eval(mod, :(using Markdown))
        # Inject @bind and widget types so cells can use them directly.
        # We inject the already-loaded objects directly instead of `import Sessions:`
        # because a previous notebook's Pkg.activate() may have corrupted LOAD_PATH,
        # making the Sessions package unfindable by the package loader.
        for (sym, val) in _WORKSPACE_INJECTIONS
            Core.eval(mod, :(const $sym = $val))
        end
        # Macro injection requires binding the mangled name that Julia looks up
        Core.eval(mod, :(var"@bind" = $_SESSIONS_MODULE.var"@bind"))
        Workspace(mod, ns, nb_abspath)
    end
end

"""
    _ends_with_semicolon(code) -> Bool

Check if the last non-whitespace, non-comment token in `code` is a semicolon.
Mirrors Pluto/REPL convention: trailing `;` suppresses cell output display.
"""
function _ends_with_semicolon(code::AbstractString)::Bool
    # Split into lines, walk backwards, skip blank/comment-only lines
    lines = split(code, '\n')
    for i in length(lines):-1:1
        line = rstrip(lines[i])
        isempty(line) && continue
        # Strip trailing comment (everything after unquoted #)
        code_part = _strip_comment(line)
        code_part = rstrip(code_part)
        isempty(code_part) && continue  # line was only a comment
        return endswith(code_part, ';')
    end
    false
end

"""Strip trailing `# comment` from a line, respecting string literals."""
function _strip_comment(line::AbstractString)
    in_string = false
    prev_backslash = false
    for (pos, c) in pairs(line)
        if !in_string && c == '#'
            return pos == 1 ? "" : SubString(line, 1, prevind(line, pos))
        elseif c == '"' && !prev_backslash
            in_string = !in_string
        end
        prev_backslash = c == '\\' && in_string
    end
    line
end

"""Execute a single cell in the workspace, capturing output and timing.

IMPORTANT: This function guarantees that `cell.state` transitions to either
`cell_done` or `cell_errored` — never left stuck in `cell_running`. A stuck
cell permanently blocks all future execution via the guard check.
"""
function execute_cell!(workspace::Workspace, cell::Cell)
    cell.state = cell_running
    cell._exec_start_time = time()
    dlog("kernel", "execute_cell! start"; cell_id=cell.id, code_len=length(cell.code))

    # Keep old output visible during execution (Pluto behavior) — replaced at the end

    # Set current cell ID so @bind knows which cell it's in
    _EXECUTING_CELL_ID[] = cell.id

    result = nothing
    err = nothing
    captured_stdout = ""
    t_start = time_ns()

    # Snapshot LOAD_PATH entries that Sessions.jl needs.  A cell may call
    # Pkg.activate() which replaces LOAD_PATH entries — we re-inject any
    # missing host entries after execution so Sessions.jl's own deps
    # (Tachikoma, PDE, etc.) remain loadable.
    host_paths = copy(LOAD_PATH)

    try
        code = "begin\n$(cell.code)\nend"
        # Stdout capture via redirect_stdout. Under Tachikoma TUI, the global
        # stdout may already be redirected. This is process-wide and not
        # thread-safe, so we use a lock to serialize redirects and a timeout
        # on read to prevent indefinite blocking.
        old_stdout = stdout
        stdout_captured = false
        local rd, wr
        try
            rd, wr = redirect_stdout()
            stdout_captured = true
        catch ex
            dlog("kernel", "redirect_stdout failed"; err=sprint(showerror, ex))
        end
        try
            # Use include_string with the notebook path so @__DIR__ resolves
            # to the notebook's directory (like running a normal .jl file).
            dlog("kernel", "eval begin"; cell_id=cell.id)
            if !isempty(workspace.notebook_path)
                result = Base.include_string(workspace.mod, code, workspace.notebook_path)
            else
                result = Base.eval(workspace.mod, Base.Meta.parse(code))
            end
            dlog("kernel", "eval done"; cell_id=cell.id)
        finally
            if stdout_captured
                try redirect_stdout(old_stdout) catch; end
                try close(wr) catch; end
            end
        end
        if stdout_captured
            try
                # Read with a timeout to prevent hanging on broken pipe
                captured_stdout = _read_pipe_timeout(rd, 5.0)
            catch ex
                dlog("kernel", "stdout read failed"; err=sprint(showerror, ex))
            end
        end
    catch e
        err = CapturedException(e, catch_backtrace())
        dlog("kernel", "cell error"; cell_id=cell.id, err=sprint(showerror, e))
    finally
        # Re-inject any host LOAD_PATH entries that a cell's Pkg.activate()
        # may have removed.  The cell's additions stay (so subsequent cells
        # in the same notebook can `using` packages from the activated env),
        # but Sessions.jl's own paths are guaranteed present.
        for hp in reverse(host_paths)
            if hp ∉ LOAD_PATH
                pushfirst!(LOAD_PATH, hp)
            end
        end
    end

    t_end = time_ns()

    # Build output — wrapped in try to guarantee state transition
    out = CellOutput()
    out.result = err === nothing ? result : nothing
    out.stdout = captured_stdout
    out.error = err
    out.runtime_ns = t_end - t_start

    try
        # Trailing semicolon suppresses result display (Pluto/REPL convention).
        suppress = err === nothing && _ends_with_semicolon(cell.code)

        if err === nothing
            if suppress
                out.output_type = :nothing
                out.text_representation = ""
                out.result = nothing
            else
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
                dlog("kernel", "output classified"; cell_id=cell.id,
                    otype=out.output_type, has_image=out.image_data !== nothing)
            end
            cell.output = out
            cell.state = cell_done
            mark_executed!(cell)
        else
            out.output_type = :error
            out.text_representation = try
                sprint(showerror, err.ex)
            catch
                "Error formatting exception"
            end
            cell.output = out
            cell.state = cell_errored
            mark_executed!(cell)
        end
    catch classify_err
        # Output classification itself failed — still mark cell as done
        dlog("kernel", "output classify FAILED"; cell_id=cell.id,
            err=sprint(showerror, classify_err))
        out.output_type = :error
        out.text_representation = "Internal error during output processing: $(sprint(showerror, classify_err))"
        cell.output = out
        cell.state = cell_errored
        mark_executed!(cell)
    end
    dlog("kernel", "execute_cell! done"; cell_id=cell.id, state=cell.state,
        runtime_ms=round((t_end - t_start) / 1_000_000, digits=1))
    cell.output
end

"""Read all bytes from a pipe with a timeout. Returns String."""
function _read_pipe_timeout(rd::IO, timeout_s::Float64)::String
    result = Channel{String}(1)
    reader = @async begin
        try
            String(read(rd))
        catch
            ""
        end
    end
    deadline = time() + timeout_s
    while !istaskdone(reader) && time() < deadline
        sleep(0.01)
    end
    if istaskdone(reader)
        try fetch(reader) catch; "" end
    else
        dlog("kernel", "stdout read TIMEOUT after $(timeout_s)s — closing pipe")
        try close(rd) catch end
        ""
    end
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
        save_session!(nb)  # incremental save after each cell
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
        save_session!(nb)  # incremental save after each cell
    end

    nb
end
