# Extractor.jl — top-level entry point for the notebook → Therapy
# component "shadcn-style" extraction pipeline.
#
# Public API:
#   extract_notebook(notebook_path, out_path, component_name; kwargs...)
#
# Pipeline:
#   1. Load notebook + build PDE topology
#   2. classify_cells (CellGraph.jl) → :static / :bond / :reactive
#   3. Run cells in a clean worker, capture rendered output (StaticRender.jl)
#   4. Compile bond + reactive cells to @island sources (Emit.jl)
#   5. Assemble single .jl file (Emit.jl::assemble)
#
# Extraction is one-way: re-run with the same out_path to overwrite.

# ExtractionPlan struct lives in extract/Types.jl so Emit.jl + this
# file can both reference it without circular include order.

"""
    validate_component_name(name::AbstractString)

Throw an `ArgumentError` unless `name` is a non-empty PascalCase
identifier (matches `[A-Z][A-Za-z0-9]*`). Mirrors what Therapy
expects of a component function name.
"""
function validate_component_name(name::AbstractString)
    isempty(name) && throw(ArgumentError("component name is required"))
    occursin(r"^[A-Z][A-Za-z0-9]*$", name) || throw(ArgumentError(
        "component name must be PascalCase (^[A-Z][A-Za-z0-9]*\$). Got: $(repr(name))"))
    return String(name)
end

"""
    extract_notebook(notebook_path, out_path, component_name;
                     overwrite::Bool=false,
                     progress::Function = identity)

Extract `notebook_path` to a single .jl file at `out_path` exposing a
top-level Therapy component named `component_name` (PascalCase).

Both `out_path` and `component_name` are REQUIRED (positional). The
generated file:
- Is self-contained: depends on Therapy + the notebook's own `using`
  imports (e.g. WasmPlot, DataFrames). No Sessions / PDE deps.
- Has every static cell output frozen at extract time as `RawHtml(…)`.
- Has each `@bind` widget rendered as a Therapy `@island`.
- Has each reactive cell compiled to a WASM `@island` that subscribes
  to its upstream bond signals.
- Carries a header comment with source path, timestamp, and
  "DO NOT EDIT — re-extract from \$notebook_path" warning.

`overwrite=false` errors if `out_path` already exists. `progress` is
called for human-readable progress messages (defaults to `identity` —
silent; the IDE wires it up to a WS broadcast).
"""
function extract_notebook(
    notebook_path::AbstractString,
    out_path::AbstractString,
    component_name::AbstractString;
    overwrite::Bool = false,
    progress::Function = identity,
)
    nb_abs  = abspath(String(notebook_path))
    out_abs = abspath(String(out_path))
    cn      = validate_component_name(component_name)
    isfile(nb_abs) || throw(ArgumentError("notebook not found: $nb_abs"))
    if isfile(out_abs) && !overwrite
        throw(ArgumentError("$out_abs already exists. Pass `overwrite=true` to replace it."))
    end

    progress("Loading notebook…")
    nb = load_notebook(nb_abs)

    progress("Building dependency graph…")
    update_topology!(nb)
    cells = classify_cells(nb)
    n_static   = count(c -> c.kind === :static,   cells)
    n_bond     = count(c -> c.kind === :bond,     cells)
    n_reactive = count(c -> c.kind === :reactive, cells)
    progress("  $(n_bond) bonds, $(n_reactive) reactive, $(n_static) static")

    progress("Running cells in a clean worker (capturing static outputs)…")
    outputs = render_static_outputs(nb, cells; progress=progress)

    progress("Lifting notebook imports…")
    imports = collect_imports(nb)
    # Target only the specific names the scaffolding uses. `using Therapy`
    # (all exports) clashes with notebook imports that export the same
    # HTML5 element names — e.g. WasmPlot.Figure vs Therapy.Figure
    # (<figure>), or a user-defined Header / Section / Details. The
    # extracted module needs @island / create_signal / RawHtml for the
    # scaffolding and `render_value` / `render_published_cell` /
    # `render_published_notebook` from Sessions for cell chrome — those
    # are the single source of truth, shared with the live IDE.
    runtime_imports = [
        "using Therapy: @island, create_signal, RawHtml",
        "using Sessions: render_value, render_published_cell, render_published_notebook",
    ]

    plan = ExtractionPlan(
        nb_abs, cn, out_abs,
        cells,
        outputs,
        imports,
        runtime_imports,
    )

    progress("Emitting $cn() to $out_abs…")
    src = assemble(plan)
    mkpath(dirname(out_abs))
    write(out_abs, src)
    progress("Done.")
    return plan
end

# ─── Import lifting ────────────────────────────────────────────────────

"""
    collect_imports(nb::Notebook) -> Vector{String}

Gather every `using …` / `import …` line that appears in any cell,
deduplicated, in first-occurrence order. Sessions-internal imports
(Sessions itself, SessionsUI, Pkg setup blocks) are filtered out:
the extracted component declares its own runtime deps.
"""
function collect_imports(nb::Notebook)::Vector{String}
    seen   = Set{String}()
    result = String[]
    for c in ordered_cells(nb)
        for line in split(c.code, '\n'; keepempty=false)
            s = strip(line)
            startswith(s, "using ") || startswith(s, "import ") || continue
            # Skip notebook-bootstrap / tooling imports that don't
            # belong in the extracted component:
            #   - `using Sessions`              (the IDE itself)
            #   - `using PlutoDependencyExplorer` (extraction-only tool)
            #   - `using Pkg`                    (notebook env bootstrap)
            # SessionsUI STAYS — it exports @bind / BoundSlider / the
            # notebook-widget surface that users actively call from cells.
            occursin(r"^using\s+Sessions(\s*$|\s*[,:])", s) && continue
            occursin(r"^import\s+Sessions(\s*$|\s*[,:])", s) && continue
            occursin(r"\bPlutoDependencyExplorer\b", s) && continue
            occursin(r"\bPkg\b",             s) && continue
            ss = String(s)
            if !(ss in seen)
                push!(seen, ss); push!(result, ss)
            end
        end
    end
    return result
end
