# Layer 1: Reactive analysis — ExpressionExplorer + PlutoDependencyExplorer integration
#
# Follows Pluto.jl's topology caching pattern:
#   - notebook.topology stores the current NotebookTopology (incrementally updated)
#   - notebook._cached_topological_order caches the full topological order
#   - updated_topology() only re-parses changed cells; unchanged cells keep their
#     cached ReactiveNode and ExprAnalysisCache

import ExpressionExplorer
import PlutoDependencyExplorer as PDE

"""Wrapper around Cell to satisfy PlutoDependencyExplorer's AbstractCell interface."""
struct SessionCell <: PDE.AbstractCell
    cell::Cell
end

"""Analyze a single cell's code and return its ReactiveNode (definitions, references, etc.)."""
function analyze_cell(cell::Cell)
    if isempty(strip(cell.code))
        return ExpressionExplorer.ReactiveNode()
    end
    expr = Base.Meta.parse("begin\n$(cell.code)\nend")
    ExpressionExplorer.compute_reactive_node(expr)
end

"""Get the set of symbols defined by a cell."""
function cell_definitions(cell::Cell)
    node = analyze_cell(cell)
    union(node.definitions, node.funcdefs_without_signatures)
end

"""Get the set of symbols referenced by a cell."""
function cell_references(cell::Cell)
    analyze_cell(cell).references
end

"""Parse cell code safely — returns a placeholder Expr on ParseError instead of crashing."""
function _safe_parse(code::String)
    try
        Base.Meta.parse("begin\n$(code)\nend")
    catch
        # Return an empty block so topology analysis can continue
        :(begin end)
    end
end

# ── Topology: incremental update (mirrors Pluto's Parse.jl) ─────────

"""
    updated_topology(old_topology, nb, updated_cells)

Incrementally update the notebook topology, re-parsing only `updated_cells`.
Mirrors Pluto.jl's `updated_topology(old_topology, notebook, updated_cells)`.
"""
function updated_topology(
    old_topology::PDE.NotebookTopology{SessionCell},
    nb::Notebook,
    updated_cells::Vector{Cell},
)
    cells = ordered_cells(nb)
    session_cells = [SessionCell(c) for c in cells]

    changed_ids = Set(c.id for c in updated_cells)
    updated_sc = filter(sc -> sc.cell.id in changed_ids, session_cells)

    PDE.updated_topology(
        old_topology,
        session_cells,
        updated_sc;
        get_code_str = sc -> sc.cell.code,
        get_code_expr = sc -> _safe_parse(sc.cell.code),
        get_cell_disabled = sc -> sc.cell.disabled,
    )
end

"""
    updated_topology(old_topology, nb)

Full rebuild — all cells treated as updated.
"""
function updated_topology(
    old_topology::PDE.NotebookTopology{SessionCell},
    nb::Notebook,
)
    cells = ordered_cells(nb)
    session_cells = [SessionCell(c) for c in cells]

    PDE.updated_topology(
        old_topology,
        session_cells,
        session_cells;
        get_code_str = sc -> sc.cell.code,
        get_code_expr = sc -> _safe_parse(sc.cell.code),
        get_cell_disabled = sc -> sc.cell.disabled,
    )
end

# ── Cached topological order (mirrors Pluto's Notebook.jl) ──────────

"""
    topological_order(nb::Notebook) -> TopologicalOrder

Return the cached topological order for the full notebook, recomputing
only when the topology has changed.  Mirrors Pluto.jl's override of
`PlutoDependencyExplorer.topological_order(notebook::Notebook)`.
"""
function _topological_order(nb::Notebook)
    topo = nb.topology
    topo === nothing && error("notebook topology not initialized — call update_topology! first")
    cached = nb._cached_topological_order
    if cached === nothing || cached.input_topology !== topo
        nb._cached_topological_order = PDE.topological_order(topo)
    end
    nb._cached_topological_order
end

# ── Public API ───────────────────────────────────────────────────────

"""
    update_topology!(nb, changed_cells) -> NotebookTopology
    update_topology!(nb)                -> NotebookTopology

Update the notebook's cached topology.  When `changed_cells` is provided,
only those cells are re-parsed (incremental).  Without it, all cells are
re-parsed (full rebuild, used on first load).

Mirrors Pluto.jl's pattern of `notebook.topology = updated_topology(old, notebook, cells)`.
"""
function update_topology!(nb::Notebook, changed_cells::Vector{Cell})
    old = nb.topology
    if old === nothing
        # First time: full build (all cells need parsing, not just changed)
        old = PDE.NotebookTopology{SessionCell}()
        nb.topology = updated_topology(old, nb)
    else
        nb.topology = updated_topology(old, nb, changed_cells)
    end
end

function update_topology!(nb::Notebook)
    old = nb.topology
    if old === nothing
        old = PDE.NotebookTopology{SessionCell}()
    end
    nb.topology = updated_topology(old, nb)
end

"""
Compute the topological execution order for a notebook (all cells).
Returns (runnable_cells, errable_cells).
"""
function execution_order(nb::Notebook)
    nb.topology === nothing && update_topology!(nb)
    topo_order = _topological_order(nb)

    runnable = Cell[sc.cell for sc in topo_order.runnable]
    errable = Dict{Cell, Any}(sc.cell => err for (sc, err) in topo_order.errable)

    (runnable=runnable, errable=errable)
end

"""
Compute execution order for a subset of cells that changed.
Only re-runs cells affected by the changes.  Incrementally updates
the cached topology so only changed cells are re-parsed.
"""
function execution_order(nb::Notebook, changed_cells::Vector{Cell})
    # Incremental topology update — only re-parses changed cells
    update_topology!(nb, changed_cells)

    topo = nb.topology
    cells = ordered_cells(nb)
    session_cells = [SessionCell(c) for c in cells]

    changed_ids = Set(c.id for c in changed_cells)
    changed_sc = filter(sc -> sc.cell.id in changed_ids, session_cells)

    topo_order = PDE.topological_order(topo, changed_sc)

    runnable = Cell[sc.cell for sc in topo_order.runnable]
    errable = Dict{Cell, Any}(sc.cell => err for (sc, err) in topo_order.errable)

    (runnable=runnable, errable=errable)
end

"""
Find all downstream dependents of a set of cells.
Returns cells that would need to re-execute if the given cells change.
"""
function downstream_dependents(nb::Notebook, changed_cells::Vector{Cell})
    order = execution_order(nb, changed_cells)
    changed_ids = Set(c.id for c in changed_cells)
    filter(c -> !(c.id in changed_ids), order.runnable)
end
