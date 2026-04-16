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
    # Find the notebook's project environment (walk up to find Project.toml)
    proj_dir = _find_notebook_project(notebook_path)
    exeflags = proj_dir !== nothing ? ["--project=$(proj_dir)"] : String[]

    # Override JULIA_LOAD_PATH — the sessions CLI shim sets it to the app env,
    # which prevents the worker from finding packages in the notebook's project.
    # Malt's env is addenv (Vector{String}), so we override with the default value.
    w = Malt.Worker(; exeflags, env=["JULIA_LOAD_PATH=@:@v#.#:@stdlib"])
    nw = NotebookWorker(w, notebook_path, false)
    _boot_worker!(nw)
    nw
end

"""Walk up from notebook path to find nearest Project.toml."""
function _find_notebook_project(notebook_path::String)::Union{String, Nothing}
    isempty(notebook_path) && return nothing
    isfile(notebook_path) || return nothing
    dir = dirname(abspath(notebook_path))
    for _ in 1:5
        if isfile(joinpath(dir, "Project.toml"))
            return dir
        end
        parent = dirname(dir)
        parent == dir && break
        dir = parent
    end
    nothing
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

    # Inject @bind + widget types into the workspace module
    # so users can immediately write @bind w BoundSlider(2:20) without setup cells.
    # Must be synchronous — cells expect @bind to be available immediately.
    _inject_notebook_api!(nw)

    println("[Worker] Booted for $(isempty(nw.notebook_path) ? "Untitled" : basename(nw.notebook_path))")
end

# Inject @bind and Bound* widget types into the worker's workspace module.
# Uses `using SessionsUI: …` (not direct binding) so a notebook that itself
# imports the same symbols re-imports the same Bindings instead of triggering
# the "import of … into SW_1 conflicts with an existing identifier; ignored"
# warning that direct const bindings produce.
function _inject_notebook_api!(nw::NotebookWorker)
    try
        Malt.remote_eval_wait(nw.worker, quote
            try
                import Sessions
                Core.eval(_workspace.mod, :(using Sessions.SessionsUI:
                    @bind,
                    BoundSlider, BoundNumberField, BoundButton, BoundCounterButton,
                    BoundCheckBox, BoundTextField, BoundPasswordField,
                    BoundSelect, BoundMultiSelect, BoundRadio, BoundRangeSlider,
                    BoundColorPicker, BoundDatePicker, BoundTimePicker,
                    BoundFilePicker, BoundClock))
            catch
            end
        end)
    catch e
        @warn "[Worker] Failed to inject Sessions types" exception=e
    end
end

"""Execute a cell's code in the worker and return a CellOutput."""
function remote_execute_cell!(nw::NotebookWorker, cell::Cell; log_callback=nothing)
    !nw.booted && error("Worker not booted")

    code = cell.code
    executed_code_hash = source_hash(cell)
    cell.state = cell_running
    cell._exec_start_time = time()

    # Create temp log file for real-time streaming
    log_file = tempname() * "_logs.txt"
    touch(log_file)

    # Start log poller — reads new lines from the file every 150ms and calls log_callback
    poll_running = Ref(true)
    last_pos = Ref(0)  # byte offset into file
    poller_task = if log_callback !== nothing
        @async begin
            while poll_running[]
                try
                    sz = filesize(log_file)
                    if sz > last_pos[]
                        new_bytes = open(log_file) do io
                            seek(io, last_pos[])
                            read(io, String)
                        end
                        last_pos[] = sz
                        for line in split(new_bytes, '\n'; keepempty=false)
                            parts = split(line, "|"; limit=3)
                            length(parts) >= 2 || continue
                            level = tryparse(Int32, parts[1])
                            level === nothing && continue
                            msg = String(parts[2])
                            kw_str = length(parts) >= 3 ? String(parts[3]) : ""
                            kwargs = Pair{String,String}[]
                            if !isempty(kw_str)
                                for p in split(kw_str, ",")
                                    eq = findfirst('=', p)
                                    eq !== nothing && push!(kwargs, String(p[1:eq-1]) => String(p[eq+1:end]))
                                end
                            end
                            log_callback(LogRecord(level, msg, "", 0, "", kwargs))
                        end
                    end
                catch; end
                sleep(0.15)
            end
        end
    else
        nothing
    end

    # Execute in worker
    cid_str = string(cell.id)
    worker_output = try
        Malt.remote_eval_fetch(nw.worker,
            :(_worker_execute(_workspace, $(code); log_file=$(log_file), cell_id=$(cid_str))))
    catch e
        @warn "[Worker] Execution failed" exception=e
        (output_type=:error,
         text_representation=sprint(showerror, e),
         stdout_text="",
         runtime_ns=UInt64(0),
         error_text=sprint(showerror, e),
         image_bytes=nothing,
         logs=NamedTuple{(:level,:message,:file,:line,:module_name,:kwargs), Tuple{Int32,String,String,Int,String,Vector{Pair{String,String}}}}[])
    end

    # Stop poller
    poll_running[] = false
    poller_task !== nothing && try wait(poller_task) catch; end
    rm(log_file; force=true)

    # Map worker output back to CellOutput
    cell.output = CellOutput()
    cell.output.output_type = worker_output.output_type
    cell.output.text_representation = worker_output.text_representation
    cell.output.stdout = worker_output.stdout_text
    cell.output.runtime_ns = worker_output.runtime_ns
    cell.output.image_data = worker_output.image_bytes
    cell.output.logs = try
        [LogRecord(r.level, r.message, r.file, r.line, r.module_name, r.kwargs) for r in worker_output.logs]
    catch
        LogRecord[]
    end

    if worker_output.output_type == :error
        cell.state = cell_errored
        cell.output.error = CapturedException(
            ErrorException(worker_output.error_text), backtrace())
        cell.output.structured_error = _parse_error_text(worker_output.error_text)
    else
        cell.state = cell_done
    end

    cell.produced_by_hash = executed_code_hash
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

    # _parse_error_text is defined in kernel.jl (shared with web.jl for cached errors)
