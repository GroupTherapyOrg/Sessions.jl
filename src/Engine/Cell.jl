# Cell.jl - Core cell data structure
#
# A Cell is the fundamental unit of a notebook, containing code and its execution state.

using UUIDs

"""
Cell execution states.
"""
@enum CellState begin
    CELL_IDLE       # Not running, no pending changes
    CELL_QUEUED     # Waiting to run (dependency changed)
    CELL_RUNNING    # Currently executing
    CELL_ERROR      # Execution failed
end

"""
Output from cell execution.
"""
struct CellOutput
    value::Any                      # The actual result value
    mime::String                    # MIME type for display (e.g., "text/plain", "text/html")
    html::String                    # Pre-rendered HTML for display
    logs::Vector{String}            # Captured stdout lines
    error_logs::Vector{String}      # Captured stderr lines
end

CellOutput() = CellOutput(nothing, "text/plain", "", String[], String[])

"""
A notebook cell containing code and execution state.

# Fields
- `id`: Unique identifier
- `code`: Julia source code
- `output`: Result of last execution
- `references`: Variables this cell reads (from ExpressionExplorer)
- `definitions`: Variables this cell defines (from ExpressionExplorer)
- `funcdefs`: Functions this cell defines
- `state`: Current execution state
- `runtime_ms`: Last execution time in milliseconds
- `folded`: Whether the cell is collapsed in UI
- `disabled`: Whether the cell is excluded from execution
"""
mutable struct Cell
    id::UUID
    code::String
    output::Union{Nothing, CellOutput}

    # Reactivity metadata (populated by ExpressionExplorer)
    references::Set{Symbol}
    definitions::Set{Symbol}
    funcdefs::Set{Symbol}

    # Execution state
    state::CellState
    runtime_ms::Union{Nothing, Float64}

    # UI state
    folded::Bool
    disabled::Bool
end

"""
    Cell(; code="", id=uuid4())

Create a new cell with optional code and ID.
"""
function Cell(; code::String="", id::UUID=uuid4())
    Cell(
        id,
        code,
        nothing,
        Set{Symbol}(),
        Set{Symbol}(),
        Set{Symbol}(),
        CELL_IDLE,
        nothing,
        false,
        false
    )
end

"""
    Cell(code::String)

Create a new cell with the given code.
"""
Cell(code::String) = Cell(; code=code)

# Convenience accessors
is_idle(cell::Cell) = cell.state == CELL_IDLE
is_queued(cell::Cell) = cell.state == CELL_QUEUED
is_running(cell::Cell) = cell.state == CELL_RUNNING
is_error(cell::Cell) = cell.state == CELL_ERROR

has_output(cell::Cell) = cell.output !== nothing
has_error(cell::Cell) = cell.state == CELL_ERROR

"""
Convert cell to JSON-serializable dictionary.
"""
function cell_to_dict(cell::Cell)
    Dict{String, Any}(
        "id" => string(cell.id),
        "code" => cell.code,
        "state" => string(cell.state),
        "runtime_ms" => cell.runtime_ms,
        "folded" => cell.folded,
        "disabled" => cell.disabled,
        "output" => cell.output === nothing ? nothing : Dict(
            "mime" => cell.output.mime,
            "html" => cell.output.html,
            "logs" => cell.output.logs,
            "error_logs" => cell.output.error_logs
        ),
        "references" => [string(s) for s in cell.references],
        "definitions" => [string(s) for s in cell.definitions]
    )
end
