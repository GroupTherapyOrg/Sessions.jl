# Layer 1: Kernel — Cell execution with workspace isolation and output capture

"""
The Workspace holds all cell-evaluated state in a dedicated module.
Each notebook gets its own workspace module so variables don't leak.
"""
mutable struct Workspace
    mod::Module
    ns::Symbol
end

let workspace_counter = Ref(0)
    global function Workspace()
        workspace_counter[] += 1
        ns = Symbol("SessionsWorkspace_", workspace_counter[])
        mod = Module(ns)
        # Pre-populate the workspace with Base
        Core.eval(mod, :(using Base))
        Workspace(mod, ns)
    end
end

"""Execute a single cell in the workspace, capturing output and timing."""
function execute_cell!(workspace::Workspace, cell::Cell)
    cell.state = cell_running
    cell.output = CellOutput()

    result = nothing
    err = nothing
    captured_stdout = ""
    t_start = time_ns()

    try
        expr = Meta.parse("begin\n$(cell.code)\nend")
        # Use a Pipe for stdout capture (IOBuffer doesn't work with redirect_stdout)
        old_stdout = stdout
        rd, wr = redirect_stdout()
        try
            result = Base.eval(workspace.mod, expr)
        finally
            redirect_stdout(old_stdout)
            close(wr)
        end
        captured_stdout = String(read(rd))
    catch e
        err = CapturedException(e, catch_backtrace())
    end

    t_end = time_ns()

    cell.output.result = err === nothing ? result : nothing
    cell.output.stdout = captured_stdout
    cell.output.error = err
    cell.output.runtime_ns = t_end - t_start

    cell.state = err === nothing ? cell_done : cell_errored
    cell.output
end

"""
Execute a notebook reactively: analyze dependencies, sort topologically, run in order.
Returns the notebook with all cells updated.
"""
function execute_notebook!(nb::Notebook; workspace::Workspace=Workspace())
    order = execution_order(nb)

    # Mark errable cells
    for (cell, err) in order.errable
        cell.state = cell_errored
        cell.output = CellOutput()
        cell.output.error = CapturedException(
            ErrorException("Reactivity error: $(typeof(err))"),
            backtrace()
        )
    end

    # Execute runnable cells in topological order
    for cell in order.runnable
        execute_cell!(workspace, cell)
    end

    nb
end

"""
Re-execute only the cells affected by changes to `changed_cells`.
"""
function execute_changed!(nb::Notebook, changed_cells::Vector{Cell}; workspace::Workspace=Workspace())
    order = execution_order(nb, changed_cells)

    for (cell, err) in order.errable
        cell.state = cell_errored
        cell.output = CellOutput()
        cell.output.error = CapturedException(
            ErrorException("Reactivity error: $(typeof(err))"),
            backtrace()
        )
    end

    for cell in order.runnable
        execute_cell!(workspace, cell)
    end

    nb
end
