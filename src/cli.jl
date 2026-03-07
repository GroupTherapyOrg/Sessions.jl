# Layer 3: CLI — Entry points and ARGS parsing

"""
    (@main)(args)

Pkg.Apps entry point. Called by `julia -m Sessions` or the `sessions` shim.

Usage:
    sessions [file.jl]              Open notebook or file in TUI
    sessions open <file.jl>         Open notebook or file in TUI
    sessions new [file.jl]          Create new notebook
    sessions run <file.jl>          Run notebook headlessly
    sessions install-jetls          Install JETLS for real-time diagnostics
"""
function (@main)(args::Vector{String})::Cint
    # Auto-install JETLS on first run if missing
    _ensure_jetls()

    if isempty(args)
        # No args → open new notebook
        new()
        return 0
    end

    cmd = args[1]
    rest = args[2:end]

    try
        if cmd == "open"
            isempty(rest) ? new() : open(rest[1])
        elseif cmd == "new"
            path = isempty(rest) ? "Untitled.jl" : rest[1]
            new(path)
        elseif cmd == "run"
            isempty(rest) && error("Usage: sessions run <file.jl>")
            verbose = "--verbose" in rest || "-v" in rest
            path = first(filter(a -> !startswith(a, "-"), rest))
            nb = run(path; verbose)
            cells = ordered_cells(nb)
            n_err = count(c -> c.state == cell_errored, cells)
            n_err > 0 && return 1
        elseif cmd == "install-jetls"
            _install_jetls()
        elseif cmd in ("--help", "-h", "help")
            _print_help()
        elseif cmd in ("--version", "-v", "version")
            println("Sessions.jl v2.0.0")
        else
            # Bare path — treat as `open`
            if endswith(cmd, ".jl")
                open(cmd)
            else
                println(stderr, "Unknown command: $cmd")
                _print_help()
                return 1
            end
        end
    catch e
        println(stderr, sprint(showerror, e))
        return 1
    end

    return 0
end


function _print_help()
    println("Sessions.jl v2 — Terminal-Native Reactive Julia Notebook")
    println()
    println("Usage:")
    println("  sessions [file.jl]          Open notebook or file (default: new notebook)")
    println("  sessions open <file.jl>     Open notebook or file in TUI")
    println("  sessions new [file.jl]      Create new notebook")
    println("  sessions run <file.jl>      Run notebook headlessly")
    println("  sessions install-jetls      Install JETLS for real-time diagnostics")
    println("  sessions --help             Show this help")
    println("  sessions --version          Show version")
end

const _JETLS_BIN = joinpath(homedir(), ".julia", "bin", "jetls")

function _ensure_jetls()
    isfile(_JETLS_BIN) && return
    # First run — offer to install
    printstyled("Sessions.jl"; color=:green, bold=true)
    println(" — JETLS not found. Installing for real-time diagnostics...")
    println("  (This is a one-time setup, may take a minute)")
    println()
    try
        _install_jetls()
    catch e
        printstyled("  Warning: "; color=:yellow)
        println("JETLS install failed — diagnostics will be disabled.")
        println("  You can retry later with: sessions install-jetls")
        println("  Error: ", sprint(showerror, e))
    end
end

function _install_jetls()
    # Import Pkg at runtime to avoid adding it as a dependency
    Pkg = Base.require(Base.PkgId(Base.UUID("44cfe95a-1eb2-52ea-b672-e2afdf69b78f"), "Pkg"))
    Apps = getfield(Pkg, :Apps)
    printstyled("  Installing JETLS (JET.jl language server)...\n"; color=:cyan)
    Apps.add(; url="https://github.com/aviatesk/JETLS.jl", rev="release")
    if isfile(_JETLS_BIN)
        printstyled("  ✓ JETLS installed successfully\n"; color=:green)
    else
        error("JETLS binary not found at $_JETLS_BIN after install")
    end
end
