# Notebook.jl - Notebook container and operations
#
# A Notebook holds cells, manages execution order, and tracks file state.

using UUIDs
using OrderedCollections
import Malt

"""
A notebook containing cells and execution context.

# Fields
- `id`: Unique notebook identifier
- `path`: File path (nothing if unsaved)
- `cells`: OrderedDict of cells by UUID
- `cell_order`: Display order of cell IDs
- `worker`: Malt.jl worker process for execution
- `modified`: Whether notebook has unsaved changes
- `project_toml`: Package environment Project.toml content
- `manifest_toml`: Package environment Manifest.toml content
"""
mutable struct Notebook
    id::UUID
    path::Union{Nothing, String}

    cells::OrderedDict{UUID, Cell}
    cell_order::Vector{UUID}

    # Execution context
    worker::Union{Nothing, Malt.Worker}

    # State tracking
    modified::Bool

    # Package environment (embedded in notebook file)
    project_toml::String
    manifest_toml::String
end

"""
    Notebook(; path=nothing)

Create a new empty notebook.
"""
function Notebook(; path::Union{Nothing, String}=nothing)
    Notebook(
        uuid4(),
        path,
        OrderedDict{UUID, Cell}(),
        UUID[],
        nothing,
        false,
        "",
        ""
    )
end

# =============================================================================
# Cell Management
# =============================================================================

"""
    add_cell!(notebook, cell; after=nothing)

Add a cell to the notebook. If `after` is specified, insert after that cell ID.
"""
function add_cell!(notebook::Notebook, cell::Cell; after::Union{Nothing, UUID}=nothing)
    notebook.cells[cell.id] = cell

    if after === nothing || !(after in notebook.cell_order)
        push!(notebook.cell_order, cell.id)
    else
        idx = findfirst(==(after), notebook.cell_order)
        insert!(notebook.cell_order, idx + 1, cell.id)
    end

    notebook.modified = true
    return cell
end

"""
    add_cell!(notebook; code="", after=nothing)

Create and add a new cell with optional code.
"""
function add_cell!(notebook::Notebook; code::String="", after::Union{Nothing, UUID}=nothing)
    cell = Cell(; code=code)
    add_cell!(notebook, cell; after=after)
end

"""
    delete_cell!(notebook, cell_id)

Remove a cell from the notebook.
"""
function delete_cell!(notebook::Notebook, cell_id::UUID)
    if haskey(notebook.cells, cell_id)
        delete!(notebook.cells, cell_id)
        filter!(!=(cell_id), notebook.cell_order)
        notebook.modified = true
        return true
    end
    return false
end

"""
    move_cell!(notebook, cell_id, new_index)

Move a cell to a new position in the display order.
"""
function move_cell!(notebook::Notebook, cell_id::UUID, new_index::Int)
    if !(cell_id in notebook.cell_order)
        return false
    end

    filter!(!=(cell_id), notebook.cell_order)
    new_index = clamp(new_index, 1, length(notebook.cell_order) + 1)
    insert!(notebook.cell_order, new_index, cell_id)
    notebook.modified = true
    return true
end

"""
    get_cell(notebook, cell_id)

Get a cell by ID, or nothing if not found.
"""
function get_cell(notebook::Notebook, cell_id::UUID)
    get(notebook.cells, cell_id, nothing)
end

"""
    update_cell_code!(notebook, cell_id, code)

Update a cell's code content.
"""
function update_cell_code!(notebook::Notebook, cell_id::UUID, code::String)
    cell = get_cell(notebook, cell_id)
    if cell !== nothing
        cell.code = code
        notebook.modified = true
        return true
    end
    return false
end

# =============================================================================
# Iteration & Access
# =============================================================================

"""
Get cells in display order.
"""
function cells_in_order(notebook::Notebook)
    [notebook.cells[id] for id in notebook.cell_order if haskey(notebook.cells, id)]
end

"""
Number of cells in the notebook.
"""
Base.length(notebook::Notebook) = length(notebook.cells)

"""
Iterate over cells in display order.
"""
function Base.iterate(notebook::Notebook, state=1)
    if state > length(notebook.cell_order)
        return nothing
    end
    cell_id = notebook.cell_order[state]
    cell = get(notebook.cells, cell_id, nothing)
    if cell === nothing
        return iterate(notebook, state + 1)
    end
    return (cell, state + 1)
end

# =============================================================================
# Worker Management
# =============================================================================

"""
    ensure_worker!(notebook)

Ensure the notebook has an active worker process.
"""
function ensure_worker!(notebook::Notebook)
    if notebook.worker === nothing || !Malt.isrunning(notebook.worker)
        notebook.worker = Malt.Worker()
        # Initialize worker with common setup
        Malt.remote_eval_wait(notebook.worker, quote
            using InteractiveUtils
        end)
    end
    return notebook.worker
end

"""
    shutdown_worker!(notebook)

Shutdown the notebook's worker process.
"""
function shutdown_worker!(notebook::Notebook)
    if notebook.worker !== nothing && Malt.isrunning(notebook.worker)
        Malt.stop(notebook.worker)
    end
    notebook.worker = nothing
end

"""
    interrupt_worker!(notebook)

Interrupt any running computation in the worker.
"""
function interrupt_worker!(notebook::Notebook)
    if notebook.worker !== nothing && Malt.isrunning(notebook.worker)
        Malt.interrupt(notebook.worker)
    end
end

# =============================================================================
# Serialization
# =============================================================================

"""
Convert notebook to JSON-serializable dictionary.
"""
function notebook_to_dict(notebook::Notebook)
    Dict{String, Any}(
        "id" => string(notebook.id),
        "path" => notebook.path,
        "modified" => notebook.modified,
        "cells" => [cell_to_dict(notebook.cells[id]) for id in notebook.cell_order if haskey(notebook.cells, id)],
        "cell_order" => [string(id) for id in notebook.cell_order]
    )
end
