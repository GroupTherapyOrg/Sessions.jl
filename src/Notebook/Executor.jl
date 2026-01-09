# =============================================================================
# Cell Executor
# =============================================================================

"""
    Executor

Manages code execution in an isolated module.
"""
mutable struct Executor
    workspace::Module
    execution_count::Int
end

"""
    Executor()

Create a new executor with a fresh workspace.
"""
function Executor()
    workspace = Module(:SessionsWorkspace)
    Executor(workspace, 0)
end

"""
    execute(exec::Executor, code::String) -> NamedTuple

Execute code and return result with captured output.
"""
function execute(exec::Executor, code::String)
    exec.execution_count += 1

    stdout_buffer = IOBuffer()
    stderr_buffer = IOBuffer()

    result = try
        expr = Meta.parse("begin\n$code\nend")

        # Redirect stdout/stderr during execution
        old_stdout = stdout
        old_stderr = stderr
        rd_out, wr_out = redirect_stdout()
        rd_err, wr_err = redirect_stderr()

        value = nothing
        try
            value = Base.eval(exec.workspace, expr)
        finally
            redirect_stdout(old_stdout)
            redirect_stderr(old_stderr)
            close(wr_out)
            close(wr_err)
            write(stdout_buffer, read(rd_out, String))
            write(stderr_buffer, read(rd_err, String))
        end

        (
            success = true,
            value = value,
            stdout = String(take!(stdout_buffer)),
            stderr = String(take!(stderr_buffer)),
            error_msg = ""
        )
    catch e
        (
            success = false,
            value = nothing,
            stdout = String(take!(stdout_buffer)),
            stderr = String(take!(stderr_buffer)),
            error_msg = sprint(showerror, e)
        )
    end

    result
end

"""
    execute_cell!(exec::Executor, cell::Cell) -> NamedTuple

Execute a cell and update its state.
"""
function execute_cell!(exec::Executor, cell::Cell)
    cell.status = RUNNING

    result = execute(exec, cell.code)

    if result.success
        cell.status = COMPLETED
        cell.output = result.value
    else
        cell.status = ERRORED
        cell.output = nothing
    end

    cell.stdout = result.stdout
    cell.stderr = result.stderr
    cell.error_msg = result.error_msg
    cell.execution_count = exec.execution_count

    result
end

"""
    restart!(exec::Executor)

Restart the executor, clearing all state.
"""
function restart!(exec::Executor)
    exec.workspace = Module(:SessionsWorkspace)
    exec.execution_count = 0
end

"""
    shutdown!(exec::Executor)

Shutdown the executor.
"""
function shutdown!(exec::Executor)
    # Nothing special needed for module-based executor
end
