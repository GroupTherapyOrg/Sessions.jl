# Worker.jl - Sandboxed code execution using Malt.jl
#
# Each notebook gets its own worker process for isolated execution.
# Supports rich MIME output (HTML, SVG, images, etc.) for Therapy.jl rendering.

import Malt
using UUIDs

# MIME type priority for rich output (highest priority first)
const MIME_PRIORITY = [
    "text/html",
    "image/svg+xml",
    "image/png",
    "image/jpeg",
    "text/markdown",
    "text/plain"
]

"""
Result of executing code in a worker.
"""
struct ExecutionResult
    success::Bool
    value::Any              # The rendered content (HTML string, base64 image, etc.)
    mime_type::String       # MIME type of the output
    stdout::String
    stderr::String
    error::Union{Nothing, String}
    stacktrace::Union{Nothing, String}
    runtime_ms::Float64
end

"""
    execute_code(worker::Malt.Worker, code::String) -> ExecutionResult

Execute Julia code in the worker process and capture all output.
Uses include_string to handle multi-line code natively (no begin...end needed).
Returns rich MIME output (HTML, SVG, images) when available.
"""
function execute_code(worker::Malt.Worker, code::String)
    start_time = time()

    # Pass the raw code - include_string handles multiple expressions natively
    result = Malt.remote_eval_fetch(worker, quote
        local _result_value = nothing
        local _result_content = ""
        local _result_mime = "text/plain"
        local _error_msg = nothing
        local _stacktrace = nothing
        local _success = true

        # MIME priority for rich output (instances, not types)
        local _MIME_PRIORITY = [
            MIME("text/html"),
            MIME("image/svg+xml"),
            MIME("image/png"),
            MIME("image/jpeg"),
            MIME("text/markdown"),
            MIME("text/plain")
        ]

        try
            # Use include_string - handles multiple expressions natively
            # Returns the value of the last expression (like Pluto)
            _result_value = include_string(Main, $code)

            # Get rich output - find best MIME type
            if _result_value !== nothing
                for mime in _MIME_PRIORITY
                    if showable(mime, _result_value)
                        _result_mime = string(mime)
                        local io = IOBuffer()
                        show(io, mime, _result_value)
                        local data = take!(io)

                        # For images, base64 encode
                        if startswith(_result_mime, "image/") && _result_mime != "image/svg+xml"
                            _result_content = Base.base64encode(data)
                        else
                            _result_content = String(data)
                        end
                        break
                    end
                end

                # Fallback to repr if nothing else worked
                if isempty(_result_content)
                    _result_content = repr(_result_value)
                    _result_mime = "text/plain"
                end
            end
        catch e
            _success = false
            _error_msg = sprint(showerror, e)
            _stacktrace = sprint(Base.show_backtrace, catch_backtrace())
        end

        # Return all captured data
        (
            success = _success,
            content = _result_content,
            mime_type = _result_mime,
            stdout = "",  # TODO: Implement proper stdout capture via IOCapture.jl
            stderr = "",
            error = _error_msg,
            stacktrace = _stacktrace
        )
    end)

    runtime_ms = (time() - start_time) * 1000

    return ExecutionResult(
        result.success,
        result.content,
        result.mime_type,
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
Handles rich MIME output (HTML, SVG, images) for Therapy.jl rendering.
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

        # Render output based on MIME type
        html_output = render_rich_output(result.value, result.mime_type)

        cell.output = CellOutput(
            result.value,
            result.mime_type,
            html_output,
            split(result.stdout, '\n', keepempty=false),
            split(result.stderr, '\n', keepempty=false)
        )
    else
        cell.state = CELL_ERROR
        # Error output with elegant styling for parchment theme
        error_html = """<div class="cell-error rounded-lg p-4 bg-red-50 dark:bg-red-950/30 border border-red-200 dark:border-red-900/50">
            <div class="font-semibold text-red-700 dark:text-red-400 mb-2">Error</div>
            <div class="font-mono text-sm text-red-600 dark:text-red-300 mb-3">$(escape_html(result.error === nothing ? "" : result.error))</div>
            <pre class="text-xs text-red-500/70 dark:text-red-400/60 overflow-x-auto whitespace-pre-wrap">$(escape_html(result.stacktrace === nothing ? "" : result.stacktrace))</pre>
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
    render_rich_output(content::String, mime_type::String) -> String

Render rich output content as HTML based on MIME type.
Uses Tailwind classes for styling, integrates with Therapy.jl's RawHtml.
"""
function render_rich_output(content::String, mime_type::String)
    if isempty(content)
        return ""
    end

    if mime_type == "text/html"
        # HTML content is returned as-is (will be wrapped in RawHtml by CellView)
        return content
    elseif mime_type == "image/svg+xml"
        # SVG is returned as-is (will be wrapped in RawHtml)
        return content
    elseif mime_type == "image/png"
        # PNG as base64 data URI
        return """<img src="data:image/png;base64,$content" class="max-w-full h-auto rounded shadow-sm" />"""
    elseif mime_type == "image/jpeg"
        # JPEG as base64 data URI
        return """<img src="data:image/jpeg;base64,$content" class="max-w-full h-auto rounded shadow-sm" />"""
    elseif mime_type == "text/markdown"
        # For now, render markdown as preformatted (TODO: add markdown renderer)
        return """<div class="prose dark:prose-invert prose-stone max-w-none">$(escape_html(content))</div>"""
    else
        # Default: plain text with elegant monospace styling
        return """<pre class="font-mono text-sm text-stone-700 dark:text-stone-300 whitespace-pre-wrap">$(escape_html(content))</pre>"""
    end
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
