# boot.jl — Loaded into each Malt worker process
#
# Defines execution functions directly in the worker's Main scope.
# No module wrapper — Malt eval can't define modules.

import Markdown
using Logging

# ── Log Capture ──
# Use NamedTuples (not custom structs) so Malt can serialize across process boundary

const _LogRecordNT = @NamedTuple{level::Int32, message::String, file::String, line::Int, module_name::String, kwargs::Vector{Pair{String,String}}}

mutable struct _SessionsLogger <: AbstractLogger
    logs::Vector{_LogRecordNT}
    log_file::Union{String,Nothing}  # path to temp file for real-time streaming
    min_level::LogLevel
end

Logging.shouldlog(l::_SessionsLogger, level, _module, group, id) = level >= l.min_level
Logging.min_enabled_level(l::_SessionsLogger) = l.min_level
Logging.catch_exceptions(::_SessionsLogger) = true

function Logging.handle_message(l::_SessionsLogger, level, message, _module, group, id, file, line; kwargs...)
    kw = Pair{String,String}[string(k) => try sprint(show, v) catch; "?" end for (k, v) in kwargs]
    rec = (level=Int32(level.level), message=string(message), file=string(file), line=Int(line), module_name=string(_module), kwargs=kw)
    push!(l.logs, rec)
    # Write to shared log file for real-time streaming to coordinator
    if l.log_file !== nothing
        try
            open(l.log_file, "a") do io
                # Simple line format: level|message|kwarg1=val1,kwarg2=val2
                kw_str = join(["$(k)=$(v)" for (k, v) in kw], ",")
                println(io, "$(rec.level)|$(rec.message)|$(kw_str)")
                flush(io)
            end
        catch; end
    end
end

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
    # Pre-inject Pkg so Pkg.activate() etc. work immediately in cells.
    # Markdown is NOT pre-injected — users must `using Markdown` explicitly.
    # (The boot script imports Markdown at top level for output classification.)
    Core.eval(mod, :(import Pkg))

    # Set working directory to notebook's location so pwd() and @__DIR__ work
    if !isempty(notebook_path) && isfile(notebook_path)
        try cd(dirname(abspath(notebook_path))) catch; end
    end

    SessionsWorkspace(mod, notebook_path)
end

# ── Output struct ──

# Use NamedTuple for output — serializes across process boundary without type issues
const _empty_output = (output_type=:nothing, text_representation="", stdout_text="", runtime_ns=UInt64(0), error_text="", image_bytes=nothing, logs=_LogRecordNT[])

# ── Cell execution ──

function _worker_execute(ws::SessionsWorkspace, code::String; log_file::String="")
    isempty(strip(code)) && return _empty_output

    t0 = time_ns()
    stdout_str = ""
    result = nothing
    had_error = false
    error_text = ""
    logs_buffer = _LogRecordNT[]
    lf = isempty(log_file) ? nothing : log_file
    logger = _SessionsLogger(logs_buffer, lf, Logging.Debug)

    Logging.with_logger(logger) do
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
    end

    runtime = UInt64(time_ns() - t0)
    suppress = !isempty(strip(code)) && endswith(rstrip(code), ';')

    if had_error
        return (output_type=:error, text_representation=error_text, stdout_text=stdout_str, runtime_ns=runtime, error_text=error_text, image_bytes=nothing, logs=logs_buffer)
    end

    if suppress || result === nothing
        return (output_type=:nothing, text_representation="", stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=nothing, logs=logs_buffer)
    end

    _classify_and_capture(result, stdout_str, runtime, logs_buffer)
end

function _classify_and_capture(result, stdout_str, runtime, logs_buffer=_LogRecordNT[])
    # Bond (@bind widget) — detect by duck typing (has .element and .defines fields)
    if hasproperty(result, :element) && hasproperty(result, :defines)
        widget = result.element
        var_name = result.defines
        # Return structured bond data — coordinator renders with @island SSR
        bond_data = _serialize_bond(widget, var_name)
        return (output_type=:bond, text_representation=bond_data, stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=nothing, logs=logs_buffer)
    end

    # Markdown
    result isa Markdown.MD && return (output_type=:markdown, text_representation=sprint(io -> Markdown.html(io, result)), stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=nothing, logs=logs_buffer)

    # text/html — Pluto parity: anything that defines `show(io, MIME"text/html"(), x)`
    # gets to render itself (DataFrames, HypertextLiteral, custom widgets, etc.).
    # We do NOT intercept Tables.jl-compatible objects with a custom renderer —
    # that diverges from Pluto and breaks any third-party widget that ships its
    # own HTML representation.
    if _try_showable(MIME"text/html"(), result)
        html = try
            sprint(io -> Base.invokelatest(show, io, MIME"text/html"(), result))
        catch; ""; end
        if !isempty(html)
            return (output_type=:html, text_representation=html, stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=nothing, logs=logs_buffer)
        end
    end

    # image/png
    if _try_showable(MIME"image/png"(), result)
        try
            io = IOBuffer()
            Base.invokelatest(show, io, MIME"image/png"(), result)
            bytes = take!(io)
            text = _text_repr(result)
            return (output_type=:image_png, text_representation=text, stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=bytes, logs=logs_buffer)
        catch; end
    end

    # image/svg+xml
    if _try_showable(MIME"image/svg+xml"(), result)
        try
            svg = sprint(io -> Base.invokelatest(show, io, MIME"image/svg+xml"(), result))
            return (output_type=:image_svg, text_representation=svg, stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=nothing, logs=logs_buffer)
        catch; end
    end

    # Inspectable collections — render as collapsible tree HTML
    if _is_tree_value(result)
        tree_html = try _render_tree_html(result) catch; "" end
        if !isempty(tree_html)
            return (output_type=:tree, text_representation=tree_html, stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=nothing, logs=logs_buffer)
        end
    end

    # text/plain
    text = _text_repr(result)
    return (output_type=:text, text_representation=text, stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=nothing, logs=logs_buffer)
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

# ── Tree view (collapsible inspect) ──

function _is_tree_value(@nospecialize(value))::Bool
    value isa Number && return false
    value isa AbstractString && return false
    value isa Symbol && return false
    value isa AbstractChar && return false
    value isa Type && return false
    value isa Enum && return false
    value isa Regex && return false
    value === nothing && return false
    value === missing && return false
    value isa AbstractVector && return true
    value isa AbstractDict && return true
    value isa Tuple && return length(value) > 0
    value isa NamedTuple && return true
    value isa AbstractSet && return true
    value isa Pair && return true
    T = typeof(value)
    nf = fieldcount(T)
    nf > 0 && !(T <: IO) && !(T <: Ref) && return true
    false
end

function _is_leaf(@nospecialize(v))::Bool
    v isa Number || v isa AbstractString || v isa Symbol || v isa AbstractChar ||
    v isa Type || v isa Enum || v isa Regex || v === nothing || v === missing
end

function _html_esc(s::AbstractString)
    replace(replace(replace(s, '&' => "&amp;"), '<' => "&lt;"), '>' => "&gt;")
end

function _short_type(T::Type)
    s = string(T)
    length(s) > 60 && return _html_esc(s[1:57] * "...")
    _html_esc(s)
end

function _leaf_repr(@nospecialize(v))
    try
        sprint(; context=IOContext(devnull, :color => false, :limit => true, :displaysize => (1, 80))) do io
            Base.invokelatest(show, io, MIME"text/plain"(), v)
        end
    catch
        repr(v)
    end
end

function _render_tree_html(@nospecialize(value); depth::Int=0, max_depth::Int=4, max_items::Int=25)
    buf = IOBuffer()
    _tree_node!(buf, value; depth, max_depth, max_items)
    String(take!(buf))
end

function _tree_node!(buf::IOBuffer, @nospecialize(value); depth::Int=0, max_depth::Int=4, max_items::Int=25)
    if depth >= max_depth || _is_leaf(value)
        print(buf, """<span class="jl-tree-val">""", _html_esc(_leaf_repr(value)), "</span>")
        return
    end

    T = typeof(value)
    tname = _short_type(T)
    open_attr = ""

    if value isa AbstractDict
        n = length(value)
        print(buf, """<details class="jl-tree"$(open_attr)><summary><span class="jl-tree-prefix">$(tname)</span> <span class="jl-tree-count">with $(n) entr$(n == 1 ? "y" : "ies")</span></summary><div class="jl-tree-items">""")
        for (i, (k, v)) in enumerate(value)
            i > max_items && (print(buf, """<div class="jl-tree-more">… $(n - max_items) more</div>"""); break)
            print(buf, """<div class="jl-tree-row"><span class="jl-tree-key">""", _html_esc(repr(k)), """</span><span class="jl-tree-sep"> ⇒ </span>""")
            _tree_node!(buf, v; depth=depth+1, max_depth, max_items)
            print(buf, "</div>")
        end
        print(buf, "</div></details>")

    elseif value isa AbstractVector
        n = length(value)
        print(buf, """<details class="jl-tree"$(open_attr)><summary><span class="jl-tree-prefix">$(tname)</span> <span class="jl-tree-count">with $(n) element$(n == 1 ? "" : "s")</span></summary><div class="jl-tree-items">""")
        for i in 1:min(n, max_items)
            print(buf, """<div class="jl-tree-row"><span class="jl-tree-key">$(i)</span><span class="jl-tree-sep"> : </span>""")
            _tree_node!(buf, value[i]; depth=depth+1, max_depth, max_items)
            print(buf, "</div>")
        end
        n > max_items && print(buf, """<div class="jl-tree-more">… $(n - max_items) more</div>""")
        print(buf, "</div></details>")

    elseif value isa Tuple
        n = length(value)
        print(buf, """<details class="jl-tree"$(open_attr)><summary><span class="jl-tree-prefix">Tuple</span> <span class="jl-tree-count">with $(n) element$(n == 1 ? "" : "s")</span></summary><div class="jl-tree-items">""")
        for i in 1:min(n, max_items)
            print(buf, """<div class="jl-tree-row"><span class="jl-tree-key">$(i)</span><span class="jl-tree-sep"> : </span>""")
            _tree_node!(buf, value[i]; depth=depth+1, max_depth, max_items)
            print(buf, "</div>")
        end
        print(buf, "</div></details>")

    elseif value isa NamedTuple
        ks = keys(value)
        n = length(ks)
        print(buf, """<details class="jl-tree"$(open_attr)><summary><span class="jl-tree-prefix">NamedTuple</span> <span class="jl-tree-count">with $(n) field$(n == 1 ? "" : "s")</span></summary><div class="jl-tree-items">""")
        for k in ks
            print(buf, """<div class="jl-tree-row"><span class="jl-tree-key">$(k)</span><span class="jl-tree-sep"> = </span>""")
            _tree_node!(buf, value[k]; depth=depth+1, max_depth, max_items)
            print(buf, "</div>")
        end
        print(buf, "</div></details>")

    elseif value isa AbstractSet
        n = length(value)
        print(buf, """<details class="jl-tree"$(open_attr)><summary><span class="jl-tree-prefix">$(tname)</span> <span class="jl-tree-count">with $(n) element$(n == 1 ? "" : "s")</span></summary><div class="jl-tree-items">""")
        for (i, v) in enumerate(value)
            i > max_items && (print(buf, """<div class="jl-tree-more">… $(n - max_items) more</div>"""); break)
            print(buf, """<div class="jl-tree-row">""")
            _tree_node!(buf, v; depth=depth+1, max_depth, max_items)
            print(buf, "</div>")
        end
        print(buf, "</div></details>")

    elseif value isa Pair
        print(buf, """<span class="jl-tree-val">""")
        _tree_node!(buf, value.first; depth=depth+1, max_depth, max_items)
        print(buf, """<span class="jl-tree-sep"> => </span>""")
        _tree_node!(buf, value.second; depth=depth+1, max_depth, max_items)
        print(buf, "</span>")

    else
        # Struct with fields
        fnames = fieldnames(T)
        n = length(fnames)
        print(buf, """<details class="jl-tree"$(open_attr)><summary><span class="jl-tree-prefix">$(tname)</span> <span class="jl-tree-count">with $(n) field$(n == 1 ? "" : "s")</span></summary><div class="jl-tree-items">""")
        for fname in fnames
            print(buf, """<div class="jl-tree-row"><span class="jl-tree-key">$(fname)</span><span class="jl-tree-sep"> = </span>""")
            fval = try getfield(value, fname) catch; "#undef" end
            _tree_node!(buf, fval; depth=depth+1, max_depth, max_items)
            print(buf, "</div>")
        end
        print(buf, "</div></details>")
    end
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
