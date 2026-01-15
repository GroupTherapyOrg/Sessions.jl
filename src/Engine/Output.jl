# Output.jl - Output rendering and MIME type handling
#
# Converts Julia values to displayable HTML based on their MIME type.
# Uses Therapy.jl for UI components, plain string interpolation for simple HTML.

# =============================================================================
# HTML Utilities
# =============================================================================

"""
    escape_html(s::String) -> String

Escape HTML special characters for safe display.
"""
function escape_html(s::String)
    s = replace(s, "&" => "&amp;")
    s = replace(s, "<" => "&lt;")
    s = replace(s, ">" => "&gt;")
    s = replace(s, "\"" => "&quot;")
    s = replace(s, "'" => "&#39;")
    return s
end

escape_html(s) = escape_html(string(s))

# =============================================================================
# MIME Type Detection
# =============================================================================

"""
    detect_mime(value) -> String

Detect the best MIME type for displaying a value.
"""
function detect_mime(value)
    # Check for explicit show methods in priority order
    mime_priority = [
        "text/html",
        "image/svg+xml",
        "image/png",
        "image/jpeg",
        "text/markdown",
        "text/plain"
    ]

    for mime in mime_priority
        if showable(MIME(mime), value)
            return mime
        end
    end

    return "text/plain"
end

"""
    render_output(value, mime::String) -> String

Render a value as HTML for the given MIME type.
"""
function render_output(value, mime::String="auto")
    if value === nothing
        return ""
    end

    # Auto-detect MIME if not specified
    actual_mime = mime == "auto" ? detect_mime(value) : mime

    try
        if actual_mime == "text/html"
            # Value already produces HTML
            io = IOBuffer()
            show(io, MIME("text/html"), value)
            return String(take!(io))
        elseif actual_mime == "text/markdown"
            # Render markdown to HTML
            io = IOBuffer()
            show(io, MIME("text/markdown"), value)
            md_content = String(take!(io))
            # TODO: Convert markdown to HTML
            return """<div class="markdown">$(escape_html(md_content))</div>"""
        elseif actual_mime == "image/svg+xml"
            io = IOBuffer()
            show(io, MIME("image/svg+xml"), value)
            return String(take!(io))
        elseif actual_mime == "image/png"
            io = IOBuffer()
            show(io, MIME("image/png"), value)
            data = base64encode(take!(io))
            return """<img src="data:image/png;base64,$data" />"""
        elseif actual_mime == "image/jpeg"
            io = IOBuffer()
            show(io, MIME("image/jpeg"), value)
            data = base64encode(take!(io))
            return """<img src="data:image/jpeg;base64,$data" />"""
        else
            # Default: text/plain
            return """<pre class="output-text">$(escape_html(repr(value)))</pre>"""
        end
    catch e
        # Fallback to repr
        return """<pre class="output-text">$(escape_html(repr(value)))</pre>"""
    end
end

# =============================================================================
# Output Formatting
# =============================================================================

"""
    format_cell_output(cell::Cell) -> String

Format a cell's output as HTML, including stdout/stderr logs.
"""
function format_cell_output(cell::Cell)
    if cell.output === nothing
        return ""
    end

    parts = String[]

    # Stdout logs
    if !isempty(cell.output.logs)
        logs_html = join(["<div class=\"log-line\">$(escape_html(line))</div>" for line in cell.output.logs], "\n")
        push!(parts, """<div class="stdout">$logs_html</div>""")
    end

    # Stderr logs
    if !isempty(cell.output.error_logs)
        logs_html = join(["<div class=\"log-line stderr\">$(escape_html(line))</div>" for line in cell.output.error_logs], "\n")
        push!(parts, """<div class="stderr">$logs_html</div>""")
    end

    # Main output
    if !isempty(cell.output.html)
        push!(parts, """<div class="output-value">$(cell.output.html)</div>""")
    end

    return join(parts, "\n")
end

"""
    format_error(error_msg::String, stacktrace::String) -> String

Format an error with stacktrace as HTML.
"""
function format_error(error_msg::String, stacktrace::Union{Nothing, String}="")
    stacktrace_html = if stacktrace !== nothing && !isempty(stacktrace)
        """<pre class="stacktrace">$(escape_html(stacktrace))</pre>"""
    else
        ""
    end

    """
    <div class="cell-error">
        <div class="error-header">Error</div>
        <div class="error-message">$(escape_html(error_msg))</div>
        $stacktrace_html
    </div>
    """
end

# =============================================================================
# Rich Display Support
# =============================================================================

"""
    supports_rich_display(value) -> Bool

Check if a value supports rich display (HTML, images, etc.).
"""
function supports_rich_display(value)
    rich_mimes = ["text/html", "image/svg+xml", "image/png", "image/jpeg"]
    any(mime -> showable(MIME(mime), value), rich_mimes)
end

"""
Base64 encode binary data.
"""
function base64encode(data::Vector{UInt8})
    Base.base64encode(data)
end

function base64encode(io::IOBuffer)
    base64encode(take!(io))
end
