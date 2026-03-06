# Layer 1: Core types for Sessions.jl v2

"""Cell execution state."""
@enum CellState begin
    cell_idle      # Not yet executed
    cell_queued    # Waiting to run
    cell_running   # Currently executing
    cell_done      # Finished successfully
    cell_errored   # Finished with error
end

"""Captured output from a cell execution."""
mutable struct CellOutput
    result::Any                        # Return value of the cell
    stdout::String                     # Captured stdout
    error::Union{Nothing, CapturedException}  # Exception + backtrace if errored
    runtime_ns::UInt64                 # Execution time in nanoseconds
end

CellOutput() = CellOutput(nothing, "", nothing, UInt64(0))

"""A single notebook cell."""
mutable struct Cell
    id::UUID
    code::String
    output::CellOutput
    state::CellState
    folded::Bool    # Hidden/folded in UI (╟─ vs ╠═ in Pluto format)
end

function Cell(; id::UUID=uuid4(), code::String="", folded::Bool=false)
    Cell(id, code, CellOutput(), cell_idle, folded)
end

Cell(code::String) = Cell(; code)

"""A notebook: ordered collection of cells with a file path."""
mutable struct Notebook
    path::String
    cells::Dict{UUID, Cell}
    cell_order::Vector{UUID}
end

function Notebook(; path::String="Untitled.jl")
    Notebook(path, Dict{UUID, Cell}(), UUID[])
end

# --- Notebook cell operations ---

"""Add a cell to the end of the notebook."""
function add_cell!(nb::Notebook, cell::Cell)
    nb.cells[cell.id] = cell
    push!(nb.cell_order, cell.id)
    cell
end

"""Add a new cell with the given code to the end of the notebook."""
function add_cell!(nb::Notebook, code::String; folded::Bool=false)
    add_cell!(nb, Cell(; code, folded))
end

"""Insert a cell at a specific position (1-based index)."""
function insert_cell!(nb::Notebook, index::Int, cell::Cell)
    nb.cells[cell.id] = cell
    insert!(nb.cell_order, index, cell.id)
    cell
end

"""Remove a cell from the notebook by UUID. Returns the removed cell or nothing."""
function remove_cell!(nb::Notebook, id::UUID)
    cell = get(nb.cells, id, nothing)
    cell === nothing && return nothing
    delete!(nb.cells, id)
    filter!(!=(id), nb.cell_order)
    cell
end

"""Get a cell by UUID."""
get_cell(nb::Notebook, id::UUID) = get(nb.cells, id, nothing)

"""Get all cells in display order."""
function ordered_cells(nb::Notebook)
    [nb.cells[id] for id in nb.cell_order if haskey(nb.cells, id)]
end

"""Number of cells in the notebook."""
Base.length(nb::Notebook) = length(nb.cell_order)
