# Layer 1: Code Formatting — Runic.jl formatter
#
# Runic.jl requires JuliaSyntax ~0.4 but WasmTarget.jl requires JuliaSyntax ≥1.
# They cannot coexist in the same Julia environment. Solution: run Runic in a
# persistent subprocess with its own isolated environment.

# --- In-process path (kept as fast path if the environment happens to be compatible) ---

const _RUNIC_MOD = Ref{Union{Module, Nothing}}(nothing)
const _RUNIC_LOADED = Ref(false)

"""Try to load Runic.jl at runtime. Returns the module or nothing."""
function _load_runic()
    _RUNIC_LOADED[] && return _RUNIC_MOD[]
    _RUNIC_LOADED[] = true
    try
        _RUNIC_MOD[] = Base.require(Base.PkgId(Base.UUID("62bfec6d-59d7-401d-8490-b29ee721c001"), "Runic"))
    catch
        _RUNIC_MOD[] = nothing
    end
    _RUNIC_MOD[]
end

# --- Persistent subprocess path (isolated Runic environment) ---

const _RUNIC_ENV_DIR = Ref("")
const _FORMATTER_PROCESS = Ref{Union{Nothing, Base.Process}}(nothing)
const _FORMATTER_IN = Ref{Union{Nothing, IO}}(nothing)
const _FORMATTER_OUT = Ref{Union{Nothing, IO}}(nothing)
const _FORMATTER_LOCK = ReentrantLock()
const _FORMATTER_AVAILABLE = Ref{Union{Nothing, Bool}}(nothing)  # nil = untested

function _runic_env_dir()
    if isempty(_RUNIC_ENV_DIR[])
        _RUNIC_ENV_DIR[] = joinpath(first(Base.DEPOT_PATH), "environments", "sessions-runic")
    end
    _RUNIC_ENV_DIR[]
end

"""Create a dedicated Runic environment (one-time, ~30s). Returns true on success."""
function _ensure_runic_env!()::Bool
    dir = _runic_env_dir()
    manifest = joinpath(dir, "Manifest.toml")
    isfile(manifest) && return true
    try
        mkpath(dir)
        # Pin JuliaSyntax to 0.4 range — Runic requires ~0.4, not the 1.x/2.x
        # that WasmTarget/JuliaLowering use. This isolated env avoids the conflict.
        write(joinpath(dir, "Project.toml"), """
[deps]
Runic = "62bfec6d-59d7-401d-8490-b29ee721c001"

[compat]
Runic = "1"
""")
        Base.run(`$(Base.julia_cmd()) --project=$dir --startup-file=no -e 'using Pkg; Pkg.resolve(); Pkg.instantiate(); Pkg.precompile()'`)
        return true
    catch e
        @warn "[Runic] Failed to create environment" exception=e
        return false
    end
end

"""Check if the persistent formatter process is alive."""
function _formatter_running()::Bool
    _FORMATTER_PROCESS[] !== nothing && process_running(_FORMATTER_PROCESS[])
end

"""Start the persistent Runic formatter subprocess.

The subprocess reads a length-prefixed protocol:
  - Read a line containing the byte count N
  - Read exactly N bytes of Julia code
  - Write a line containing the byte count M of the result
  - Write exactly M bytes of formatted code
  - Flush and loop
"""
function _start_formatter!()::Bool
    _formatter_running() && return true
    _ensure_runic_env!() || return false
    dir = _runic_env_dir()

    try
        script = """
using Runic
while !eof(stdin)
    line = readline(stdin)
    n = tryparse(Int, line)
    n === nothing && continue
    code = String(read(stdin, n))
    try
        formatted = Runic.format_string(code)
        println(stdout, length(codeunits(formatted)))
        write(stdout, formatted)
    catch
        println(stdout, length(codeunits(code)))
        write(stdout, code)
    end
    flush(stdout)
end
"""
        inp = Pipe()
        out = Pipe()
        cmd = `$(Base.julia_cmd()) --project=$dir --startup-file=no -e $script`
        proc = Base.run(pipeline(cmd; stdin=inp, stdout=out, stderr=devnull), wait=false)

        Base.close(out.in)
        Base.close(inp.out)

        _FORMATTER_PROCESS[] = proc
        _FORMATTER_IN[] = inp.in
        _FORMATTER_OUT[] = out.out

        # Wait for the process to be ready by sending a trivial format request
        write(inp.in, "3\n")
        write(inp.in, "x=1")
        flush(inp.in)
        resp_line = readline(out.out)
        n = parse(Int, resp_line)
        _ = String(read(out.out, n))

        return true
    catch
        _stop_formatter!()
        return false
    end
end

"""Stop the formatter subprocess."""
function _stop_formatter!()
    if _FORMATTER_IN[] !== nothing
        try; close(_FORMATTER_IN[]); catch; end
    end
    if _FORMATTER_PROCESS[] !== nothing
        try; kill(_FORMATTER_PROCESS[]); catch; end
    end
    _FORMATTER_PROCESS[] = nothing
    _FORMATTER_IN[] = nothing
    _FORMATTER_OUT[] = nothing
end

"""Format code via the persistent subprocess. Returns original code on failure.

Uses a timeout to prevent deadlock if the subprocess hangs — the lock is
never held for more than 5 seconds."""
function _format_code_subprocess(code::String)::String
    # Non-blocking lock — if another format is in progress, skip
    trylock(_FORMATTER_LOCK) || return code
    try
        _start_formatter!() || return code
        inp = _FORMATTER_IN[]
        out = _FORMATTER_OUT[]
        (inp === nothing || out === nothing) && return code

        # Check subprocess is alive
        if _FORMATTER_PROCESS[] !== nothing && !process_running(_FORMATTER_PROCESS[])
            _stop_formatter!()
            return code
        end

        # Send: byte count + code
        write(inp, string(length(codeunits(code))), "\n")
        write(inp, code)
        flush(inp)

        # Read with timeout — prevents deadlock if subprocess hangs
        result = Ref(code)
        reader = @async begin
            resp_line = readline(out)
            n = parse(Int, resp_line)
            String(read(out, n))
        end
        status = timedwait(() -> istaskdone(reader), 5.0)
        if status == :ok && !istaskfailed(reader)
            result[] = fetch(reader)
        else
            _stop_formatter!()
        end
        return result[]
    catch
        _stop_formatter!()
        return code
    finally
        unlock(_FORMATTER_LOCK)
    end
end

# --- Public API ---

"""Check if Runic.jl is available for formatting (subprocess with isolated env)."""
function format_code_available()::Bool
    # Subprocess path: test once (in-process won't work due to JuliaSyntax version conflict)
    if _FORMATTER_AVAILABLE[] === nothing
        _FORMATTER_AVAILABLE[] = _ensure_runic_env!()
    end
    _FORMATTER_AVAILABLE[] === true
end

"""Format Julia source code using Runic.jl.

Returns formatted code if Runic is available and the code is valid Julia.
Returns the original code unchanged if:
- Runic.jl is not available (neither in-process nor subprocess)
- The code has syntax errors that prevent formatting
- Any other error occurs during formatting
"""
function format_code(code::String)::String
    isempty(code) && return code
    # Use persistent subprocess with isolated Runic environment
    # (in-process path disabled — JuliaSyntax version conflict with WasmTarget)
    result = _format_code_subprocess(code)
    result
end
