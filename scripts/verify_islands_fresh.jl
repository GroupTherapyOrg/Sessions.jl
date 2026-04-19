#!/usr/bin/env julia
# Verify committed static/islands/ matches current @island sources.
#
# Fast path for CI: re-hashes each island's source file and compares
# against the `source_sha256` entry in static/islands/manifest.toml.
# No WASM compile involved — just a few SHA-256 computations. Exits
# non-zero if any island is stale, with a hint to re-run
# scripts/bake_islands.jl.
#
# Usage:
#   julia +1.12 --project=. scripts/verify_islands_fresh.jl

import Pkg
let root = dirname(@__DIR__)
    if Base.active_project() != joinpath(root, "Project.toml")
        Pkg.activate(root; io = devnull)
    end
end

using SHA
using TOML

const ROOT     = dirname(@__DIR__)
const MANIFEST = joinpath(ROOT, "static", "islands", "manifest.toml")

if !isfile(MANIFEST)
    println("✗ static/islands/manifest.toml missing — run `julia scripts/bake_islands.jl`")
    exit(1)
end

manifest = TOML.parsefile(MANIFEST)
islands  = get(manifest, "islands", Dict{String, Any}())
isempty(islands) && (println("✗ no islands in manifest"); exit(1))

stale = String[]
for (name, entry) in islands
    src = joinpath(ROOT, get(entry, "source", ""))
    isfile(src) || (push!(stale, "$name (source missing: $src)"); continue)
    live = bytes2hex(SHA.sha256(read(src)))
    baked = get(entry, "source_sha256", "")
    live == baked && continue
    push!(stale, "$name ($(basename(src)))")
end

if isempty(stale)
    println("✓ all $(length(islands)) islands fresh")
    exit(0)
else
    println("✗ $(length(stale)) stale island(s):")
    for s in stale; println("    - $(s)"); end
    println("\nRe-bake with: julia +1.12 --project=. scripts/bake_islands.jl")
    exit(1)
end
