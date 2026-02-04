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

Uses `parse_cell_code` to handle multi-line cells transparently -
users don't need to wrap code in begin...end.
"""
function analyze_cell!(cell::Cell)
    if isempty(strip(cell.code))
        cell.references = Set{Symbol}()
        cell.definitions = Set{Symbol}()
        cell.funcdefs = Set{Symbol}()
        return cell
    end

    try
        # Use parse_cell_code for auto begin...end wrapping
        expr = parse_cell_code(cell.code)
        println("[Sessions] Analyzing code: $(repr(cell.code))")
        println("[Sessions] Parsed expr: $(expr)")

        node = ExpressionExplorer.compute_reactive_node(expr)
        println("[Sessions] ReactiveNode: refs=$(node.references), defs=$(node.definitions)")

        cell.references = node.references
        cell.definitions = node.definitions
        cell.funcdefs = node.funcdefs_without_signatures
    catch e
        # Log the error instead of silently swallowing it
        println("[Sessions] analyze_cell! ERROR: $(sprint(showerror, e))")
        println("[Sessions] Stacktrace: $(sprint(Base.show_backtrace, catch_backtrace()))")
        cell.references = Set{Symbol}()
        cell.definitions = Set{Symbol}()
        cell.funcdefs = Set{Symbol}()
    end

    return cell
end

"""
    analyze_code(code::String)

Analyze code without a cell, returning (references, definitions, funcdefs).
Uses `parse_cell_code` for auto begin...end wrapping of multi-line code.
"""
function analyze_code(code::String)
    if isempty(strip(code))
        return (Set{Symbol}(), Set{Symbol}(), Set{Symbol}())
    end

    try
        # Use parse_cell_code for auto begin...end wrapping
        expr = parse_cell_code(code)
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
    SessionsCell <: PlutoDependencyExplorer.AbstractCell

Wrapper cell type for PlutoDependencyExplorer integration.
PDE requires cells to subtype AbstractCell for topology computation.

The PDE interface is callback-based (via `updated_topology` keyword args):
- `get_code_str(cell)` → returns code string
- `get_code_expr(cell)` → returns parsed expression
- `get_cell_disabled(cell)` → returns Bool

This is Sessions.jl's adapter that wraps our Cell type for dependency analysis.
"""
struct SessionsCell <: PDE.AbstractCell
    id::UUID
    code::String
end

# Create SessionsCell from our Cell
SessionsCell(cell::Cell) = SessionsCell(cell.id, cell.code)

# Helper functions for PDE callbacks (these are NOT method overrides,
# they are passed to updated_topology as keyword arguments)
_get_code_str(c::SessionsCell) = c.code
_get_code_expr(c::SessionsCell) = parse_cell_code(c.code)
_get_cell_disabled(c::SessionsCell) = false

"""
    compute_topology(notebook)

Build a NotebookTopology from the notebook's cells using PlutoDependencyExplorer.
Uses `parse_cell_code` for auto begin...end wrapping of multi-line cells.

Returns a `PDE.NotebookTopology{SessionsCell}` object.
"""
function compute_topology(notebook::Notebook)
    # First, analyze all cells
    for cell in values(notebook.cells)
        analyze_cell!(cell)
    end

    # Wrap cells for PDE
    sessions_cells = [SessionsCell(cell) for cell in values(notebook.cells)]

    # Create empty topology and update with our cells
    empty_topology = PDE.NotebookTopology{SessionsCell}()

    topology = PDE.updated_topology(
        empty_topology,
        sessions_cells,
        sessions_cells;
        get_code_str = c -> c.code,
        get_code_expr = c -> parse_cell_code(c.code),  # Use parse_cell_code for auto begin...end
        get_cell_disabled = c -> false
    )

    return topology
end

"""
    update_topology!(notebook::Notebook)
    update_topology!(notebook::Notebook, changed_cell_ids::Vector{UUID})

Update the notebook's dependency topology after cell changes.

If `changed_cell_ids` is provided, only those cells are re-analyzed (more efficient).
If not provided, all cells are re-analyzed.

This function:
1. Analyzes changed cells to extract references/definitions
2. Updates the PDE topology with new dependency information
3. Stores the result in `notebook.topology`

# Returns
The updated `NotebookTopology{SessionsCell}` object.

# Example
```julia
# After editing a cell
update_cell_code!(notebook, cell_id, "y = x * 2")
update_topology!(notebook, [cell_id])

# Or refresh all cells
update_topology!(notebook)
```
"""
function update_topology!(notebook::Notebook)
    # Analyze all cells and rebuild topology
    for cell in values(notebook.cells)
        analyze_cell!(cell)
    end

    sessions_cells = [SessionsCell(cell) for cell in values(notebook.cells)]

    if notebook.topology === nothing
        notebook.topology = PDE.NotebookTopology{SessionsCell}()
    end

    notebook.topology = PDE.updated_topology(
        notebook.topology,
        sessions_cells,  # changed cells = all cells
        sessions_cells;  # all cells
        get_code_str = c -> c.code,
        get_code_expr = c -> parse_cell_code(c.code),
        get_cell_disabled = c -> false
    )

    return notebook.topology
end

function update_topology!(notebook::Notebook, changed_cell_ids::Vector{UUID})
    # Only analyze changed cells
    for cell_id in changed_cell_ids
        cell = get_cell(notebook, cell_id)
        if cell !== nothing
            analyze_cell!(cell)
        end
    end

    # Get all cells for PDE
    all_cells = [SessionsCell(cell) for cell in values(notebook.cells)]

    # Get only changed cells for incremental update
    changed_cells = [SessionsCell(notebook.cells[id]) for id in changed_cell_ids
                     if haskey(notebook.cells, id)]

    if notebook.topology === nothing
        notebook.topology = PDE.NotebookTopology{SessionsCell}()
    end

    notebook.topology = PDE.updated_topology(
        notebook.topology,
        changed_cells,
        all_cells;
        get_code_str = c -> c.code,
        get_code_expr = c -> parse_cell_code(c.code),
        get_cell_disabled = c -> false
    )

    return notebook.topology
end

"""
    get_execution_order(notebook, changed_cells::Vector{UUID})

Given cells that changed, compute the full list of cells that need to run,
in topological order.

This function:
1. Ensures the topology is up-to-date (calls update_topology! if needed)
2. Finds all downstream cells that depend on the changed cells
3. Returns cells sorted in dependency order (upstream before downstream)

# Arguments
- `notebook`: The notebook containing cells
- `changed_cells`: UUIDs of cells that were modified

# Returns
A Vector of Cells in execution order (upstream cells first).

# Example
```julia
# After changing cell1, get all cells that need to re-run
order = get_execution_order(notebook, [cell1.id])
for cell in order
    execute_cell!(notebook, cell.id)
end
```
"""
function get_execution_order(notebook::Notebook, changed_cells::Vector{UUID})
    # Ensure topology is up-to-date
    if notebook.topology === nothing
        update_topology!(notebook)
    else
        # Update topology for changed cells
        update_topology!(notebook, changed_cells)
    end

    # Build dependency graph from analyzed cells
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
    # Sort by dependency depth (cells with no dependencies come first)
    function dependency_depth(cell_id::UUID, visited=Set{UUID}())
        if cell_id in visited
            return 0  # Cycle detected, return 0 to avoid infinite recursion
        end
        push!(visited, cell_id)

        if !haskey(notebook.cells, cell_id)
            return 0
        end

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

"""
    detect_and_mark_cycles!(notebook)

Check for circular dependencies and mark affected cells with CELL_ERROR state.

Returns (has_cycle::Bool, cycle_cells::Vector{UUID})

When a cycle is detected:
- All cells in the cycle are set to CELL_ERROR state
- Their output is set to a CellOutput with the cycle error message

# Example
```julia
has_cycle, cycle_ids = detect_and_mark_cycles!(notebook)
if has_cycle
    @warn "Circular dependency detected" cells=cycle_ids
end
```
"""
function detect_and_mark_cycles!(notebook::Notebook)
    found_cycle, cycle_ids = has_cycle(notebook)

    if found_cycle
        error_msg = "CircularDependencyError: This cell is part of a circular dependency cycle with cells: $(join([string(id)[1:8] for id in cycle_ids], ", "))..."

        for cell_id in cycle_ids
            cell = get_cell(notebook, cell_id)
            if cell !== nothing
                cell.state = CELL_ERROR
                # CellOutput signature: (value, mime, html, logs, error_logs)
                cell.output = CellOutput(
                    nothing,
                    "text/plain",
                    "<pre class=\"error\">$error_msg</pre>",
                    String[],
                    [error_msg]
                )
            end
        end
    end

    return (found_cycle, cycle_ids)
end

"""
    get_upstream_cells(notebook, cell_id)

Find all cells that the given cell depends on (directly or indirectly).

# Returns
Vector of upstream Cell objects in topological order (dependencies first).
"""
function get_upstream_cells(notebook::Notebook, cell_id::UUID)
    cell = get_cell(notebook, cell_id)
    if cell === nothing
        return Cell[]
    end

    # Ensure cells are analyzed
    if notebook.topology === nothing
        update_topology!(notebook)
    end

    # Build symbol -> definer map
    symbol_to_definer = Dict{Symbol, UUID}()
    for c in values(notebook.cells)
        for sym in union(c.definitions, c.funcdefs)
            symbol_to_definer[sym] = c.id
        end
    end

    # BFS to find all upstream cells
    upstream = Set{UUID}()
    queue = [cell_id]

    while !isempty(queue)
        current_id = popfirst!(queue)
        current = get_cell(notebook, current_id)
        if current === nothing
            continue
        end

        for ref in current.references
            if haskey(symbol_to_definer, ref)
                definer_id = symbol_to_definer[ref]
                if definer_id != current_id && !(definer_id in upstream)
                    push!(upstream, definer_id)
                    push!(queue, definer_id)
                end
            end
        end
    end

    # Sort by dependency depth
    cells = [notebook.cells[id] for id in upstream if haskey(notebook.cells, id)]

    # Simple depth calculation
    function depth(c)
        d = 0
        for ref in c.references
            if haskey(symbol_to_definer, ref)
                definer_id = symbol_to_definer[ref]
                if definer_id in upstream
                    d = max(d, depth(notebook.cells[definer_id]) + 1)
                end
            end
        end
        return d
    end

    sort!(cells, by=depth)
    return cells
end

"""
    get_dependency_info(notebook, cell_id)

Get detailed dependency information for a cell.

# Returns
A NamedTuple with:
- `upstream`: Vector of upstream cell IDs (cells this cell depends on)
- `downstream`: Vector of downstream cell IDs (cells that depend on this cell)
- `definitions`: Set of symbols this cell defines
- `references`: Set of symbols this cell references
- `unresolved`: Set of referenced symbols that no cell defines
"""
function get_dependency_info(notebook::Notebook, cell_id::UUID)
    cell = get_cell(notebook, cell_id)
    if cell === nothing
        return (
            upstream = UUID[],
            downstream = UUID[],
            definitions = Set{Symbol}(),
            references = Set{Symbol}(),
            unresolved = Set{Symbol}()
        )
    end

    # Ensure analyzed
    analyze_cell!(cell)

    # Build symbol -> definer map
    symbol_to_definer = Dict{Symbol, UUID}()
    for c in values(notebook.cells)
        analyze_cell!(c)
        for sym in union(c.definitions, c.funcdefs)
            symbol_to_definer[sym] = c.id
        end
    end

    # Find upstream cells
    upstream = UUID[]
    for ref in cell.references
        if haskey(symbol_to_definer, ref)
            definer_id = symbol_to_definer[ref]
            if definer_id != cell_id && !(definer_id in upstream)
                push!(upstream, definer_id)
            end
        end
    end

    # Find downstream cells
    downstream = UUID[]
    cell_defines = union(cell.definitions, cell.funcdefs)
    for c in values(notebook.cells)
        if c.id != cell_id
            for ref in c.references
                if ref in cell_defines && !(c.id in downstream)
                    push!(downstream, c.id)
                    break
                end
            end
        end
    end

    # Find unresolved references
    unresolved = Set{Symbol}()
    for ref in cell.references
        if !haskey(symbol_to_definer, ref)
            push!(unresolved, ref)
        end
    end

    return (
        upstream = upstream,
        downstream = downstream,
        definitions = cell.definitions,
        references = cell.references,
        unresolved = unresolved
    )
end
