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

# =============================================================================
# Smart Multi-line Cell Parsing (Auto begin...end)
# =============================================================================

"""
    parse_cell_code(code::String) -> Expr

Parse cell code, automatically wrapping multi-expression code in begin...end.
This is transparent to the user - they write multiple lines, we handle it.

# Behavior
- Single expression: Returns as-is
- Multiple top-level expressions: Wraps in begin...end block
- Incomplete expression: Tries wrapping to complete it
- Empty/whitespace: Returns nothing literal

# Examples
```julia
# Single expression - returned as-is
parse_cell_code("x = 1")  # => :(x = 1)

# Multiple expressions - auto-wrapped
parse_cell_code("x = 1\\ny = 2\\nx + y")  # => begin x = 1; y = 2; x + y end

# User never needs to write begin...end explicitly
```
"""
function parse_cell_code(code::String)
    stripped = strip(code)

    # Empty code
    if isempty(stripped)
        return :nothing
    end

    # Try parsing as single expression first
    expr = Base.Meta.parse(code, raise=false)

    # If it parsed cleanly as a single non-error expression, use it
    if !(expr isa Expr && expr.head == :incomplete)
        return expr
    end

    # Try parsing all expressions
    try
        full_parse = Base.Meta.parseall(code)

        if full_parse isa Expr && full_parse.head == :toplevel
            # Filter out LineNumberNode entries
            exprs = filter(e -> !(e isa LineNumberNode), full_parse.args)

            if length(exprs) == 0
                return :nothing
            elseif length(exprs) == 1
                return first(exprs)
            else
                # Multiple expressions - wrap in begin...end block
                # This makes all variables defined at module scope (not local)
                return Expr(:block, exprs...)
            end
        end

        return full_parse
    catch e
        # If parseall fails, try wrapping in begin...end
        wrapped = "begin\n$code\nend"
        try
            return Base.Meta.parse(wrapped)
        catch
            # Return the original error expression
            return expr
        end
    end
end

"""
    get_executable_code(code::String) -> String

Get the code string that should be executed, wrapping in begin...end if needed.
This is what gets sent to the worker for execution.
"""
function get_executable_code(code::String)
    stripped = strip(code)

    if isempty(stripped)
        return "nothing"
    end

    # Try parsing to see if it's multiple expressions
    try
        full_parse = Base.Meta.parseall(code)

        if full_parse isa Expr && full_parse.head == :toplevel
            exprs = filter(e -> !(e isa LineNumberNode), full_parse.args)

            if length(exprs) > 1
                # Multiple expressions - wrap in begin...end
                return "begin\n$code\nend"
            end
        end
    catch
        # If parsing fails, try wrapped version
        wrapped = "begin\n$code\nend"
        try
            Base.Meta.parse(wrapped)
            return wrapped
        catch
            # Return original, let execution show the error
        end
    end

    return code
end

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
