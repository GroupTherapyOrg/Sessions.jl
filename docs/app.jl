#!/usr/bin/env julia
# Sessions.jl Documentation Site
#
# Usage (from Sessions.jl root directory):
#   julia +1.12 --project=. docs/app.jl dev      # also works (auto-activates docs env)
#   julia +1.12 --project=docs docs/app.jl dev   # Development server
#   julia +1.12 --project=docs docs/app.jl build # Build static site to docs/dist
#
# The docs project (docs/Project.toml) declares its own deps — including
# demo-only packages like WasmPlot + DataFrames used by extracted
# notebooks — so they do not leak into the root Sessions runtime.
# For convenience, this script re-activates docs/ on launch so the shorter
# `--project=.` command still works.

import Pkg
let docs_env = @__DIR__
    if Base.active_project() != joinpath(docs_env, "Project.toml")
        Pkg.activate(docs_env; io = devnull)
    end
end

using Therapy
using Sessions
using UUIDs

# Change to docs directory for relative paths
cd(@__DIR__)

# =============================================================================
# App Configuration
# =============================================================================

app = App(
    routes_dir = "src/routes",
    components_dir = "src/components",
    title = "Sessions.jl",
    output_dir = "dist",
    base_path = "/Sessions.jl",
    layout = :Layout
)

# =============================================================================
# Load file-based routes + components first
# =============================================================================

Therapy.load_app!(app)

# =============================================================================
# Register routes for Sessions-extracted notebooks
# =============================================================================
# Each .jl file under docs/src/components/notebooks/ is a self-contained
# Therapy component (output of `Sessions.extract_notebook(...)`).
# `Therapy.load_app!` above walks `components/` recursively, so the
# notebook files are already included into Main.TherapyApp and their
# `@island` definitions are in the island registry. All we need to
# do here is wire up the /notebooks/<slug>/ routes + expose the
# slug → function map to the gallery + sidebar (PageComponents.jl).
#
# Slug = lowercased filename without .jl. Dropping a freshly-extracted
# notebook in the dir + restarting picks it up automatically.

const EXTRACTED_NOTEBOOKS = Dict{String, Function}()

let extracted_dir = joinpath(@__DIR__, "src", "components", "notebooks")
    if isdir(extracted_dir)
        host = isdefined(Main, :TherapyApp) ? getfield(Main, :TherapyApp) : Main
        for file in sort(readdir(extracted_dir))
            endswith(file, ".jl") || continue
            name_sym = Symbol(splitext(file)[1])       # "Welcome.jl" → :Welcome
            slug = lowercase(String(name_sym))         # :Welcome → "welcome"
            try
                # World-age dance: the @island definition reached its
                # final world AFTER `Therapy.load_app!` returned, so a
                # bare `getfield` triggers Julia 1.12's strict-binding
                # warning. `invokelatest` does the right thing.
                raw = Base.invokelatest(getfield, host, name_sym)
                # Extracted notebooks export an `@island` (IslandDef).
                # Routes + EXTRACTED_NOTEBOOKS both expect a plain
                # Function — wrap the IslandDef in a thunk so the
                # ::Function conversion on `push!(routes, …)` succeeds.
                fn = raw isa Function ? raw : (() -> Base.invokelatest(raw))
                EXTRACTED_NOTEBOOKS[slug] = fn
                push!(app.routes, "/notebooks/$(slug)/" => fn)
                println("  Registered extracted notebook: /notebooks/$(slug)/  ← $(file)")
            catch e
                @warn "[docs] Failed to register extracted notebook" file=file exception=e
            end
        end
    end
end

# =============================================================================
# Run - dev or build based on args
# =============================================================================

Therapy.run(app)
