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
function _inject_notebook_api!(nw::NotebookWorker)
    try
        Malt.remote_eval_wait(nw.worker, :(try
            import Sessions
            _mod = _workspace.mod
            # Inject all Bound* widget types from Sessions (re-exported from SessionsUI)
            for name in [:BoundSlider, :BoundTextField, :BoundCheckBox, :BoundSelect,
                         :BoundNumberField, :BoundButton, :BoundCounterButton]
                Core.eval(_mod, Expr(:const, Expr(:(=), name, getfield(Sessions, name))))
            end
            Core.eval(_mod, :(var"@bind" = $(Sessions.var"@bind")))
        catch; end))
    catch e
        @warn "[Worker] Failed to inject Sessions types" exception=e
    end
end

"""Execute a cell's code in the worker and return a CellOutput."""
function remote_execute_cell!(nw::NotebookWorker, cell::Cell)
    !nw.booted && error("Worker not booted")

    code = cell.code
    # Capture the hash of the code we're ACTUALLY executing.
    # If cell.code changes during execution (external edit, agent),
    # mark_executed! must use this hash, not the new code's hash.
    executed_code_hash = source_hash(cell)
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
    # Map log records from worker (NamedTuple) to LogRecord structs
    cell.output.logs = try
        [LogRecord(r.level, r.message, r.file, r.line, r.module_name, r.kwargs) for r in worker_output.logs]
    catch
        LogRecord[]
    end

    if worker_output.output_type == :error
        cell.state = cell_errored
        cell.output.error = CapturedException(
            ErrorException(worker_output.error_text), backtrace())
        # Build structured error from the error text for rich display
        cell.output.structured_error = _parse_error_text(worker_output.error_text)
    else
        cell.state = cell_done
    end

    # Use the hash of the code that was actually executed, not current cell.code
    # (cell.code may have changed during execution via external edit)
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

"""Parse a plain error text (from worker) into a StructuredError for rich display."""
function _parse_error_text(error_text::String)::StructuredError
    lines = split(error_text, '\n')
    isempty(lines) && return StructuredError("Error", error_text, StructuredFrame[], 0, error_text)

    # First line(s) before "Stacktrace:" are the error message
    msg_lines = String[]
    stack_start = 0
    for (i, line) in enumerate(lines)
        if startswith(strip(line), "Stacktrace:")
            stack_start = i + 1
            break
        end
        push!(msg_lines, String(line))
    end
    message = strip(join(msg_lines, '\n'))

    # Extract error type from message (e.g. "LoadError: ..." → "LoadError")
    type_name = "Error"
    m = match(r"^([A-Za-z]+Error|[A-Za-z]+Exception)", message)
    m !== nothing && (type_name = m.match)

    # Parse stack frames: pattern is " [N] func_name\n    @ Module path:line"
    frames = StructuredFrame[]
    i = stack_start
    while i <= length(lines)
        line = String(lines[i])
        # Match frame header: " [N] function_name(args...)"
        fm = match(r"^\s*\[(\d+)\]\s+(.+)$", line)
        if fm !== nothing
            func = strip(fm.captures[2])
            func_short = replace(func, r"\{.*\}" => "")  # strip type params
            # Look for location on next line: "    @ Module file:line"
            file_short = ""
            file_full = ""
            line_no = 0
            from_base = false
            from_user = false
            inlined = false
            if i + 1 <= length(lines)
                loc = String(lines[i + 1])
                lm = match(r"^\s+@\s+(\S+)\s+(.+):(\d+)$", loc)
                if lm !== nothing
                    mod_name = lm.captures[1]
                    file_full = lm.captures[2]
                    line_no = parse(Int, lm.captures[3])
                    file_short = basename(file_full)
                    from_base = contains(file_full, "Base") || contains(file_full, "Core") || startswith(file_full, ".")
                    from_user = contains(mod_name, "SW_") || contains(mod_name, "SessionsWorkspace")
                    i += 1
                end
            end
            inlined = contains(func, " [inlined]")
            importance = from_user ? :important : from_base ? :dim : :normal
            push!(frames, StructuredFrame(func, func_short, file_full, file_short, line_no, inlined, false, from_base, from_user, importance))
        end
        i += 1
    end

    StructuredError(type_name, message, frames, 0, error_text)
end
