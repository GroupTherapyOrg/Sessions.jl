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

    # Tables.jl — detect BEFORE text/html (DataFrames registers text/html but we want our own rendering)
    if _is_table_like(result)
        table_json = try _serialize_table(result) catch; "" end
        if !isempty(table_json)
            return (output_type=:table, text_representation=table_json, stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=nothing)
        end
    end

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

# ── Table detection + serialization ──

"""Detect Tables.jl-compatible objects (DataFrames, CSV results, etc.)."""
function _is_table_like(result)
    # Find Tables module from loaded packages (not Main — it's in workspace module scope)
    tables_mod = _find_tables_module()
    tables_mod === nothing && return false
    try
        Base.invokelatest(getfield(tables_mod, :rowaccess), result)::Bool
    catch
        false
    end
end

function _find_tables_module()
    for (id, mod) in Base.loaded_modules
        id.name == "Tables" && return mod
    end
    nothing
end

"""Serialize a Tables.jl-compatible object as JSON for the coordinator."""
function _serialize_table(result)
    T = _find_tables_module()
    T === nothing && return ""
    rows_iter = Base.invokelatest(getfield(T, :rows), result)
    schema = Base.invokelatest(getfield(T, :schema), rows_iter)

    col_names = string.(schema.names)
    col_types = [_compact_type_name(t) for t in schema.types]
    ncol = length(col_names)

    # Count total rows (may iterate)
    nrow = try
        length(Base.invokelatest(getfield(T, :rows), result))
    catch
        0
    end

    # Extract first N rows as string arrays
    max_rows = 100
    buf = IOBuffer()
    print(buf, "{\"cols\":[")
    for (i, n) in enumerate(col_names)
        i > 1 && print(buf, ",")
        print(buf, "\"", _json_esc(n), "\"")
    end
    print(buf, "],\"types\":[")
    for (i, t) in enumerate(col_types)
        i > 1 && print(buf, ",")
        print(buf, "\"", _json_esc(t), "\"")
    end
    print(buf, "],\"nrow\":", nrow, ",\"ncol\":", ncol, ",\"rows\":[")

    row_count = 0
    for row in Base.invokelatest(getfield(T, :rows), result)
        row_count += 1
        row_count > max_rows && break
        row_count > 1 && print(buf, ",")
        print(buf, "[")
        for (j, name) in enumerate(schema.names)
            j > 1 && print(buf, ",")
            val = try
                Base.invokelatest(getproperty, row, name)
            catch
                nothing
            end
            print(buf, "\"", _json_esc(_cell_str(val)), "\"")
        end
        print(buf, "]")
    end
    print(buf, "]}")
    String(take!(buf))
end

function _json_esc(s::AbstractString)
    replace(replace(replace(replace(s,
        '\\' => "\\\\"),
        '"' => "\\\""),
        '\n' => "\\n"),
        '\r' => "\\r")
end

function _compact_type_name(T::Type)
    s = string(T)
    # Strip module prefixes for common types
    s = replace(s, r"^.*\." => "")
    # Shorten Union{Missing, X} to X?
    m = match(r"^Union\{Missing,\s*(.+)\}$", s)
    m !== nothing && return m.captures[1] * "?"
    m = match(r"^Union\{(.+),\s*Missing\}$", s)
    m !== nothing && return m.captures[1] * "?"
    s
end

function _cell_str(val)
    val === nothing && return ""
    val === missing && return "missing"
    val isa AbstractString && return val
    val isa Bool && return val ? "true" : "false"
    sprint(show, val; context=IOContext(devnull, :compact => true, :limit => true))
end

# ── Bond serialization ──

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
