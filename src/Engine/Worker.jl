# Worker.jl - Sandboxed code execution using Malt.jl
#
# Each notebook gets its own worker process for isolated execution.

import Malt
using UUIDs

"""
Result of executing code in a worker.
"""
struct ExecutionResult
    success::Bool
    value::Any
    output_type::Type
    stdout::String
    stderr::String
    error::Union{Nothing, String}
    stacktrace::Union{Nothing, String}
    runtime_ms::Float64
end

"""
    execute_code(worker::Malt.Worker, code::String) -> ExecutionResult

Execute Julia code in the worker process and capture all output.
"""
function execute_code(worker::Malt.Worker, code::String)
    start_time = time()

    result = Malt.remote_eval_fetch(worker, quote
        local _result_value = nothing
        local _result_type = Nothing
        local _error_msg = nothing
        local _stacktrace = nothing
        local _success = true

        try
            # Parse and evaluate (skip stdout/stderr capture for now)
            local expr = Meta.parse($code)
            _result_value = Core.eval(Main, expr)
            _result_type = typeof(_result_value)
        catch e
            _success = false
            _error_msg = sprint(showerror, e)
            _stacktrace = sprint(Base.show_backtrace, catch_backtrace())
        end

        # Return all captured data
        (
            success = _success,
            value = _success ? repr(_result_value) : nothing,
            value_type = string(_result_type),
            stdout = "",  # TODO: Implement proper stdout capture
            stderr = "",  # TODO: Implement proper stderr capture
            error = _error_msg,
            stacktrace = _stacktrace
        )
    end)

    runtime_ms = (time() - start_time) * 1000

    return ExecutionResult(
        result.success,
        result.value,
        Any,  # We lose the actual type, but have the string representation
        result.stdout,
        result.stderr,
        result.error,
        result.stacktrace,
        runtime_ms
    )
end

"""
    execute_cell!(notebook::Notebook, cell::Cell) -> ExecutionResult

Execute a cell in the notebook's worker and update the cell state.
"""
function execute_cell!(notebook::Notebook, cell::Cell)
    # Ensure worker exists
    worker = ensure_worker!(notebook)

    # Update state to running
    cell.state = CELL_RUNNING

    # Execute
    result = execute_code(worker, cell.code)

    # Update cell with results
    cell.runtime_ms = result.runtime_ms

    if result.success
        cell.state = CELL_IDLE
        cell.output = CellOutput(
            result.value,
            "text/plain",  # TODO: Detect MIME type
            escape_html(string(result.value)),
            split(result.stdout, '\n', keepempty=false),
            split(result.stderr, '\n', keepempty=false)
        )
    else
        cell.state = CELL_ERROR
        error_html = """<div class="error">
            <div class="error-message">$(escape_html(result.error))</div>
            <pre class="stacktrace">$(escape_html(result.stacktrace === nothing ? "" : result.stacktrace))</pre>
        </div>"""
        cell.output = CellOutput(
            nothing,
            "text/html",
            error_html,
            split(result.stdout, '\n', keepempty=false),
            split(result.stderr, '\n', keepempty=false)
        )
    end

    return result
end

"""
    execute_reactive!(notebook::Notebook, cell_id::UUID) -> Vector{ExecutionResult}

Execute a cell and all its downstream dependencies in order.
"""
function execute_reactive!(notebook::Notebook, cell_id::UUID)
    # Get cells to run in order
    cells_to_run = get_execution_order(notebook, [cell_id])

    # Mark all as queued
    for cell in cells_to_run
        cell.state = CELL_QUEUED
    end

    # Execute in order
    results = ExecutionResult[]
    for cell in cells_to_run
        result = execute_cell!(notebook, cell)
        push!(results, result)

        # If error, stop execution (downstream cells remain queued)
        if !result.success
            break
        end
    end

    return results
end

"""
    run_all!(notebook::Notebook) -> Vector{ExecutionResult}

Execute all cells in dependency order.
"""
function run_all!(notebook::Notebook)
    cells_to_run = get_all_execution_order(notebook)

    # Mark all as queued
    for cell in cells_to_run
        cell.state = CELL_QUEUED
    end

    # Execute in order
    results = ExecutionResult[]
    for cell in cells_to_run
        result = execute_cell!(notebook, cell)
        push!(results, result)
    end

    return results
end

# Note: escape_html is defined in Output.jl
