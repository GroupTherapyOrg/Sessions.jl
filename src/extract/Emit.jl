# Emit.jl — assemble an ExtractionPlan into a single .jl Therapy
# component. Shape (ONE @island per reactive cell — so each cell's
# WasmTarget compile is INDEPENDENT and one failure doesn't kill
# reactivity for its siblings):
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
#     # MODULE-LEVEL bond signals — shared across every island below.
#     # Therapy's analyzer scans each island's closures; when a closure
#     # captures a SignalGetter whose field name matches a module-level
#     # binding the analyzer infers `shared_name = "<name>"` and the
#     # compiled island imports the signal from the shared registry
#     # instead of owning a local copy. Result: move slider → bond
#     # island broadcasts → every dependent island re-runs locally.
#     const _n_signal = create_signal(8)
#     const n         = 8                # plain alias for cell bodies
#                                        # evaluated at module load
#     # …one pair per @bind in the notebook…
#
#     # Each cell's body runs once at module load with bonds at default.
#     # Provides SSR frozen output + fallback when an island fails to
#     # hydrate.
#     const _cell_<id> = try let <verbatim user code> end catch _e; _e end
#
#     # ── Per-bond @island ──
#     @island function _Bond_<name>()
#         n, set_n = _n_signal          # destructure shared signal
#         create_effect(() -> n())      # dummy read → forces analyzer
#                                       # to detect shared signal (the
#                                       # external-scan walks closures
#                                       # only; Input bindings alone
#                                       # don't trigger shared_name
#                                       # inference — Analysis.jl:270).
#         return CellDiv(
#             cell_id = "…",
#             source_code = "@bind n BoundSlider(...)",
#             output = Div(Input(:value=>n, :on_input=>set_n, …),
#                          Span(:class=>"su-slider-out", n)))
#     end
#
#     # ── Per-reactive-cell @island (memo — numeric output) ──
#     @island function _Reactive_<id>()
#         n, _ = _n_signal              # destructure; closure-captured
#         _reactive = create_memo(() -> <rewritten body>)
#         return CellDiv(cell_id=…, source_code=…, reactive=true,
#                        output=Span(_reactive))
#     end
#
#     # ── Per-reactive-cell @island (effect + Canvas — plot) ──
#     @island function _Reactive_<id>()
#         n, _ = _n_signal
#         create_effect(() -> begin
#             <rewritten body>          # the trailing Figure ref is
#             render!(…)                # replaced with render!(…) by
#         end)                          # `_flatten_for_render`.
#         return CellDiv(cell_id=…, source_code=…, reactive=true,
#                        output=Canvas(:width=>…, :height=>…))
#     end
#
#     # Outer notebook — plain function, not an @island. Just wires
#     # static cells + island calls in document order. If any island
#     # above fails to compile, that island's reactive cell freezes
#     # at its SSR-rendered default; siblings keep hydrating.
#     function <Name>()
#         render_published_notebook(
#             CellDiv(cell_id=…, output=RawHtml(render_value(_cell_<id>))),  # static
#             _Bond_n(),                                                      # bond island
#             _Reactive_<id>(),                                               # reactive island
#             …,
#             assets_html = _NOTEBOOK_ASSETS_HTML,
#         )
#     end
#   end
#   const <Name> = <Name>Mod.<Name>
#
# Zero extract-time heuristics about "what WasmTarget can compile":
# every reactive cell is emitted as a compile-attempting island. When
# WasmTarget rejects one (DataFrames today, random package X tomorrow),
# Therapy skips WASM for just that island. Sessions's notebook-init.js
# then retroactively WALL-bands it at runtime by detecting the missing
# `data-hydrated="true"` marker. Siblings are untouched.

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
Returns `nothing` if the widget isn't a shape v1 can emit natively;
callers fall back to rendering the frozen widget HTML.
Handles `BoundSlider(X:Y)` and `BoundSlider(X:S:Y; default=…)`.
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

# ─── AST helpers ───────────────────────────────────────────────────────

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

"Strip every `LineNumberNode` out of an `Expr` tree."
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

"Unwrap a top-level `begin … end` wrapper so the serialized source
doesn't get an extra layer of `begin/end`."
function _strip_wrapping_block(expr)::String
    if expr isa Expr && expr.head === :block
        args = filter(a -> !(a isa LineNumberNode), expr.args)
        if length(args) == 1
            return string(args[1])
        else
            return join(map(string, args), "\n")
        end
    end
    return string(expr)
end

"""
Walk `expr` and replace every bare `Symbol` matching a bond name with
`:(name())` (a signal read). Skips LHS of assignment, `for`/`let`
binders, and macro-name slots.
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
        iter = expr.args[1]; body = expr.args[2]
        return Expr(:for, _rewrite_iter(iter, bonds),
                    _rewrite_bond_reads(body, bonds))
    elseif h === :let
        return Expr(:let, expr.args[1], _rewrite_bond_reads(expr.args[2], bonds))
    elseif h === :macrocall
        new_args = Any[expr.args[1], expr.args[2]]
        for a in expr.args[3:end]
            push!(new_args, _rewrite_bond_reads(a, bonds))
        end
        return Expr(:macrocall, new_args...)
    elseif h === :. && length(expr.args) == 2 && expr.args[2] isa QuoteNode
        return Expr(:., _rewrite_bond_reads(expr.args[1], bonds), expr.args[2])
    else
        return Expr(h, [_rewrite_bond_reads(a, bonds) for a in expr.args]...)
    end
end

"for-loop iteration spec → rewrite only the range RHS, not the loop var."
function _rewrite_iter(iter, bonds::Set{Symbol})
    if iter isa Expr && iter.head === :block
        return Expr(:block, [_rewrite_iter(a, bonds) for a in iter.args]...)
    elseif iter isa Expr && iter.head === :(=)
        return Expr(:(=), iter.args[1], _rewrite_bond_reads(iter.args[2], bonds))
    else
        return iter
    end
end

"True if `code` looks like a WasmPlot figure cell (Figure(…) /
barplot! / lines! / heatmap!). Drives memo-vs-effect emit shape."
function _is_wasmplot_body(code::AbstractString)::Bool
    occursin(r"\b(WP\.|WasmPlot\.)?Figure\s*\(", code)            && return true
    occursin(r"\b(barplot|lines|scatter|heatmap|hist)\s*!", code) && return true
    return false
end

"""
Flatten a WasmPlot cell body into a `begin`-block suitable for
dropping inside `create_effect(() -> begin … end)`.

Unwraps a single outer `let`; if the trailing expression is a bare
variable reference (usual Pluto shape `let fig = …; fig end`),
replaces the tail with `render!(<var>)`. Complex trailing
expressions get bound to `_wasmplot_fig` and that local is rendered.
"""
function _flatten_for_render(expr)::String
    inner = expr
    if inner isa Expr && inner.head === :block
        stmts = filter(a -> !(a isa LineNumberNode), inner.args)
        if length(stmts) == 1 && stmts[1] isa Expr && stmts[1].head === :let
            body = stmts[1].args[2]
            if body isa Expr && body.head === :block
                return _append_render_bang(body)
            end
        end
        return _append_render_bang(inner)
    end
    return string(expr)
end

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
    return _strip_wrapping_block(body_expr)
end

# ─── Reactive cell AST → island body ───────────────────────────────────

struct ReactiveBody
    kind::Symbol              # :memo | :effect
    decl_source::String       # Julia to splice into the @island body
    output_expr::String       # goes into CellDiv(output = …)
    canvas_w::Int             # only used when kind === :effect
    canvas_h::Int
end

"""
Translate a bond-dependent cell body into the create_memo /
create_effect code that belongs inside its own @island. Rewrites bare
bond refs (`n` → `n()`) via AST walk and picks the `:memo` vs
`:effect` shape based on whether the body is a WasmPlot figure cell.

Throws `ParseError` when the cell body isn't valid Julia; caller
turns that into a WALL emit.
"""
function translate_reactive_body(code::AbstractString, bonds::Set{Symbol},
                                 memo_local::AbstractString)::ReactiveBody
    body_expr = Base.Meta.parse("begin\n$(strip(code))\nend")
    rewritten = _rewrite_bond_reads(body_expr, bonds)
    rewritten = _strip_linenumbers(rewritten)

    if _is_wasmplot_body(code)
        w, h = _wasmplot_canvas_size(body_expr)
        body_str = _flatten_for_render(rewritten)
        decl = join([
            "        create_effect(() -> begin",
            _indent(body_str, 12),
            "        end)",
        ], "\n") * "\n"
        return ReactiveBody(:effect, decl, "Canvas(:width => $(w), :height => $(h))", w, h)
    end

    body_str = _strip_wrapping_block(rewritten)
    decl = join([
        "        $(memo_local) = create_memo(() -> begin",
        _indent(body_str, 12),
        "        end)",
    ], "\n") * "\n"
    return ReactiveBody(:memo, decl, "Span($(memo_local))", 0, 0)
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

"""
Emit module-level shared-signal constants + plain default aliases.

For every @bind cell we emit a pair:

    const _<name>_signal = create_signal(<default>)
    const <name>         = <default>

The signal is imported by each @island that needs it (bond + every
reactive dependent) via `<name>, <set> = _<name>_signal`. Therapy's
analyzer scans each island's closures for captured SignalGetter
fields; a module-level signal not registered via the island's own
local `create_signal(...)` calls is detected as "external" (see
`Analysis.jl:270-297`) and tagged `shared_name = "<name>"`. Compiled
islands then import the signal from the cross-island pub/sub registry
instead of owning a local copy — that's what makes the slider drive
every dependent reactive cell in a different @island.

The plain `const <name> = <default>` alias is for the module-load
cell-body evaluations (the `_cell_<id>` constants): they run in
module scope where the bond name should resolve to the default.
"""
function emit_module_signals(specs::Dict{Symbol, BondSpec},
                             fallback_defaults::Dict{Symbol, String})::String
    isempty(specs) && isempty(fallback_defaults) && return "    # (no bonds)\n"
    lines = String["    # ── Module-level shared signals (one per @bind) ──"]
    for (bond, spec) in pairs(specs)
        push!(lines, "    const _$(bond)_signal = create_signal($(spec.default_expr))")
        push!(lines, "    const $(bond)          = $(spec.default_expr)")
    end
    for (bond, def) in pairs(fallback_defaults)
        haskey(specs, bond) && continue
        push!(lines, "    const _$(bond)_signal = create_signal($(def))")
        push!(lines, "    const $(bond)          = $(def)")
    end
    return join(lines, "\n") * "\n"
end

# ─── Per-cell island emitters ──────────────────────────────────────────

"Island name for the bond cell binding `<name>`."
_bond_island_name(bond::Symbol) = "_Bond_$(bond)"

"Island name for a reactive cell (memo or effect)."
_reactive_island_name(cc::CellClass) = "_Reactive_$(_id_suffix(cc.cell.id))"

"""
Emit a `@island function _Bond_<name>()` that owns the shared signal
widget for `@bind <name> <widget>`. The dummy `create_effect(() ->
<name>())` reads the signal so Therapy's analyzer detects the captured
getter and emits a shared-import, not a local global (Analysis.jl:270
only scans closure captures — Input bindings alone don't infer
shared_name).
"""
function emit_bond_island(cc::CellClass, spec::Union{BondSpec, Nothing})::String
    bond    = cc.bond_name::Symbol
    fname   = _bond_island_name(bond)
    folded  = cc.cell.folded ? "true" : "false"

    output_expr = if spec === nothing
        suffix = _id_suffix(cc.cell.id)
        "RawHtml(render_value(_cell_$(suffix)))"
    else
        "Div(:class => \"flex items-center gap-3\",\n" *
        "            Input(:type     => \"range\",\n" *
        "                  :min      => $(repr(spec.min_expr)),\n" *
        "                  :max      => $(repr(spec.max_expr)),\n" *
        "                  :step     => $(repr(spec.step_expr)),\n" *
        "                  :value    => $(bond),\n" *
        "                  :on_input => set_$(bond),\n" *
        "                  :class    => $(repr(spec.widget_class))),\n" *
        "            Span(:class => \"su-slider-out\", $(bond)))"
    end

    join([
        "    @island function $(fname)()",
        "        $(bond), set_$(bond) = _$(bond)_signal",
        "        create_effect(() -> $(bond)())  # forces shared_name detection",
        "        CellDiv(",
        "            cell_id     = $(repr(string(cc.cell.id))),",
        "            source_code = $(_code_literal(cc.cell.code)),",
        "            runtime_ns  = $(_cell_runtime_literal(cc)),",
        "            state       = $(_cell_state_literal(cc)),",
        "            folded      = $(folded),",
        "            show_output = true,",
        "            output      = $(output_expr),",
        "        )",
        "    end",
    ], "\n") * "\n"
end

"""
Emit a `@island function _Reactive_<id>()` per bond-dependent cell.
Each is an independent compile unit: WasmTarget-rejection for one
doesn't affect its siblings. The runtime fallback in notebook-init.js
paints a WALL band on any island that never hydrates.
"""
function emit_reactive_island(cc::CellClass, bonds::Set{Symbol})::String
    fname        = _reactive_island_name(cc)
    suffix       = _id_suffix(cc.cell.id)
    folded       = cc.cell.folded ? "true" : "false"
    show_out     = _suppresses_output(cc.cell.code) ? "false" : "true"
    cell_type    = _is_markdown_cell_code(cc.cell.code) ? ":markdown" : ":code"
    memo_local   = "_reactive_$(suffix)"
    upstream     = sort(collect(cc.upstream_bonds))

    # Try to translate body to reactive (memo / effect). On ParseError
    # or any failure, emit a WALL island — its `CellDiv` gets
    # `state = :wasm_failed` + a frozen SSR output.
    translation = try
        translate_reactive_body(cc.cell.code, bonds, memo_local)
    catch _e
        nothing
    end

    if translation === nothing
        return join([
            "    @island function $(fname)()",
            "        # Unparseable body — fall through to frozen WALL SSR output.",
            "        CellDiv(",
            "            cell_id     = $(repr(string(cc.cell.id))),",
            "            source_code = $(_code_literal(cc.cell.code)),",
            "            runtime_ns  = $(_cell_runtime_literal(cc)),",
            "            state       = :wasm_failed,",
            "            cell_type   = $(cell_type),",
            "            folded      = $(folded),",
            "            show_output = $(show_out),",
            "            reactive    = false,",
            "            output      = RawHtml(render_value(_cell_$(suffix))),",
            "        )",
            "    end",
        ], "\n") * "\n"
    end

    # Signal destructures — one per upstream bond.
    sig_lines = String[]
    for b in upstream
        push!(sig_lines, "        $(b), _ = _$(b)_signal")
    end

    return join([
        "    @island function $(fname)()",
        join(sig_lines, "\n"),
        rstrip(translation.decl_source),
        "        CellDiv(",
        "            cell_id     = $(repr(string(cc.cell.id))),",
        "            source_code = $(_code_literal(cc.cell.code)),",
        "            runtime_ns  = $(_cell_runtime_literal(cc)),",
        "            state       = $(_cell_state_literal(cc)),",
        "            cell_type   = $(cell_type),",
        "            folded      = $(folded),",
        "            show_output = $(show_out),",
        "            reactive    = true,",
        "            output      = $(translation.output_expr),",
        "        )",
        "    end",
    ], "\n") * "\n"
end

# ─── Static cell CellDiv inside the outer function ─────────────────────

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
    print(io, emit_module_signals(specs, fallback_defaults))
    println(io)

    # Cell-value consts (module-load eval with bonds at their defaults).
    println(io, "    # ── Cell values (source preserved, evaluated at module load)")
    for cc in plan.cells
        s = emit_cell_const(cc)
        isempty(s) && continue
        print(io, s)
    end
    println(io)

    bond_names = Set(keys(specs)) ∪ Set(keys(fallback_defaults))

    # Per-bond @island (shared signal widget).
    for cc in plan.cells
        cc.kind === :bond || continue
        print(io, emit_bond_island(cc, get(specs, cc.bond_name, nothing)))
        println(io)
    end

    # Per-reactive-cell @island.
    for cc in plan.cells
        cc.kind === :reactive || continue
        print(io, emit_reactive_island(cc, bond_names))
        println(io)
    end

    # Outer function — plain, no @island. Assembles static cells +
    # island calls in document order.
    println(io, "    function $(plan.component_name)()")
    println(io, "        render_published_notebook(")
    cell_calls = String[]
    for cc in plan.cells
        cc.kind === :static && _is_bootstrap_cell(cc.cell.code) && continue
        line = if cc.kind === :static
            emit_static_cell_call(cc)
        elseif cc.kind === :bond
            "            $(_bond_island_name(cc.bond_name))()"
        else
            "            $(_reactive_island_name(cc))()"
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
    println(io, "# Surface the outer function at top scope so the docs registry")
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
    println(io, "# Self-contained Therapy component. Each @bind cell + each")
    println(io, "# bond-dependent cell becomes its OWN `@island` — each with")
    println(io, "# an independent WasmTarget compile. If WasmTarget rejects")
    println(io, "# one island (a DataFrame memo, a package with no WASM")
    println(io, "# coverage, …), siblings still hydrate. A runtime fallback")
    println(io, "# in notebook-init.js paints a red 'WASM compile failed'")
    println(io, "# band over any island that never reaches data-hydrated.")
    println(io, "#")
    println(io, "# Bond signals live at module scope: `const _<name>_signal =")
    println(io, "# create_signal(default)`. Each island destructures it and")
    println(io, "# captures it in a closure; Therapy's analyzer detects the")
    println(io, "# shared `@(name)` binding and emits cross-island imports.")
    println(io, "# Move the slider → bond island broadcasts via")
    println(io, "# `window.__therapy.set('<name>', v)` → every subscribed")
    println(io, "# island re-runs its memo/effect locally. No server.")
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
