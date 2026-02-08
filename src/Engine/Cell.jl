# Cell.jl - Core cell data structure
#
# A Cell is the fundamental unit of a notebook, containing code and its execution state.

using UUIDs

"""
    CellState

Cell execution states.

- `CELL_IDLE`: Not running, no pending changes
- `CELL_QUEUED`: Waiting to run (dependency changed)
- `CELL_RUNNING`: Currently executing
- `CELL_ERROR`: Execution failed
- `CELL_STALE`: Upstream changed but cell hasn't been re-run yet
"""
@enum CellState begin
    CELL_IDLE       # Not running, no pending changes
    CELL_QUEUED     # Waiting to run (dependency changed)
    CELL_RUNNING    # Currently executing
    CELL_ERROR      # Execution failed
    CELL_STALE      # Upstream changed, needs re-run
end

"""
    CellType

Cell content type — determines rendering and execution behavior.

- `:code`: Julia code cell (default)
- `:markdown`: Markdown content cell (rendered as HTML, not executed)
"""
const CellType = Symbol  # :code or :markdown

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
    Cell

A notebook cell containing code and execution state.

# Fields
- `id::UUID`: Unique identifier
- `code::String`: Julia source code
- `output::Union{Nothing, CellOutput}`: Result of last execution
- `references::Set{Symbol}`: Variables this cell reads (from ExpressionExplorer)
- `definitions::Set{Symbol}`: Variables this cell defines (from ExpressionExplorer)
- `funcdefs::Set{Symbol}`: Functions this cell defines
- `state::CellState`: Current execution state
- `runtime_ms::Union{Nothing, Float64}`: Last execution time in milliseconds
- `cell_type::Symbol`: `:code` or `:markdown`
- `last_run_at::Union{Nothing, Float64}`: Unix timestamp of last execution
- `folded::Bool`: Whether the cell is collapsed in UI
- `disabled::Bool`: Whether the cell is excluded from execution
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
    last_run_at::Union{Nothing, Float64}

    # Cell metadata
    cell_type::Symbol  # :code or :markdown

    # UI state
    folded::Bool
    disabled::Bool
end

"""
    Cell(; code="", id=uuid4(), cell_type=:code)

Create a new cell with optional code, ID, and type.
"""
function Cell(; code::String="", id::UUID=uuid4(), cell_type::Symbol=:code)
    Cell(
        id,
        code,
        nothing,
        Set{Symbol}(),
        Set{Symbol}(),
        Set{Symbol}(),
        CELL_IDLE,
        nothing,
        nothing,
        cell_type,
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
is_stale(cell::Cell) = cell.state == CELL_STALE

has_output(cell::Cell) = cell.output !== nothing
has_error(cell::Cell) = cell.state == CELL_ERROR
is_markdown(cell::Cell) = cell.cell_type == :markdown
is_code(cell::Cell) = cell.cell_type == :code

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
    # Check for :incomplete (incomplete expression) or :error (e.g., multiple expressions)
    if !(expr isa Expr && (expr.head == :incomplete || expr.head == :error))
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
    cell_to_dict(cell::Cell) -> Dict{String, Any}

Convert cell to JSON-serializable dictionary for WebSocket state sync.
"""
function cell_to_dict(cell::Cell)
    Dict{String, Any}(
        "id" => string(cell.id),
        "code" => cell.code,
        "state" => string(cell.state),
        "cell_type" => string(cell.cell_type),
        "runtime_ms" => cell.runtime_ms,
        "last_run_at" => cell.last_run_at,
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
