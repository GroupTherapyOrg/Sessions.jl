# Debug logging — writes timestamped entries to ~/.sessions/debug.log
# Enable with SESSIONS_DEBUG=1 environment variable.
# Log file is rotated at 2MB.

const _DEBUG_ENABLED = Ref(false)
const _DEBUG_IO = Ref{Union{IOStream, Nothing}}(nothing)
const _DEBUG_LOCK = ReentrantLock()
const _DEBUG_MAX_SIZE = 2_000_000  # 2MB

function _debug_init!()
    _DEBUG_ENABLED[] = get(ENV, "SESSIONS_DEBUG", "") in ("1", "true", "yes")
    _DEBUG_ENABLED[] || return
    dir = joinpath(homedir(), ".sessions")
    mkpath(dir)
    path = joinpath(dir, "debug.log")
    # Rotate if too large
    if isfile(path) && filesize(path) > _DEBUG_MAX_SIZE
        old = path * ".1"
        try isfile(old) && rm(old) catch end
        try mv(path, old) catch end
    end
    try
        _DEBUG_IO[] = Base.open(path, "a")
    catch
        _DEBUG_ENABLED[] = false
    end
end

function _debug_close!()
    io = _DEBUG_IO[]
    _DEBUG_IO[] = nothing
    io !== nothing && try close(io) catch end
end

"""
    dlog(tag, msg; kw...)

Write a debug log entry. No-op when SESSIONS_DEBUG is not set.
Tag is a short category like "kernel", "app", "repl".
"""
function dlog(tag::AbstractString, msg::AbstractString; kw...)
    _DEBUG_ENABLED[] || return
    io = _DEBUG_IO[]
    io === nothing && return
    lock(_DEBUG_LOCK) do
        ts = Libc.strftime("%H:%M:%S", time())
        ms = lpad(round(Int, (time() % 1) * 1000), 3, '0')
        print(io, ts, ".", ms, " [", tag, "] ", msg)
        for (k, v) in kw
            print(io, " ", k, "=", v)
        end
        println(io)
        flush(io)
    end
    nothing
end
