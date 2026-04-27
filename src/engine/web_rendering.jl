# web_rendering.jl — Web rendering: notebook → Therapy.jl VNodes
#
# Provides: render_cell, render_output_html, _render_output, CellGap,
#           _render_table_html, _render_tree_html, notebook_title.
#
# Single source of truth for cell-output HTML. Used by the live IDE
# (over WS) and (after Phase 3 lands) by the publish build pipeline.

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

# =============================================================================
# HTML String Renderers (shared: live app WS + Phase 3 publish)
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

    # Pluto emits a bare <table.pluto-table> with no caption and no
    # surrounding card. The wrap is a thin overflow-x:auto container so
    # wide tables get a horizontal scrollbar without disturbing the
    # cell-out flow.
    print(buf, """<div class="pluto-table-wrap"><table class="pluto-table"><thead>""")
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
        # Stateful expand/collapse toggle (Pluto only ships "more"; the
        # collapse direction is our addition). The button's data-state
        # tracks whether the hidden rows are revealed; clicking flips
        # display on every .pluto-table-hidden row and swaps the label.
        toggle_js = """var btn=this;var t=btn.closest('table');var rows=t.querySelectorAll('.pluto-table-hidden');var collapsed=btn.dataset.state!=='open';rows.forEach(function(r){r.style.display=collapsed?'':'none'});btn.dataset.state=collapsed?'open':'closed';btn.textContent=collapsed?'⌃ less':'⋮ '+btn.dataset.moreLabel;"""
        print(buf, """<tr><td colspan="$(ncol + 1)" class="pluto-tree-more-td">""")
        print(buf, """<pluto-tree-more data-state="closed" data-more-label=\"""",
              more_label, """\" onclick=\"""", toggle_js, """\">⋮ """,
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

"""Render cell output as a VNode for SSR.

Delegates to `render_output_html` for most types. Only keeps a VNode
shortcut for bonds (so RawHtml composes cleanly into the parent VNode
tree without a string-detour). Everything else flows through the
unified HTML-string renderer at the bottom of this fallthrough."""
function _render_output(cell::Cell)
    output = cell.output
    result = output.result

    output.output_type == :nothing && return nothing

    # Bond — SessionsUI's Bond defines MIME"text/html" → wrap as RawHtml.
    # In dev mode the page-level BOND_BRIDGE_JS attaches input listeners.
    # In publish mode (Phase 3) the wrapping @island will own the signal.
    if output.output_type == :bond && result isa Bond
        return RawHtml(sprint(show, MIME"text/html"(), result))
    end

    # All types: delegate to render_output_html (single source of truth)
    html = render_output_html(cell)
    isempty(html) ? nothing : RawHtml(html)
end

# =============================================================================
# render_output_html — single source of truth for cell output as HTML string
# =============================================================================

"""
    render_output_html(cell::Cell) -> String

Render cell output to an HTML string. Used by the live app (WS updates)
and by `_render_output` for SSR. Single source of truth.
"""
function render_output_html(cell::Cell)
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
        return isempty(text) ? "" : """<pre class="cell-text-output">$(_html_esc(text))</pre>"""
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
    render_cell(cell::Cell; mode=:static, index=0) -> VNode

Unified cell rendering function — single source of truth.

**mode=:static** — Output as VNode via `_render_output()`, no run/menu buttons, no stale/idle states.
**mode=:live** — Output as HTML string via `render_output_html()` → RawHtml, with run + menu buttons
and stale/idle/executing CSS classes.

Both modes share: CellToggle @island, CM editor host, runtime badge, cell-wrap/code-cell structure.
"""
function render_cell(cell::Cell; mode::Symbol=:static, index::Int=0)
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
        output_node = _render_output(cell)
        if output_node !== nothing
            push!(parts, Div(:class => "cell-out", :style => "padding:4px 0 8px;overflow-x:auto;",
                output_node))
        end
        # Stdout (live mode gets stdout via WS)
        if !isempty(output.stdout)
            push!(parts,
                Div(:class => "cell-out font-mono text-xs whitespace-pre overflow-x-auto",
                    :style => "padding:6px 0 10px;line-height:1.5;color:var(--output-text);",
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
    # CellView @island — owns ALL per-cell reactive chrome (eye toggle,
    # state classes, .stale class, runtime badge text, run/menu buttons).
    # The `cm-cell` host is passed as a child so CodeMirror initializes
    # against the same DOM node it always has.
    # =======================================================================
    state_int = if cell.state == cell_idle;     0
                elseif cell.state == cell_queued; 1
                elseif cell.state == cell_running; 2
                elseif cell.state == cell_done;    3
                elseif cell.state == cell_errored; 4
                else 0 end
    needs_run = is_stale(cell) || (is_never_run(cell) && !isempty(strip(cell.code)))
    initial_stale = (mode == :live && needs_run) ? 1 : 0
    initial_open = cell.folded ? 0 : 1
    initial_runtime = mode == :live ? Int(output.runtime_ns) : 0

    # CellView lives in src/components/CellView.jl, loaded into the
    # `Main.TherapyApp` module by Therapy.load_app! at app startup (same
    # path as every other Sessions @island). Look it up at SSR time
    # rather than depending on it at package-load time.
    #
    # All kwargs MUST be Int AND match the count + order of create_signal
    # calls in CellView — Therapy's compiler maps prop_names[i] →
    # signal_(i-1) by index. cell_id is read from the DOM at click time
    # inside CellView's button onclicks, so we don't pass it through.
    cell_view = if isdefined(Main, :TherapyApp) &&
                   isdefined(getfield(Main, :TherapyApp), :CellView)
        getfield(getfield(Main, :TherapyApp), :CellView)
    else
        nothing
    end
    if cell_view !== nothing
        push!(parts, cell_view(
                initial_state = state_int,
                initial_stale = initial_stale,
                initial_runtime_ns = initial_runtime,
                initial_open = initial_open) do
            Div(:class => "cm-cell",
                :data_cell_id => cell_id,
                :data_src => String(code))
        end)
    else
        # Fallback when running outside an app (e.g. precompile step):
        # render the cm-cell host bare so render_cell stays callable
        # without the component layer.
        push!(parts, Div(:class => "cm-cell",
            :data_cell_id => cell_id,
            :data_src => String(code)))
    end

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

# =============================================================================
# Published-notebook helpers — single source of truth for extracted
# notebooks. Emit.jl generates calls into these so the published output
# reuses IDE cell chrome; any styling tweak to cell-wrap/cell-body/cell-out
# propagates to both live IDE and published docs automatically.
# =============================================================================

"""
    render_value(x) -> String

Render any cell value to an HTML string. Same MIME classifier the live
IDE output pipeline uses. Priority:

  1. Exception → styled error block.
  2. `showable(MIME"text/html"(), x)` → `show(MIME"text/html"(), x)`.
     Covers Markdown.MD, DataFrames.DataFrame, WasmPlot.Figure,
     SessionsUI.Bond, and anything else that opts in.
  3. Tree-like values (Dict, Set, structs, Tuples, non-string arrays) →
     collapsible tree (`_render_tree_html`).
  4. Fallback: `sprint(print, x)`.

Step 2 before 3 is deliberate: Markdown.MD has both a text/html show
method AND is tree-like — we want the HTML form.

Public API. Called from extracted notebook @islands and from
`render_published_cell` for frozen output.
"""
function render_value(x)::String
    html = _render_value_raw(x)
    _inject_therapy_script_markers(html)
end

# ── Therapy SSR fallback ────────────────────────────────────────────
#
# Therapy.SSR.Render has specialised `render_html!` methods for Strings,
# Numbers, VNodes, and a handful of primitives; anything else crashes
# the page-render step with a MethodError. That matters for reactive
# cells whose `create_memo` returns a "rich" value Therapy doesn't
# recognise — DataFrames, Markdown.MD, custom structs with a
# `show(::MIME"text/html")` method, etc.
#
# The extractor intentionally doesn't pre-filter those cells (nothing
# should STOP from compiling at extract time — WasmTarget is the sole
# gatekeeper), so the SSR pass has to cope. This fallback routes any
# value Therapy's method table doesn't handle through `render_value`
# (the same MIME classifier the live IDE uses), giving DataFrames +
# Markdown + WasmPlot figures a working SSR path without special-
# casing the extractor.
#
# At WASM hydrate time this method isn't involved — Therapy's WASM
# runtime updates DOM nodes directly based on the memo type. If the
# @island failed to compile (e.g. DataFrame memo), no WASM loads and
# the SSR-rendered frozen output stays visible; the sliders render but
# don't drive anything, which matches the "try-to-compile, fall back
# gracefully" contract.
Therapy.render_html!(io::IO, x, ctx::Therapy.SSRContext) =
    print(io, render_value(x))

function _render_value_raw(x)::String
    x isa Exception && return string(
        "<pre class=\"jl-error-fallback\">",
        sprint(showerror, x), "</pre>")
    try
        if Base.showable(MIME"text/html"(), x)
            return sprint(io -> show(io, MIME"text/html"(), x))
        end
    catch
    end
    try
        if _is_tree_value(x)
            return _render_tree_html(x)
        end
    catch
    end
    sprint(print, x)
end

"""
Inject `/* __therapy */` into every `<script>` tag that lacks it.
Therapy's ClientRouter (Therapy.jl/src/Router/ClientRouter.jl:162–170)
only re-executes body `<script>` tags after a client-side page swap
if their content contains a magic marker (`therapy-island`,
`TherapyHydrate`, `__therapy`, or `__tw`). Cell outputs that embed
scripts — WasmPlot canvas renderers, Plotly blocks, MathJax
preambles, etc. — otherwise stay inert on SPA navigation and only
come to life after a full page reload. The marker is a JS comment
so it's a no-op at runtime.
"""
function _inject_therapy_script_markers(html::AbstractString)::String
    # Only touch `<script>` opens that lack a src= (inline scripts)
    # and aren't already marked. Case-insensitive on the tag name.
    replace(
        html,
        r"<script(?![^>]*\bsrc\s*=)(?![^>]*__therapy)([^>]*)>"i =>
            s"<script\1>/* __therapy */ ",
    )
end

"""
    render_source_block(code; cell_id="", runtime_ns=0, state=:done) -> Union{VNode, Nothing}

Return the full CellView-equivalent source chrome: cell-eye fold
toggle, cell-code-wrap, code-cell card, cell-ctrls (runtime badge),
and the read-only CodeMirror host. 1-to-1 DOM match with what the
IDE's CellView @island renders at SSR — minus run / menu buttons
(no kernel to target) and dynamic state transitions (static cells).

Empty code yields `nothing` so bootstrap cells don't get a blank
editor. The outer wrap's `.code-hidden` class (applied by
`render_published_cell` when the cell is folded) hides the code
wrapper via CSS; the cell-eye toggle still reveals it.
"""
function render_source_block(code::AbstractString;
                              cell_id::AbstractString="",
                              runtime_ns::Integer=0,
                              state::Symbol=:done)
    code = rstrip(code)
    isempty(code) && return nothing

    # notebook-chrome.css applies `position:relative;overflow:hidden;`
    # explicitly, so no Tailwind utilities are needed here. Published
    # .jl files must not rely on whatever utilities happen to be in
    # the host site's compiled Tailwind output.
    code_cell_cls = "code-cell"
    state === :errored && (code_cell_cls *= " cv-errored")

    runtime_str = _format_runtime(UInt64(max(runtime_ns, 0)))

    # Inline JS for fold toggle. Flips `code-hidden` on the enclosing
    # .cell-wrap so the CSS rule hides the cell-code-wrap — matches how
    # the live IDE drives fold through CSS (sans the @island signal).
    eye_onclick = "var w=this.closest('.cell-wrap');if(w)w.classList.toggle('code-hidden');"

    Div(:class => "cell-island",
        Div(:class => "cell-eye",
            :on_click => eye_onclick,
            :title => "Toggle source",
            Div(:style => "position:relative;width:14px;height:14px;",
                RawHtml("""<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>"""))),
        Div(:class => "cell-code-wrap",
            Div(:class => code_cell_cls,
                # cell-ctrls positioning lives in notebook-chrome.css so
                # the bundle self-contains — Tailwind utility classes
                # on the .jl side wouldn't survive docs's scan path.
                Div(:class => "cell-ctrls",
                    Span(:class => "rt-badge", runtime_str)),
                Div(:class => "cm-cell cm-cell-published",
                    :data_cell_id => cell_id,
                    :data_src => String(code),
                    :data_readonly => "1"))))
end

"""
    CellDiv(; cell_id, source_code, output=nothing, cell_type=:code,
              folded=false, show_output=true, runtime_ns=0,
              state=:done) -> VNode

Canonical cell chrome for published notebooks. 1-to-1 match with the
live IDE's `cell-wrap > cell-body > [cell-out, cell-island]` structure.

Accepts any Therapy value as `output`:
  - `RawHtml(...)`  for a frozen static cell (SSR-evaluated body).
  - `Input(...)` / `Span(memo)` / `Canvas(...)` / etc. for bond +
    reactive cells living inside an `@island` — reactivity flows
    through Therapy's native signal subscription, no innerHTML swap.
  - `nothing` for a source-only cell (rare).

**Visibility semantics** (author-controlled, not reader-controlled):
  - `folded=true` (Pluto's `# ╟─` prefix): source is NOT in the DOM at
    all, reader cannot reveal. Typical: markdown, boilerplate imports.
  - `folded=false` (Pluto's `# ╠═`): source shown on load, reader can
    toggle via cell-eye gutter icon — ephemeral, reload returns shown.
  - `show_output=false` (trailing `;`): cell-out slot is omitted.

`cell_type=:markdown` adds the purple left stripe
(`.md-cell::before`) that distinguishes markdown cells in the IDE.

**State:**
  - `:done`        normal cell.
  - `:errored`     add `cv-errored` → red-shadow lift.
  - `:wasm_failed` WALL-cell mode — reactive cell whose body can't
    compile to WebAssembly. Renders a red error band above the frozen
    output so the reader understands why the cell isn't reactive.

`runtime_ns` is baked into the `.rt-badge` (human-formatted).
"""
function CellDiv(; cell_id::AbstractString,
                   source_code::AbstractString = "",
                   output = nothing,
                   cell_type::Symbol = :code,
                   folded::Bool = false,
                   show_output::Bool = true,
                   runtime_ns::Integer = 0,
                   state::Symbol = :done,
                   reactive::Bool = false)
    parts = Any[]
    wrap_cls = "cell-wrap"
    cell_type === :markdown && (wrap_cls *= " md-cell")
    has_output = show_output && output !== nothing
    has_output && (wrap_cls *= " has-output")
    folded && (wrap_cls *= " code-hidden")
    state === :errored && (wrap_cls *= " wrap-errored")
    state === :wasm_failed && (wrap_cls *= " wrap-wasm-failed")

    # WALL-cell band — reader-facing explanation. Sits ABOVE the frozen
    # output so it's the first thing seen. Same markup shape as the
    # structured-error renderer so notebook-chrome.css styling applies
    # automatically (`.jl-error` + `.jl-error-badge`).
    state === :wasm_failed && push!(parts,
        Div(:class => "jl-error wasm-failed-band",
            Div(:class => "jl-error-content",
                Div(:class => "jl-error-header",
                    Span(:class => "jl-error-badge", "WASM compile failed"),
                    Span(:class => "jl-error-type", "Cell frozen at initial value")),
                Div(:class => "jl-error-message",
                    "This reactive cell's body can't compile to WebAssembly, so it no longer re-runs when its upstream bond changes. The output below is frozen at the bond's default value."))))

    # Output goes above source (Pluto convention).
    has_output && push!(parts, Div(:class => "cell-out",
        :data_cell_id => cell_id,
        :style => "padding:4px 0 2px;overflow-x:auto;",
        output))

    # Source block: positional `Show` → returns `nothing` or `render()`.
    # Do-block sugar would route to the ShowNode-emitting form which
    # leaves a `display:none` tombstone in HTML.
    if !isempty(source_code)
        src = Therapy.Show(!folded, () -> render_source_block(source_code;
            cell_id=cell_id, runtime_ns=runtime_ns, state=state))
        src !== nothing && push!(parts, src)
    end

    # `data-reactive="true"` tags cells whose output depends on WASM
    # hydration (memos, effects). notebook-init.js scans these after
    # DOMContentLoaded: if the surrounding `[data-component]` island
    # never reaches `data-hydrated="true"` (the `@island` failed to
    # WASM-compile, or WASM threw at hydrate time), the JS adds the
    # wrap-wasm-failed class + error band so the reader sees a clear
    # explanation instead of a stale canvas / frozen span. Static
    # cells skip this treatment; they don't depend on WASM anyway.
    attrs = Any[:data_cell_id => cell_id, :class => wrap_cls]
    reactive && push!(attrs, :data_reactive => "true")
    Div(attrs...,
        Div(:class => "cell-body", parts...))
end

"""Legacy alias — `render_published_cell` is the pre-`CellDiv` name
held for any external caller. Delete once no extracted notebooks
reference it. `output_content` → `output`."""
function render_published_cell(; cell_id::AbstractString,
                                 source_code::AbstractString,
                                 output_content,
                                 show_source::Bool=true,
                                 folded::Bool=false,
                                 show_output::Bool=true,
                                 runtime_ns::Integer=0,
                                 state::Symbol=:done)
    CellDiv(; cell_id, source_code, output=output_content,
              folded, show_output, runtime_ns, state)
end

# ── Self-contained asset bundle ──────────────────────────────────────
# Load at module init so `using Sessions` picks them up once; every
# `render_published_notebook` call then emits them inline.
#
# Shadcn-style: the notebook carries its own chrome (CSS + CodeMirror
# + init JS) so dropping an extracted .jl into ANY Therapy app just
# works. Docs sites no longer need to wire editor.js or notebook CSS
# at the Layout level.
#
# Singleton guards make re-rendering (SPA nav, gallery pages with
# multiple notebooks) idempotent: the CSS uses an `id="…"` sentinel
# that the inline script removes from later copies, and the JS sets
# `window.__SESSIONS_NB_BOOT = true` on first run.
const _STATIC_DIR = normpath(joinpath(@__DIR__, "..", "..", "static"))
const NOTEBOOK_CHROME_CSS = let p = joinpath(_STATIC_DIR, "notebook-chrome.css")
    isfile(p) ? read(p, String) : ""
end
const NOTEBOOK_EDITOR_JS = let p = joinpath(_STATIC_DIR, "editor.js")
    isfile(p) ? read(p, String) : ""
end
const NOTEBOOK_INIT_JS = let p = joinpath(_STATIC_DIR, "notebook-init.js")
    isfile(p) ? read(p, String) : ""
end

"""
Return the inline `<style>` + `<script>` bundle every published
notebook brings along. Three tags, each with a singleton-guard data
attribute so multiple notebooks on one page dedupe.

1. `<style data-sessions-nb-chrome>` — notebook-chrome.css.
2. `<script data-sessions-nb-editor>` — editor.js (sets window.C),
   guarded by `window.__SESSIONS_NB_CM_LOADED` so the ~600KB bundle
   only evaluates once.
3. `<script data-sessions-nb-init>` — notebook-init.js (read-only
   CodeMirror init + theme reactivity), guarded by
   `window.__SESSIONS_NB_BOOT`.

Public so extraction can call it at extract time and bake the exact
string into the generated .jl file (`const _NOTEBOOK_ASSETS_HTML =
…`). At runtime the extracted notebook then passes that literal
back via `render_published_notebook(…; assets_html = …)` — the
host never has to reach into Sessions at all.
"""
function published_notebook_assets_html()::String
    # Each <script> starts with `/* __therapy */` so Therapy.jl's
    # ClientRouter picks it up for re-execution after a client-side
    # page swap. The router uses a substring match on the script
    # body (`ClientRouter.jl` line 162–170: any of `therapy-island`,
    # `TherapyHydrate`, `__therapy`, `__tw`) to decide whether to
    # re-run after swap; without the marker, navigating to a notebook
    # page via SPA nav leaves the new scripts inert and the CM hosts
    # render as empty divs. The marker is a plain JS comment so it
    # costs nothing at runtime.
    string(
        "<style data-sessions-nb-chrome=\"1\">", NOTEBOOK_CHROME_CSS, "</style>",
        "<script data-sessions-nb-editor=\"1\">",
            "/* __therapy */ ",
            "if(!window.__SESSIONS_NB_CM_LOADED){window.__SESSIONS_NB_CM_LOADED=true;",
            NOTEBOOK_EDITOR_JS,
            "}",
        "</script>",
        "<script data-sessions-nb-init=\"1\">",
            "/* __therapy */ ",
            NOTEBOOK_INIT_JS,
        "</script>",
    )
end

"""
    render_published_notebook(cells...; assets_html=nothing) -> VNode

Outer container for a published notebook. Matches the live IDE's
`.nb-cell-list` inner container (max-width, horizontal padding) so
published pages feel identical to the IDE's notebook body.

Prepends a self-contained asset bundle (CSS + CodeMirror bundle +
init script). `assets_html` is the Tailwind-style shadcn override:

  - Extracted notebooks bake the bundle into their own `.jl` at
    extract time (see Emit.jl) and pass it back here, so the file
    is fully self-contained — drop it in any Therapy app and it
    renders without touching Sessions internals at runtime.
  - Calling `render_published_notebook(…)` without `assets_html` (eg
    at the REPL, in tests, or in ad-hoc Therapy apps that `using
    Sessions`) falls back to the Sessions-bundled copy.

Singleton JS guards make it safe to include multiple notebooks on
one page — each bundle is a no-op after the first evaluation.
"""
function render_published_notebook(cells...; assets_html::Union{Nothing, AbstractString}=nothing)
    html = assets_html === nothing ? published_notebook_assets_html() : String(assets_html)
    Div(:class => "notebook-extracted",
        RawHtml(html),
        Div(:class => "nb-cell-list",
            :style => "max-width:900px;margin:0 auto;padding-left:28px;padding-right:28px;position:relative;",
            cells...))
end

