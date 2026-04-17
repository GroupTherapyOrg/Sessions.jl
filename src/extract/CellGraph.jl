# CellGraph.jl — classify a notebook's cells for extraction
#
# Three buckets, derived from PlutoDependencyExplorer + a bond scan:
#   :bond     — cell defines a `@bind name BoundXxx(...)` (or directly
#                returns one). Becomes a widget @island in the output.
#   :reactive — cell transitively depends on at least one bond. Re-runs
#                client-side (WASM @island) when an upstream bond changes.
#   :static   — everything else. Output frozen at extract time.
#
# The classification is purely on cell *content* — runtime success isn't
# considered here. The static rendering / WASM compile stages handle
# their own failures separately.

import PlutoDependencyExplorer as PDE

# CellClass + ExtractionPlan structs live in extract/Types.jl,
# included before this file so all stage modules can refer to them
# without ordering pain.

"""
    classify_cells(nb::Notebook) -> Vector{CellClass}

Walk every cell in document order, classify each. The notebook's
topology MUST be up to date; call `update_topology!(nb)` first.
"""
function classify_cells(nb::Notebook)::Vector{CellClass}
    nb.topology === nothing && error("classify_cells: topology not built — call update_topology!(nb) first")
    cells = ordered_cells(nb)

    # Pass 1: find bond cells. A bond cell either:
    #   (a) Top-level @bind macro:    `@bind n BoundSlider(2:30)`
    #   (b) Direct widget assignment: `n = BoundSlider(2:30)` (rare)
    # We detect (a) by scanning the parsed AST for `@bind name expr`.
    bond_for_cell = Dict{Cell, Symbol}()           # cell → bound symbol
    cell_for_bond = Dict{Symbol, Cell}()           # bound sym → defining cell
    for c in cells
        bn = _detect_bind_name(c.code)
        if bn !== nothing
            bond_for_cell[c] = bn
            cell_for_bond[bn] = c
        end
    end

    # Pass 2: for every other cell, walk its references through the
    # topology to find which bonds (if any) it transitively depends on.
    upstream_for_cell = Dict{Cell, Set{Symbol}}()
    for c in cells
        haskey(bond_for_cell, c) && continue
        upstream_for_cell[c] = _upstream_bonds(nb, c, cell_for_bond)
    end

    # Pass 3: build the typed result vector in original document order.
    result = CellClass[]
    for c in cells
        if haskey(bond_for_cell, c)
            push!(result, CellClass(c, :bond, bond_for_cell[c], Set{Symbol}()))
        else
            up = get(upstream_for_cell, c, Set{Symbol}())
            kind = isempty(up) ? :static : :reactive
            push!(result, CellClass(c, kind, nothing, up))
        end
    end
    return result
end

# ─── Bond detection ────────────────────────────────────────────────────

"""
    _detect_bind_name(code::String) -> Union{Symbol, Nothing}

If `code` is a single `@bind name expr` macro call (the canonical bond
form) return `name`; otherwise `nothing`. Tolerant to surrounding
comments and `begin … end`. We deliberately don't try to recognise
exotic patterns — those become `:reactive` or `:static` and the
extraction either still works or fails loudly downstream.
"""
function _detect_bind_name(code::AbstractString)::Union{Symbol, Nothing}
    code = strip(code)
    isempty(code) && return nothing
    expr = try
        Base.Meta.parse("begin\n$(code)\nend")
    catch
        return nothing
    end
    return _scan_bind(expr)
end

function _scan_bind(expr)
    if expr isa Expr
        if expr.head === :macrocall && length(expr.args) >= 3 &&
           (expr.args[1] === Symbol("@bind") || expr.args[1] === GlobalRef(SessionsUI, Symbol("@bind")))
            target = expr.args[3]
            target isa Symbol && return target
        end
        for a in expr.args
            r = _scan_bind(a)
            r === nothing || return r
        end
    end
    return nothing
end

# ─── Upstream bond scan ────────────────────────────────────────────────

"""
    _upstream_bonds(nb, cell, cell_for_bond) -> Set{Symbol}

Walk the topology backwards from `cell` and collect every bond name
the cell transitively depends on. Uses PDE's predecessors map: for
every reference of `cell`, find which other cell `defines` it, recurse.
"""
function _upstream_bonds(nb::Notebook, cell::Cell, cell_for_bond::Dict{Symbol,Cell})::Set{Symbol}
    bonds = Set{Symbol}()
    visited = Set{Cell}()
    _collect_upstream_bonds!(bonds, nb, cell, cell_for_bond, visited)
    return bonds
end

function _collect_upstream_bonds!(
    bonds::Set{Symbol},
    nb::Notebook,
    cell::Cell,
    cell_for_bond::Dict{Symbol, Cell},
    visited::Set{Cell},
)
    cell in visited && return
    push!(visited, cell)
    topo = nb.topology
    topo === nothing && return
    sc = SessionCell(cell)
    nodes = topo.nodes
    haskey(nodes, sc) || return
    refs = nodes[sc].references
    # For each referenced symbol, find which (if any) cell defines it.
    for sym in refs
        if haskey(cell_for_bond, sym)
            push!(bonds, sym)
            # Don't recurse through the bond cell itself — its own deps
            # don't matter, we already counted it.
            continue
        end
        # Find the cell defining this symbol (if any) and recurse.
        for (other_sc, other_node) in nodes
            other_sc.cell === cell && continue
            if sym in other_node.definitions || sym in other_node.funcdefs_without_signatures
                _collect_upstream_bonds!(bonds, nb, other_sc.cell, cell_for_bond, visited)
                break
            end
        end
    end
end
