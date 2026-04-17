# Emit.jl — assemble an ExtractionPlan into a single .jl Therapy
# component. Shape is the (B) layout the user signed off on:
#
#   module <Name>Mod
#     using Therapy
#     using <user notebook deps>
#
#     _render(x) = ...                 # MIME text/html bridge
#
#     const <bond>_signal = create_signal(default)   # one per @bind
#
#     # Cell values — source preserved verbatim, evaluated at module
#     # load by Julia (NOT compiled to WASM). This is where Markdown,
#     # WasmPlot, DataFrames, etc. live. They run host-side at SSG
#     # build, which is fine — the result objects are what we render.
#     const _cell_<id> = try begin <user code> end catch e; e end
#
#     # Per-bond tiny @island — wraps the SessionsUI widget. WASM-
#     # compiles trivially (just a signal destructure + the widget's
#     # show()-emitted HTML).
#     @island function _Bond_<bond>_<id>() ... end
#
#     # Per-reactive-cell tiny @island — captures upstream bond signals
#     # so cross-island sync wires correctly. v1: renders the frozen
#     # _cell_<id> value (computed at module load with the bond
#     # default). v2: re-execute in WASM as WasmTarget coverage grows.
#     @island function _Cell_<id>() ... end
#
#     # Outer notebook = PLAIN function. No WASM constraint here, so it
#     # always renders regardless of any @island compile failures.
#     # Cells appear in document order, each wrapped in the same
#     # cell-wrap > cell-body > cell-out chain the Sessions IDE uses.
#     function <Name>()
#         Div(...)
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

# ─── Per-cell emission ────────────────────────────────────────────────

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

"`const _cell_<id> = try begin <code> end catch e; e end` — module-load eval.
Returns an empty string when the cell is pure bootstrap (skip)."
function emit_cell_const(cc::CellClass)::String
    code = strip(cc.cell.code)
    _is_bootstrap_cell(code) && return ""
    suffix = _id_suffix(cc.cell.id)
    return """
    # ── Cell $(cc.cell.id) ($(cc.kind)) ──
    const _cell_$(suffix) = try
        let
$(_indent(code, 12))
        end
    catch _e
        _e
    end
    """
end

"Tiny @island per @bind — destructures the shared signal, renders the widget."
function emit_bond_island(cc::CellClass)::String
    suffix = _id_suffix(cc.cell.id)
    bond   = cc.bond_name
    fname  = "_Bond_$(bond)_$(suffix)"
    return """
    @island function $(fname)()
        $(bond), set_$(bond) = $(bond)_signal
        Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
            RawHtml(_render(_cell_$(suffix))))
    end
    """
end

"Tiny @island per reactive cell — captures upstream bonds, frozen render in v1."
function emit_reactive_island(cc::CellClass)::String
    suffix = _id_suffix(cc.cell.id)
    fname  = "_Cell_$(suffix)"
    binds  = String[]
    for b in sort(collect(cc.upstream_bonds))
        push!(binds, "        $(b), _ = $(b)_signal")
    end
    binds_block = isempty(binds) ? "" : join(binds, "\n") * "\n"
    return """
    # TODO[extract-v2]: re-execute this cell body in WASM on bond change.
    # v1 freezes the output at the bond defaults; the bond widget itself
    # remains interactive.
    @island function $(fname)()
$(binds_block)        Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
            RawHtml(_render(_cell_$(suffix))))
    end
    """
end

# ─── Outer-function cell call sites ───────────────────────────────────

"""
A static cell: the outer function renders its frozen value via _render.
Wraps in `cell-wrap > cell-body > cell-out` to match the IDE chrome.
"""
function emit_static_call(cc::CellClass)::String
    suffix = _id_suffix(cc.cell.id)
    return """        Div(:class => "cell-wrap relative",
            Div(:class => "cell-body",
                Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
                    RawHtml(_render(_cell_$(suffix))))))"""
end

"A bond/reactive cell: outer function calls into the cell's tiny @island."
function emit_island_call(cc::CellClass)::String
    suffix = _id_suffix(cc.cell.id)
    fname  = cc.kind === :bond ? "_Bond_$(cc.bond_name)_$(suffix)" : "_Cell_$(suffix)"
    return """        Div(:class => "cell-wrap relative",
            Div(:class => "cell-body",
                $(fname)()))"""
end

# ─── Shared signals + render helper ────────────────────────────────────

function emit_shared_signals(plan::ExtractionPlan)::String
    lines = String["    # ── Shared signals (one per @bind in the source) ──"]
    any_bond = false
    for cc in plan.cells
        cc.kind === :bond || continue
        any_bond = true
        default_lit = _bond_default_literal(cc.cell.code)
        push!(lines, "    const $(cc.bond_name)_signal = create_signal($(default_lit))")
    end
    any_bond || push!(lines, "    # (none)")
    return join(lines, "\n")
end

function emit_render_helper()::String
    return """
    \"\"\"
    Render any cell value to an HTML string. Tries Sessions's tree
    renderer for Dicts/Sets/structs (if the host loaded it), then
    `Base.show(MIME"text/html"(), …)` for everything else (Markdown,
    DataFrames, plots — they all define their own show methods),
    falling back to `print` for plain values.
    \"\"\"
    function _render(x)::String
        x isa Exception && return string(\"<pre style='color:#c33;font-family:monospace;font-size:12px;padding:8px;background:#fee;border-radius:4px'>\", sprint(showerror, x), \"</pre>\")
        if isdefined(Main, :Sessions)
            try
                sess = Main.Sessions
                if Base.invokelatest(getfield(sess, :_is_tree_value), x)
                    return Base.invokelatest(getfield(sess, :_render_tree_html), x)
                end
            catch
            end
        end
        try
            sprint(io -> show(io, MIME\"text/html\"(), x))
        catch
            sprint(print, x)
        end
    end
    """
end

# ─── File assembly ─────────────────────────────────────────────────────

function assemble(plan::ExtractionPlan)::String
    io = IOBuffer()
    _write_header(io, plan)
    println(io, "module $(plan.component_name)Mod")
    println(io)
    _write_imports(io, plan)
    println(io, emit_render_helper())
    println(io)
    println(io, emit_shared_signals(plan))
    println(io)

    # Cell value consts (module-load eval).
    println(io, "    # ── Cell values (source preserved, evaluated at module load) ──")
    for cc in plan.cells
        print(io, _indent(emit_cell_const(cc), 0))
    end
    println(io)

    # Tiny @islands per bond + reactive cell.
    any_island = false
    for cc in plan.cells
        cc.kind === :static && continue
        any_island = true
        emit_fn = cc.kind === :bond ? emit_bond_island : emit_reactive_island
        print(io, _indent(emit_fn(cc), 0))
        println(io)
    end
    any_island || println(io, "    # (no bond / reactive cells — notebook is fully static)")

    # Outer notebook function (plain — no @island).
    println(io, "    function $(plan.component_name)()")
    println(io, "        Div(:class => \"notebook-extracted\",")
    println(io, "            Div(:class => \"nb-cell-list\",")
    println(io, "                :style => \"max-width:900px;margin:0 auto;padding-left:28px;padding-right:28px;position:relative;\",")
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
        # Re-indent two extra levels (we're inside the nb-cell-list nest).
        line = replace(line, "        " => "                "; count=1)
        push!(cell_calls, line)
    end
    println(io, join(cell_calls, ",\n"))
    println(io, "            )")
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
    println(io, "# This file is a self-contained Therapy component. The user's")
    println(io, "# cell SOURCE is preserved verbatim — markdown stays markdown,")
    println(io, "# code stays code. Each cell evaluates once at module load and")
    println(io, "# its value is rendered through Base.show(MIME\"text/html\"(),…)")
    println(io, "# (the same pipeline the Sessions IDE uses live).")
    println(io, "#")
    println(io, "# Architecture:")
    println(io, "#   - Outer `function $(plan.component_name)()` is plain Julia.")
    println(io, "#     It just lays out cells in document order; it always works")
    println(io, "#     regardless of WASM compile state.")
    println(io, "#   - Each @bind cell becomes a tiny @island that wraps the")
    println(io, "#     SessionsUI widget. Bond signals are module-level shared")
    println(io, "#     signals so cross-island sync is automatic.")
    println(io, "#   - Each reactive cell becomes a tiny @island that captures")
    println(io, "#     its upstream bond signals. v1 renders the frozen value")
    println(io, "#     computed at module load (using the bond defaults). v2")
    println(io, "#     re-executes the body in WASM as WasmTarget grows.")
    println(io, "#")
    println(io, "# Edit by hand to restyle Tailwind classes, change cell content,")
    println(io, "# remove cells, etc. Re-running `Sessions.extract_notebook` with")
    println(io, "# the same out_path overwrites the file.")
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
