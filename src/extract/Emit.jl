# Emit.jl — assemble an ExtractionPlan into a single .jl Therapy
# component. Shape (one @island per notebook, the reference pattern
# Therapy.jl uses in its own NotebookDemo):
#
#   module <Name>Mod
#     using Therapy: @island, create_signal, RawHtml, Div, Input, Span
#     using Sessions: CellDiv, render_value, render_published_notebook
#     using <user notebook deps — Markdown, DataFrames, WasmPlot, …>
#
#     # Baked asset bundle so the .jl drops into any Therapy app.
#     const _NOTEBOOK_ASSETS_HTML = "…"
#
#     # Bond defaults — plain constants so cell bodies can reference
#     # `n` at module-load time. The @island overrides them with
#     # create_signal inside its own scope.
#     const _default_n = 8
#     const n          = _default_n
#
#     # Each cell's source is preserved verbatim and wrapped in a
#     # module-level try/let so (a) the user code reads as it did in
#     # the notebook and (b) an errored cell doesn't fail the whole
#     # module load.
#     const _cell_<id> = try let
#         <verbatim user code>
#     end catch _e
#         _e
#     end
#
#     # ONE @island per notebook. Outer body runs as regular Julia at
#     # SSR (so DataFrames / Markdown / arbitrary show methods all run
#     # fine — confirmed at Therapy's Analysis.jl:215). Only reactive
#     # closures (create_memo / create_effect / event handlers) get
#     # WASM-compiled, and v1 doesn't emit any of those inside cell
#     # bodies yet — bond SIGNALS drive the widget UI itself, every
#     # reactive-dep cell falls through as a WALL cell frozen at the
#     # bond default.
#     @island function <Name>()
#         n, set_n = create_signal(_default_n)
#
#         return render_published_notebook(
#             CellDiv(cell_id=…, source_code=…, cell_type=:markdown,
#                     folded=true, runtime_ns=…, state=:done,
#                     output = RawHtml(render_value(_cell_<id>))),
#             CellDiv(cell_id=…, source_code=…, runtime_ns=…,
#                     output = Div(Input(:type=>"range", :min=>…,
#                                        :max=>…, :value=>n,
#                                        :on_input=>set_n, …),
#                                  Span(:class=>"su-slider-out", n))),
#             CellDiv(cell_id=…, source_code=…, state=:wasm_failed,
#                     output = RawHtml(render_value(_cell_<id>))),
#             assets_html = _NOTEBOOK_ASSETS_HTML,
#         )
#     end
#   end
#   const <Name> = <Name>Mod.<Name>
#
# Why not a memo-per-reactive-cell in v1: Pluto cell bodies are
# arbitrary Julia (md"…", DataFrame, arbitrary show()); WasmTarget
# only compiles a narrow subset. Translating every reactive cell to
# a WASM-safe create_memo requires a static analysis we don't have
# yet. v1 ships the correct ARCHITECTURE (one island, native Input
# bonds, CellDiv chrome) and degrades reactive cells to WALL; v1.1
# adds a heuristic translator for simple numeric memos.

using Dates: now

# ─── Helpers ──────────────────────────────────────────────────────────

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

"True if the cell's code is a Markdown string macro (`md\"…\"` or
`md\"\"\"…\"\"\"`). Used to drive `cell_type=:markdown` so the purple
stripe lights up (`.md-cell::before`)."
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

"""
    BondSpec

Everything the emitter needs to render a `@bind name widget_expr`
cell natively (Therapy Input + signal) rather than via frozen
widget HTML.

  - `default_expr`   Julia-source expression that produces the initial
                     signal value (a literal, usually).
  - `kind`           `:slider` for now — extendable later.
  - `min_expr`, `max_expr`, `step_expr`  source-level attribute
                     expressions emitted directly into `Input(:min=>…)`.
  - `widget_class`   CSS class to attach (`"su-slider"`, …) so any
                     widget-specific styles from notebook-chrome.css
                     still apply.
"""
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
callers fall back to frozen widget HTML.

Handles:
  - `BoundSlider(X:Y)`             step defaults to 1
  - `BoundSlider(X:Y; default=Z)`  explicit default
  - `BoundSlider(X:S:Y; …)`        explicit float / non-unit step

Anything else → `nothing`.
"""
function _parse_bond_widget(code::AbstractString)::Union{BondSpec, Nothing}
    expr = try
        Base.Meta.parse("begin\n$(strip(code))\nend")
    catch
        return nothing
    end
    widget_call = _find_bind_widget(expr)
    widget_call === nothing && return nothing

    # widget_call looks like `BoundSlider(2:30; default=8)` — strip any
    # leading module prefix (SessionsUI.BoundSlider, etc.) to get the
    # bare constructor name.
    fname = widget_call.args[1]
    name_sym = fname isa Expr && fname.head === :. ? fname.args[end].value : fname
    name_sym isa QuoteNode && (name_sym = name_sym.value)
    name_sym isa Symbol || return nothing

    if name_sym === :BoundSlider
        return _parse_slider_args(widget_call)
    end
    return nothing
end

"Walk `expr` (which may be a `begin…end` wrapping the cell) and return
the widget `:call` node from a `@bind name widget` — or `nothing`."
function _find_bind_widget(expr)
    if expr isa Expr
        if expr.head === :macrocall && length(expr.args) >= 3 &&
           (expr.args[1] === Symbol("@bind") ||
            expr.args[1] isa GlobalRef && expr.args[1].name === Symbol("@bind"))
            w = expr.args[4]  # :line is args[2], name is args[3], widget is args[4]
            w isa Expr && w.head === :call && return w
        end
        for a in expr.args
            r = _find_bind_widget(a)
            r === nothing || return r
        end
    end
    return nothing
end

"`BoundSlider(X:Y)` / `BoundSlider(X:Y; default=Z)` → BondSpec. Returns
`nothing` on unexpected shapes."
function _parse_slider_args(call::Expr)::Union{BondSpec, Nothing}
    # call.args[1] = fname, [2:end] = positional + parameters
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

    # We need min / max / step as source-level expressions. The cleanest
    # way is to recognise `a:b` and `a:s:b` directly; anything else (a
    # pre-built vector, an expression returning a range) is too hard
    # to statically analyse and we fall back to non-native rendering.
    if range_expr isa Expr && range_expr.head === :call && range_expr.args[1] === :(:)
        args = range_expr.args
        if length(args) == 3           # a:b
            min_e  = string(args[2])
            max_e  = string(args[3])
            step_e = "1"
        elseif length(args) == 4       # a:s:b
            min_e  = string(args[2])
            step_e = string(args[3])
            max_e  = string(args[4])
        else
            return nothing
        end
        default_expr = default_expr === nothing ? min_e : default_expr
        return BondSpec(default_expr, :slider, min_e, max_e, step_e, "su-slider")
    end
    return nothing
end

# ─── Module-level constants ────────────────────────────────────────────

"""
`const _cell_<id> = try let <user code> end catch _e; _e end` — every
cell's body runs once at module load. Bond-default consts (`const n =
8`) are declared before cells, so reactive cells that read `n` resolve
to the default at this stage. The @island then overrides `n` locally
with its signal.

Returns an empty string for bootstrap cells (Pkg / using blocks that
belong at module top).
"""
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
`const _default_<bond> = <default>` + plain alias `const <bond> =
_default_<bond>` for every bond in the notebook. The plain alias is
what lets a reactive cell body (executed at module load) read `n` or
`l` and resolve to the default — the @island overrides these names
with signals inside its own scope.

Emits bond-spec constants too (range min/max/step) so the @island
body can reference them when constructing the Input.
"""
function emit_bond_defaults(specs::Dict{Symbol, BondSpec},
                            fallback_defaults::Dict{Symbol, String})::String
    isempty(specs) && isempty(fallback_defaults) && return "    # (no bonds)\n"
    lines = String["    # ── Bond defaults (one per @bind) ──"]
    # Specs we could parse fully.
    for (bond, spec) in pairs(specs)
        push!(lines, "    const _default_$(bond) = $(spec.default_expr)")
        push!(lines, "    const $(bond)          = _default_$(bond)")
    end
    # Bonds we couldn't parse — need SOME default so the reactive cell
    # bodies don't throw UndefVar at module load. `missing` matches
    # SessionsUI's `initial_value` fallback.
    for (bond, def) in pairs(fallback_defaults)
        haskey(specs, bond) && continue
        push!(lines, "    const _default_$(bond) = $(def)")
        push!(lines, "    const $(bond)          = _default_$(bond)")
    end
    return join(lines, "\n") * "\n"
end

# ─── Per-cell emission inside @island return tree ──────────────────────

"""
Static cell — pre-computed module-level value rendered via
`render_value` (same MIME classifier the live IDE uses, so DataFrames
/ Markdown / WasmPlot all render identically to the IDE).
"""
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

"""
Bond cell — native Therapy `Input` widget bound to the create_signal
declared at the top of the @island. Widget renders via a Div
containing the slider + a live-value Span — matches SessionsUI's
BoundSlider HTML (su-slider + su-slider-out classes) so existing CSS
applies. For widgets we can't natively emit, falls back to a frozen
RawHtml of the rendered widget (no reactivity — caller handles).
"""
function emit_bond_cell_call(cc::CellClass, spec::Union{BondSpec, Nothing})::String
    bond         = cc.bond_name
    folded_lit   = cc.cell.folded ? "true" : "false"
    show_out_lit = "true"  # always show the widget — it's the control
    suffix       = _id_suffix(cc.cell.id)

    output_expr = if spec === nothing
        # Unparseable widget — render the frozen SessionsUI HTML.
        "RawHtml(render_value(_cell_$(suffix)))"
    else
        # Native Therapy Input. Step/min/max/default all source-level
        # expressions so `2:30` → "2" / "30" / "1" untouched.
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
        "                show_output = $(show_out_lit),",
        "                output      = $(output_expr),",
        "            )",
    ], "\n")
end

"""
Reactive cell (bond-dependent) — WALL for v1. The cell body was
evaluated once at module load with every bond at its default, so
the output reflects the initial bond state. State `:wasm_failed`
triggers the red band above the output making it obvious to the
reader that this cell is frozen rather than live.
"""
function emit_reactive_cell_call(cc::CellClass)::String
    suffix       = _id_suffix(cc.cell.id)
    folded_lit   = cc.cell.folded ? "true" : "false"
    show_out_lit = _suppresses_output(cc.cell.code) ? "false" : "true"
    cell_type_lit = _is_markdown_cell_code(cc.cell.code) ? ":markdown" : ":code"
    join([
        "            CellDiv(",
        "                cell_id     = $(repr(string(cc.cell.id))),",
        "                source_code = $(_code_literal(cc.cell.code)),",
        "                runtime_ns  = $(_cell_runtime_literal(cc)),",
        "                state       = :wasm_failed,",
        "                cell_type   = $(cell_type_lit),",
        "                folded      = $(folded_lit),",
        "                show_output = $(show_out_lit),",
        "                output      = RawHtml(render_value(_cell_$(suffix))),",
        "            )",
    ], "\n")
end

# ─── File assembly ─────────────────────────────────────────────────────

"""
Bake the full notebook asset bundle (CSS + CodeMirror + init JS)
into the generated module as a single `const _NOTEBOOK_ASSETS_HTML`
literal. `repr` handles all escape concerns.
"""
function emit_asset_bundle_const()::String
    html = published_notebook_assets_html()
    "    const _NOTEBOOK_ASSETS_HTML = $(repr(html))\n"
end

"""
Build the `(specs, fallback_defaults)` maps needed by
`emit_bond_defaults`. Bond cells whose widget is parseable produce
a BondSpec; others fall back to `missing` (the SessionsUI default
convention) so reactive cell bodies that read the bond at module
load still have a value.
"""
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

    # Cell value consts (module-load eval).
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

    # The one @island per notebook.
    println(io, "    @island function $(plan.component_name)()")
    # Signal declarations.
    if isempty(specs) && isempty(fallback_defaults)
        println(io, "        # (no bonds in this notebook)")
    else
        println(io, "        # ── Bond signals (create_signal captures the default) ──")
        for bond in keys(specs)
            println(io, "        $(bond), set_$(bond) = create_signal(_default_$(bond))")
        end
        for bond in keys(fallback_defaults)
            haskey(specs, bond) && continue
            println(io, "        $(bond), set_$(bond) = create_signal(_default_$(bond))")
        end
    end
    println(io)

    println(io, "        render_published_notebook(")
    cell_calls = String[]
    for cc in plan.cells
        # Skip bootstrap-only cells (their imports are at module top via
        # collect_imports; nothing to render).
        if cc.kind === :static && _is_bootstrap_cell(cc.cell.code)
            continue
        end
        line = if cc.kind === :static
            emit_static_cell_call(cc)
        elseif cc.kind === :bond
            emit_bond_cell_call(cc, get(specs, cc.bond_name, nothing))
        else  # :reactive
            emit_reactive_cell_call(cc)
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
    println(io, "# This file is a self-contained Therapy component. Cell SOURCE")
    println(io, "# is preserved verbatim and rendered through a read-only")
    println(io, "# CodeMirror editor. Each cell value is computed once at module")
    println(io, "# load and rendered through `Sessions.render_value` — the same")
    println(io, "# MIME classifier the live IDE output pipeline uses.")
    println(io, "#")
    println(io, "# Architecture (matches Therapy.jl's NotebookDemo reference):")
    println(io, "#   - ONE @island function per notebook. Outer body runs as")
    println(io, "#     regular Julia at SSR (DataFrames / Markdown / arbitrary")
    println(io, "#     show() methods all fine). Only reactive closures inside")
    println(io, "#     the body get WASM-compiled.")
    println(io, "#   - Each @bind becomes a create_signal whose getter is")
    println(io, "#     bound into a native Therapy `Input(:value=>, :on_input=>)` —")
    println(io, "#     no `<bond>` bridge JS, no WebSocket.")
    println(io, "#   - Reactive cells (bond-dependent) render v1-frozen at the")
    println(io, "#     bond default with a `state=:wasm_failed` badge — WasmTarget")
    println(io, "#     can't compile md\"…\" / DataFrame / arbitrary show() in")
    println(io, "#     memo bodies yet. v1.1 adds a heuristic translator for")
    println(io, "#     simple numeric cells.")
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
