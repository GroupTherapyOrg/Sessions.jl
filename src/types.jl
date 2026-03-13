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
    result::Any                        # Return value of the cell (actual Julia object)
    stdout::String                     # Captured stdout
    error::Union{Nothing, CapturedException}  # Exception + backtrace if errored
    runtime_ns::UInt64                 # Execution time in nanoseconds
    output_type::Symbol                # :text, :nothing, :error, :markdown, :dataframe, :image_png
    text_representation::String        # Fallback text rendering for any output type
    image_data::Union{Nothing, Vector{UInt8}}  # PNG bytes for :image_png output (not serialized)
end

CellOutput() = CellOutput(nothing, "", nothing, UInt64(0), :nothing, "", nothing)

"""A single notebook cell."""
mutable struct Cell
    id::UUID
    code::String
    output::CellOutput
    state::CellState
    folded::Bool              # Hidden/folded in UI (╟─ vs ╠═ in Pluto format)
    disabled::Bool            # Disabled cells are skipped during execution
    produced_by_hash::String  # Hash of source code that produced the current output ("" = never executed)
    _exec_start_time::Float64 # monotonic time() when execution started (for stuck-cell detection)
end

function Cell(; id::UUID=uuid4(), code::String="", folded::Bool=false, disabled::Bool=false)
    Cell(id, code, CellOutput(), cell_idle, folded, disabled, "", 0.0)
end

Cell(code::String) = Cell(; code)

"""A notebook: ordered collection of cells with a file path."""
mutable struct Notebook
    path::String
    cells::Dict{UUID, Cell}
    cell_order::Vector{UUID}
    _topology::Any       # cached NotebookTopology (or nothing)
    _topo_cells::Any     # cached SessionCell wrappers (or nothing)
end

function Notebook(; path::String="Untitled.jl")
    Notebook(path, Dict{UUID, Cell}(), UUID[], nothing, nothing)
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

"""Swap cell at `idx` with the one above it. Returns true if swapped."""
function swap_cell_up!(nb::Notebook, idx::Int)
    (idx <= 1 || idx > length(nb.cell_order)) && return false
    nb.cell_order[idx], nb.cell_order[idx-1] = nb.cell_order[idx-1], nb.cell_order[idx]
    true
end

"""Swap cell at `idx` with the one below it. Returns true if swapped."""
function swap_cell_down!(nb::Notebook, idx::Int)
    (idx < 1 || idx >= length(nb.cell_order)) && return false
    nb.cell_order[idx], nb.cell_order[idx+1] = nb.cell_order[idx+1], nb.cell_order[idx]
    true
end

# --- Stale detection ---

"""Deterministic hash of a cell's source code."""
source_hash(cell::Cell) = string(hash(strip(cell.code)), base=16)

"""Check if a cell has never been executed."""
is_never_run(cell::Cell) = cell.produced_by_hash == ""

"""Check if a cell is stale (source changed since last execution)."""
function is_stale(cell::Cell)
    is_never_run(cell) && return false  # never-run is a separate state
    source_hash(cell) != cell.produced_by_hash
end

"""Get all stale cells in the notebook (source changed since last execution)."""
function stale_cells(nb::Notebook)
    [nb.cells[id] for id in nb.cell_order if haskey(nb.cells, id) && is_stale(nb.cells[id])]
end

"""Get all never-run cells in the notebook."""
function never_run_cells(nb::Notebook)
    [nb.cells[id] for id in nb.cell_order if haskey(nb.cells, id) && is_never_run(nb.cells[id])]
end

"""Mark a cell as executed (update produced_by_hash to match current source)."""
function mark_executed!(cell::Cell)
    cell.produced_by_hash = source_hash(cell)
    cell
end
