# Layer 3: CLI — Entry points and ARGS parsing

"""
    Sessions.main(args=ARGS)

Main CLI entry point. Parses command-line arguments and dispatches.

Usage:
    julia -e 'using Sessions; Sessions.main()' -- [command] [options]

Commands:
    open <file.jl>     Open notebook in TUI (default if file given)
    run <file.jl>      Run notebook headlessly
    new [file.jl]      Create new notebook and open in TUI

Options:
    --verbose, -v      Verbose output (for run mode)
"""
function main(args::Vector{String}=ARGS)
    if isempty(args)
        println("Sessions.jl v2 — Terminal-Native Reactive Julia Notebook")
        println()
        println("Usage:")
        println("  sessions open <file.jl>   Open notebook in TUI")
        println("  sessions run <file.jl>    Run notebook headlessly")
        println("  sessions new [file.jl]    Create new notebook")
        println()
        println("Or: julia -e 'using Sessions; Sessions.open(\"file.jl\")'")
        return
    end

    cmd = args[1]
    rest = args[2:end]

    if cmd == "open"
        isempty(rest) && error("Usage: sessions open <file.jl>")
        open(rest[1])
    elseif cmd == "run"
        isempty(rest) && error("Usage: sessions run <file.jl>")
        verbose = "--verbose" in rest || "-v" in rest
        path = first(filter(a -> !startswith(a, "-"), rest))
        nb = run(path; verbose)
        cells = ordered_cells(nb)
        n_done = count(c -> c.state == cell_done, cells)
        n_err = count(c -> c.state == cell_errored, cells)
        if n_err > 0
            println("$(n_done) ok, $(n_err) errors")
            exit(1)
        end
    elseif cmd == "new"
        path = isempty(rest) ? "Untitled.jl" : rest[1]
        new(path)
    else
        # If first arg looks like a file path, treat as `open`
        if endswith(cmd, ".jl") && isfile(cmd)
            open(cmd)
        else
            error("Unknown command: $cmd. Use open, run, or new.")
        end
    end
end
