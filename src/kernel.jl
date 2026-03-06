# Layer 1: Kernel — Cell execution with workspace isolation and output capture

using Markdown: Markdown

"""
Classify a cell's return value into an output type for TUI rendering.
Returns a Symbol: :nothing, :error, :markdown, :dataframe, :image_png, or :text.
"""
function classify_output(value)::Symbol
    value === nothing && return :nothing
    value isa Markdown.MD && return :markdown
    # Check for Tables.jl-compatible tabular data (duck typing)
    try
        mod = parentmodule(typeof(value))
        if isdefined(mod, :Tables) || _has_table_interface(value)
            return :dataframe
        end
    catch; end
    # Check for image/png MIME support (plots)
    if hasmethod(show, Tuple{IO, MIME"image/png", typeof(value)})
        return :image_png
    end
    return :text
end

"""Check if a value looks like tabular data (duck typing without Tables.jl dependency)."""
function _has_table_interface(value)
    # Common table-like types: Vector{<:NamedTuple}, Matrix, etc.
    value isa AbstractVector{<:NamedTuple} && return true
    # Check if Tables module is loaded and value is a table
    tables_mod = get(Base.loaded_modules, Base.PkgId(Base.UUID("bd369af6-aec1-5ad0-b16a-f7cc5008161c"), "Tables"), nothing)
    if tables_mod !== nothing
        try
            return tables_mod.istable(value)
        catch; end
    end
    false
end

"""Generate a text representation of any value for fallback display."""
function text_representation(value)::String
    value === nothing && return ""
    try
        sprint(show, MIME"text/plain"(), value; context=:limit => true)
    catch
        try
            sprint(show, value)
        catch
            repr(value)
        end
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
        Workspace(mod, ns)
    end
end

"""Execute a single cell in the workspace, capturing output and timing."""
function execute_cell!(workspace::Workspace, cell::Cell)
    cell.state = cell_running
    cell.output = CellOutput()

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

    cell.output.result = err === nothing ? result : nothing
    cell.output.stdout = captured_stdout
    cell.output.error = err
    cell.output.runtime_ns = t_end - t_start

    if err === nothing
        cell.output.output_type = classify_output(result)
        cell.output.text_representation = text_representation(result)
        cell.state = cell_done
        mark_executed!(cell)
    else
        cell.output.output_type = :error
        cell.output.text_representation = sprint(showerror, err.ex)
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
