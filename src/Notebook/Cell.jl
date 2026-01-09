# =============================================================================
# Cell Data Structure
# =============================================================================

"""
Cell status during execution lifecycle.
"""
@enum CellStatus begin
    IDLE        # Not running
    QUEUED      # Waiting to execute
    RUNNING     # Currently executing
    COMPLETED   # Finished successfully
    ERRORED     # Finished with error
end

"""
    Cell

A single notebook cell containing code and execution state.
"""
mutable struct Cell
    id::UUID
    code::String
    output::Any
    stdout::String
    stderr::String
    status::CellStatus
    error_msg::String
    execution_count::Int
end

"""
    Cell(code::String="")

Create a new cell with the given code.
"""
function Cell(code::String="")
    Cell(uuid4(), code, nothing, "", "", IDLE, "", 0)
end

"""
    Cell(id::UUID, code::String)

Create a cell with a specific ID.
"""
function Cell(id::UUID, code::String)
    Cell(id, code, nothing, "", "", IDLE, "", 0)
end

# Convert Cell to Dict for JSON serialization
function Base.Dict(cell::Cell)
    Dict(
        "id" => string(cell.id),
        "code" => cell.code,
        "output" => cell.output === nothing ? nothing : repr(cell.output),
        "stdout" => cell.stdout,
        "stderr" => cell.stderr,
        "status" => string(cell.status),
        "error_msg" => cell.error_msg,
        "execution_count" => cell.execution_count
    )
end
