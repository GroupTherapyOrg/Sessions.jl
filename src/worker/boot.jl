# boot.jl — Loaded into each Malt worker process
#
# Defines execution functions directly in the worker's Main scope.
# No module wrapper — Malt eval can't define modules.

import Markdown

# ── Workspace ──

const _ws_counter = Ref(0)

mutable struct SessionsWorkspace
    mod::Module
    notebook_path::String
end

function _create_workspace(; notebook_path::String="")
    _ws_counter[] += 1
    ns = Symbol("SW_", _ws_counter[])
    mod = Module(ns)
    Core.eval(mod, :(import Base))
    # Pre-inject Markdown so md"..." works immediately
    Core.eval(mod, :(import Markdown))

    # Activate notebook directory if Project.toml exists
    if !isempty(notebook_path) && isfile(notebook_path)
        dir = dirname(abspath(notebook_path))
        proj = joinpath(dir, "Project.toml")
        if isfile(proj)
            try
                Core.eval(mod, :(import Pkg; Pkg.activate($(dir))))
            catch; end
        end
    end

    SessionsWorkspace(mod, notebook_path)
end

# ── Output struct ──

# Use NamedTuple for output — serializes across process boundary without type issues
const _empty_output = (output_type=:nothing, text_representation="", stdout_text="", runtime_ns=UInt64(0), error_text="", image_bytes=nothing)

# ── Cell execution ──

function _worker_execute(ws::SessionsWorkspace, code::String)
    isempty(strip(code)) && return _empty_output

    t0 = time_ns()
    stdout_str = ""
    result = nothing
    had_error = false
    error_text = ""

    try
        old_stdout = stdout
        rd, wr = redirect_stdout()
        stdout_task = @async try; read(rd, String); catch; ""; end

        try
            result = Base.invokelatest(include_string, ws.mod, code,
                isempty(ws.notebook_path) ? "cell" : ws.notebook_path)
        catch e
            had_error = true
            error_text = sprint(showerror, e, catch_backtrace())
        finally
            redirect_stdout(old_stdout)
            close(wr)
            stdout_str = fetch(stdout_task)
            close(rd)
        end
    catch e
        had_error = true
        error_text = sprint(showerror, e, catch_backtrace())
    end

    runtime = UInt64(time_ns() - t0)
    suppress = !isempty(strip(code)) && endswith(rstrip(code), ';')

    if had_error
        return (output_type=:error, text_representation=error_text, stdout_text=stdout_str, runtime_ns=runtime, error_text=error_text, image_bytes=nothing)
    end

    if suppress || result === nothing
        return (output_type=:nothing, text_representation="", stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=nothing)
    end

    _classify_and_capture(result, stdout_str, runtime)
end

function _classify_and_capture(result, stdout_str, runtime)
    # Bond (@bind widget) — detect by duck typing (has .element and .defines fields)
    if hasproperty(result, :element) && hasproperty(result, :defines)
        widget = result.element
        var_name = result.defines
        # Return structured bond data — coordinator renders with @island SSR
        bond_data = _serialize_bond(widget, var_name)
        return (output_type=:bond, text_representation=bond_data, stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=nothing)
    end

    # Markdown
    result isa Markdown.MD && return (output_type=:markdown, text_representation=sprint(io -> Markdown.html(io, result)), stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=nothing)

    # text/html
    if _try_showable(MIME"text/html"(), result)
        html = try
            sprint(io -> Base.invokelatest(show, io, MIME"text/html"(), result))
        catch; ""; end
        if !isempty(html)
            return (output_type=:html, text_representation=html, stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=nothing)
        end
    end

    # image/png
    if _try_showable(MIME"image/png"(), result)
        try
            io = IOBuffer()
            Base.invokelatest(show, io, MIME"image/png"(), result)
            bytes = take!(io)
            text = _text_repr(result)
            return (output_type=:image_png, text_representation=text, stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=bytes)
        catch; end
    end

    # image/svg+xml
    if _try_showable(MIME"image/svg+xml"(), result)
        try
            svg = sprint(io -> Base.invokelatest(show, io, MIME"image/svg+xml"(), result))
            return (output_type=:image_svg, text_representation=svg, stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=nothing)
        catch; end
    end

    # text/plain
    text = _text_repr(result)
    return (output_type=:text, text_representation=text, stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=nothing)
end

"""Serialize bond widget info for the coordinator to render with @island SSR."""
function _serialize_bond(widget, var_name)
    # Duck-type slider detection: has .values and .default fields
    if hasproperty(widget, :values) && hasproperty(widget, :default)
        vals = widget.values
        min_v = first(vals)
        max_v = last(vals)
        step_v = length(vals) > 1 ? vals[2] - vals[1] : 1
        def_v = widget.default
        return "slider:$(var_name):$(min_v):$(max_v):$(step_v):$(def_v)"
    end
    # Fallback
    wtype = nameof(typeof(widget))
    return "widget:$(var_name):$(wtype)"
end

function _try_showable(mime, value)
    try; Base.invokelatest(showable, mime, value)::Bool; catch; false; end
end

function _text_repr(value)
    try
        sprint(; context=IOContext(devnull, :color => false, :limit => true, :displaysize => (40, 120))) do io
            Base.invokelatest(show, io, MIME"text/plain"(), value)
        end
    catch
        sprint(show, value)
    end
end

nothing
