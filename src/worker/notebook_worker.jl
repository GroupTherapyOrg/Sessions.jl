# notebook_worker.jl — Worker process per notebook (Pluto-style)
#
# Uses Malt.jl (like Pluto) to run each notebook in a separate process.
# The key insight from Pluto: send EXPRESSIONS to eval, never serialize
# function references. Use include(path) as an expression, not
# remotecall(include, pid, path).

import Malt

# Boot script content path (worker includes this file)
const _BOOT_SCRIPT_PATH = joinpath(@__DIR__, "boot.jl")

"""A Malt worker process for a single notebook."""
mutable struct NotebookWorker
    worker::Malt.Worker
    notebook_path::String
    booted::Bool
end

"""Create a new notebook worker process."""
function NotebookWorker(; notebook_path::String="")
    w = Malt.Worker()
    nw = NotebookWorker(w, notebook_path, false)
    _boot_worker!(nw)
    nw
end

"""Boot the worker — Pluto-style: send expressions, never function references."""
function _boot_worker!(nw::NotebookWorker)
    # Write boot code to a temp file (worker process needs a file path)
    boot_file = tempname() * "_sessions_boot.jl"
    write(boot_file, read(_BOOT_SCRIPT_PATH, String))

    # Pluto pattern: include as an EXPRESSION, not a function call.
    # This becomes Core.eval(Main, :(include("/path/to/boot.jl")))
    # which works because `include` is resolved as a symbol in Main.
    Malt.remote_eval_wait(nw.worker, :(include($(boot_file))))

    rm(boot_file; force=true)

    # Create workspace in the worker (also as expression)
    nb_path = nw.notebook_path
    Malt.remote_eval_wait(nw.worker, :(_workspace = _create_workspace(; notebook_path=$nb_path)))

    nw.booted = true
    println("[Worker] Booted for $(isempty(nw.notebook_path) ? "Untitled" : basename(nw.notebook_path))")
end

"""Execute a cell's code in the worker and return a CellOutput."""
function remote_execute_cell!(nw::NotebookWorker, cell::Cell)
    !nw.booted && error("Worker not booted")

    code = cell.code
    cell.state = cell_running
    cell._exec_start_time = time()

    # Execute in worker — send code as expression, get back NamedTuple
    worker_output = try
        Malt.remote_eval_fetch(nw.worker, :(_worker_execute(_workspace, $(code))))
    catch e
        @warn "[Worker] Execution failed" exception=e
        (output_type=:error,
         text_representation=sprint(showerror, e),
         stdout_text="",
         runtime_ns=UInt64(0),
         error_text=sprint(showerror, e),
         image_bytes=nothing)
    end

    # Map worker output back to CellOutput
    cell.output = CellOutput()
    cell.output.output_type = worker_output.output_type
    cell.output.text_representation = worker_output.text_representation
    cell.output.stdout = worker_output.stdout_text
    cell.output.runtime_ns = worker_output.runtime_ns
    cell.output.image_data = worker_output.image_bytes

    if worker_output.output_type == :error
        cell.state = cell_errored
        cell.output.error = CapturedException(
            ErrorException(worker_output.error_text), backtrace())
    else
        cell.state = cell_done
    end

    mark_executed!(cell)
    cell.output
end

"""Stop the worker process."""
function stop_worker!(nw::NotebookWorker)
    if nw.booted
        try Malt.stop(nw.worker) catch; end
        nw.booted = false
        println("[Worker] Stopped")
    end
end

"""Restart the worker (kill + reboot)."""
function restart_worker!(nw::NotebookWorker)
    stop_worker!(nw)
    nw.worker = Malt.Worker()
    _boot_worker!(nw)
end

"""Check if worker is alive."""
function is_worker_alive(nw::NotebookWorker)::Bool
    nw.booted && Malt.isrunning(nw.worker)
end
