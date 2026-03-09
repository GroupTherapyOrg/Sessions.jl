# Layer 1: Headless mode — Sessions.run() for non-interactive execution

"""
    Sessions.run(path::String; verbose=false) -> Notebook

Load and execute a notebook file headlessly (no TUI).
Returns the executed notebook with all cell outputs populated.
"""
function run(path::String; verbose::Bool=false)
    nb = load_notebook(path)
    run(nb; verbose)
end

"""
    Sessions.run(nb::Notebook; verbose=false) -> Notebook

Execute an already-loaded notebook headlessly.
Returns the notebook with all cell outputs populated.
"""
function run(nb::Notebook; verbose::Bool=false)
    ws = Workspace(; notebook_path=nb.path)

    if verbose
        println("Sessions.run: $(nb.path)")
        println("  Cells: $(length(nb))")
    end

    order = execution_order(nb)

    # Mark errable cells
    for (cell, err) in order.errable
        cell.state = cell_errored
        cell.output = CellOutput()
        cell.output.error = CapturedException(
            ErrorException("Reactivity error: $(typeof(err))"),
            backtrace()
        )
        if verbose
            println("  ERROR [$(cell.id)]: reactivity error")
        end
    end

    # Execute runnable cells in topological order
    for (i, cell) in enumerate(order.runnable)
        if verbose
            code_preview = first(cell.code, 40)
            code_preview = replace(code_preview, '\n' => "\\n")
            println("  [$i/$(length(order.runnable))] $(code_preview)")
        end

        execute_cell!(ws, cell)

        if verbose && cell.state == cell_errored
            println("    FAILED: $(cell.output.error)")
        end
    end

    if verbose
        n_done = count(c -> c.state == cell_done, values(nb.cells))
        n_err = count(c -> c.state == cell_errored, values(nb.cells))
        println("  Done: $n_done ok, $n_err errors")
    end

    save_session!(nb)
    nb
end
