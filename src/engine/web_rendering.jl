# web_rendering.jl — Web rendering: notebook → Therapy.jl VNodes
#
# Provides: PrerenderedGallery, execute_notebook_for_web, NotebookPage,
#           render_cell, render_output_html, CellGap, notebook helpers.

using Therapy
import Markdown
import Base64

# =============================================================================
# Shared Helpers (used by both static export and live app)
# =============================================================================

"""Format runtime nanoseconds into a compact human string."""
function _format_runtime(ns::UInt64)
    ns == 0 && return ""
    ms = ns / 1_000_000
    if ms < 1
        return "$(round(ns / 1000, digits=1))μs"
    elseif ms < 1000
        return "$(round(ms, digits=1))ms"
    else
        return "$(round(ms / 1000, digits=2))s"
    end
end

# SVG icon constants (shared by static export and live app)
const _SVG_RUN = """<svg width="10" height="10" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2.5v11l10-5.5z"/></svg>"""
const _SVG_MENU = """<svg width="11" height="11" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="8" cy="3" r="1.2"/><circle cx="8" cy="8" r="1.2"/><circle cx="8" cy="13" r="1.2"/></svg>"""
const _SVG_PLUS = """<svg width="8" height="8" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M8 2v12M2 8h12"/></svg>"""

# Load CodeMirror 6 bundle at include time (same pattern as app Layout.jl)
const _EDITOR_BUNDLE_JS = let
    p = joinpath(@__DIR__, "web", "static", "editor.js")
    isfile(p) ? read(p, String) : "/* editor.js not found */"
end

# =============================================================================
# Pre-rendered Gallery
# =============================================================================

"""
Pre-rendered variants for a cell driven by a slider.

Used by `execute_notebook_for_web` to capture output variants
for each slider value, enabling client-side switching without server roundtrips.
"""
struct PrerenderedGallery
    slider_cell_id::UUID
    var_name::Symbol
    slider::BoundSlider
    images::Dict{Any, Vector{UInt8}}    # slider_value → PNG bytes (fallback)
    plotly_data::Dict{Any, String}      # slider_value → Plotly JSON string
    html_variants::Dict{Any, String}    # slider_value → rendered HTML string (text/dataframe/etc.)
end

# =============================================================================
# Table Styling
# =============================================================================

const _WEB_TH_CLS = "px-4 py-3 text-left text-xs font-medium text-warm-500 dark:text-warm-400 uppercase tracking-wider"
const _WEB_TR_CLS = "border-b border-warm-200 dark:border-warm-700"
const _WEB_TD_CLS = "px-4 py-3 text-sm text-warm-700 dark:text-warm-300"

# =============================================================================
# Badge Component (for bond output rendering)
# =============================================================================

function _WebBadge(children...; variant::String="default", class::String="")
    base = "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium"
    vc = variant == "outline" ? "border border-warm-300 dark:border-warm-600 text-warm-700 dark:text-warm-300" :
        "bg-accent-100 dark:bg-accent-900 text-accent-700 dark:text-accent-300"
    Span(:class => "$(base) $(vc) $(class)", children...)
end

# =============================================================================
# HTML String Renderers (shared: live app WS + static export fallback)
# =============================================================================

function _html_esc(s::AbstractString)
    replace(replace(replace(s, '&' => "&amp;"), '<' => "&lt;"), '>' => "&gt;")
end

# Post-process Markdown HTML to wrap LaTeX for MathJax.
# Julia's Markdown.html renders LaTeX as &#36;formula&#36; with HTML-escaped
# braces/operators. We unescape and wrap in .tex elements for MathJax.
function _unescape_latex(s::AbstractString)
    s = replace(s, "&#123;" => "{")
    s = replace(s, "&#125;" => "}")
    s = replace(s, "&#61;" => "=")
    s = replace(s, "&#43;" => "+")
    s = replace(s, "&lt;" => "<")
    s = replace(s, "&gt;" => ">")
    s = replace(s, "&amp;" => "&")
    s
end

function _wrap_latex_for_mathjax(html::AbstractString)
    ds = raw"$"
    # Display math: bare &#36;...&#36; on its own line → $$...$$
    html = replace(html, r"(?<![>a-zA-Z])&#36;((?:[^&]|&(?!#36;))+)&#36;\n" =>
        m -> begin
            inner = match(r"&#36;((?:[^&]|&(?!#36;))+)&#36;", m)
            inner === nothing && return m
            string("\n", ds, ds, _unescape_latex(inner.captures[1]), ds, ds, "\n")
        end)
    # Inline math: &#36;...&#36; inside text → $...$
    html = replace(html, r"&#36;((?:[^&]|&(?!#36;))+?)&#36;" =>
        m -> begin
            inner = match(r"&#36;((?:[^&]|&(?!#36;))+?)&#36;", m)
            inner === nothing && return m
            string(ds, _unescape_latex(inner.captures[1]), ds)
        end)
    html
end

"""Wrap text between backticks (`...`) in <code>...</code> for inline code styling.
Also recognises common identifier patterns Julia emits without backticks."""
function _wrap_inline_code(text::AbstractString)::String
    # Backtick-delimited spans become <code>...</code>.
    parts = String[]
    last_end = 0  # byte index of last consumed position (0 = nothing consumed yet)
    for m in eachmatch(r"`([^`]+)`", text)
        if m.offset > last_end + 1
            push!(parts, _html_esc(text[(last_end+1):(m.offset-1)]))
        end
        push!(parts, """<code class="jl-inline">$(_html_esc(String(m.captures[1])))</code>""")
        last_end = m.offset + ncodeunits(m.match) - 1
    end
    if last_end < ncodeunits(text)
        push!(parts, _html_esc(text[(last_end+1):end]))
    end
    isempty(parts) && return _html_esc(text)
    return join(parts)
end

"""Try to split a structured error into (wrap_type, specific_type, body, suggestion).
Returns (wrap, inner, msg, suggestion) where wrap may be empty string."""
function _split_error_parts(se::StructuredError)
    type_name = se.type_name
    message = se.message

    wrap_types = ("LoadError", "InitError", "TaskFailedException", "CompositeException")

    # Strip "in expression starting at ..." trailer Julia appends to LoadError.
    body = strip(replace(message, r"\nin expression starting at .*$"s => ""))

    # showerror output for wrappers usually duplicates the type as a leading
    # "TypeName: " prefix on the message — strip that first.
    pref = "$(type_name): "
    startswith(body, pref) && (body = body[(length(pref)+1):end])

    wrap_type = ""
    specific_type = type_name

    # If the outer type is a known wrapper, iteratively peel inner wrappers off
    # the body until we land on the real cause. Without this, nested
    # `LoadError: LoadError: UndefVarError: …` would yield wrap=LoadError and
    # specific=LoadError (a visible duplicate).
    if type_name in wrap_types
        wrap_type = type_name
        body = strip(body)
        while true
            m = match(r"^([A-Za-z_][A-Za-z0-9_\.]*(?:Error|Exception)):\s*(.*)"s, body)
            m === nothing && break
            captured = String(m.captures[1])
            captured_short = replace(captured, r"^(?:Base\.Meta\.|Base\.|Core\.)" => "")
            if captured_short in wrap_types
                body = strip(String(m.captures[2]))
                continue
            end
            specific_type = captured_short
            body = strip(String(m.captures[2]))
            break
        end
    end

    # Strip a redundant leading "ErrorType: " prefix if it duplicates specific_type.
    pref2 = "$(specific_type): "
    startswith(body, pref2) && (body = body[(length(pref2)+1):end])

    # Pull out an actionable suggestion if present. Julia commonly emits these as:
    #   - Run `import Pkg; Pkg.add(...)` to install...
    #   - Hint: ...
    # We split on the first matching newline + bullet/hint and treat that line
    # (and anything after it) as the suggestion.
    suggestion = ""
    lines = split(body, '\n')
    sug_idx = 0
    for (i, ln) in enumerate(lines)
        s = strip(ln)
        if startswith(s, "- ") || startswith(s, "Hint:") || startswith(s, "Suggestion:") ||
           occursin(r"^Run\s+`"i, s)
            sug_idx = i
            break
        end
    end
    if sug_idx > 0
        sug_lines = lines[sug_idx:end]
        # Strip leading bullet/marker on each suggestion line for cleaner display.
        cleaned = String[]
        for ln in sug_lines
            s = String(strip(ln))
            s = replace(s, r"^-\s+" => "")
            s = replace(s, r"^(?:Hint|Suggestion)\s*:\s*"i => "")
            isempty(s) && continue
            push!(cleaned, s)
        end
        suggestion = join(cleaned, " ")
        body = strip(join(lines[1:sug_idx-1], '\n'))
    end

    body = strip(body)
    isempty(body) && (body = message)

    return (wrap_type, specific_type, String(body), String(suggestion))
end

"""A frame is 'user-relevant' if it's clearly user code, top-level execution scope,
or one of the Sessions.jl entry points the notebook reaches through."""
function _is_user_relevant_frame(frame::StructuredFrame)::Bool
    frame.from_user && return true
    func_low = lowercase(frame.func)
    occursin("top-level scope", func_low) && return true
    occursin("_worker_execute", func_low) && return true
    occursin(r"sessions[^/\\]*\.jl"i, frame.file) && return true
    return false
end

"""Render a StructuredError as rich HTML with collapsible stack trace.
Layout: header (wrap badge + specific type), message with inline code,
optional amber suggestion card, then a collapsed-by-default stack trace."""
function _render_structured_error_html(se::StructuredError)
    wrap_type, specific_type, body, suggestion = _split_error_parts(se)

    buf = IOBuffer()
    print(buf, """<div class="jl-error">""")
    print(buf, """<div class="jl-error-content">""")

    # Header: [wrap badge] specific-type-text
    print(buf, """<div class="jl-error-header">""")
    if !isempty(wrap_type)
        print(buf, """<span class="jl-error-badge">""", _html_esc(wrap_type), "</span>")
        print(buf, """<span class="jl-error-type">""", _html_esc(specific_type), "</span>")
    else
        print(buf, """<span class="jl-error-badge">""", _html_esc(specific_type), "</span>")
    end
    print(buf, "</div>")

    # Message with inline-code-wrapped backtick spans
    print(buf, """<div class="jl-error-message">""", _wrap_inline_code(body), "</div>")

    # Optional amber suggestion card
    if !isempty(suggestion)
        print(buf, """<div class="jl-error-suggestion">""")
        print(buf, """<span class="jl-error-suggestion-icon" aria-hidden="true">!</span>""")
        print(buf, """<span>""", _wrap_inline_code(suggestion), "</span>")
        print(buf, "</div>")
    end

    print(buf, "</div>")  # /jl-error-content

    # Collapsed-by-default stack trace
    if !isempty(se.frames)
        n_visible = length(se.frames)
        summary_text = "Stack trace ($(n_visible) frame$(n_visible == 1 ? "" : "s"))"
        se.hidden_frame_count > 0 && (summary_text *= ", $(se.hidden_frame_count) hidden")

        print(buf, """<details class="jl-error-stacktrace">""")
        print(buf, """<summary><span class="jl-error-stack-arrow"></span>""", summary_text, "</summary>")
        print(buf, "<ol>")
        for (i, frame) in enumerate(se.frames)
            cls = string(frame.importance)
            _is_user_relevant_frame(frame) && (cls *= " user-frame")
            print(buf, """<li class="jl-frame $(cls)" title="$(_html_esc(frame.func))">""")
            print(buf, """<span class="jl-frame-idx">$(i)</span>""")
            print(buf, """<span class="jl-frame-func">""", _html_esc(frame.func_short), "</span>")
            print(buf, """<span class="jl-frame-loc">@ """, _html_esc(frame.file_short), ":", frame.line, "</span>")
            if frame.inlined
                print(buf, """<span class="jl-frame-tag">inlined</span>""")
            end
            print(buf, "</li>")
        end
        print(buf, "</ol></details>")
    end

    print(buf, "</div>")
    String(take!(buf))
end

"""Render a Julia value as a collapsible HTML tree view."""
function _render_tree_html(@nospecialize(value); depth::Int=0, max_depth::Int=3, max_items::Int=25)
    buf = IOBuffer()
    _render_tree_node!(buf, value; depth, max_depth, max_items)
    String(take!(buf))
end

function _render_tree_node!(buf::IOBuffer, @nospecialize(value); depth::Int=0, max_depth::Int=3, max_items::Int=25)
    # Leaf: scalar values or max depth exceeded
    if depth >= max_depth || _is_leaf_value(value)
        text = try
            sprint(; context=IOContext(devnull, :color => false, :limit => true, :displaysize => (1, 80))) do io
                Base.invokelatest(show, io, MIME"text/plain"(), value)
            end
        catch
            repr(value)
        end
        print(buf, """<span class="jl-tree-val">""", _html_esc(text), "</span>")
        return
    end

    T = typeof(value)
    type_name = _short_type_name(T)
    open_attr = ""

    if value isa AbstractVector
        n = length(value)
        print(buf, """<details class="jl-tree"$(open_attr)><summary><span class="jl-tree-prefix">$(type_name)</span> <span class="jl-tree-count">($(n) element$(n == 1 ? "" : "s"))</span></summary><div class="jl-tree-items">""")
        _render_indexed_items!(buf, value, n; depth, max_depth, max_items)
        print(buf, "</div></details>")

    elseif value isa AbstractDict
        n = length(value)
        print(buf, """<details class="jl-tree"$(open_attr)><summary><span class="jl-tree-prefix">$(type_name)</span> <span class="jl-tree-count">($(n) entr$(n == 1 ? "y" : "ies"))</span></summary><div class="jl-tree-items">""")
        for (i, (k, v)) in enumerate(value)
            i > max_items && (print(buf, """<div class="jl-tree-more">… $(n - max_items) more</div>"""); break)
            print(buf, """<div class="jl-tree-row"><span class="jl-tree-key">""", _html_esc(repr(k)), """</span><span class="jl-tree-sep"> → </span>""")
            _render_tree_node!(buf, v; depth=depth+1, max_depth, max_items)
            print(buf, "</div>")
        end
        print(buf, "</div></details>")

    elseif value isa Tuple
        n = length(value)
        print(buf, """<details class="jl-tree"$(open_attr)><summary><span class="jl-tree-prefix">Tuple</span> <span class="jl-tree-count">($(n) element$(n == 1 ? "" : "s"))</span></summary><div class="jl-tree-items">""")
        for i in 1:min(n, max_items)
            print(buf, """<div class="jl-tree-row"><span class="jl-tree-key">$(i)</span><span class="jl-tree-sep"> : </span>""")
            _render_tree_node!(buf, value[i]; depth=depth+1, max_depth, max_items)
            print(buf, "</div>")
        end
        n > max_items && print(buf, """<div class="jl-tree-more">… $(n - max_items) more</div>""")
        print(buf, "</div></details>")

    elseif value isa NamedTuple
        n = length(value)
        print(buf, """<details class="jl-tree"$(open_attr)><summary><span class="jl-tree-prefix">NamedTuple</span> <span class="jl-tree-count">($(n) field$(n == 1 ? "" : "s"))</span></summary><div class="jl-tree-items">""")
        for k in keys(value)
            print(buf, """<div class="jl-tree-row"><span class="jl-tree-key">$(k)</span><span class="jl-tree-sep"> = </span>""")
            _render_tree_node!(buf, value[k]; depth=depth+1, max_depth, max_items)
            print(buf, "</div>")
        end
        print(buf, "</div></details>")

    elseif value isa AbstractSet
        n = length(value)
        print(buf, """<details class="jl-tree"$(open_attr)><summary><span class="jl-tree-prefix">$(type_name)</span> <span class="jl-tree-count">($(n) element$(n == 1 ? "" : "s"))</span></summary><div class="jl-tree-items">""")
        for (i, v) in enumerate(value)
            i > max_items && (print(buf, """<div class="jl-tree-more">… $(n - max_items) more</div>"""); break)
            print(buf, """<div class="jl-tree-row">""")
            _render_tree_node!(buf, v; depth=depth+1, max_depth, max_items)
            print(buf, "</div>")
        end
        print(buf, "</div></details>")

    elseif value isa Pair
        print(buf, """<span class="jl-tree-val">""")
        _render_tree_node!(buf, value.first; depth=depth+1, max_depth, max_items)
        print(buf, """<span class="jl-tree-sep"> => </span>""")
        _render_tree_node!(buf, value.second; depth=depth+1, max_depth, max_items)
        print(buf, "</span>")

    else
        # Struct with fields
        fnames = fieldnames(T)
        n = length(fnames)
        print(buf, """<details class="jl-tree"$(open_attr)><summary><span class="jl-tree-prefix">$(type_name)</span> <span class="jl-tree-count">($(n) field$(n == 1 ? "" : "s"))</span></summary><div class="jl-tree-items">""")
        for fname in fnames
            print(buf, """<div class="jl-tree-row"><span class="jl-tree-key">$(fname)</span><span class="jl-tree-sep"> = </span>""")
            fval = try getfield(value, fname) catch; "#undef" end
            _render_tree_node!(buf, fval; depth=depth+1, max_depth, max_items)
            print(buf, "</div>")
        end
        print(buf, "</div></details>")
    end
end

function _render_indexed_items!(buf::IOBuffer, value, n::Int; depth, max_depth, max_items)
    show_count = min(n, max_items)
    for i in 1:show_count
        print(buf, """<div class="jl-tree-row"><span class="jl-tree-key">$(i)</span><span class="jl-tree-sep"> : </span>""")
        _render_tree_node!(buf, value[i]; depth=depth+1, max_depth, max_items)
        print(buf, "</div>")
    end
    n > max_items && print(buf, """<div class="jl-tree-more">… $(n - max_items) more</div>""")
end

function _is_leaf_value(@nospecialize(value))::Bool
    value isa Number || value isa AbstractString || value isa Symbol ||
    value isa AbstractChar || value isa Type || value isa Enum ||
    value isa Regex || value === nothing || value === missing
end

function _short_type_name(T::Type)::String
    s = string(T)
    # Truncate long parametric types
    length(s) > 60 && return s[1:57] * "..."
    _html_esc(s)
end

function _parse_json_string_array(s::String)
    results = String[]
    last_i = ncodeunits(s)
    i = 1
    while i <= last_i
        if s[i] == '"'
            j = nextind(s, i)
            buf = IOBuffer()
            while j <= last_i
                if s[j] == '\\' && nextind(s, j) <= last_i
                    j2 = nextind(s, j)
                    c = s[j2]
                    if c == '"'; write(buf, '"')
                    elseif c == '\\'; write(buf, '\\')
                    elseif c == 'n'; write(buf, '\n')
                    elseif c == 'r'; write(buf, '\r')
                    else write(buf, c)
                    end
                    j = nextind(s, j2)
                elseif s[j] == '"'
                    break
                else
                    write(buf, s[j])
                    j = nextind(s, j)
                end
            end
            push!(results, String(take!(buf)))
            i = j <= last_i ? nextind(s, j) : j + 1
        else
            i = nextind(s, i)
        end
    end
    results
end

function _extract_json_string_array(json::String, key::String)
    pat = "\"$(key)\":["
    idx = findfirst(pat, json)
    idx === nothing && return String[]
    start = last(idx) + 1
    last_i = ncodeunits(json)
    depth = 1
    i = start
    while i <= last_i && depth > 0
        c = json[i]
        c == '[' && (depth += 1)
        c == ']' && (depth -= 1)
        i = nextind(json, i)
    end
    arr_str = json[start:prevind(json, i, 2)]
    _parse_json_string_array(arr_str)
end

function _extract_json_nested_array(json::String, key::String)
    pat = "\"$(key)\":["
    idx = findfirst(pat, json)
    idx === nothing && return String[]
    start = last(idx) + 1
    last_i = ncodeunits(json)
    depth = 1
    i = start
    while i <= last_i && depth > 0
        c = json[i]
        c == '[' && (depth += 1)
        c == ']' && (depth -= 1)
        i = nextind(json, i)
    end
    arr_content = json[start:prevind(json, i, 2)]
    results = String[]
    arr_last = ncodeunits(arr_content)
    j = 1
    while j <= arr_last
        if arr_content[j] == '['
            d = 1
            k = nextind(arr_content, j)
            while k <= arr_last && d > 0
                arr_content[k] == '[' && (d += 1)
                arr_content[k] == ']' && (d -= 1)
                k = nextind(arr_content, k)
            end
            push!(results, arr_content[nextind(arr_content, j):prevind(arr_content, k, 2)])
            j = k
        else
            j = nextind(arr_content, j)
        end
    end
    results
end

function _extract_json_int(json::String, key::String)
    pat = "\"$(key)\":"
    idx = findfirst(pat, json)
    idx === nothing && return 0
    start = last(idx) + 1
    last_i = ncodeunits(json)
    i = start
    while i <= last_i && (json[i] in ('0':'9'))
        i = nextind(json, i)
    end
    parse(Int, json[start:prevind(json, i)])
end

"""Simple JSON parser for table data. Returns Dict or nothing."""
function _parse_table_json(json::String)
    try
        cols = _extract_json_string_array(json, "cols")
        types = _extract_json_string_array(json, "types")
        rows_str = _extract_json_nested_array(json, "rows")
        nrow = _extract_json_int(json, "nrow")
        ncol = _extract_json_int(json, "ncol")

        rows = Vector{String}[]
        for row_str in rows_str
            push!(rows, _parse_json_string_array(row_str))
        end

        Dict(:cols => cols, :types => types, :rows => rows, :nrow => nrow, :ncol => ncol)
    catch e
        @warn "[Sessions] Failed to parse table JSON" exception=e
        nothing
    end
end

function _write_pluto_table_row(buf::IOBuffer, idx::Int, row::Vector{String})
    print(buf, "<tr><th>", idx, "</th>")
    for cell in row
        print(buf, "<td><div>", _html_esc(cell), "</div></td>")
    end
    print(buf, "</tr>")
end

"""Render a Tables.jl-serialized payload into Pluto-compatible
`<table class="pluto-table">` DOM.

Mirrors Pluto's frontend `TableView.js` output structure exactly:
- `<thead>` carries two rows: `tr.schema-names` (always visible) and
  `tr.schema-types` (revealed on `thead:hover` via CSS).
- First column is the row index `<th>`; each cell is `<td><div>…</div></td>`
  so Firefox's table layout still honours `td max-width:300px` (Pluto
  workaround).
- Truncation: show first N, a `<tr>` with a clickable "more" sentinel,
  then the last row so the user always sees the endpoint."""
function _render_table_html(table_json::String)
    isempty(table_json) && return ""

    data = _parse_table_json(table_json)
    data === nothing && return ""

    cols = data[:cols]
    types = data[:types]
    rows = data[:rows]
    nrow = data[:nrow]
    ncol = data[:ncol]
    isempty(cols) && return ""

    initial_visible = 10
    total_serialized = length(rows)
    truncated = total_serialized > initial_visible

    buf = IOBuffer()

    print(buf, """<div class="pluto-table-wrap"><div class="pluto-table-dim">""",
          nrow, "×", ncol, " DataFrame</div>")
    print(buf, """<table class="pluto-table"><thead>""")
    # schema-names row (always visible)
    print(buf, """<tr class="schema-names"><th></th>""")
    for name in cols
        print(buf, "<th>", _html_esc(name), "</th>")
    end
    print(buf, "</tr>")
    # schema-types row (hidden via CSS until thead:hover)
    print(buf, """<tr class="schema-types"><th></th>""")
    for t in types
        print(buf, "<th>", _html_esc(t), "</th>")
    end
    print(buf, "</tr></thead><tbody>")

    if truncated
        # First N rows
        for i in 1:initial_visible
            _write_pluto_table_row(buf, i, rows[i])
        end
        # Hidden middle rows (revealed when "more" is clicked)
        for i in (initial_visible + 1):(total_serialized - 1)
            print(buf, """<tr class="pluto-table-hidden" style="display:none"><th>""",
                  i, "</th>")
            for cell in rows[i]
                print(buf, "<td><div>", _html_esc(cell), "</div></td>")
            end
            print(buf, "</tr>")
        end
        hidden_count = total_serialized - initial_visible - 1
        more_label = nrow > total_serialized ? "more" : "$(hidden_count) more"
        print(buf, """<tr><td colspan="$(ncol + 1)" class="pluto-tree-more-td">""")
        print(buf, """<pluto-tree-more onclick="this.closest('table').querySelectorAll('.pluto-table-hidden').forEach(function(r){r.style.display=''});this.closest('tr').remove()">⋮ """,
              more_label, "</pluto-tree-more></td></tr>")
        # Anchor row: the very last row so the user sees both endpoints
        _write_pluto_table_row(buf, total_serialized, rows[end])
    else
        for (i, row) in enumerate(rows)
            _write_pluto_table_row(buf, i, row)
        end
    end

    print(buf, "</tbody></table></div>")
    String(take!(buf))
end

# Bond rendering is now owned by SessionsUI.Bond's MIME"text/html" show
# (emits canonical `<bond def="x">…widget…</bond>`); cells flow through
# the generic html branch in worker boot.jl. The page-level
# SessionsUI.BOND_BRIDGE_JS attaches input listeners and sends set_bond
# WS messages. No bond-specific renderer needed here.

# =============================================================================
# Notebook Helpers
# =============================================================================

"""Extract the first H1 heading from markdown cells in a notebook."""
function notebook_title(nb::Notebook)
    for id in nb.cell_order
        cell = get(nb.cells, id, nothing)
        cell === nothing && continue
        code = strip(cell.code)
        if _is_markdown_cell(code)
            content = _extract_markdown_content(code)
            for line in split(content, '\n')
                line = strip(line)
                if startswith(line, "# ") && !startswith(line, "## ")
                    return String(strip(line[3:end]))
                end
            end
        end
    end
    return basename(nb.path)
end

"""Check if cell code is a Markdown string macro (md\"...\")."""
function _is_markdown_cell(code::AbstractString)
    stripped = strip(code)
    startswith(stripped, "md\"") || startswith(stripped, "md\"\"\"")
end

"""Extract the markdown content from a md\"...\" or md\"\"\"...\"\"\" cell."""
function _extract_markdown_content(code::AbstractString)
    stripped = strip(code)
    if startswith(stripped, "md\"\"\"") && endswith(stripped, "\"\"\"")
        return stripped[6:end-3]
    elseif startswith(stripped, "md\"") && endswith(stripped, "\"")
        return stripped[4:end-1]
    end
    stripped
end

"""
Render pre-rendered HTML variants for a slider-dependent cell.

Returns a container with all slider value variants embedded as hidden/shown divs.
The interaction script toggles visibility client-side when the slider moves.
"""
function _render_html_gallery(cell::Cell, prerendered)
    gallery = get(prerendered, cell.id, nothing)
    gallery === nothing && return nothing
    isempty(gallery.html_variants) && return nothing

    slider_id = string(gallery.slider_cell_id)
    variant_divs = []
    for val in gallery.slider.values
        html_str = get(gallery.html_variants, val, nothing)
        html_str === nothing && continue
        is_default = val == gallery.slider.default
        push!(variant_divs,
            Div(:data_slider_value => string(val),
                :style => is_default ? "display:block" : "display:none",
                RawHtml(html_str)))
    end
    isempty(variant_divs) && return nothing

    Div(:class => "notebook-html-gallery",
        :data_slider_html => slider_id,
        variant_divs...)
end

"""Render cell output as a VNode for SSR (static export + initial render).

Delegates to `render_output_html` for most types. Only keeps VNode-specific
paths for bonds/galleries that need live Julia objects for @island SSR.
"""
function _render_output(cell::Cell, prerendered=Dict{UUID, PrerenderedGallery}())
    output = cell.output
    result = output.result

    output.output_type == :nothing && return nothing

    # Bond — needs live result for @island SSR
    if output.output_type == :bond
        return _render_bond_output(result, cell, prerendered)
    end

    # Plotly — needs live result for gallery pre-rendering
    if output.output_type == :plotly_json
        return _render_plotly_output(cell, prerendered)
    end

    # Image — needs gallery pre-rendering
    if output.output_type == :image_png
        return _render_image_output(cell, prerendered)
    end

    # NOTE: Tables.jl values are now classified as :table in worker
    # boot.jl (was :dataframe) and rendered through the
    # standard render_output_html() path which delegates to
    # _render_table_html() for pluto-table HTML. The old _render_table_output
    # and _render_reactive_table helpers were deleted with that refactor.

    # Text with live WASM binding for slider-bound values
    if output.output_type == :text
        gallery = get(prerendered, cell.id, nothing)
        if gallery !== nothing && result isa Integer
            slider_id = string(gallery.slider_cell_id)
            return Div(:class => "notebook-bound-value",
                :data_bound_to => slider_id,
                BoundValue(value=Int(result)))
        end
        gallery_node = _render_html_gallery(cell, prerendered)
        gallery_node !== nothing && return gallery_node
    end

    # All other types: delegate to render_output_html (single source of truth)
    html = render_output_html(cell; prerendered)
    isempty(html) ? nothing : RawHtml(html)
end

function _render_image_output(cell::Cell, prerendered)
    gallery = get(prerendered, cell.id, nothing)

    if gallery !== nothing
        slider_id = string(gallery.slider_cell_id)
        img_tags = []
        for val in gallery.slider.values
            bytes = get(gallery.images, val, nothing)
            bytes === nothing && continue
            b64 = Base64.base64encode(bytes)
            is_default = val == gallery.slider.default
            push!(img_tags,
                Img(:src => "data:image/png;base64,$b64",
                    :alt => "Plot for $(gallery.var_name) = $val",
                    :data_slider_value => string(val),
                    :style => is_default ? "display:block" : "display:none",
                    :class => "rounded-lg max-w-full"))
        end
        return Div(:class => "notebook-plot-gallery",
            :data_slider_images => slider_id, img_tags...)
    end

    if cell.output.image_data !== nothing
        b64 = Base64.base64encode(cell.output.image_data)
        return Img(:src => "data:image/png;base64,$b64",
            :alt => "Plot output", :class => "rounded-lg max-w-full")
    end

    nothing
end

function _render_plotly_output(cell::Cell, prerendered)
    gallery = get(prerendered, cell.id, nothing)
    plot_id = "plotly-" * string(cell.id)[1:8]

    if gallery !== nothing && !isempty(gallery.plotly_data)
        slider_id = string(gallery.slider_cell_id)
        scripts = [
            RawHtml("""<script type="application/json" data-plotly-for="$plot_id" data-plotly-value="$val">$(gallery.plotly_data[val])</script>""")
            for val in gallery.slider.values if haskey(gallery.plotly_data, val)
        ]
        return Div(:class => "notebook-plotly",
            Div(:id => plot_id,
                :data_plotly_plot => slider_id,
                :data_plotly_default => string(gallery.slider.default),
                :class => "w-full rounded-lg",
                :style => "min-height:400px;"),
            scripts...)
    end

    json_str = _to_json(cell.output.result)
    return Div(:class => "notebook-plotly",
        Div(:id => plot_id, :class => "w-full rounded-lg", :style => "min-height:400px;"),
        RawHtml("""<script type="application/json" data-plotly-for="$plot_id">$json_str</script>"""),
        RawHtml("""<script>(function(){var el=document.getElementById('$plot_id');var s=document.querySelector('[data-plotly-for="$plot_id"]');if(el&&s&&window.Plotly){var d=JSON.parse(s.textContent);Plotly.newPlot(el,d.data,d.layout,{responsive:true})}})();</script>"""))
end

function _render_bond_output(result, cell::Cell, prerendered)
    # SessionsUI's `Bond` defines MIME"text/html" — render via the standard
    # HTML path (sprint(show, MIME"text/html"(), result)) so all widget
    # types share one code path. The page-level BOND_BRIDGE_JS wires
    # input → WS, no custom VNode wrapper needed.
    if result isa Bond
        return RawHtml(sprint(show, MIME"text/html"(), result))
    end
    nothing
end

# =============================================================================
# render_output_html — single source of truth for cell output as HTML string
# =============================================================================

"""
    render_output_html(cell::Cell; prerendered=Dict()) -> String

Render cell output to an HTML string. Used by the live app (WS updates)
and as a fallback in static export. Single source of truth — replaces both
`_web_render_output_html` (web_server.jl) and `_render_cell_output_html` (CellView.jl).
"""
function render_output_html(cell::Cell; prerendered=Dict{UUID, PrerenderedGallery}())
    output = cell.output
    # Markdown
    if output.output_type == :markdown
        md_html = if output.result !== nothing
            try
                sprint(io -> Markdown.html(io, output.result))
            catch
                output.text_representation
            end
        else
            output.text_representation
        end
        # Post-process LaTeX: Julia's Markdown renders $formula$ as &#36;formula&#36;
        # Wrap in .tex spans so MathJax can typeset them (same approach as Pluto's LaTeX.jl)
        md_html = _wrap_latex_for_mathjax(md_html)
        # Pluto parity: no wrapper class — markdown content lives directly in
        # `.cell-out` and inherits typography from the output container's
        # baseline rules (defined in input.css).
        return md_html
    end
    # Bond — only reachable for cached old sessions; new bonds flow through
    # the :html branch below since SessionsUI's Bond.show emits text/html.
    if output.output_type == :bond
        return output.text_representation
    end
    # Table
    if output.output_type == :table
        return _render_table_html(output.text_representation)
    end
    # HTML
    if output.output_type == :html
        html = output.text_representation
        return isempty(html) ? "" : html
    end
    # Tree view (collapsible arrays, dicts, structs)
    if output.output_type == :tree
        # In-process path: render from actual object
        if output.result !== nothing
            return _render_tree_html(output.result)
        end
        # Worker path: HTML already rendered in text_representation
        return output.text_representation
    end
    # Error — structured if available, plain text fallback
    if output.output_type == :error
        se = output.structured_error
        # Parse on the fly if no structured error (e.g. cached from .sessions.toml)
        if se === nothing && !isempty(output.text_representation)
            se = _parse_error_text(output.text_representation)
        end
        if se !== nothing
            return _render_structured_error_html(se)
        end
        err_msg = _html_esc(output.text_representation)
        return """<div class="jl-error"><div class="jl-error-message">$(err_msg)</div></div>"""
    end
    # SVG
    if output.output_type == :image_svg
        svg = output.text_representation
        return isempty(svg) ? "" : """<div class="overflow-x-auto">$(svg)</div>"""
    end
    # Text — plain monospace
    if output.output_type == :text
        text = output.text_representation
        return isempty(text) ? "" : """<pre class="text-sm font-mono whitespace-pre-wrap" style="color:var(--output-text);line-height:1.5;">$(_html_esc(text))</pre>"""
    end
    # Image PNG — base64
    if output.output_type == :image_png && output.image_data !== nothing
        b64 = Base64.base64encode(output.image_data)
        return """<img src="data:image/png;base64,$(b64)" alt="Plot output" class="rounded-lg max-w-full">"""
    end
    # Nothing / unknown — empty
    ""
end

# =============================================================================
# render_cell — unified cell rendering (static export + live app)
# =============================================================================

"""
    render_cell(cell::Cell; mode=:static, index=0, prerendered=Dict()) -> VNode

Unified cell rendering function — single source of truth.

**mode=:static** — Output as VNode via `_render_output()`, no run/menu buttons, no stale/idle states.
**mode=:live** — Output as HTML string via `render_output_html()` → RawHtml, with run + menu buttons
and stale/idle/executing CSS classes.

Both modes share: CellToggle @island, CM editor host, runtime badge, cell-wrap/code-cell structure.
"""
function render_cell(cell::Cell; mode::Symbol=:static, index::Int=0,
                     prerendered=Dict{UUID, PrerenderedGallery}())
    # Static export: skip disabled/empty cells. Live app: render all (disabled shown dimmed)
    mode == :static && cell.disabled && return nothing
    code = strip(cell.code)
    mode == :static && isempty(code) && return nothing

    output = cell.output
    cell_id = string(cell.id)
    runtime_str = _format_runtime(output.runtime_ns)

    parts = Any[]

    # =======================================================================
    # Output area — ABOVE code (Pluto-style: output before code)
    # =======================================================================
    if mode == :static
        output_node = _render_output(cell, prerendered)
        if output_node !== nothing
            push!(parts, Div(:class => "cell-out", :style => "padding:4px 0 8px;overflow-x:auto;",
                output_node))
        end
        # Stdout (live mode gets stdout via WS)
        if !isempty(output.stdout)
            push!(parts,
                Div(:class => "cell-out font-mono text-xs whitespace-pre overflow-x-auto",
                    :style => "padding:6px 0 10px;line-height:1.5;color:#7ca0bf;",
                    output.stdout))
        end
    else  # :live
        output_html = render_output_html(cell)
        has_text_output = !isempty(output.text_representation) && output.output_type != :nothing && output.output_type != :markdown
        has_output = has_text_output || !isempty(output_html)
        is_rich_output = output.output_type in (:markdown, :html, :table, :image_png, :image_svg, :bond)

        out_div = if has_output
            out_content = !isempty(output_html) ? RawHtml(output_html) :
                          has_text_output ? output.text_representation : nothing
            if out_content !== nothing
                if is_rich_output
                    Div(:class => "cell-out",
                        :data_cell_id => cell_id,
                        :style => "padding:4px 0 2px;overflow-x:auto;",
                        out_content)
                else
                    Div(:class => "cell-out font-mono text-xs text-tout whitespace-pre overflow-x-auto",
                        :data_cell_id => cell_id,
                        :style => "padding:4px 0 2px;line-height:1.5;",
                        out_content)
                end
            else
                Div(:class => "cell-out", :data_cell_id => cell_id, :style => "display:none;")
            end
        else
            Div(:class => "cell-out", :data_cell_id => cell_id, :style => "display:none;")
        end
        push!(parts, out_div)
    end

    # =======================================================================
    # Hover controls (top-right)
    # =======================================================================
    ctrl_children = Any[]
    if !isempty(runtime_str)
        push!(ctrl_children, Span(:class => "rt-badge", runtime_str))
    end
    if mode == :live
        push!(ctrl_children,
            Therapy.Button(:class => "ctrl-btn run-btn",
                :title => "Run cell (Shift+Enter)",
                :on_click => "window._sessionsRunCell('$(cell_id)')",
                RawHtml(_SVG_RUN)))
        push!(ctrl_children,
            Therapy.Button(:class => "ctrl-btn menu-btn",
                :title => "Cell actions",
                :on_click => "window._sessionsShowCellMenu(this,'$(cell_id)')",
                RawHtml(_SVG_MENU)))
    end
    ctrls = Div(:class => "cell-ctrls absolute top-1 right-1.5 flex items-center z-10",
        ctrl_children...)

    # =======================================================================
    # Code cell
    # =======================================================================
    cls = "code-cell relative overflow-hidden"
    if mode == :live
        cell.state == cell_idle && (cls *= " idle")
        # Match stale_cells() semantics: never-run cells with code are visually
        # equivalent to stale (both need a run). Without this, externally-added
        # cells render without the amber depth treatment even though the
        # run-stale counter includes them.
        needs_run = is_stale(cell) || (is_never_run(cell) && !isempty(strip(cell.code)))
        needs_run && (cls *= " stale")
    end
    code_cell_classes = cls

    code_cell = Div(:class => code_cell_classes,
        ctrls,
        Div(:class => "cm-cell",
            :data_cell_id => cell_id,
            :data_src => String(code)))

    # CellToggle island (eye toggle + fold) wrapping the code-cell
    push!(parts, CellToggle(; initial_open = cell.folded ? 0 : 1) do
        code_cell
    end)

    # Stdout container — below code, above next cell gap (like Pluto's log section)
    if mode == :live
        stdout_text = output.stdout
        if !isempty(stdout_text)
            push!(parts, Div(:class => "cell-stdout", :data_cell_id => cell_id,
                RawHtml(_html_esc(stdout_text))))
        else
            push!(parts, RawHtml("""<div class="cell-stdout" data-cell-id="$(cell_id)" style="display:none"></div>"""))
        end
    end

    # Logs container — below code, below stdout (for @info/@warn/@error/@debug)
    if mode == :live
        logs_display = cell.show_logs ? "" : "display:none"
        push!(parts, RawHtml("""<div class="cell-logs" data-cell-id="$(cell_id)" data-show-logs="$(cell.show_logs ? "1" : "0")" style="$(logs_display)"></div>"""))
    end

    # Cell shoulder (drag handle) — only in live mode
    if mode == :live
        push!(parts, RawHtml("""<div class="cell-shoulder" draggable="true" title="Drag to move cell"></div>"""))
    end

    wrap_cls = "cell-wrap relative"
    cell.disabled && (wrap_cls *= " cell-disabled")
    cell.folded && (wrap_cls *= " code-hidden")
    has_visible_output = output.output_type != :nothing && !isempty(output.text_representation)
    has_visible_output && (wrap_cls *= " has-output")
    # Seed the depth-state class for SSR so errored cells render lifted on first
    # paint (the WS bridge keeps it in sync afterwards).
    cell.state == cell_errored && (wrap_cls *= " wrap-errored")
    # .cell-body wraps the visual contents so running/stale states can translate
    # the whole block as a unit while the shadow pseudo-element on .cell-wrap
    # stays fixed beneath.
    Div(:data_cell_id => cell_id, :class => wrap_cls,
        Div(:class => "cell-body", parts...))
end

# =============================================================================
# CellGap — divider between cells with "+ Code" button (live app)
# =============================================================================

function CellGap(; after_cell_id::String="")
    Div(:class => "cdiv",
        Div(:class => "cdiv-inner",
            Therapy.Button(:class => "cdiv-btn",
                :on_click => "window._sessionsAddCell&&_sessionsAddCell('$(after_cell_id)')",
                RawHtml(_SVG_PLUS))))
end

function _slider_interaction_script()
    RawHtml("""<script>
(function() {
  // Initialize Plotly datasets
  document.querySelectorAll('[data-plotly-plot]').forEach(function(el) {
    var plotId = el.id;
    var def = el.dataset.plotlyDefault;
    var scripts = document.querySelectorAll('[data-plotly-for="' + plotId + '"]');
    el._plotlyDatasets = {};
    scripts.forEach(function(s) {
      var val = s.dataset.plotlyValue || 'default';
      el._plotlyDatasets[val] = JSON.parse(s.textContent);
    });
    if (el._plotlyDatasets[def] && window.Plotly) {
      var d = el._plotlyDatasets[def];
      Plotly.newPlot(el, d.data, d.layout, {responsive:true});
    }
  });

  // Bind slider interactions — works with WASM island sliders
  document.querySelectorAll('[data-bind-slider-id]').forEach(function(bondEl) {
    var sliderId = bondEl.dataset.bindSliderId;
    var rangeInput = bondEl.querySelector('therapy-island input[type="range"]');
    if (!rangeInput) rangeInput = bondEl.querySelector('input[type="range"]');
    if (!rangeInput) return;

    rangeInput.addEventListener('input', function() {
      var val = rangeInput.value;

      // Swap image galleries
      document.querySelectorAll('[data-slider-images="' + sliderId + '"] img').forEach(function(img) {
        img.style.display = img.dataset.sliderValue === val ? 'block' : 'none';
      });

      // Swap Plotly plots
      var plotEl = document.querySelector('[data-plotly-plot="' + sliderId + '"]');
      if (plotEl && plotEl._plotlyDatasets && plotEl._plotlyDatasets[val] && window.Plotly) {
        Plotly.react(plotEl, plotEl._plotlyDatasets[val].data, plotEl._plotlyDatasets[val].layout);
      }

      // Swap pre-rendered HTML variants (text, etc.)
      document.querySelectorAll('[data-slider-html="' + sliderId + '"] > [data-slider-value]').forEach(function(div) {
        div.style.display = div.dataset.sliderValue === val ? 'block' : 'none';
      });

      // Toggle reactive table rows — show rows where index ≤ slider value
      document.querySelectorAll('[data-slider-table="' + sliderId + '"] tbody tr[data-row-index]').forEach(function(tr) {
        tr.style.display = parseInt(tr.dataset.rowIndex) <= parseInt(val) ? '' : 'none';
      });

      // Live WASM bridge: dispatch input event to BoundValue islands
      // The hidden input inside each BoundValue island receives the value,
      // triggering the WASM handler which updates the signal → DOM binding.
      document.querySelectorAll('[data-bound-to="' + sliderId + '"] therapy-island input[type="hidden"]').forEach(function(hidden) {
        hidden.value = val;
        hidden.dispatchEvent(new Event('input', { bubbles: true }));
      });
    });
  });
})();
</script>""")
end

# =============================================================================
# Notebook Execution Pipeline
# =============================================================================

"""
    execute_notebook_for_web(path; verbose=false) -> (Notebook, Dict{UUID, PrerenderedGallery})

Execute a notebook for web publishing with pre-rendered slider galleries.

Returns `(notebook, prerendered)` where `prerendered` maps plot cell UUIDs
to `PrerenderedGallery` structs containing images for each slider value.
"""
function execute_notebook_for_web(path; verbose=false)
    nb = load_notebook(path)
    ws = Workspace()

    # 1. Execute all cells in topological order
    order = execution_order(nb)

    for (cell, err) in order.errable
        cell.state = cell_errored
        mark_executed!(cell)
        cell.output = CellOutput()
        cell.output.error = CapturedException(
            ErrorException("Reactivity error: $(typeof(err))"),
            backtrace()
        )
        verbose && println("    ERROR [$(cell.id)]: reactivity error")
    end

    for (i, cell) in enumerate(order.runnable)
        if verbose
            code_preview = first(cell.code, 40)
            code_preview = replace(code_preview, '\n' => "\\n")
            println("    [$i/$(length(order.runnable))] $(code_preview)")
        end
        execute_cell!(ws, cell)
    end

    # 2. Reclassify images (headless mode lacks graphics protocol → images classified as :text)
    for cell in ordered_cells(nb)
        if cell.output.output_type == :text && cell.output.result !== nothing
            if Base.invokelatest(showable, MIME"image/png"(), cell.output.result)
                cell.output.output_type = :image_png
                cell.output.image_data = _capture_png_bytes(cell.output.result)
                verbose && println("    Reclassified cell $(cell.id) as :image_png")
            end
        end
    end

    # 2b. Classify Plotly JSON outputs (Dict with "data" + "layout" keys)
    for cell in ordered_cells(nb)
        if cell.output.output_type == :text && cell.output.result isa Dict
            r = cell.output.result
            if haskey(r, "data") && haskey(r, "layout")
                cell.output.output_type = :plotly_json
                verbose && println("    Classified cell $(cell.id) as :plotly_json")
            end
        end
    end

    # 3. Pre-render slider-dependent cell outputs for all values
    #    This enables client-side switching of text, tables, images, and plots
    #    without server roundtrips — the foundation for interactive notebooks.
    prerendered = Dict{UUID, PrerenderedGallery}()
    for cell in ordered_cells(nb)
        cell.output.output_type == :bond || continue
        bond = cell.output.result
        bond isa Bond || continue
        slider = bond.element
        slider isa BoundSlider || continue

        var_name = bond.defines
        deps = downstream_dependents(nb, [cell])
        # Include ALL dependent cells with visible output, not just plots
        reactive_deps = filter(d -> d.output.output_type in (
            :image_png, :plotly_json, :text, :table
        ), deps)
        isempty(reactive_deps) && continue

        if verbose
            println("    Pre-rendering :$(var_name) slider ($(length(slider.values)) values × $(length(reactive_deps)) deps)")
        end

        for dep in reactive_deps
            # Dataframe deps use reactive table (SSR all rows + JS row toggling)
            # instead of pre-rendering separate tables for each slider value.
            # The cell was already executed at the default value, so result has all rows.
            if dep.output.output_type == :table
                prerendered[dep.id] = PrerenderedGallery(
                    cell.id, var_name, slider,
                    Dict{Any,Vector{UInt8}}(), Dict{Any,String}(), Dict{Any,String}()
                )
                verbose && println("      Dep $(dep.id): reactive table (no pre-rendering)")
                continue
            end

            images = Dict{Any, Vector{UInt8}}()
            plotly_data = Dict{Any, String}()
            html_variants = Dict{Any, String}()

            for val in slider.values
                set_bond_value!(var_name, val)
                Core.eval(ws.mod, :($var_name = $val))
                execute_cell!(ws, dep)

                # Reclassify if needed (headless mode lacks graphics protocol)
                if dep.output.output_type == :text && dep.output.result !== nothing
                    if Base.invokelatest(showable, MIME"image/png"(), dep.output.result)
                        dep.output.output_type = :image_png
                        dep.output.image_data = _capture_png_bytes(dep.output.result)
                    end
                end

                # Capture Plotly JSON
                if dep.output.result isa Dict && haskey(dep.output.result, "data") && haskey(dep.output.result, "layout")
                    dep.output.output_type = :plotly_json
                    plotly_data[val] = _to_json(dep.output.result)
                end

                # Capture PNG fallback
                if dep.output.image_data !== nothing
                    images[val] = copy(dep.output.image_data)
                end

                # Capture rendered HTML for text/dataframe outputs
                if dep.output.output_type in (:text, :table)
                    vnode = _render_output(dep)  # no prerendered arg → plain render
                    if vnode !== nothing
                        html_variants[val] = render_to_string(vnode)
                    end
                end
            end

            # Restore default value
            set_bond_value!(var_name, slider.default)
            Core.eval(ws.mod, :($var_name = $(slider.default)))
            execute_cell!(ws, dep)

            # Reclassify restored default too
            if dep.output.output_type == :text && dep.output.result !== nothing
                if Base.invokelatest(showable, MIME"image/png"(), dep.output.result)
                    dep.output.output_type = :image_png
                    dep.output.image_data = _capture_png_bytes(dep.output.result)
                end
            end
            if dep.output.result isa Dict && haskey(dep.output.result, "data") && haskey(dep.output.result, "layout")
                dep.output.output_type = :plotly_json
            end

            prerendered[dep.id] = PrerenderedGallery(
                cell.id, var_name, slider, images, plotly_data, html_variants
            )

            if verbose
                n_img = length(images)
                n_plotly = length(plotly_data)
                n_html = length(html_variants)
                println("      Dep $(dep.id): $(n_img) images, $(n_plotly) plotly, $(n_html) html variants")
            end
        end
    end

    return nb, prerendered
end

# =============================================================================
# NotebookPage — main entry point (self-contained: includes all CSS/fonts/JS)
# =============================================================================

"""Google Fonts needed by notebook rendering (DM Sans, Fraunces, JetBrains Mono)."""
function _notebook_fonts()
    RawHtml("""<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,100..1000;1,9..40,100..1000&family=JetBrains+Mono:ital,wght@0,100..800;1,100..800&family=Fraunces:ital,opsz,wght@0,9..144,100..900;1,9..144,100..900&display=swap" rel="stylesheet">""")
end

"""
Shared CSS for notebook rendering — single source of truth.

Used by both `_notebook_stylesheet()` (static export) and `Layout.jl` (live app).
Includes: cell chrome, accent bar, eye toggle, runtime badge, markdown prose,
Pluto-style tables (sst-*), CodeMirror overrides, slider widgets.
"""
const NOTEBOOK_CSS = """/* Cell chrome — light defaults, dark overrides */
.code-cell{background:var(--cell-bg);border:1px solid var(--cell-border);border-radius:8px;transition:border-color .2s;}
.code-cell:hover{border-color:var(--cell-border-hov);}
/* code-cell left accent bar removed — traffic light on cell-wrap */
.cell-ctrls{opacity:0;transform:translateY(-3px);transition:opacity .15s,transform .15s;pointer-events:none;}
.code-cell:hover .cell-ctrls{opacity:1;transform:translateY(0);pointer-events:auto;}
.rt-badge{font-size:11px;font-family:'JetBrains Mono','Fira Code',monospace;color:#B5A898;background:transparent;border:none;padding:0;}
.cell-eye{position:absolute;left:-28px;top:0;bottom:0;width:24px;display:flex;align-items:center;justify-content:center;opacity:0;transition:opacity .15s;cursor:pointer;z-index:5;}
.cell-wrap:hover .cell-eye{opacity:1;}
.cell-eye svg{color:#a0aec0;transition:color .15s;}
.cell-eye:hover svg{color:#219669;}
/* Cell chrome — dark overrides (accent bar only, bg/border use CSS vars) */
/* dark code-cell ::before removed — traffic light on cell-wrap */
.dark .rt-badge{color:#7A7A8E;background:transparent;border:none;}
.dark .cell-eye svg{color:#3d5068;}
.dark .cell-eye:hover svg{color:#56d4a0;}
.cell-out{overflow-x:auto;}
/* Notebook slider */
.notebook-slider{display:flex;align-items:center;gap:12px;padding:8px 0;}
.notebook-plotly{border-radius:8px;overflow:hidden;}
/* Markdown prose — defined in theme.css (single source of truth) */
/* Sessions Table (sst-*) — light defaults, dark overrides */
.sst-wrap{font-family:'JetBrains Mono','Fira Code',monospace;font-size:14px;overflow-x:auto;max-width:100%;}
.sst-table{border-collapse:collapse;width:auto;border-top:2px solid #219669;border-bottom:1px solid #e2e8f0;}
.sst-th{padding:12px 20px;color:#219669;font-weight:700;font-size:14px;text-align:left;border-bottom:1px solid #e2e8f0;white-space:nowrap;}
.sst-type-row .sst-type-th{padding:0 20px 8px;color:#a0aec0;font-weight:400;font-size:11px;font-style:italic;text-align:left;border-bottom:1px solid #e2e8f0;opacity:0;transition:opacity .15s;}
.sst-table thead:hover .sst-type-row .sst-type-th{opacity:1;}
.sst-row-label{color:#1a202c;font-weight:700;font-size:13px;text-align:right;padding:10px 16px 10px 12px;width:1%;white-space:nowrap;border-bottom:1px solid rgba(226,232,240,.6);}
.sst-td{padding:10px 20px;color:#1a202c;border-bottom:1px solid rgba(226,232,240,.6);text-align:left;white-space:nowrap;max-width:300px;overflow:auto;}
.sst-row:hover .sst-td,.sst-row:hover .sst-row-label{background:rgba(86,212,160,.04);}
.sst-more{padding:10px 20px;color:#718096;font-size:13px;text-align:center;cursor:pointer;border-bottom:1px solid rgba(226,232,240,.6);transition:color .15s;}
.sst-more:hover{color:#219669;}
/* Sessions Table — dark overrides */
.dark .sst-table{border-top-color:#56d4a0;border-bottom-color:#2a3a4f;}
.dark .sst-th{color:#56d4a0;border-bottom-color:#2a3a4f;}
.dark .sst-type-row .sst-type-th{color:#3d5068;border-bottom-color:#2a3a4f;}
.dark .sst-row-label{color:#d4dce8;border-bottom-color:rgba(42,58,79,.3);}
.dark .sst-td{color:#d4dce8;border-bottom-color:rgba(42,58,79,.3);}
.dark .sst-more{color:#6b7d93;border-bottom-color:rgba(42,58,79,.3);}
.dark .sst-more:hover{color:#56d4a0;}
/* CodeMirror overrides */
.cm-cell .cm-editor{background:transparent!important;}
.cm-cell .cm-scroller{overflow-x:auto;}
.cm-cell .cm-focused{outline:none!important;}"""

function _notebook_stylesheet()
    RawHtml("""<style id="sessions-notebook-css">$(NOTEBOOK_CSS)</style>""")
end

"""CodeMirror 6 bundle (inlined) + read-only init script for static notebooks."""
function _notebook_editor_bundle()
    Fragment(
        RawHtml(string("<script>", _EDITOR_BUNDLE_JS, "</script>")),
        RawHtml("""<script>
(function() {
  if (typeof C === 'undefined' || !C.EditorView) return;

  var hlTheme = C.HighlightStyle.define([
    {tag:C.t.keyword,color:"#e06b65"},{tag:C.t.controlKeyword,color:"#e06b65"},
    {tag:C.t.operatorKeyword,color:"#e06b65"},{tag:C.t.definitionKeyword,color:"#e06b65"},
    {tag:C.t.moduleKeyword,color:"#e06b65"},
    {tag:C.t.string,color:"#56d4a0"},{tag:C.t.character,color:"#56d4a0"},
    {tag:C.t.comment,color:"#4a6178",fontStyle:"italic"},
    {tag:C.t.lineComment,color:"#4a6178",fontStyle:"italic"},
    {tag:C.t.number,color:"#d4a056"},{tag:C.t.integer,color:"#d4a056"},
    {tag:C.t.float,color:"#d4a056"},{tag:C.t.bool,color:"#d4a056"},
    {tag:C.t.function(C.t.variableName),color:"#7bb8e8"},
    {tag:C.t.definition(C.t.variableName),color:"#7bb8e8"},
    {tag:C.t.typeName,color:"#b08fd8"},{tag:C.t.className,color:"#b08fd8"},
    {tag:C.t.variableName,color:"#d4dce8"},
    {tag:C.t.punctuation,color:"#6b7d93"},{tag:C.t.paren,color:"#6b7d93"},
    {tag:C.t.squareBracket,color:"#6b7d93"},{tag:C.t.brace,color:"#6b7d93"},
    {tag:C.t.operator,color:"#d4dce8"},{tag:C.t.special(C.t.string),color:"#7bb8e8"},
    {tag:C.t.macroName,color:"#d4a056"},
  ]);

  var edTheme = C.EditorView.theme({
    "&":{backgroundColor:"transparent",color:"#d4dce8"},
    ".cm-gutters":{backgroundColor:"transparent",color:"#3d5068",border:"none",minWidth:"38px"},
    ".cm-activeLine":{backgroundColor:"transparent"},
    ".cm-activeLineGutter":{backgroundColor:"transparent",color:"#3d5068"},
    ".cm-content":{fontFamily:"'JetBrains Mono',monospace",fontSize:"13px",lineHeight:"1.65",padding:"8px 0"},
    ".cm-scroller":{fontFamily:"'JetBrains Mono',monospace"},
    ".cm-line":{paddingLeft:"4px"},
    ".cm-cursor":{display:"none"},
  },{dark:true});

  function initSessionsCM() {
    document.querySelectorAll('.cm-cell').forEach(function(host) {
      if (host.querySelector('.cm-editor')) return;
      var src = host.dataset.src || '';
      new C.EditorView({
        state: C.EditorState.create({
          doc: src,
          extensions: [
            C.lineNumbers(),
            C.highlightSpecialChars(),
            C.drawSelection(),
            C.bracketMatching(),
            C.julia(),
            C.syntaxHighlighting(hlTheme),
            edTheme,
            C.EditorState.readOnly.of(true),
            C.EditorView.editable.of(false),
          ]
        }),
        parent: host
      });
    });
  }

  // Init on page load
  initSessionsCM();

  // Re-init after SPA navigation (Therapy.jl router swaps #page-content)
  window.addEventListener('therapy:router:loaded', initSessionsCM);
})();
</script>"""))
end

"""
    NotebookPage(nb::Notebook; prerendered=Dict()) -> VNode

Render a notebook as Therapy.jl VNodes with self-contained CSS, fonts, and JS.

Any Therapy.jl app that calls this gets the full Sessions.jl notebook experience —
cell chrome, accent bars, CodeMirror syntax highlighting, Pluto-style tables,
markdown prose, interactive sliders — without any additional setup.

```julia
using Sessions

nb, pre = Sessions.execute_notebook_for_web("notebook.jl")
MyLayout(Sessions.NotebookPage(nb; prerendered=pre))
```
"""
function NotebookPage(nb::Notebook;
        prerendered=Dict{UUID, PrerenderedGallery}())
    cells = ordered_cells(nb)
    rendered = Any[
        _notebook_fonts(),
        _notebook_stylesheet(),
    ]
    for cell in cells
        node = render_cell(cell; mode=:static, prerendered=prerendered)
        node !== nothing && push!(rendered, node)
    end

    # Add inline JS for slider/plotly interactivity
    has_sliders = any(c -> c.output.output_type == :bond && c.output.result isa Bond && c.output.result.element isa BoundSlider, cells)
    has_plotly = any(c -> c.output.output_type == :plotly_json, cells)

    if has_sliders || has_plotly
        push!(rendered, _slider_interaction_script())
    end

    # NOTE: CodeMirror bundle + init is NOT included here.
    # The consuming Layout (docs Layout.jl, or any Therapy app layout) is
    # responsible for loading the editor.js bundle and running initSessionsCM().
    # This keeps NotebookPage purely structural (HTML + CSS).

    Div(:class => "space-y-4 pl-8", rendered...)
end
