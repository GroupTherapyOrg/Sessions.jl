# Notebook.jl - Notebook container and operations
#
# A Notebook holds cells, manages execution order, and tracks file state.

using UUIDs
using OrderedCollections
import Malt

"""
    Notebook

A notebook containing cells and execution context.

# Fields
- `id::UUID`: Unique notebook identifier
- `path::Union{Nothing, String}`: File path (nothing if unsaved)
- `cells::OrderedDict{UUID, Cell}`: Cells by UUID
- `cell_order::Vector{UUID}`: Display order of cell IDs
- `topology`: PlutoDependencyExplorer topology for dependency tracking
- `worker::Union{Nothing, Malt.Worker}`: Malt.jl worker process for execution
- `modified::Bool`: Whether notebook has unsaved changes
- `project_toml::String`: Package environment Project.toml content
- `manifest_toml::String`: Package environment Manifest.toml content
- `title::String`: Notebook title (for display)
- `author::String`: Author name
- `created_at::Union{Nothing, Float64}`: Unix timestamp of creation
- `sessions_version::String`: Sessions.jl version that last saved this notebook
"""
mutable struct Notebook
    id::UUID
    path::Union{Nothing, String}

    cells::OrderedDict{UUID, Cell}
    cell_order::Vector{UUID}

    # Dependency topology (PlutoDependencyExplorer)
    # This is updated by update_topology!() after cell changes
    topology::Any  # PDE.NotebookTopology{SessionsCell} or nothing

    # Execution context
    worker::Union{Nothing, Malt.Worker}

    # State tracking
    modified::Bool

    # Package environment (embedded in notebook file)
    project_toml::String
    manifest_toml::String

    # Notebook metadata
    title::String
    author::String
    created_at::Union{Nothing, Float64}
    sessions_version::String
end

const SESSIONS_VERSION = "0.1.0"

"""
    Notebook(; path=nothing, title="", author="")

Create a new empty notebook.
"""
function Notebook(; path::Union{Nothing, String}=nothing, title::String="", author::String="")
    Notebook(
        uuid4(),
        path,
        OrderedDict{UUID, Cell}(),
        UUID[],
        nothing,  # topology - computed on demand by update_topology!()
        nothing,  # worker
        false,    # modified
        "",       # project_toml
        "",       # manifest_toml
        title,
        author,
        time(),   # created_at
        SESSIONS_VERSION
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
The worker is started with the same project environment as the main process
so that Sessions and its dependencies are available.
"""
function ensure_worker!(notebook::Notebook)
    if notebook.worker === nothing || !Malt.isrunning(notebook.worker)
        # Get the project path from the current LOAD_PATH
        # This ensures the worker has access to Sessions and all dependencies
        project_path = Base.active_project()

        # Create worker with the same project environment
        if project_path !== nothing
            notebook.worker = Malt.Worker(exeflags=["--project=$(project_path)"])
        else
            notebook.worker = Malt.Worker()
        end

        # Initialize worker with common setup
        # Sessions is loaded to make @bind macro available
        Malt.remote_eval_wait(notebook.worker, quote
            using InteractiveUtils
            using Sessions
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
        "title" => notebook.title,
        "author" => notebook.author,
        "created_at" => notebook.created_at,
        "sessions_version" => notebook.sessions_version,
        "cells" => [cell_to_dict(notebook.cells[id]) for id in notebook.cell_order if haskey(notebook.cells, id)],
        "cell_order" => [string(id) for id in notebook.cell_order]
    )
end
