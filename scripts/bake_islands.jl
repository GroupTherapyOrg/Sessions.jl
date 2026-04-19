#!/usr/bin/env julia
# Pre-bake IDE @island WASM bytes so `sessions` never has to compile at
# runtime. Loads the IDE App, walks every registered @island, runs
# Therapy.compile_island(name; optimize_wasm=true), and writes the
# resulting JS loader (with WASM bytes embedded as base64) to
# static/islands/<name>.js. A TOML manifest next to the loaders records
# per-island source SHA-256 hashes + Julia / Therapy / WasmTarget versions
# so Therapy's runtime loader can detect staleness and fall back to
# live compile if anything drifts.
#
# Usage (from repo root):
#   julia +1.12 --project=. scripts/bake_islands.jl
#
# Commit the resulting static/islands/ tree to git — downstream
# `Pkg.Apps.add` users never pay the compile cost because the bytes
# are right there in their package cache.

import Pkg
let root = dirname(@__DIR__)
    if Base.active_project() != joinpath(root, "Project.toml")
        Pkg.activate(root; io = devnull)
    end
end

# Local Therapy clone if present (development convenience).
let local_therapy = joinpath(@__DIR__, "..", "..", "Therapy.jl")
    isdir(local_therapy) && push!(LOAD_PATH, local_therapy)
end

using Therapy
using Sessions
using SessionsUI
using SHA
using TOML
using Dates

const ROOT       = dirname(@__DIR__)
const COMP_DIR   = joinpath(ROOT, "src", "components")
const OUT_DIR    = joinpath(ROOT, "static", "islands")

# Map island name → .jl source file. Two-pass lookup:
#   (1) exact filename match (CellView → CellView.jl)
#   (2) fallback: scan every component .jl for `@island <Name>(`
#       so islands defined in a differently-named file (e.g.
#       NotebookIsland inside Notebook.jl) still resolve.
function _source_for(name::AbstractString)
    target = lowercase(string(name))
    hit = nothing
    for (root, _, files) in walkdir(COMP_DIR)
        for f in files
            endswith(f, ".jl") || continue
            lowercase(splitext(f)[1]) == target && return joinpath(root, f)
        end
    end
    # Fallback: grep each file for `@island function <Name>(` (Therapy's
    # canonical form) or the bare `@island <Name>(` shorthand.
    needle_fn   = "@island function $(name)("
    needle_bare = "@island $(name)("
    for (root, _, files) in walkdir(COMP_DIR)
        for f in files
            endswith(f, ".jl") || continue
            path = joinpath(root, f)
            src  = read(path, String)
            (occursin(needle_fn, src) || occursin(needle_bare, src)) && return path
        end
    end
    return nothing
end

function main()
    # Mirror Sessions' app.jl minimally — enough to get @island
    # definitions into the registry. Skip everything Malt / PTY /
    # WebSocket: the bake never serves traffic.
    cd(ROOT)

    app = Therapy.App(
        routes_dir     = joinpath(ROOT, "src", "routes"),
        components_dir = joinpath(ROOT, "src", "components"),
        title          = "Sessions.jl",
        output_dir     = joinpath(ROOT, "dist"),
        layout         = :Layout,
    )

    println("Loading app (routes + components)…")
    Therapy.load_app!(app)
    println("  $(length(app.interactive)) @island components discovered")

    isdir(OUT_DIR) || mkpath(OUT_DIR)

    # Clear any stale .js from a previous bake so deleted islands
    # don't linger. The manifest is overwritten below.
    for f in readdir(OUT_DIR; join = true)
        endswith(f, ".js") && rm(f; force = true)
    end

    manifest = Dict{String, Any}(
        "baked_at"         => string(Dates.now()),
        "julia_version"    => string(VERSION),
        "therapy_version"  => string(pkgversion(Therapy)),
        "wasmtarget_version" => _try_pkgversion(:WasmTarget),
        "sessions_version" => string(pkgversion(Sessions)),
        "islands"          => Dict{String, Any}(),
    )

    for ic in app.interactive
        ic.component === nothing && continue
        name = ic.name
        src_path = _source_for(name)
        if src_path === nothing
            @warn "Could not locate source file for island; skipping" name
            continue
        end
        src_sha = bytes2hex(sha256(read(src_path)))

        println("▸ Baking $(name)")
        result = Base.invokelatest(Therapy.compile_island, Symbol(name);
                                   optimize_wasm = true)

        js_path = joinpath(OUT_DIR, "$(name).js")
        write(js_path, result.js)

        manifest["islands"][name] = Dict(
            "source"        => relpath(src_path, ROOT),
            "source_sha256" => src_sha,
            "wasm_size"     => result.wasm_size,
            "n_signals"     => result.n_signals,
            "n_handlers"    => result.n_handlers,
        )

        kb = round(result.wasm_size / 1024; digits = 1)
        println("    WASM: $(kb) KB  |  signals: $(result.n_signals)  |  handlers: $(result.n_handlers)")
    end

    open(joinpath(OUT_DIR, "manifest.toml"), "w") do io
        TOML.print(io, manifest; sorted = true)
    end

    n = length(manifest["islands"])
    println("\n✓ Baked $(n) island(s) → $(relpath(OUT_DIR, ROOT))")
end

# pkgversion can return nothing for stdlibs / unregistered deps; coerce
# to string for manifest serialization.
function _try_pkgversion(name::Symbol)
    try
        m = Base.require_stdlib isa Function ? nothing : nothing
        for (uuid, pkg) in Base.loaded_modules
            nameof(pkg) === name && return string(pkgversion(pkg))
        end
    catch
    end
    return "unknown"
end

main()
