# Emit.jl — assemble an ExtractionPlan into a single .jl Therapy
# component. Shape (one @island per notebook — matches Therapy.jl's
# own NotebookDemo):
#
#   module <Name>Mod
#     using Therapy: @island, create_signal, create_memo, create_effect,
#                    RawHtml, Div, Input, Span, Canvas
#     using Sessions: CellDiv, render_value, render_published_notebook
#     using <user notebook deps>
#
#     # Baked asset bundle so the .jl drops into any Therapy app.
#     const _NOTEBOOK_ASSETS_HTML = "…"
#
#     # Bond defaults as plain constants so every static cell body that
#     # reads the bond at module-load time resolves. The @island below
#     # shadows these with create_signal inside its scope.
#     const _default_n = 8
#     const n          = _default_n
#
#     # Each cell's body runs once at module load for SSR baseline.
#     const _cell_<id> = try let <verbatim code> end catch _e; _e end
#
#     # ONE @island per notebook. Outer body runs regular Julia at SSR
#     # (DataFrames / Markdown / show()… all fine — confirmed via
#     # Therapy Analysis.jl:215). Only the reactive CLOSURES passed to
#     # create_memo / create_effect / event-handlers get WASM-compiled.
#     @island function <Name>()
#         # Bond signals.
#         n, set_n = create_signal(_default_n)
#
#         # Reactive memos — one per simple bond-dependent cell. The
#         # body is the cell's source with bare bond references
#         # (`n`) rewritten to signal reads (`n()`) so updates flow.
#         _reactive_<id> = create_memo(() -> begin <rewritten body> end)
#
#         # Reactive effects — WasmPlot / canvas-writing cells go
#         # through here. Same rewrite, plus `render!(fig)` appended.
#         create_effect(() -> begin <rewritten body>; render!(fig) end)
#
#         return render_published_notebook(
#             CellDiv(output = RawHtml(render_value(_cell_<id>))),         # static
#             CellDiv(output = Div(Input(:value=>n, :on_input=>set_n,…))), # bond
#             CellDiv(output = Span(_reactive_<id>)),                      # reactive memo
#             CellDiv(output = Canvas(:width=>…, :height=>…)),             # reactive plot
#             CellDiv(output = RawHtml(render_value(_cell_<id>)),
#                     state = :wasm_failed),                               # WALL
#             assets_html = _NOTEBOOK_ASSETS_HTML,
#         )
#     end
#   end
#   const <Name> = <Name>Mod.<Name>
#
# WALL fallback: bond-dependent cells whose body uses patterns
# WasmTarget can't handle (DataFrame, Markdown.MD, arbitrary show()
# methods returning non-primitives) get frozen at the bond default
# and decorated with a `state=:wasm_failed` band — explicit to the
# reader that the cell isn't live.

using Dates: now

# ─── String helpers ────────────────────────────────────────────────────

"Sanitize a UUID into a valid Julia identifier suffix."
function _id_suffix(id)::String
    s = replace(string(id), "-" => "_")
    isdigit(first(s)) ? "_" * s : s
end

"Indent each line of `s` by `n` spaces."
function _indent(s::AbstractString, n::Int)
    pad = " "^n
    join((pad * line for line in split(rstrip(s), '\n')), "\n")
end

"""
Emit a Julia string literal containing `code` verbatim. `repr` handles
all escape concerns (triple-quoted markdown, `\$` interpolations,
minified JS binary), and the result round-trips through Julia's
parser back to the original string.
"""
_code_literal(code::AbstractString) = repr(String(code))

"""
True if the cell is purely `using/import` lines and/or `Pkg.activate /
Pkg.add` calls — notebook bootstrap that's already been lifted to the
module top via `collect_imports` (or just doesn't belong in the
rendered output at all).
"""
function _is_bootstrap_cell(code::AbstractString)::Bool
    s = strip(code)
    isempty(s) && return true
    occursin(r"\bPkg\.activate\b", s) && return true
    occursin(r"\bPkg\.add\b",      s) && return true
    for raw in split(s, '\n')
        line = strip(raw)
        (isempty(line) || startswith(line, "#")) && continue
        (startswith(line, "using ") || startswith(line, "import ")) && continue
        occursin(r"^\s*Pkg\.", line) && continue
        line in ("begin", "end", "])") && continue
        return false
    end
    return true
end

"`true` if the cell's last non-blank, non-comment line ends with `;` —
Pluto's convention for suppressing output."
function _suppresses_output(code::AbstractString)::Bool
    body = strip(code)
    isempty(body) && return false
    lines = split(body, '\n')
    for i in length(lines):-1:1
        line = rstrip(lines[i])
        ln_trimmed = strip(line)
        isempty(ln_trimmed) && continue
        startswith(ln_trimmed, "#") && continue
        m = match(r"^(.*?)\s*#[^\"]*$", line)
        last_code = m === nothing ? line : m.captures[1]
        return endswith(rstrip(last_code), ";")
    end
    return false
end

"True if the cell's code is a Markdown string macro."
function _is_markdown_cell_code(code::AbstractString)::Bool
    s = strip(code)
    startswith(s, "md\"\"\"") || startswith(s, "md\"")
end

"Return the `state = :done` / `:errored` Symbol the published shell wants."
function _cell_state_literal(cc::CellClass)::String
    cc.cell.output.output_type === :error ? ":errored" : ":done"
end

"Return the runtime_ns integer captured at extract time (or 0)."
_cell_runtime_literal(cc::CellClass)::String = string(Int(cc.cell.output.runtime_ns))

# ─── Bond widget parsing ───────────────────────────────────────────────

struct BondSpec
    default_expr::String
    kind::Symbol
    min_expr::String
    max_expr::String
    step_expr::String
    widget_class::String
end

"""
Best-effort parse of a `@bind name widget_expr` cell into a `BondSpec`.
Returns `nothing` if the widget isn't a shape v1 can emit natively.
Supports `BoundSlider(X:Y)` and `BoundSlider(X:S:Y; default=…)`.
"""
function _parse_bond_widget(code::AbstractString)::Union{BondSpec, Nothing}
    expr = try
        Base.Meta.parse("begin\n$(strip(code))\nend")
    catch
        return nothing
    end
    widget_call = _find_bind_widget(expr)
    widget_call === nothing && return nothing

    fname = widget_call.args[1]
    name_sym = fname isa Expr && fname.head === :. ? fname.args[end].value : fname
    name_sym isa QuoteNode && (name_sym = name_sym.value)
    name_sym isa Symbol || return nothing

    name_sym === :BoundSlider && return _parse_slider_args(widget_call)
    return nothing
end

"Walk `expr` (which may be a `begin…end` wrapping the cell) and return
the widget `:call` node from a `@bind name widget` — or `nothing`."
function _find_bind_widget(expr)
    if expr isa Expr
        if expr.head === :macrocall && length(expr.args) >= 3 &&
           (expr.args[1] === Symbol("@bind") ||
            expr.args[1] isa GlobalRef && expr.args[1].name === Symbol("@bind"))
            w = expr.args[4]
            w isa Expr && w.head === :call && return w
        end
        for a in expr.args
            r = _find_bind_widget(a)
            r === nothing || return r
        end
    end
    return nothing
end

"`BoundSlider(X:Y)` / `BoundSlider(X:Y; default=Z)` → BondSpec."
function _parse_slider_args(call::Expr)::Union{BondSpec, Nothing}
    positional = Any[]
    default_expr = nothing
    for a in call.args[2:end]
        if a isa Expr && a.head === :parameters
            for kw in a.args
                if kw isa Expr && kw.head === :kw && kw.args[1] === :default
                    default_expr = string(kw.args[2])
                end
            end
        else
            push!(positional, a)
        end
    end
    isempty(positional) && return nothing
    range_expr = positional[1]

    if range_expr isa Expr && range_expr.head === :call && range_expr.args[1] === :(:)
        args = range_expr.args
        if length(args) == 3       # a:b
            min_e, step_e, max_e = string(args[2]), "1", string(args[3])
        elseif length(args) == 4   # a:s:b
            min_e, step_e, max_e = string(args[2]), string(args[3]), string(args[4])
        else
            return nothing
        end
        default_expr = default_expr === nothing ? min_e : default_expr
        return BondSpec(default_expr, :slider, min_e, max_e, step_e, "su-slider")
    end
    return nothing
end

# ─── Reactive-cell translator ──────────────────────────────────────────
#
# Strategy:
#
#   1. Parse the cell body to an AST.
#   2. Detect whether the cell is (a) WALL (patterns WasmTarget can't
#      handle — DataFrame, arbitrary show() methods), (b) WasmPlot
#      (Figure + render!-style canvas output), or (c) plain memo.
#   3. AST-walk the body replacing bare bond `Symbol`s with
#      `:(n())` (signal reads) so updates flow. Shadowing binders
#      (`let n = …`, `for n in …`, `n = …`) are detected and their
#      LHS is left alone.
#   4. Serialize the rewritten AST via `string(expr)` (surface syntax).
#
# The memo/effect declarations land at the top of the @island body;
# the cell's `output=` slot references the local getter (`Span(m)`)
# or a Canvas placeholder.

"""
Result of classifying + translating a single reactive cell. Each
variant is what the @island emitter needs to produce — declarations
above the return tree and a CellDiv `output=` expression.
"""
struct ReactiveEmit
    kind::Symbol                 # :memo | :effect | :wall | :unparseable
    decl_source::String          # Julia to splice above the return (empty for wall)
    output_expr::String          # goes into CellDiv(output = …)
end

"""
Strip `#`-prefixed single-line comments from `code` so downstream
pattern-based WALL heuristics don't false-match content inside
comments (e.g. an explanatory comment mentioning `"n = \$(n)"`
shouldn't force the whole cell into WALL). String literals are
preserved — a simple state machine flips between in-string and
out-of-string as it scans each line.
"""
function _strip_comments_linewise(code::AbstractString)::String
    out = IOBuffer()
    for raw_line in split(code, '\n'; keepempty = true)
        in_str = false; str_q = '"'; prev = '\0'
        cut = nothing
        chars = collect(raw_line)
        for (i, c) in enumerate(chars)
            if in_str
                (c == str_q && prev != '\\') && (in_str = false)
            else
                if c == '"' && prev != '\\'
                    in_str = true; str_q = c
                elseif c == '#'
                    cut = i
                    break
                end
            end
            prev = c
        end
        if cut === nothing
            print(out, raw_line)
        else
            print(out, raw_line[1:prevind(raw_line, cut)])
        end
        print(out, '\n')
    end
    return String(take!(out))
end

"True if `code` looks like a WasmPlot figure cell — determines
whether the reactive translator emits a `create_effect + Canvas`
shape vs a plain `create_memo + Span`. Pattern-matching on the cell
source; WasmTarget compilability is checked at BUILD time, not here."
function _is_wasmplot_body(code::AbstractString)::Bool
    code = _strip_comments_linewise(code)
    occursin(r"\b(WP\.|WasmPlot\.)?Figure\s*\(", code)            && return true
    occursin(r"\b(barplot|lines|scatter|heatmap|hist)\s*!", code) && return true
    return false
end

"""
Extract `(width, height)` from a `Figure(size=(W,H))` call anywhere in
`body_expr`. Returns `(680, 220)` if none found (NotebookStep4 default).
Uses `Ref`s since Julia closures don't rebind captured locals.
"""
function _wasmplot_canvas_size(body_expr)::Tuple{Int, Int}
    w = Ref(680); h = Ref(220)
    _walk(body_expr) do node
        if node isa Expr && node.head === :call
            fn = node.args[1]
            is_figure = (fn === :Figure) ||
                (fn isa Expr && fn.head === :. && fn.args[end] isa QuoteNode &&
                 fn.args[end].value === :Figure)
            is_figure || return
            for arg in node.args[2:end]
                # Kwargs can appear two ways depending on whether the
                # call used a semicolon: `f(;key=val)` wraps them in
                # an `Expr(:parameters, kw...)`; `f(key=val)` emits the
                # bare `Expr(:kw, key, val)` at the call site.
                kws = if arg isa Expr && arg.head === :parameters
                    arg.args
                elseif arg isa Expr && arg.head === :kw
                    (arg,)
                else
                    continue
                end
                for kw in kws
                    kw isa Expr && kw.head === :kw && kw.args[1] === :size || continue
                    val = kw.args[2]
                    val isa Expr && val.head === :tuple && length(val.args) == 2 || continue
                    wv, hv = val.args
                    wv isa Integer && (w[] = Int(wv))
                    hv isa Integer && (h[] = Int(hv))
                end
            end
        end
    end
    return (w[], h[])
end

"Depth-first Expr walker — applies `fn` to every node."
function _walk(fn, expr)
    fn(expr)
    if expr isa Expr
        for a in expr.args
            _walk(fn, a)
        end
    end
end

"""
Strip every `LineNumberNode` out of an `Expr` tree. `string(expr)`
otherwise emits them as `#= file:line =#` block comments that
clutter the generated .jl output without adding any value.
"""
function _strip_linenumbers(expr)
    if expr isa Expr
        new_args = Any[]
        for a in expr.args
            a isa LineNumberNode && continue
            push!(new_args, _strip_linenumbers(a))
        end
        return Expr(expr.head, new_args...)
    else
        return expr
    end
end

"""
Walk `expr` and replace every bare `Symbol` matching a bond name with
`:(name())` (a signal read). Skips LHS of assignment, `for`/`let`
binders, and macro-name slots — so local shadowing still works and
`@bind` / `@some_other_macro` aren't accidentally rewritten.
"""
function _rewrite_bond_reads(expr, bonds::Set{Symbol})
    if expr isa Symbol
        return expr in bonds ? Expr(:call, expr) : expr
    elseif !(expr isa Expr)
        return expr
    end

    h = expr.head
    if h === :(=) && length(expr.args) == 2
        return Expr(:(=), expr.args[1], _rewrite_bond_reads(expr.args[2], bonds))
    elseif h === :for
        # `for iter ; body end` — rewrite body + iter RHS, leave iter LHS alone.
        iter = expr.args[1]; body = expr.args[2]
        return Expr(:for, _rewrite_iter(iter, bonds),
                    _rewrite_bond_reads(body, bonds))
    elseif h === :let
        return Expr(:let, expr.args[1], _rewrite_bond_reads(expr.args[2], bonds))
    elseif h === :macrocall
        # args[1] macro name, args[2] LineNumberNode, args[3…] rewritten.
        new_args = Any[expr.args[1], expr.args[2]]
        for a in expr.args[3:end]
            push!(new_args, _rewrite_bond_reads(a, bonds))
        end
        return Expr(:macrocall, new_args...)
    elseif h === :. && length(expr.args) == 2 && expr.args[2] isa QuoteNode
        # Field access a.b — rewrite `a` only if it's a bond; field stays.
        return Expr(:., _rewrite_bond_reads(expr.args[1], bonds), expr.args[2])
    else
        return Expr(h, [_rewrite_bond_reads(a, bonds) for a in expr.args]...)
    end
end

"Walk a `for` iteration spec (either `var = range` or a block of
them) and rewrite only the range RHS — loop variables must keep
their original name so the body reads them locally."
function _rewrite_iter(iter, bonds::Set{Symbol})
    if iter isa Expr && iter.head === :block
        return Expr(:block, [_rewrite_iter(a, bonds) for a in iter.args]...)
    elseif iter isa Expr && iter.head === :(=)
        return Expr(:(=), iter.args[1], _rewrite_bond_reads(iter.args[2], bonds))
    else
        return iter
    end
end

"""
True if `code` uses a package that is **known** to be incompatible
with WasmTarget — not a heuristic, a hard fact about where Julia
stdlibs + common ecosystem packages currently stand:

  - `DataFrame(` / `DataFrame{`  DataFrames.jl is column-storage +
     PrettyTables; none of that exists in WasmTarget's method cover.
  - `md"…"`                     Markdown macro expands to parser
     machinery + html rendering that's not in coverage either.

Cells matching these patterns would turn into malformed WASM when
WasmTarget tries to lower them, which then either crashes wasm-opt
("popping from empty stack", our exact symptom) OR even if it slips
past validation it crashes on the first instantiation. Either way,
ONE such cell in the `@island` kills reactivity for every OTHER
bond-dependent cell, because Therapy has one compile unit per
island. To keep the sibling cells reactive we freeze these at the
bond default with a `:wasm_failed` band, while every OTHER reactive
cell (simple arithmetic, WasmPlot closures, etc.) is still emitted
untouched and handed to WasmTarget. This isn't the old heuristic
wall — broadcasts, string-interp, and friends all still go through.
"""
function _is_known_incompatible_body(code::AbstractString)::Bool
    code = _strip_comments_linewise(code)
    occursin(r"\bDataFrame\s*[\(\{]", code) && return true
    occursin(r"\bmd\"", code)               && return true
    return false
end

"""
Translate a bond-dependent cell into declarations + output expression
for embedding in the @island body.

Extractor default: emit every reactive cell as `create_memo` /
`create_effect` and let WasmTarget decide. The only preemptive
walling is for `_is_known_incompatible_body` patterns (DataFrames,
Markdown) — if left as a live memo, these would take the whole
`@island` down with them (wasm-opt rejects the malformed bytecode,
Therapy skips WASM for EVERY cell in that island). Walling just
those known-impossible cells keeps their siblings reactive.
"""
function translate_reactive(cc::CellClass, bonds::Set{Symbol})::ReactiveEmit
    code    = String(strip(cc.cell.code))
    suffix  = _id_suffix(cc.cell.id)
    memo_id = "_reactive_$(suffix)"

    _is_known_incompatible_body(code) && return ReactiveEmit(:wall, "",
        "RawHtml(render_value(_cell_$(suffix)))")

    body_expr = try
        Base.Meta.parse("begin\n$(code)\nend")
    catch
        return ReactiveEmit(:wall, "",
            "RawHtml(render_value(_cell_$(suffix)))")
    end

    rewritten = _rewrite_bond_reads(body_expr, bonds)
    rewritten_stripped = _strip_linenumbers(rewritten)

    if _is_wasmplot_body(code)
        w, h = _wasmplot_canvas_size(body_expr)
        # Flatten the cell body into a single begin-block whose
        # trailing `fig` reference is replaced by `render!(fig)`.
        # Matches Therapy NotebookStep4's shape (one flat begin-block
        # inside create_effect) exactly — WasmTarget's type-inferrer
        # is demonstrably happy with that shape.
        body_str = _flatten_for_render(rewritten_stripped)
        decl = join([
            "        create_effect(() -> begin",
            _indent(body_str, 12),
            "        end)",
            "",
        ], "\n")
        output = "Canvas(:width => $(w), :height => $(h))"
        return ReactiveEmit(:effect, decl, output)
    end

    body_str = _strip_wrapping_block(rewritten_stripped)
    decl = join([
        "        $(memo_id) = create_memo(() -> begin",
        _indent(body_str, 12),
        "        end)",
        "",
    ], "\n")
    output = "Span($(memo_id))"
    return ReactiveEmit(:memo, decl, output)
end

"""
Flatten a WasmPlot cell body into a `begin`-block suitable for
dropping straight inside `create_effect(() -> begin … end)`.

Unwraps a single outer `let` (if present), and if the trailing
expression is a bare variable reference — the usual Pluto shape
`let fig = Figure(); …; fig end` — rewrites the trailing reference
to `render!(<var>)` so the canvas actually gets drawn to. If the
trailing expression is a complex one (e.g. `Figure(…)` directly),
it's assigned to `_wasmplot_fig` first and that local is rendered.

Falls through to `string(expr)` for any shape we don't recognise
(which WasmTarget will usually reject, prompting the user to
rewrite — but the translator doesn't pre-judge).
"""
function _flatten_for_render(expr)::String
    # If wrapped in begin-block, peel it off.
    inner = expr
    if inner isa Expr && inner.head === :block
        stmts = filter(a -> !(a isa LineNumberNode), inner.args)
        if length(stmts) == 1 && stmts[1] isa Expr && stmts[1].head === :let
            # let { … } end  — extract the body block.
            body = stmts[1].args[2]
            if body isa Expr && body.head === :block
                return _append_render_bang(body)
            end
        end
        # Plain block with (possibly) many stmts.
        return _append_render_bang(inner)
    end
    # Anything else — just stringify.
    return string(expr)
end

"Take an `Expr(:block, stmts…, last)` and return a stringified
`begin`-less body whose trailing expression has been replaced by
`render!(last)` (bare variable) or assigned then rendered (complex)."
function _append_render_bang(block::Expr)::String
    stmts = filter(a -> !(a isa LineNumberNode), block.args)
    isempty(stmts) && return ""
    head_stmts = stmts[1:end-1]
    tail       = stmts[end]
    new_tail = tail isa Symbol ?
        Expr(:call, :render!, tail) :
        Expr(:block,
             Expr(:(=), :_wasmplot_fig, tail),
             Expr(:call, :render!, :_wasmplot_fig))
    body_expr = Expr(:block, head_stmts..., new_tail)
    # Drop the `begin`/`end` wrapping `string` adds to a :block.
    return _strip_wrapping_block(body_expr)
end

"Unwrap a top-level `begin … end` wrapper produced by our parse so
the serialized source doesn't get an extra layer of `begin/end`."
function _strip_wrapping_block(expr)::String
    if expr isa Expr && expr.head === :block
        # Drop leading LineNumberNodes for readability.
        args = filter(a -> !(a isa LineNumberNode), expr.args)
        if length(args) == 1
            return string(args[1])
        else
            return join(map(string, args), "\n")
        end
    end
    return string(expr)
end

# ─── Module-level constants ────────────────────────────────────────────

function emit_cell_const(cc::CellClass)::String
    code = strip(cc.cell.code)
    _is_bootstrap_cell(code) && return ""
    suffix = _id_suffix(cc.cell.id)
    join([
        "    # ── Cell $(cc.cell.id) ($(cc.kind)) ──",
        "    const _cell_$(suffix) = try",
        "        let",
        _indent(code, 12),
        "        end",
        "    catch _e",
        "        _e",
        "    end",
    ], "\n") * "\n"
end

function emit_bond_defaults(specs::Dict{Symbol, BondSpec},
                            fallback_defaults::Dict{Symbol, String})::String
    isempty(specs) && isempty(fallback_defaults) && return "    # (no bonds)\n"
    lines = String["    # ── Bond defaults (one per @bind) ──"]
    for (bond, spec) in pairs(specs)
        push!(lines, "    const _default_$(bond) = $(spec.default_expr)")
        push!(lines, "    const $(bond)          = _default_$(bond)")
    end
    for (bond, def) in pairs(fallback_defaults)
        haskey(specs, bond) && continue
        push!(lines, "    const _default_$(bond) = $(def)")
        push!(lines, "    const $(bond)          = _default_$(bond)")
    end
    return join(lines, "\n") * "\n"
end

# ─── CellDiv call-site emitters ────────────────────────────────────────

function emit_static_cell_call(cc::CellClass)::String
    suffix = _id_suffix(cc.cell.id)
    folded_lit   = cc.cell.folded ? "true" : "false"
    show_out_lit = _suppresses_output(cc.cell.code) ? "false" : "true"
    cell_type_lit = _is_markdown_cell_code(cc.cell.code) ? ":markdown" : ":code"
    join([
        "            CellDiv(",
        "                cell_id     = $(repr(string(cc.cell.id))),",
        "                source_code = $(_code_literal(cc.cell.code)),",
        "                runtime_ns  = $(_cell_runtime_literal(cc)),",
        "                state       = $(_cell_state_literal(cc)),",
        "                cell_type   = $(cell_type_lit),",
        "                folded      = $(folded_lit),",
        "                show_output = $(show_out_lit),",
        "                output      = RawHtml(render_value(_cell_$(suffix))),",
        "            )",
    ], "\n")
end

function emit_bond_cell_call(cc::CellClass, spec::Union{BondSpec, Nothing})::String
    bond         = cc.bond_name
    folded_lit   = cc.cell.folded ? "true" : "false"
    suffix       = _id_suffix(cc.cell.id)

    output_expr = if spec === nothing
        "RawHtml(render_value(_cell_$(suffix)))"
    else
        "Div(:class => \"flex items-center gap-3\",\n" *
        "                    Input(:type     => \"range\",\n" *
        "                          :min      => $(repr(spec.min_expr)),\n" *
        "                          :max      => $(repr(spec.max_expr)),\n" *
        "                          :step     => $(repr(spec.step_expr)),\n" *
        "                          :value    => $(bond),\n" *
        "                          :on_input => set_$(bond),\n" *
        "                          :class    => $(repr(spec.widget_class))),\n" *
        "                    Span(:class => \"su-slider-out\", $(bond)))"
    end

    join([
        "            CellDiv(",
        "                cell_id     = $(repr(string(cc.cell.id))),",
        "                source_code = $(_code_literal(cc.cell.code)),",
        "                runtime_ns  = $(_cell_runtime_literal(cc)),",
        "                state       = $(_cell_state_literal(cc)),",
        "                folded      = $(folded_lit),",
        "                show_output = true,",
        "                output      = $(output_expr),",
        "            )",
    ], "\n")
end

"`re` is the `ReactiveEmit` for this cell; its `output_expr` goes into
the CellDiv slot, and `:wasm_failed` is applied only when the cell
fell back to WALL. Non-wall cells get `reactive=true` so the runtime
fallback (notebook-init.js) can retroactively WALL them if the
surrounding `@island` never hydrates."
function emit_reactive_cell_call(cc::CellClass, re::ReactiveEmit)::String
    suffix       = _id_suffix(cc.cell.id)
    folded_lit   = cc.cell.folded ? "true" : "false"
    show_out_lit = _suppresses_output(cc.cell.code) ? "false" : "true"
    cell_type_lit = _is_markdown_cell_code(cc.cell.code) ? ":markdown" : ":code"
    state_lit = re.kind === :wall ? ":wasm_failed" : _cell_state_literal(cc)
    reactive_lit = re.kind === :wall ? "false" : "true"
    join([
        "            CellDiv(",
        "                cell_id     = $(repr(string(cc.cell.id))),",
        "                source_code = $(_code_literal(cc.cell.code)),",
        "                runtime_ns  = $(_cell_runtime_literal(cc)),",
        "                state       = $(state_lit),",
        "                cell_type   = $(cell_type_lit),",
        "                folded      = $(folded_lit),",
        "                show_output = $(show_out_lit),",
        "                reactive    = $(reactive_lit),",
        "                output      = $(re.output_expr),",
        "            )",
    ], "\n")
end

# ─── File assembly ─────────────────────────────────────────────────────

function emit_asset_bundle_const()::String
    html = published_notebook_assets_html()
    "    const _NOTEBOOK_ASSETS_HTML = $(repr(html))\n"
end

function _collect_bond_specs(plan::ExtractionPlan)
    specs             = Dict{Symbol, BondSpec}()
    fallback_defaults = Dict{Symbol, String}()
    for cc in plan.cells
        cc.kind === :bond || continue
        cc.bond_name === nothing && continue
        spec = _parse_bond_widget(cc.cell.code)
        if spec === nothing
            fallback_defaults[cc.bond_name] = "missing"
        else
            specs[cc.bond_name] = spec
        end
    end
    return (specs, fallback_defaults)
end

function assemble(plan::ExtractionPlan)::String
    io = IOBuffer()
    _write_header(io, plan)
    println(io, "module $(plan.component_name)Mod")
    println(io)
    _write_imports(io, plan)
    println(io, "    # ── Self-contained CSS + CodeMirror + init JS bundle ──")
    println(io, "    # Baked in at extraction time so this file renders in ANY")
    println(io, "    # Therapy app without reaching into Sessions's static/")
    println(io, "    # assets at runtime. Re-extraction refreshes the bundle.")
    print(io, emit_asset_bundle_const())
    println(io)

    specs, fallback_defaults = _collect_bond_specs(plan)
    print(io, emit_bond_defaults(specs, fallback_defaults))
    println(io)

    # Cell-value consts (module-load eval).
    println(io, "    # ── Cell values (source preserved, evaluated at module load)")
    println(io, "    # Bond reads inside cell bodies resolve against the plain")
    println(io, "    # `const <bond>` aliases declared above. The @island body")
    println(io, "    # below overrides those names locally with create_signal.")
    for cc in plan.cells
        s = emit_cell_const(cc)
        isempty(s) && continue
        print(io, s)
    end
    println(io)

    # Pre-translate every reactive cell so we know its declarations
    # (memos / effects) before emitting the @island body.
    bond_names = Set(keys(specs)) ∪ Set(keys(fallback_defaults))
    reactive_by_id = Dict{Any, ReactiveEmit}()
    for cc in plan.cells
        cc.kind === :reactive || continue
        reactive_by_id[cc.cell.id] = translate_reactive(cc, bond_names)
    end

    # The one @island per notebook.
    println(io, "    @island function $(plan.component_name)()")

    # Signal decls (bond_names iteration preserves insertion order via
    # explicit loop over keys).
    if isempty(specs) && isempty(fallback_defaults)
        println(io, "        # (no bonds in this notebook)")
    else
        println(io, "        # ── Bond signals ──")
        for bond in keys(specs)
            println(io, "        $(bond), set_$(bond) = create_signal(_default_$(bond))")
        end
        for bond in keys(fallback_defaults)
            haskey(specs, bond) && continue
            println(io, "        $(bond), set_$(bond) = create_signal(_default_$(bond))")
        end
        println(io)
    end

    # Reactive decls.
    any_reactive = any(cc -> cc.kind === :reactive, plan.cells)
    if any_reactive
        println(io, "        # ── Reactive memos + effects ──")
        for cc in plan.cells
            cc.kind === :reactive || continue
            re = reactive_by_id[cc.cell.id]
            isempty(re.decl_source) && continue
            print(io, re.decl_source)
        end
        println(io)
    end

    println(io, "        render_published_notebook(")
    cell_calls = String[]
    for cc in plan.cells
        if cc.kind === :static && _is_bootstrap_cell(cc.cell.code)
            continue
        end
        line = if cc.kind === :static
            emit_static_cell_call(cc)
        elseif cc.kind === :bond
            emit_bond_cell_call(cc, get(specs, cc.bond_name, nothing))
        else  # :reactive
            emit_reactive_cell_call(cc, reactive_by_id[cc.cell.id])
        end
        push!(cell_calls, line)
    end
    print(io, join(cell_calls, ",\n"))
    println(io, ";")
    println(io, "            assets_html = _NOTEBOOK_ASSETS_HTML,")
    println(io, "        )")
    println(io, "    end")

    println(io, "end  # module $(plan.component_name)Mod")
    println(io)
    println(io, "# Surface the @island at top scope so the docs registry")
    println(io, "# (or any caller) can grab it directly.")
    println(io, "const $(plan.component_name) = $(plan.component_name)Mod.$(plan.component_name)")
    return String(take!(io))
end

function _write_header(io::IO, plan::ExtractionPlan)
    println(io, "# ── Sessions.jl extracted notebook ─────────────────────────")
    println(io, "#")
    println(io, "# Source : $(plan.notebook_path)")
    println(io, "# Date   : $(now())")
    println(io, "#")
    println(io, "# Self-contained Therapy component. Cell SOURCE is preserved")
    println(io, "# verbatim; cell VALUES are computed once at module load and")
    println(io, "# rendered through `Sessions.render_value` — the same MIME")
    println(io, "# classifier the live IDE output pipeline uses.")
    println(io, "#")
    println(io, "# Architecture (matches Therapy.jl's NotebookDemo reference):")
    println(io, "#   - ONE @island function per notebook. Outer body runs as")
    println(io, "#     regular Julia at SSR (DataFrames / Markdown / arbitrary")
    println(io, "#     show() methods all fine). Only reactive closures inside")
    println(io, "#     the body get WASM-compiled.")
    println(io, "#   - Each @bind becomes a create_signal bound into a native")
    println(io, "#     Therapy `Input(:value=>, :on_input=>)` — no <bond>")
    println(io, "#     bridge JS, no WebSocket.")
    println(io, "#   - Each bond-dependent cell becomes a create_memo (simple")
    println(io, "#     return value, rendered via Span) or create_effect (canvas-")
    println(io, "#     drawing cell, rendered via Canvas). Bare bond refs in the")
    println(io, "#     cell body are rewritten to signal reads (n → n()).")
    println(io, "#   - Cells whose body uses WasmTarget-hostile patterns")
    println(io, "#     (DataFrame, md\"…\", @show, display) fall back to WALL:")
    println(io, "#     frozen at the bond default with a `state=:wasm_failed`")
    println(io, "#     badge making the non-reactivity visible to the reader.")
    println(io, "#   - Static cells are pure SSR: frozen output via render_value.")
    println(io, "#")
    println(io, "# Re-running `Sessions.extract_notebook` with the same out_path")
    println(io, "# overwrites the file.")
    println(io, "# ───────────────────────────────────────────────────────────")
    println(io)
end

function _write_imports(io::IO, plan::ExtractionPlan)
    for line in plan.runtime_imports
        println(io, "    " * line)
    end
    for line in plan.imports
        println(io, "    " * line)
    end
    println(io)
end
