# DependencyTracker.jl - Cell dependency analysis using Pluto's packages
#
# This module provides reactive execution capabilities by leveraging:
# - ExpressionExplorer.jl: Find variables referenced/defined in code
# - PlutoDependencyExplorer.jl: Topological ordering of cells
#
# These are the same packages Pluto uses internally for its reactivity!

using ExpressionExplorer
import PlutoDependencyExplorer as PDE

"""
    SessionCell - Wrapper for our Cell type to work with PlutoDependencyExplorer.

PlutoDependencyExplorer expects cells that implement AbstractCell.
"""
struct SessionCell <: PDE.AbstractCell
    id::UUID
    code::String
end

"""
    NotebookReactivity

Manages the reactive dependency graph for all cells using PlutoDependencyExplorer.
"""
mutable struct NotebookReactivity
    # Topology from PlutoDependencyExplorer
    topology::PDE.NotebookTopology{SessionCell}

    # Cache of SessionCells
    cells::Vector{SessionCell}
end

"""
Create an empty reactivity manager.
"""
function NotebookReactivity()
    NotebookReactivity(
        PDE.NotebookTopology{SessionCell}(),
        SessionCell[]
    )
end

"""
    update_cells!(reactivity::NotebookReactivity, cells::Dict{UUID, Cell})

Update the topology with the current cells from the notebook.
"""
function update_cells!(reactivity::NotebookReactivity, cells::Dict{UUID, Cell})
    # Convert to SessionCells
    session_cells = [SessionCell(cell.id, cell.code) for cell in values(cells)]
    reactivity.cells = session_cells

    # Update topology
    reactivity.topology = PDE.updated_topology(
        reactivity.topology,
        session_cells, session_cells;
        get_code_str = c -> c.code,
        get_code_expr = c -> begin
            try
                isempty(strip(c.code)) ? :() : Meta.parse("begin\n$(c.code)\nend")
            catch
                :()  # Return empty on parse error
            end
        end
    )

    return reactivity
end

"""
    get_execution_order(reactivity::NotebookReactivity) -> Vector{UUID}

Get the topological order for running all cells.
Returns cell IDs in the order they should be executed.
"""
function get_execution_order(reactivity::NotebookReactivity)::Vector{UUID}
    order = PDE.topological_order(reactivity.topology)
    return [cell.id for cell in order.runnable]
end

"""
    get_downstream_cells(reactivity::NotebookReactivity, cell_id::UUID) -> Vector{UUID}

Get cells that depend on the given cell (directly or indirectly).
Returns cell IDs in topological order.
"""
function get_downstream_cells(reactivity::NotebookReactivity, cell_id::UUID)::Vector{UUID}
    # Find the cell
    cell_idx = findfirst(c -> c.id == cell_id, reactivity.cells)
    if cell_idx === nothing
        return UUID[]
    end

    cell = reactivity.cells[cell_idx]

    # Get the full topological order
    order = PDE.topological_order(reactivity.topology)

    # Find cells that come after this one in the order and depend on it
    # For now, return all cells after this one (simplified)
    # A more sophisticated approach would trace the actual dependency graph
    downstream = UUID[]
    found_cell = false

    for runnable_cell in order.runnable
        if runnable_cell.id == cell_id
            found_cell = true
            continue
        end
        if found_cell
            push!(downstream, runnable_cell.id)
        end
    end

    return downstream
end

"""
    get_cell_references(reactivity::NotebookReactivity, cell_id::UUID) -> Set{Symbol}

Get the variables referenced by a cell.
"""
function get_cell_references(reactivity::NotebookReactivity, cell_id::UUID)::Set{Symbol}
    cell_idx = findfirst(c -> c.id == cell_id, reactivity.cells)
    if cell_idx === nothing
        return Set{Symbol}()
    end

    cell = reactivity.cells[cell_idx]
    code = cell.code

    if isempty(strip(code))
        return Set{Symbol}()
    end

    try
        expr = Meta.parse("begin\n$code\nend")
        node = ExpressionExplorer.compute_reactive_node(expr)
        return node.references
    catch
        return Set{Symbol}()
    end
end

"""
    get_cell_definitions(reactivity::NotebookReactivity, cell_id::UUID) -> Set{Symbol}

Get the variables defined by a cell.
"""
function get_cell_definitions(reactivity::NotebookReactivity, cell_id::UUID)::Set{Symbol}
    cell_idx = findfirst(c -> c.id == cell_id, reactivity.cells)
    if cell_idx === nothing
        return Set{Symbol}()
    end

    cell = reactivity.cells[cell_idx]
    code = cell.code

    if isempty(strip(code))
        return Set{Symbol}()
    end

    try
        expr = Meta.parse("begin\n$code\nend")
        node = ExpressionExplorer.compute_reactive_node(expr)
        return node.definitions
    catch
        return Set{Symbol}()
    end
end

# =============================================================================
# Legacy API compatibility
# =============================================================================
# These functions maintain compatibility with the previous DependencyTracker API

"""
    DependencyGraph - Legacy wrapper around NotebookReactivity.
"""
const DependencyGraph = NotebookReactivity

"""
    analyze_cell(code::String) -> NamedTuple

Analyze a cell's code using ExpressionExplorer.
Returns a named tuple with :references and :definitions.
"""
function analyze_cell(code::String)
    if isempty(strip(code))
        return (references=Set{Symbol}(), definitions=Set{Symbol}(), funcdefs=Set{Symbol}())
    end

    try
        expr = Meta.parse("begin\n$code\nend")
        node = ExpressionExplorer.compute_reactive_node(expr)
        return (
            references=node.references,
            definitions=node.definitions,
            funcdefs=node.funcdefs_without_signatures
        )
    catch e
        @warn "Failed to analyze cell" exception=e
        return (references=Set{Symbol}(), definitions=Set{Symbol}(), funcdefs=Set{Symbol}())
    end
end

"""
    update_cell!(graph::DependencyGraph, cell_id::UUID, code::String)

Legacy API: Update dependency tracking for a cell.
"""
function update_cell!(graph::DependencyGraph, cell_id::UUID, code::String)
    # This is now a no-op since we use update_cells! with all cells
    # The actual update happens in the server's message handler
    return analyze_cell(code)
end

"""
    remove_cell!(graph::DependencyGraph, cell_id::UUID)

Legacy API: Remove a cell from tracking.
"""
function remove_cell!(graph::DependencyGraph, cell_id::UUID)
    # Filter out the cell
    filter!(c -> c.id != cell_id, graph.cells)
end
