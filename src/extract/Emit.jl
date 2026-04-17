# Emit.jl — assemble an ExtractionPlan into a single .jl Therapy
# component. Shape:
#
#   module <Name>Mod
#     using Therapy: @island, create_signal, RawHtml
#     using Sessions: render_value, render_published_cell,
#                     render_published_notebook
#     using <user notebook deps>
#
#     # One shared signal per @bind (module scope so islands can
#     # cross-subscribe). The plain-name alias lets static cells that
#     # read `n` / `l` at module load resolve against the default.
#     const <bond>_signal = create_signal(default)
#     const <bond>       = default
#
#     # Cell values — source preserved verbatim, evaluated at module
#     # load by Julia (NOT compiled to WASM). Markdown, WasmPlot,
#     # DataFrames run host-side at SSG build; the result objects are
#     # what we render.
#     const _cell_<id> = try begin <user code> end catch e; e end
#
#     # Per-bond tiny @island — destructures the shared signal and
#     # returns the widget's frozen HTML. WASM-compiles trivially.
#     # cell-out wrapping happens in render_published_cell, NOT here.
#     @island function _Bond_<bond>_<id>()
#         <bond>, set_<bond> = <bond>_signal
#         RawHtml(render_value(_cell_<id>))
#     end
#
#     # Per-reactive-cell tiny @island — captures upstream bond signals
#     # so cross-island sync wires correctly. v1 renders the frozen
#     # _cell_<id> value (computed at module load with the bond
#     # default). v2 re-executes in WASM as WasmTarget coverage grows.
#     @island function _Cell_<id>()
#         <bond>, _ = <bond>_signal   # one line per upstream bond
#         RawHtml(render_value(_cell_<id>))
#     end
#
#     # Outer notebook = plain function. No WASM constraint, so it
#     # always renders regardless of any @island compile failures.
#     # Every cell flows through render_published_cell → same
#     # cell-wrap/cell-body/cell-out chrome the live IDE uses, so any
#     # styling tweak in web_rendering.jl propagates here for free.
#     function <Name>()
#         render_published_notebook(
#             render_published_cell(cell_id=…, source_code=…,
#                                   output_content=RawHtml(render_value(_cell_<id>))),
#             render_published_cell(cell_id=…, source_code=…,
#                                   output_content=_Bond_<bond>_<id>()),
#             …)
#     end
#   end
#   const <Name> = <Name>Mod.<Name>
#
# Risk isolation: a per-cell @island that fails to WASM-compile only
# kills THAT cell. Static cells (and the outer function) are pure
# Julia/Therapy and never enter WasmTarget.

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

"Best-effort default extraction from a `BoundXxx(... ; default=X)` source."
function _bond_default_literal(code::AbstractString)::String
    m = match(r"default\s*=\s*([^,\)\s][^,\)]*)", code)
    m === nothing ? "0" : strip(m.captures[1])
end

"""
Emit a Julia string literal containing `code` verbatim. Uses `repr`
so triple-quoted markdown blocks (`md\"\"\"…\"\"\"`), `\$` interpolations,
and any escape sequences in user code all round-trip safely through
the generated file. The output is one-line with `\\n` escapes — less
pretty to human-read than triple-quoted blocks, but always correct.
"""
_code_literal(code::AbstractString) = repr(String(code))

"""
True if the cell is purely `using/import` lines and/or `Pkg.activate /
Pkg.add` calls — i.e. notebook bootstrap that's already been lifted
to the module top via `collect_imports` (or just doesn't belong in
the rendered output at all).
"""
function _is_bootstrap_cell(code::AbstractString)::Bool
    s = strip(code)
    isempty(s) && return true
    # Heuristic: if a cell touches Pkg.activate or Pkg.add anywhere,
    # it's a notebook-environment-bootstrap block. The rendered docs
    # site already has its own project; we don't want to mutate it
    # at module load.
    occursin(r"\bPkg\.activate\b", s) && return true
    occursin(r"\bPkg\.add\b",      s) && return true
    # Otherwise: allow only blank/comment/`using/import`/Pkg.* lines.
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

# ─── Per-cell emission ────────────────────────────────────────────────

"`const _cell_<id> = try begin <code> end catch e; e end` — module-load eval.
Returns an empty string when the cell is pure bootstrap (skip)."
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
Tiny @island per @bind — destructures the shared signal, returns the
widget's frozen HTML. The enclosing `render_published_cell` owns the
cell-out wrapping; this just emits the inner content.
"""
function emit_bond_island(cc::CellClass)::String
    suffix = _id_suffix(cc.cell.id)
    bond   = cc.bond_name
    fname  = "_Bond_$(bond)_$(suffix)"
    join([
        "    @island function $(fname)()",
        "        $(bond), set_$(bond) = $(bond)_signal",
        "        RawHtml(render_value(_cell_$(suffix)))",
        "    end",
    ], "\n") * "\n"
end

"""
Tiny @island per reactive cell — captures upstream bonds, returns the
frozen cell value rendered through the shared render_value pipeline.
As with the bond island, cell-out wrapping happens in the outer call
to render_published_cell, not here.
"""
function emit_reactive_island(cc::CellClass)::String
    suffix = _id_suffix(cc.cell.id)
    fname  = "_Cell_$(suffix)"
    lines = [
        "    # TODO[extract-v2]: re-execute this cell body in WASM on bond change.",
        "    # v1 freezes the output at the bond defaults; the bond widget itself",
        "    # remains interactive.",
        "    @island function $(fname)()",
    ]
    for b in sort(collect(cc.upstream_bonds))
        push!(lines, "        $(b), _ = $(b)_signal")
    end
    push!(lines, "        RawHtml(render_value(_cell_$(suffix)))")
    push!(lines, "    end")
    join(lines, "\n") * "\n"
end

# ─── Outer-function cell call sites ───────────────────────────────────

"Return the `state = :done` / `:errored` Symbol the published shell wants."
function _cell_state_literal(cc::CellClass)::String
    cc.cell.output.output_type === :error ? ":errored" : ":done"
end

"Return the runtime_ns integer captured at extract time (or 0)."
_cell_runtime_literal(cc::CellClass)::String = string(Int(cc.cell.output.runtime_ns))

"`true` if the cell's last non-blank, non-comment line ends with `;` —
Pluto's convention for suppressing output. Matches `rstrip` + regex
against the final expression rather than inspecting the parsed AST,
since we keep source verbatim and don't want to second-guess macros."
function _suppresses_output(code::AbstractString)::Bool
    body = strip(code)
    isempty(body) && return false
    # Walk lines bottom-up, skipping trailing blank / comment-only lines.
    lines = split(body, '\n')
    for i in length(lines):-1:1
        line = rstrip(lines[i])
        ln_trimmed = strip(line)
        isempty(ln_trimmed) && continue
        startswith(ln_trimmed, "#") && continue
        # Drop a trailing `# …` comment on the last code line before
        # checking for `;` — `x; # comment` should still suppress.
        m = match(r"^(.*?)\s*#[^\"]*$", line)
        last_code = m === nothing ? line : m.captures[1]
        return endswith(rstrip(last_code), ";")
    end
    return false
end

"""
A static cell: render its frozen value via `render_value` inside the
shared `render_published_cell` shell. `cell.folded` drives `folded=`,
a trailing `;` in the source drives `show_output=false`.
"""
function emit_static_call(cc::CellClass)::String
    suffix = _id_suffix(cc.cell.id)
    folded_lit     = cc.cell.folded ? "true" : "false"
    show_out_lit   = _suppresses_output(cc.cell.code) ? "false" : "true"
    join([
        "            render_published_cell(",
        "                cell_id = $(repr(string(cc.cell.id))),",
        "                source_code = $(_code_literal(cc.cell.code)),",
        "                output_content = RawHtml(render_value(_cell_$(suffix))),",
        "                runtime_ns = $(_cell_runtime_literal(cc)),",
        "                state = $(_cell_state_literal(cc)),",
        "                folded = $(folded_lit),",
        "                show_output = $(show_out_lit),",
        "            )",
    ], "\n")
end

"""
A bond or reactive cell: the cell-out slot becomes a call to the
cell's tiny @island. Bonds always render their widget (forcing
`show_output=true`) since that's the interactive control the user
needs to drive the signal; reactive cells honour trailing `;`.
"""
function emit_island_call(cc::CellClass)::String
    suffix = _id_suffix(cc.cell.id)
    fname  = cc.kind === :bond ? "_Bond_$(cc.bond_name)_$(suffix)" : "_Cell_$(suffix)"
    folded_lit   = cc.cell.folded ? "true" : "false"
    show_out_lit = (cc.kind === :bond || !_suppresses_output(cc.cell.code)) ? "true" : "false"
    join([
        "            render_published_cell(",
        "                cell_id = $(repr(string(cc.cell.id))),",
        "                source_code = $(_code_literal(cc.cell.code)),",
        "                output_content = $(fname)(),",
        "                runtime_ns = $(_cell_runtime_literal(cc)),",
        "                state = $(_cell_state_literal(cc)),",
        "                folded = $(folded_lit),",
        "                show_output = $(show_out_lit),",
        "            )",
    ], "\n")
end

# ─── Shared signals ────────────────────────────────────────────────────

function emit_shared_signals(plan::ExtractionPlan)::String
    lines = String["    # ── Shared signals (one per @bind in the source) ──"]
    any_bond = false
    for cc in plan.cells
        cc.kind === :bond || continue
        any_bond = true
        default_lit = _bond_default_literal(cc.cell.code)
        push!(lines, "    const $(cc.bond_name)_signal = create_signal($(default_lit))")
        # Expose the plain default at module scope so reactive cells that
        # read `n` / `l` at module-load can resolve the name. v1: cells
        # see the frozen default; v2 WASM islands override via signal
        # destructure inside the @island body.
        push!(lines, "    const $(cc.bond_name) = $(default_lit)")
    end
    any_bond || push!(lines, "    # (none)")
    return join(lines, "\n")
end

# ─── File assembly ─────────────────────────────────────────────────────

"""
Bake the full notebook asset bundle (CSS + CodeMirror + init JS)
into the generated module as a single `const _NOTEBOOK_ASSETS_HTML`
literal. Read at extract time, emitted verbatim — the .jl file is
then fully self-contained: every rule, every byte of CodeMirror, the
read-only init script. Drop it into any Therapy app that has Sessions
+ Therapy in its Project.toml and it renders pixel-identical to the
live IDE without the host touching any stylesheet.

`repr` handles all escape concerns (the one `\"\"\"` sequence in
editor.js, `\$` interpolation marks, arbitrary binary byte sequences
in the minified JS bundle). The resulting literal round-trips through
Julia's parser back to the original string.
"""
function emit_asset_bundle_const()::String
    html = published_notebook_assets_html()
    "    const _NOTEBOOK_ASSETS_HTML = $(repr(html))\n"
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
    println(io, emit_shared_signals(plan))
    println(io)

    # Cell value consts (module-load eval).
    println(io, "    # ── Cell values (source preserved, evaluated at module load) ──")
    for cc in plan.cells
        s = emit_cell_const(cc)
        isempty(s) && continue
        print(io, s)
    end
    println(io)

    # Tiny @islands per bond + reactive cell.
    any_island = false
    for cc in plan.cells
        cc.kind === :static && continue
        any_island = true
        emit_fn = cc.kind === :bond ? emit_bond_island : emit_reactive_island
        print(io, emit_fn(cc))
        println(io)
    end
    any_island || println(io, "    # (no bond / reactive cells — notebook is fully static)")

    # Outer notebook function (plain — no @island).
    println(io, "    function $(plan.component_name)()")
    println(io, "        render_published_notebook(")
    cell_calls = String[]
    for cc in plan.cells
        # Skip bootstrap-only static cells (their imports are at module
        # top via collect_imports; nothing to render).
        if cc.kind === :static && _is_bootstrap_cell(cc.cell.code)
            continue
        end
        line = if cc.kind === :static
            emit_static_call(cc)
        else
            emit_island_call(cc)
        end
        push!(cell_calls, line)
    end
    print(io, join(cell_calls, ",\n"))
    println(io, ";")
    # Pass the baked-in assets so render_published_notebook emits
    # OUR inlined CSS+JS bundle rather than reaching into Sessions's
    # static/ at runtime. This is what makes the .jl standalone.
    println(io, "            assets_html = _NOTEBOOK_ASSETS_HTML,")
    println(io, "        )")
    println(io, "    end")

    println(io, "end  # module $(plan.component_name)Mod")
    println(io)
    println(io, "# Surface the function at top scope so the docs registry")
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
    println(io, "# CodeMirror editor (the docs site's Layout picks up every")
    println(io, "# .cm-cell element on load + SPA navigation). Each cell value")
    println(io, "# is computed once at module load and rendered through")
    println(io, "# `Sessions.render_value` — the same MIME classifier the live")
    println(io, "# IDE output pipeline uses, so Markdown/DataFrames/WasmPlot/")
    println(io, "# SessionsUI.Bond all render identically to the IDE.")
    println(io, "#")
    println(io, "# Architecture:")
    println(io, "#   - Cell chrome (cell-wrap > cell-body > [cell-out, cm-cell])")
    println(io, "#     flows through `Sessions.render_published_cell` — single")
    println(io, "#     source of truth with the live IDE's `render_cell`.")
    println(io, "#   - Outer `function $(plan.component_name)()` is plain Julia.")
    println(io, "#     It just calls `render_published_notebook` with the cells")
    println(io, "#     in document order; it always works regardless of WASM")
    println(io, "#     compile state.")
    println(io, "#   - Each @bind cell becomes a tiny @island that wraps the")
    println(io, "#     SessionsUI widget. Bond signals are module-level shared")
    println(io, "#     signals so cross-island sync is automatic.")
    println(io, "#   - Each reactive cell becomes a tiny @island that captures")
    println(io, "#     its upstream bond signals. v1 renders the frozen value")
    println(io, "#     computed at module load (using the bond defaults). v2")
    println(io, "#     re-executes the body in WASM as WasmTarget grows.")
    println(io, "#")
    println(io, "# Re-running `Sessions.extract_notebook` with the same out_path")
    println(io, "# overwrites the file. Hand-edits survive until the next")
    println(io, "# extraction, so prefer editing the source notebook fixture.")
    println(io, "# ───────────────────────────────────────────────────────────")
    println(io)
end

function _write_imports(io::IO, plan::ExtractionPlan)
    # Runtime imports (populated by Extractor.jl): Therapy primitives +
    # Sessions published-notebook helpers. `Sessions` also provides
    # `render_value` — the same MIME classifier the live IDE uses, so we
    # never duplicate it here.
    for line in plan.runtime_imports
        println(io, "    " * line)
    end
    for line in plan.imports
        println(io, "    " * line)
    end
    println(io)
end
