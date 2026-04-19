#!/usr/bin/env julia
# Build a PackageCompiler sysimage for Sessions.
#
# Runs as a standalone script so it can be invoked either from:
#   - `julia +1.12 --project=. scripts/build_sysimage.jl`     (dev)
#   - `sessions sysimage`                                     (CLI subcommand)
#
# Output path is Julia-version-aware so upgrading Julia doesn't yield a
# stale sysimage:
#   ~/.julia/compiled/sessions/v<julia_version>/sessions.<ext>
#
# `sessions` launches detect that path and re-exec themselves under
# `--sysimage=…` (see src/cli.jl). If the sysimage doesn't exist,
# launches proceed without it and print a tip pointing at this script.

import Pkg
let root = dirname(@__DIR__)
    if Base.active_project() != joinpath(root, "Project.toml")
        Pkg.activate(root; io = devnull)
    end
end

# PackageCompiler is a build-time-only dep — add to the active project
# on the fly if the user hasn't got it. Scoped to this script so the
# slim runtime project.toml doesn't carry it.
try
    @eval using PackageCompiler
catch
    println("[sysimage] PackageCompiler not installed — adding it now…")
    Pkg.add("PackageCompiler")
    @eval using PackageCompiler
end

const ROOT = dirname(@__DIR__)

function sysimage_path()
    depot = first(DEPOT_PATH)
    ext   = Sys.iswindows() ? ".dll" : Sys.isapple() ? ".dylib" : ".so"
    dir   = joinpath(depot, "compiled", "sessions", "v$(VERSION)")
    return joinpath(dir, "sessions$(ext)"), dir
end

function main()
    out, dir = sysimage_path()
    isdir(dir) || mkpath(dir)

    println("▸ Building Sessions sysimage")
    println("  Target        : $(out)")
    println("  Packages      : Sessions, Therapy, SessionsUI")
    println("  Precompile    : scripts/precompile_workload.jl")
    println("  (This is a one-time ~60 s build. Julia cold start afterwards drops from a few seconds to ~0.3 s.)")

    t0 = time()
    PackageCompiler.create_sysimage(
        [:Sessions, :Therapy, :SessionsUI];
        sysimage_path             = out,
        precompile_execution_file = joinpath(ROOT, "scripts", "precompile_workload.jl"),
    )
    dt = time() - t0

    println("\n✓ Sysimage built in $(round(dt; digits=1)) s → $(out)")
    println("  Future `sessions` launches will auto-load it (detected by path + Julia version).")
end

main()
