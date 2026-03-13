# Layer 1: Reactive analysis — ExpressionExplorer + PlutoDependencyExplorer integration

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

"""
Build a NotebookTopology from a Notebook, using the cached topology when
available.  Only changed cells are re-parsed; unchanged cells keep their
cached ReactiveNode/ExprAnalysisCache (like Pluto.jl does).

When `changed_cells` is `nothing`, all cells are treated as changed
(full rebuild — used on first load).
"""
function build_topology(nb::Notebook; changed_cells::Union{Nothing, Vector{Cell}}=nothing)
    cells = ordered_cells(nb)
    session_cells = [SessionCell(c) for c in cells]

    old_topo = nb._topology
    if old_topo === nothing
        # First build: analyze all cells
        old_topo = PDE.NotebookTopology{SessionCell}()
        updated = session_cells
    elseif changed_cells === nothing
        # Explicit full rebuild requested
        updated = session_cells
    else
        # Incremental: only re-parse the changed cells
        changed_ids = Set(c.id for c in changed_cells)
        updated = filter(sc -> sc.cell.id in changed_ids, session_cells)
    end

    topology = PDE.updated_topology(
        old_topo,
        session_cells,
        updated;
        get_code_str = sc -> sc.cell.code,
        get_code_expr = sc -> _safe_parse(sc.cell.code),
    )

    # Cache for next time
    nb._topology = topology
    nb._topo_cells = session_cells

    topology, session_cells
end

"""
Compute the topological execution order for a notebook (all cells).
Returns (runnable_cells, errable_cells) where:
  - runnable_cells: Vector{Cell} in correct execution order
  - errable_cells: Dict{Cell, ReactivityError} for cells with errors
"""
function execution_order(nb::Notebook)
    topology, session_cells = build_topology(nb)
    topo_order = PDE.topological_order(topology)

    runnable = Cell[sc.cell for sc in topo_order.runnable]
    errable = Dict{Cell, Any}(sc.cell => err for (sc, err) in topo_order.errable)

    (runnable=runnable, errable=errable)
end

"""
Compute execution order for a subset of cells that changed.
Only re-runs cells affected by the changes.  Uses cached topology
so only the changed cells are re-parsed.
"""
function execution_order(nb::Notebook, changed_cells::Vector{Cell})
    topology, session_cells = build_topology(nb; changed_cells)

    # Find the SessionCell wrappers for changed cells
    changed_ids = Set(c.id for c in changed_cells)
    changed_sc = filter(sc -> sc.cell.id in changed_ids, session_cells)

    topo_order = PDE.topological_order(topology, changed_sc)

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
