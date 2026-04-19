# cli.jl — Entry point for `sessions` CLI command
#
# Installed via: Pkg.Apps.add(url="https://github.com/GroupTherapyOrg/Sessions.jl")
# Creates ~/.julia/bin/sessions
#
# Usage:
#   sessions                              # New empty notebook
#   sessions notebook.jl                  # Open notebook
#   sessions run notebook.jl              # Run headlessly (CI/scripts)
#   sessions --help                       # Show usage

function (@main)(args)
    # Filter out "--" separator (passed by shell/Pkg.Apps shim)
    args = filter(a -> a != "--", args)
    if "--help" in args || "-h" in args
        println("""
        Sessions.jl — Web-native reactive Julia notebook

        Usage:
          sessions                       Open new notebook in browser
          sessions <notebook.jl>         Open existing notebook
          sessions run <notebook.jl>     Run notebook headlessly (CI/scripts)
          sessions sysimage              Build a sysimage for faster boot (~60s one-time)
          sessions --help                Show this help

        The web IDE opens at http://127.0.0.1:8080
        """)
        return
    end

    # Resolve paths relative to the user's actual working directory
    # (Pkg.Apps shims may change cwd before invoking Julia)
    user_cwd = pwd()

    # Sysimage builder subcommand
    if !isempty(args) && args[1] == "sysimage"
        _build_sysimage()
        return
    end

    # Headless run mode
    if !isempty(args) && args[1] == "run"
        nb_path = length(args) >= 2 ? abspath(user_cwd, args[2]) : nothing
        if nb_path === nothing
            println("Error: sessions run requires a notebook path")
            println("Usage: sessions run <notebook.jl>")
            return
        end
        if !isfile(nb_path)
            println("Error: file not found: $nb_path")
            return
        end
        _maybe_reexec_with_sysimage(args)
        Sessions.run(nb_path)
        return
    end

    # Web IDE mode — launch the web server
    _maybe_reexec_with_sysimage(args)

    nb_path = nothing
    work_dir = user_cwd
    if !isempty(args)
        arg = abspath(user_cwd, args[1])
        if endswith(args[1], ".jl") && isfile(arg)
            nb_path = arg
            work_dir = dirname(arg)
        elseif isdir(arg)
            # Directory: open explorer rooted here, no notebook
            work_dir = arg
        end
    end

    _launch_web(nb_path; work_dir)
end

# ─── Sysimage integration ─────────────────────────────────────────────
# We cannot inject `--sysimage=<path>` into Pkg.Apps' julia_flags —
# those are shell-escaped before emission, so env-var / depot-path
# expansion never happens. Instead, `(@main)` detects on every launch
# whether our sysimage exists at its depot-local path and re-execs the
# process under it. One-time ~50 ms re-exec cost buys multi-second
# Julia cold start savings.

function _sysimage_path()
    depot = first(DEPOT_PATH)
    ext   = Sys.iswindows() ? ".dll" : Sys.isapple() ? ".dylib" : ".so"
    dir   = joinpath(depot, "compiled", "sessions", "v$(VERSION)")
    return joinpath(dir, "sessions$(ext)")
end

function _using_sessions_sysimage()
    imgfile = Base.JLOptions().image_file
    imgfile == C_NULL && return false
    return occursin(joinpath("compiled", "sessions"), unsafe_string(imgfile))
end

function _maybe_reexec_with_sysimage(args::Vector{String})
    _using_sessions_sysimage() && return
    path = _sysimage_path()
    if !isfile(path)
        # Suggest once so users know the option exists. Non-blocking.
        println("[sessions] tip: build a sysimage for ~10× faster boot — `sessions sysimage`")
        return
    end
    if Sys.iswindows()
        # No execv on Windows; spawn + propagate exit code. Adds a
        # process but still beats skipping the sysimage. Julia's
        # `ccall(:execv)` equivalent on Win is `_execv` but POSIX
        # re-exec semantics don't map cleanly, so keep it simple.
        julia = joinpath(Sys.BINDIR, Base.julia_exename())
        cmd = `$(julia) --sysimage=$(path) --startup-file=no -m Sessions $args`
        println("[sessions] relaunching under sysimage…")
        rc = run(cmd; wait = true)
        exit(rc.exitcode)
    end
    julia = joinpath(Sys.BINDIR, Base.julia_exename())
    println("[sessions] relaunching under sysimage…")
    argv = String["julia", "--sysimage=$(path)", "--startup-file=no", "-m", "Sessions"]
    append!(argv, args)
    cargs = [pointer(Base.cconvert(Cstring, a)) for a in argv]
    push!(cargs, C_NULL)
    GC.@preserve argv cargs begin
        ccall(:execv, Cint, (Cstring, Ptr{Ptr{Cchar}}), julia, cargs)
    end
    # If execv returns, it failed — fall through to the non-sysimage path.
    println("[sessions] sysimage re-exec failed; continuing without")
end

function _build_sysimage()
    script = joinpath(@__DIR__, "..", "scripts", "build_sysimage.jl")
    if !isfile(script)
        println("Error: sysimage builder not found at $(script)")
        return
    end
    # Spawn a fresh Julia process so PackageCompiler doesn't have to
    # compete with the already-loaded Sessions/Therapy for memory.
    julia = joinpath(Sys.BINDIR, Base.julia_exename())
    project_root = dirname(@__DIR__)
    run(`$(julia) --startup-file=no --project=$(project_root) $(script)`)
end

function _launch_web(nb_path::Union{String, Nothing}; work_dir::String=pwd())
    # The web app entry point
    web_app_path = joinpath(@__DIR__, "..", "app.jl")
    if !isfile(web_app_path)
        println("Error: web app not found at $web_app_path")
        return
    end

    # Set working directory so file explorer + terminal root there
    try cd(work_dir) catch; end

    # Build ARGS for the web app
    web_args = ["dev"]
    if nb_path !== nothing
        push!(web_args, nb_path)
    end

    # Run in Main so that `Main.Sessions` and `Main.WEB_STATE` are accessible
    # to web components (they reference Main.Sessions.*, Main.WEB_STATE[], etc.)
    old_args = copy(ARGS)
    empty!(ARGS)
    append!(ARGS, web_args)
    try
        Main.eval(:(include($web_app_path)))
    finally
        empty!(ARGS)
        append!(ARGS, old_args)
    end
end
