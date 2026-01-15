# Reactivity.jl - Dependency tracking and execution ordering
#
# Uses ExpressionExplorer and PlutoDependencyExplorer from the Pluto ecosystem
# to determine cell dependencies and compute execution order.
# ExpressionExplorer and PDE are imported at the Sessions.jl module level.

# =============================================================================
# Cell Analysis (ExpressionExplorer)
# =============================================================================

"""
    analyze_cell!(cell)

Analyze a cell's code to find variable references and definitions.
Updates the cell's `references`, `definitions`, and `funcdefs` fields.
"""
function analyze_cell!(cell::Cell)
    if isempty(strip(cell.code))
        cell.references = Set{Symbol}()
        cell.definitions = Set{Symbol}()
        cell.funcdefs = Set{Symbol}()
        return cell
    end

    try
        expr = Base.Meta.parse(cell.code)
        node = ExpressionExplorer.compute_reactive_node(expr)

        cell.references = node.references
        cell.definitions = node.definitions
        cell.funcdefs = node.funcdefs_without_signatures
    catch e
        # If parsing fails, leave reactivity metadata empty
        # The execution error will be caught later
        cell.references = Set{Symbol}()
        cell.definitions = Set{Symbol}()
        cell.funcdefs = Set{Symbol}()
    end

    return cell
end

"""
    analyze_code(code::String)

Analyze code without a cell, returning (references, definitions, funcdefs).
"""
function analyze_code(code::String)
    if isempty(strip(code))
        return (Set{Symbol}(), Set{Symbol}(), Set{Symbol}())
    end

    try
        expr = Base.Meta.parse(code)
        node = ExpressionExplorer.compute_reactive_node(expr)
        return (node.references, node.definitions, node.funcdefs_without_signatures)
    catch
        return (Set{Symbol}(), Set{Symbol}(), Set{Symbol}())
    end
end

# =============================================================================
# PlutoDependencyExplorer Integration
# =============================================================================

"""
Wrapper cell type for PlutoDependencyExplorer.
PDE requires cells to subtype AbstractCell.
"""
struct PDECell <: PDE.AbstractCell
    id::UUID
    code::String
end

# Create PDECell from our Cell
PDECell(cell::Cell) = PDECell(cell.id, cell.code)

"""
    compute_topology(notebook)

Build a NotebookTopology from the notebook's cells using PlutoDependencyExplorer.
"""
function compute_topology(notebook::Notebook)
    # First, analyze all cells
    for cell in values(notebook.cells)
        analyze_cell!(cell)
    end

    # Wrap cells for PDE
    pde_cells = [PDECell(cell) for cell in values(notebook.cells)]

    # Create empty topology and update with our cells
    empty_topology = PDE.NotebookTopology{PDECell}()

    topology = PDE.updated_topology(
        empty_topology,
        pde_cells,
        pde_cells;
        get_code_str = c -> c.code,
        get_code_expr = c -> Base.Meta.parse(c.code),
        get_cell_disabled = c -> false
    )

    return topology
end

"""
    get_execution_order(notebook, changed_cells::Vector{UUID})

Given cells that changed, compute the full list of cells that need to run,
in topological order.

Returns a Vector of Cells in execution order.
"""
function get_execution_order(notebook::Notebook, changed_cells::Vector{UUID})
    # Analyze all cells first
    for cell in values(notebook.cells)
        analyze_cell!(cell)
    end

    # Build dependency graph manually since PDE API may vary
    # For each cell, find which other cells depend on its definitions

    # Map: symbol -> cell that defines it
    symbol_to_definer = Dict{Symbol, UUID}()
    for cell in values(notebook.cells)
        for sym in cell.definitions
            symbol_to_definer[sym] = cell.id
        end
        for sym in cell.funcdefs
            symbol_to_definer[sym] = cell.id
        end
    end

    # Map: cell_id -> cells that depend on it (downstream)
    downstream = Dict{UUID, Set{UUID}}()
    for cell in values(notebook.cells)
        downstream[cell.id] = Set{UUID}()
    end

    for cell in values(notebook.cells)
        for ref in cell.references
            if haskey(symbol_to_definer, ref)
                definer_id = symbol_to_definer[ref]
                if definer_id != cell.id
                    push!(downstream[definer_id], cell.id)
                end
            end
        end
    end

    # BFS to find all cells that need to run
    to_run = Set{UUID}(changed_cells)
    queue = copy(changed_cells)

    while !isempty(queue)
        current = popfirst!(queue)
        for dependent in get(downstream, current, Set{UUID}())
            if !(dependent in to_run)
                push!(to_run, dependent)
                push!(queue, dependent)
            end
        end
    end

    # Topological sort based on dependencies
    # Simple approach: sort by dependency depth
    function dependency_depth(cell_id::UUID, visited=Set{UUID}())
        if cell_id in visited
            return 0  # Cycle, return 0
        end
        push!(visited, cell_id)

        cell = notebook.cells[cell_id]
        max_depth = 0
        for ref in cell.references
            if haskey(symbol_to_definer, ref)
                definer_id = symbol_to_definer[ref]
                if definer_id != cell_id && definer_id in to_run
                    max_depth = max(max_depth, dependency_depth(definer_id, visited) + 1)
                end
            end
        end
        return max_depth
    end

    # Sort cells by dependency depth
    cells_to_run = [notebook.cells[id] for id in to_run if haskey(notebook.cells, id)]
    sort!(cells_to_run, by=c -> dependency_depth(c.id))

    return cells_to_run
end

"""
    get_all_execution_order(notebook)

Get execution order for running all cells from scratch.
"""
function get_all_execution_order(notebook::Notebook)
    all_ids = collect(keys(notebook.cells))
    get_execution_order(notebook, all_ids)
end

"""
    get_downstream_cells(notebook, cell_id)

Find all cells that depend on the given cell (directly or indirectly).
"""
function get_downstream_cells(notebook::Notebook, cell_id::UUID)
    cell = get_cell(notebook, cell_id)
    if cell === nothing
        return Cell[]
    end

    # Get execution order starting from this cell
    order = get_execution_order(notebook, [cell_id])

    # Remove the original cell from the result
    filter!(c -> c.id != cell_id, order)

    return order
end

# =============================================================================
# Cycle Detection
# =============================================================================

"""
    has_cycle(notebook)

Check if the notebook has circular dependencies.
Returns (has_cycle::Bool, cycle_cells::Vector{UUID})
"""
function has_cycle(notebook::Notebook)
    # Analyze all cells
    for cell in values(notebook.cells)
        analyze_cell!(cell)
    end

    # Build symbol -> definer map
    symbol_to_definer = Dict{Symbol, UUID}()
    for cell in values(notebook.cells)
        for sym in union(cell.definitions, cell.funcdefs)
            symbol_to_definer[sym] = cell.id
        end
    end

    # Build adjacency list (cell -> cells it depends on)
    depends_on = Dict{UUID, Set{UUID}}()
    for cell in values(notebook.cells)
        depends_on[cell.id] = Set{UUID}()
        for ref in cell.references
            if haskey(symbol_to_definer, ref)
                definer_id = symbol_to_definer[ref]
                if definer_id != cell.id
                    push!(depends_on[cell.id], definer_id)
                end
            end
        end
    end

    # DFS to detect cycles
    WHITE, GRAY, BLACK = 0, 1, 2
    color = Dict(id => WHITE for id in keys(notebook.cells))
    cycle_cells = UUID[]

    function dfs(cell_id)
        color[cell_id] = GRAY
        for dep in get(depends_on, cell_id, Set{UUID}())
            if color[dep] == GRAY
                # Found cycle
                push!(cycle_cells, cell_id)
                push!(cycle_cells, dep)
                return true
            elseif color[dep] == WHITE
                if dfs(dep)
                    push!(cycle_cells, cell_id)
                    return true
                end
            end
        end
        color[cell_id] = BLACK
        return false
    end

    for cell_id in keys(notebook.cells)
        if color[cell_id] == WHITE
            if dfs(cell_id)
                return (true, unique(cycle_cells))
            end
        end
    end

    return (false, UUID[])
end
