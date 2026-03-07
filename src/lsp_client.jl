# Layer 1: LSP Client — JSON-RPC client for JETLS.jl language server
# Spawns JETLS as a subprocess, communicates via stdin/stdout JSON-RPC.
# Provides real-time diagnostics, completions, hover, go-to-definition.
# On by default (opt-out). Gracefully degrades if JETLS is not installed.

using UUIDs

# ── LSP Message Types ──────────────────────────────────────────────

"""A single LSP diagnostic (from textDocument/publishDiagnostics)."""
struct LspDiagnostic
    line::Int           # 0-based line from LSP, converted to 1-based
    col::Int            # 0-based character offset
    end_line::Int
    end_col::Int
    severity::Symbol    # :error, :warning, :info, :hint
    message::String
    source::String      # "JET", "JuliaSyntax", etc.
    code::String        # diagnostic code (e.g., "MethodError")
end

"""LSP completion item."""
struct LspCompletionItem
    label::String
    kind::Symbol        # :function, :variable, :module, :keyword, etc.
    detail::String      # type signature / brief info
    documentation::String
end

"""LSP hover result."""
struct LspHoverResult
    contents::String    # markdown content
    line::Int
    col::Int
end

# ── LSP Client ─────────────────────────────────────────────────────

"""Status of the LSP server connection."""
@enum LspStatus begin
    lsp_off         # disabled by user
    lsp_starting    # subprocess spawning
    lsp_ready       # initialized, accepting requests
    lsp_error       # failed to start or crashed
end

mutable struct LspClient
    status::LspStatus
    process::Union{Nothing, Base.Process}
    stdin_pipe::Union{Nothing, IO}
    stdout_pipe::Union{Nothing, IO}
    request_id::Int
    pending::Dict{Int, Channel{Any}}    # request_id -> response channel
    diagnostics::Dict{String, Vector{LspDiagnostic}}  # uri -> diagnostics
    server_capabilities::Dict{String, Any}
    reader_task::Union{Nothing, Task}
    error_message::String
    enabled::Bool       # opt-out flag
    completion_cache::Vector{LspCompletionItem}  # last completion results
end

function LspClient(; enabled::Bool=true)
    LspClient(
        enabled ? lsp_starting : lsp_off,
        nothing, nothing, nothing,
        0,
        Dict{Int, Channel{Any}}(),
        Dict{String, Vector{LspDiagnostic}}(),
        Dict{String, Any}(),
        nothing,
        "",
        enabled,
        LspCompletionItem[]
    )
end

"""Start the JETLS language server as a subprocess."""
function start_lsp!(client::LspClient; project_dir::String=".")
    !client.enabled && return
    client.status = lsp_starting

    # Try to start JETLS
    try
        # Use the jetls app binary installed via Pkg.Apps
        jetls_bin = joinpath(homedir(), ".julia", "bin", "jetls")
        if !isfile(jetls_bin)
            client.status = lsp_error
            client.error_message = "JETLS not installed. Install: julia -e 'using Pkg; Pkg.Apps.add(; url=\"https://github.com/aviatesk/JETLS.jl\", rev=\"release\")'"
            return
        end

        cmd = `$jetls_bin serve --stdio`

        inp = Pipe()
        out = Pipe()
        err = Pipe()

        proc = Base.run(pipeline(cmd; stdin=inp, stdout=out, stderr=err), wait=false)
        client.process = proc

        # Close child-side ends so we get proper EOF behavior
        Base.close(out.in)
        Base.close(inp.out)
        Base.close(err.in)

        client.stdin_pipe = inp.in   # we write to this
        client.stdout_pipe = out.out  # we read from this

        # Start reader task
        client.reader_task = @async _lsp_reader_loop(client)

        # Send initialize request
        _send_initialize!(client, project_dir)

    catch e
        client.status = lsp_error
        client.error_message = "LSP start failed: $(sprint(showerror, e))"
    end
end

"""Stop the LSP server."""
function stop_lsp!(client::LspClient)
    client.status = lsp_off
    if client.process !== nothing
        try
            _send_notification!(client, "shutdown", Dict{String,Any}())
            _send_notification!(client, "exit", Dict{String,Any}())
        catch; end
        try
            kill(client.process)
        catch; end
        client.process = nothing
    end
    client.stdin_pipe = nothing
    client.stdout_pipe = nothing
    client.reader_task = nothing
end

# ── JSON-RPC Wire Protocol ─────────────────────────────────────────

"""Send a JSON-RPC request and return a channel for the response."""
function _send_request!(client::LspClient, method::String, params::Dict{String,Any})::Channel{Any}
    client.request_id += 1
    id = client.request_id
    ch = Channel{Any}(1)
    client.pending[id] = ch

    msg = Dict{String,Any}(
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => method,
        "params" => params
    )
    _write_lsp_message!(client, msg)
    ch
end

"""Send a JSON-RPC notification (no response expected)."""
function _send_notification!(client::LspClient, method::String, params)
    msg = Dict{String,Any}(
        "jsonrpc" => "2.0",
        "method" => method,
        "params" => params
    )
    _write_lsp_message!(client, msg)
end

"""Write a JSON-RPC message with Content-Length header."""
function _write_lsp_message!(client::LspClient, msg::Dict)
    client.stdin_pipe === nothing && return
    # Minimal JSON serialization (no external dependency needed)
    body = _to_json(msg)
    header = "Content-Length: $(sizeof(body))\r\n\r\n"
    try
        write(client.stdin_pipe, header)
        write(client.stdin_pipe, body)
        flush(client.stdin_pipe)
    catch; end
end

"""Read LSP messages from stdout in a loop."""
function _lsp_reader_loop(client::LspClient)
    io = client.stdout_pipe
    io === nothing && return
    try
        while isopen(io) && client.process !== nothing && process_running(client.process)
            msg = _read_lsp_message(io)
            msg === nothing && break
            _handle_lsp_message!(client, msg)
        end
    catch e
        if !(e isa EOFError || e isa Base.IOError)
            client.error_message = "LSP reader error: $(sprint(showerror, e))"
        end
    end
    if client.status == lsp_ready
        client.status = lsp_error
        client.error_message = "LSP server exited unexpectedly"
    end
end

"""Read a single LSP message (Content-Length header + body)."""
function _read_lsp_message(io::IO)
    # Read headers
    content_length = 0
    while true
        line = readline(io)
        isempty(line) && break  # blank line = end of headers
        if startswith(line, "Content-Length:")
            content_length = parse(Int, strip(line[16:end]))
        end
    end
    content_length == 0 && return nothing

    # Read body
    body = read(io, content_length)
    return _from_json(String(body))
end

"""Handle an incoming LSP message."""
function _handle_lsp_message!(client::LspClient, msg::Dict)
    if haskey(msg, "id") && haskey(msg, "result")
        # Response to a request
        id = msg["id"]
        if id isa Number
            id = Int(id)
        end
        ch = pop!(client.pending, id, nothing)
        ch !== nothing && put!(ch, msg["result"])
    elseif haskey(msg, "id") && haskey(msg, "error")
        # Error response
        id = msg["id"]
        if id isa Number
            id = Int(id)
        end
        ch = pop!(client.pending, id, nothing)
        ch !== nothing && put!(ch, msg["error"])
    elseif haskey(msg, "method")
        # Notification from server
        _handle_lsp_notification!(client, msg["method"], get(msg, "params", Dict()))
    end
end

"""Handle LSP server notifications."""
function _handle_lsp_notification!(client::LspClient, method::String, params)
    if method == "textDocument/publishDiagnostics"
        _handle_diagnostics!(client, params)
    end
    # Other notifications (window/logMessage, etc.) are silently ignored
end

"""Process publishDiagnostics notification."""
function _handle_diagnostics!(client::LspClient, params)
    uri = get(params, "uri", "")
    raw_diags = get(params, "diagnostics", [])

    diags = LspDiagnostic[]
    for d in raw_diags
        range = get(d, "range", Dict())
        start = get(range, "start", Dict())
        finish = get(range, "end", Dict())
        severity_num = get(d, "severity", 1)
        severity = severity_num == 1 ? :error :
                   severity_num == 2 ? :warning :
                   severity_num == 3 ? :info : :hint

        push!(diags, LspDiagnostic(
            get(start, "line", 0) + 1,   # convert 0-based to 1-based
            get(start, "character", 0),
            get(finish, "line", 0) + 1,
            get(finish, "character", 0),
            severity,
            get(d, "message", ""),
            get(d, "source", "JETLS"),
            string(get(d, "code", ""))
        ))
    end

    client.diagnostics[uri] = diags
end

# ── LSP Lifecycle ──────────────────────────────────────────────────

"""Send the initialize request to the LSP server."""
function _send_initialize!(client::LspClient, project_dir::String)
    params = Dict{String,Any}(
        "processId" => getpid(),
        "rootUri" => "file://$(abspath(project_dir))",
        "capabilities" => Dict{String,Any}(
            "textDocument" => Dict{String,Any}(
                "publishDiagnostics" => Dict{String,Any}(
                    "relatedInformation" => true
                ),
                "completion" => Dict{String,Any}(
                    "completionItem" => Dict{String,Any}(
                        "snippetSupport" => false,
                        "documentationFormat" => ["plaintext"]
                    )
                ),
                "hover" => Dict{String,Any}(
                    "contentFormat" => ["plaintext", "markdown"]
                )
            )
        ),
        "workspaceFolders" => [
            Dict{String,Any}(
                "uri" => "file://$(abspath(project_dir))",
                "name" => basename(project_dir)
            )
        ]
    )

    ch = _send_request!(client, "initialize", params)

    # Handle response asynchronously
    @async begin
        try
            result = timedwait(() -> isready(ch), 30.0)
            if result == :ok
                response = take!(ch)
                if response isa Dict
                    client.server_capabilities = get(response, "capabilities", Dict())
                    _send_notification!(client, "initialized", Dict{String,Any}())
                    client.status = lsp_ready
                else
                    client.status = lsp_error
                    client.error_message = "LSP initialize returned error"
                end
            else
                client.status = lsp_error
                client.error_message = "LSP initialize timed out (30s)"
            end
        catch e
            client.status = lsp_error
            client.error_message = "LSP init error: $(sprint(showerror, e))"
        end
    end
end

# ── Document Sync ──────────────────────────────────────────────────

"""Notify the LSP server that a document was opened."""
function lsp_did_open!(client::LspClient, uri::String, text::String; language_id::String="julia")
    client.status != lsp_ready && return
    _send_notification!(client, "textDocument/didOpen", Dict{String,Any}(
        "textDocument" => Dict{String,Any}(
            "uri" => uri,
            "languageId" => language_id,
            "version" => 1,
            "text" => text
        )
    ))
end

"""Notify the LSP server that a document changed (full sync)."""
function lsp_did_change!(client::LspClient, uri::String, text::String, version::Int)
    client.status != lsp_ready && return
    _send_notification!(client, "textDocument/didChange", Dict{String,Any}(
        "textDocument" => Dict{String,Any}(
            "uri" => uri,
            "version" => version
        ),
        "contentChanges" => [
            Dict{String,Any}("text" => text)
        ]
    ))
end

"""Notify the LSP server that a document was saved (triggers deep analysis)."""
function lsp_did_save!(client::LspClient, uri::String, text::String)
    client.status != lsp_ready && return
    _send_notification!(client, "textDocument/didSave", Dict{String,Any}(
        "textDocument" => Dict{String,Any}("uri" => uri),
        "text" => text
    ))
end

"""Notify the LSP server that a document was closed."""
function lsp_did_close!(client::LspClient, uri::String)
    client.status != lsp_ready && return
    _send_notification!(client, "textDocument/didClose", Dict{String,Any}(
        "textDocument" => Dict{String,Any}("uri" => uri)
    ))
end

# ── Completion ─────────────────────────────────────────────────────

"""Request completions at a given position. Returns items asynchronously."""
function lsp_completion!(client::LspClient, uri::String, line::Int, col::Int)::Channel{Any}
    _send_request!(client, "textDocument/completion", Dict{String,Any}(
        "textDocument" => Dict{String,Any}("uri" => uri),
        "position" => Dict{String,Any}("line" => line - 1, "character" => col)
    ))
end

"""Parse LSP completion response into LspCompletionItems."""
function parse_completions(response)::Vector{LspCompletionItem}
    items = LspCompletionItem[]
    raw = if response isa Dict
        get(response, "items", [])
    elseif response isa Vector
        response
    else
        return items
    end

    for item in raw
        kind_num = get(item, "kind", 1)
        kind = _completion_kind(kind_num)
        push!(items, LspCompletionItem(
            get(item, "label", ""),
            kind,
            get(item, "detail", ""),
            _extract_docs(get(item, "documentation", ""))
        ))
    end
    items
end

function _completion_kind(n::Number)
    n = Int(n)
    n == 1  && return :text
    n == 2  && return :method
    n == 3  && return :function
    n == 4  && return :constructor
    n == 5  && return :field
    n == 6  && return :variable
    n == 7  && return :class
    n == 8  && return :interface
    n == 9  && return :module
    n == 10 && return :property
    n == 14 && return :keyword
    n == 21 && return :constant
    return :text
end

function _extract_docs(doc)
    doc isa String && return doc
    doc isa Dict && return get(doc, "value", "")
    ""
end

"""
Request completions with a timeout. Returns Vector{LspCompletionItem}.
On timeout or error, returns empty vector (never hangs).
"""
function lsp_complete_with_timeout!(client::LspClient, uri::String, line::Int, col::Int;
                                     timeout::Float64=1.0)::Vector{LspCompletionItem}
    client.status != lsp_ready && return LspCompletionItem[]
    ch = lsp_completion!(client, uri, line, col)
    result = timedwait(() -> isready(ch), timeout)
    if result == :ok
        response = take!(ch)
        if response isa Dict && haskey(response, "error")
            client.completion_cache = LspCompletionItem[]
            return client.completion_cache
        end
        client.completion_cache = parse_completions(response)
        return client.completion_cache
    end
    client.completion_cache = LspCompletionItem[]
    client.completion_cache
end

# ── Hover ──────────────────────────────────────────────────────────

"""Request hover info at a position."""
function lsp_hover!(client::LspClient, uri::String, line::Int, col::Int)::Channel{Any}
    _send_request!(client, "textDocument/hover", Dict{String,Any}(
        "textDocument" => Dict{String,Any}("uri" => uri),
        "position" => Dict{String,Any}("line" => line - 1, "character" => col)
    ))
end

"""Parse hover response."""
function parse_hover(response)::Union{Nothing, LspHoverResult}
    response === nothing && return nothing
    !(response isa Dict) && return nothing
    contents = get(response, "contents", "")
    text = if contents isa String
        contents
    elseif contents isa Dict
        get(contents, "value", "")
    elseif contents isa Vector
        join([c isa String ? c : get(c, "value", "") for c in contents], "\n")
    else
        ""
    end
    isempty(text) && return nothing
    LspHoverResult(text, 0, 0)
end

# ── Go-to-Definition ───────────────────────────────────────────────

"""Request go-to-definition at a position."""
function lsp_definition!(client::LspClient, uri::String, line::Int, col::Int)::Channel{Any}
    _send_request!(client, "textDocument/definition", Dict{String,Any}(
        "textDocument" => Dict{String,Any}("uri" => uri),
        "position" => Dict{String,Any}("line" => line - 1, "character" => col)
    ))
end

# ── Minimal JSON Serialization ─────────────────────────────────────
# Avoids dependency on JSON.jl. Only needs to handle Dict, Vector, String, Number, Bool, Nothing.

function _to_json(v)::String
    io = IOBuffer()
    _write_json(io, v)
    String(take!(io))
end

function _write_json(io::IO, v::Dict)
    write(io, '{')
    first = true
    for (k, val) in v
        first || write(io, ',')
        first = false
        _write_json(io, string(k))
        write(io, ':')
        _write_json(io, val)
    end
    write(io, '}')
end

function _write_json(io::IO, v::Vector)
    write(io, '[')
    for (i, item) in enumerate(v)
        i > 1 && write(io, ',')
        _write_json(io, item)
    end
    write(io, ']')
end

function _write_json(io::IO, v::AbstractString)
    write(io, '"')
    for c in v
        if c == '"'
            write(io, "\\\"")
        elseif c == '\\'
            write(io, "\\\\")
        elseif c == '\n'
            write(io, "\\n")
        elseif c == '\r'
            write(io, "\\r")
        elseif c == '\t'
            write(io, "\\t")
        else
            write(io, c)
        end
    end
    write(io, '"')
end

function _write_json(io::IO, v::Number)
    if v isa AbstractFloat && (isnan(v) || isinf(v))
        write(io, "null")
    else
        write(io, string(v))
    end
end

_write_json(io::IO, v::Bool) = write(io, v ? "true" : "false")
_write_json(io::IO, ::Nothing) = write(io, "null")
_write_json(io::IO, v::Symbol) = _write_json(io, string(v))

# Minimal JSON parser (handles LSP responses — objects, arrays, strings, numbers, bools, null)

function _from_json(s::String)
    pos = Ref(1)
    result = _parse_json_value(s, pos)
    result
end

function _skip_ws(s::String, pos::Ref{Int})
    while pos[] <= length(s) && s[pos[]] in (' ', '\t', '\n', '\r')
        pos[] += 1
    end
end

function _parse_json_value(s::String, pos::Ref{Int})
    _skip_ws(s, pos)
    pos[] > length(s) && return nothing
    c = s[pos[]]
    c == '"' && return _parse_json_string(s, pos)
    c == '{' && return _parse_json_object(s, pos)
    c == '[' && return _parse_json_array(s, pos)
    c == 't' && return _parse_json_true(s, pos)
    c == 'f' && return _parse_json_false(s, pos)
    c == 'n' && return _parse_json_null(s, pos)
    return _parse_json_number(s, pos)
end

function _parse_json_string(s::String, pos::Ref{Int})
    pos[] += 1  # skip opening "
    buf = IOBuffer()
    while pos[] <= length(s)
        c = s[pos[]]
        if c == '"'
            pos[] += 1
            return String(take!(buf))
        elseif c == '\\'
            pos[] += 1
            pos[] > length(s) && break
            esc = s[pos[]]
            if esc == '"'; write(buf, '"')
            elseif esc == '\\'; write(buf, '\\')
            elseif esc == '/'; write(buf, '/')
            elseif esc == 'n'; write(buf, '\n')
            elseif esc == 'r'; write(buf, '\r')
            elseif esc == 't'; write(buf, '\t')
            elseif esc == 'u'
                # Unicode escape: \uXXXX
                if pos[] + 4 <= length(s)
                    hex = s[pos[]+1:pos[]+4]
                    pos[] += 4
                    cp = tryparse(UInt32, hex; base=16)
                    cp !== nothing && write(buf, Char(cp))
                end
            else
                write(buf, esc)
            end
        else
            write(buf, c)
        end
        pos[] += 1
    end
    String(take!(buf))
end

function _parse_json_object(s::String, pos::Ref{Int})
    pos[] += 1  # skip {
    obj = Dict{String, Any}()
    _skip_ws(s, pos)
    pos[] <= length(s) && s[pos[]] == '}' && (pos[] += 1; return obj)
    while pos[] <= length(s)
        _skip_ws(s, pos)
        key = _parse_json_string(s, pos)
        _skip_ws(s, pos)
        pos[] <= length(s) && s[pos[]] == ':' && (pos[] += 1)
        val = _parse_json_value(s, pos)
        obj[key] = val
        _skip_ws(s, pos)
        pos[] > length(s) && break
        if s[pos[]] == ','
            pos[] += 1
        elseif s[pos[]] == '}'
            pos[] += 1
            break
        end
    end
    obj
end

function _parse_json_array(s::String, pos::Ref{Int})
    pos[] += 1  # skip [
    arr = Any[]
    _skip_ws(s, pos)
    pos[] <= length(s) && s[pos[]] == ']' && (pos[] += 1; return arr)
    while pos[] <= length(s)
        val = _parse_json_value(s, pos)
        push!(arr, val)
        _skip_ws(s, pos)
        pos[] > length(s) && break
        if s[pos[]] == ','
            pos[] += 1
        elseif s[pos[]] == ']'
            pos[] += 1
            break
        end
    end
    arr
end

function _parse_json_true(s::String, pos::Ref{Int})
    pos[] += 4  # "true"
    true
end

function _parse_json_false(s::String, pos::Ref{Int})
    pos[] += 5  # "false"
    false
end

function _parse_json_null(s::String, pos::Ref{Int})
    pos[] += 4  # "null"
    nothing
end

function _parse_json_number(s::String, pos::Ref{Int})
    start = pos[]
    # Consume sign
    pos[] <= length(s) && s[pos[]] == '-' && (pos[] += 1)
    # Consume digits
    while pos[] <= length(s) && s[pos[]] in '0':'9'
        pos[] += 1
    end
    is_float = false
    # Decimal point
    if pos[] <= length(s) && s[pos[]] == '.'
        is_float = true
        pos[] += 1
        while pos[] <= length(s) && s[pos[]] in '0':'9'
            pos[] += 1
        end
    end
    # Exponent
    if pos[] <= length(s) && s[pos[]] in ('e', 'E')
        is_float = true
        pos[] += 1
        pos[] <= length(s) && s[pos[]] in ('+', '-') && (pos[] += 1)
        while pos[] <= length(s) && s[pos[]] in '0':'9'
            pos[] += 1
        end
    end
    num_str = s[start:pos[]-1]
    if is_float
        return parse(Float64, num_str)
    else
        return parse(Int, num_str)
    end
end

# ── Notebook ↔ LSP Document Sync ──────────────────────────────────

"""Generate a virtual file URI for a notebook cell."""
function cell_uri(nb::Notebook, cell_id::UUID)::String
    "file://$(abspath(nb.path))#cell-$(cell_id)"
end

"""Generate a virtual URI for the whole notebook (all cells concatenated).
Uses a non-existent .jl path inside the project root so JETLS treats it as a
virtual document within scope, avoiding conflicts with the file scanner."""
function notebook_uri(nb::Notebook)::String
    # Must be inside the Julia project root (where Project.toml lives) for JETLS to analyze.
    # Must NOT match a real file to avoid the scanner overwriting our content.
    root = _find_project_root(nb.path)
    "file://$(root)/.sessions-virtual-notebook.jl"
end

"""Find the Julia project root (directory containing Project.toml)."""
function _find_project_root(path::String)::String
    dir = isempty(path) ? pwd() : dirname(abspath(path))
    # Walk up until we find Project.toml or hit filesystem root
    for _ in 1:20
        isfile(joinpath(dir, "Project.toml")) && return dir
        parent = dirname(dir)
        parent == dir && break  # filesystem root
        dir = parent
    end
    # Fallback to pwd if no Project.toml found
    pwd()
end

"""Concatenate all cell code into a single virtual document for LSP analysis."""
function notebook_as_document(nb::Notebook)::String
    parts = String[]
    for id in nb.cell_order
        cell = get(nb.cells, id, nothing)
        cell === nothing && continue
        push!(parts, cell.code)
    end
    join(parts, "\n\n")
end

"""Map a line number in the concatenated document back to (cell_id, cell_line)."""
function document_line_to_cell(nb::Notebook, doc_line::Int)::Union{Nothing, Tuple{UUID, Int}}
    current_line = 1
    for id in nb.cell_order
        cell = get(nb.cells, id, nothing)
        cell === nothing && continue
        n_lines = count(==('\n'), cell.code) + 1
        if doc_line >= current_line && doc_line < current_line + n_lines
            return (id, doc_line - current_line + 1)
        end
        current_line += n_lines + 1  # +1 for the blank line from \n\n separator
    end
    nothing
end

"""Sync the entire notebook to the LSP server."""
function lsp_sync_notebook!(client::LspClient, nb::Notebook, version::Int)
    client.status != lsp_ready && return
    uri = notebook_uri(nb)
    text = notebook_as_document(nb)
    if version == 1
        lsp_did_open!(client, uri, text)
    else
        lsp_did_change!(client, uri, text, version)
    end
    # Send didSave to trigger JETLS deep analysis (JET inference pass)
    lsp_did_save!(client, uri, text)
end

"""Get LSP diagnostics mapped back to notebook cells."""
function lsp_cell_diagnostics(client::LspClient, nb::Notebook)::Dict{UUID, Vector{Diagnostic}}
    result = Dict{UUID, Vector{Diagnostic}}()
    uri = notebook_uri(nb)
    lsp_diags = get(client.diagnostics, uri, LspDiagnostic[])

    for ld in lsp_diags
        mapping = document_line_to_cell(nb, ld.line)
        mapping === nothing && continue
        cell_id, cell_line = mapping
        if !haskey(result, cell_id)
            result[cell_id] = Diagnostic[]
        end
        push!(result[cell_id], Diagnostic(
            cell_line,
            ld.severity,
            ld.message,
            ld.source
        ))
    end
    result
end

"""Convert LSP diagnostics for a standalone file into `Diagnostic` vector."""
function lsp_file_diagnostics(client::LspClient, path::String)::Vector{Diagnostic}
    uri = "file://" * path
    lsp_diags = get(client.diagnostics, uri, LspDiagnostic[])
    [Diagnostic(ld.line, ld.severity, ld.message, ld.source) for ld in lsp_diags]
end
