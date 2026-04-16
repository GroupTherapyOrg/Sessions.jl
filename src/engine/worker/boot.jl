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

function _worker_execute(ws::SessionsWorkspace, code::String; log_file::String="", cell_id::String="")
    isempty(strip(code)) && return _empty_output

    t0 = time_ns()
    stdout_str = ""
    result = nothing
    had_error = false
    error_text = ""
    logs_buffer = _LogRecordNT[]
    lf = isempty(log_file) ? nothing : log_file
    logger = _SessionsLogger(logs_buffer, lf, Logging.Debug)

    # Tell SessionsUI's @bind macro which cell is executing so bonds get
    # registered against a real cell_id. Without this every bond was
    # stored under UUID(0) (the "no cell context" sentinel) and the
    # coordinator's `get(nb.cells, UUID(0), nothing)` lookup always
    # failed, so downstream cells never re-ran on slider drags.
    if !isempty(cell_id)
        try
            Sessions.SessionsUI._EXECUTING_CELL_ID[] = Base.UUID(cell_id)
        catch; end
    end

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
    # Bonds, BoundSlider, BoundCheckBox, etc. all define MIME"text/html" via
    # SessionsUI.Base.show, so they fall through to the generic html branch
    # below — no per-widget intercept here. SessionsUI's show emits the
    # canonical `<bond def="x">…widget…</bond>` HTML; the page-level
    # BOND_BRIDGE_JS in Sessions wires input events back over WS.

    # Markdown
    result isa Markdown.MD && return (output_type=:markdown, text_representation=sprint(io -> Markdown.html(io, result)), stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=nothing, logs=logs_buffer)

    # Tables.jl — Pluto parity. Pluto's MIME order has `pluto.table+object`
    # BEFORE `text/html` so DataFrames don't fall back to DataFrames.jl's own
    # HTML (which gives the squished "Int64Int64Float64" header rendering).
    # We do the same: detect Tables.jl-compatible values, serialize to a
    # structured JSON the server renders into Pluto-style <table.pluto-table>
    # with sticky headers + hover-reveal type row.
    if _is_table_like(result)
        json = try _serialize_table(result) catch; "" end
        if !isempty(json)
            return (output_type=:table, text_representation=json, stdout_text=stdout_str, runtime_ns=runtime, error_text="", image_bytes=nothing, logs=logs_buffer)
        end
    end

    # text/html — anything else that defines `show(io, MIME"text/html"(), x)`
    # (HypertextLiteral, custom widgets, our own Bond, etc.).
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

    # Inspectable collections — render as collapsible tree HTML.
    # Delegate both the predicate and the renderer to the canonical
    # implementations in Sessions.web_rendering so worker + server stay
    # in sync (same DOM, same depth, no parameter drift).
    if Base.invokelatest(getfield(Sessions, :_is_tree_value), result)
        tree_html = try
            Base.invokelatest(getfield(Sessions, :_render_tree_html), result)
        catch; ""; end
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

function _try_showable(mime, value)
    try; Base.invokelatest(showable, mime, value)::Bool; catch; false; end
end

# ── Tree view (collapsible inspect) ──
# Tree predicate + HTML renderer live in Sessions/src/engine/web_rendering.jl
# (`_is_tree_value`, `_render_tree_html`). The worker reaches them via
# `Base.invokelatest(getfield(Sessions, :…), …)` so there is exactly one
# implementation, and worker and server stay in sync (max_depth=3,
# matching Pluto). The duplicate worker-local helpers used to live here
# and drifted to max_depth=4 — removed in the cleanup.

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
