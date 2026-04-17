#!/usr/bin/env julia
# Sessions.jl Documentation Site
#
# Usage (from Sessions.jl root directory):
#   julia +1.12 --project=. docs/app.jl dev    # Development server
#   julia +1.12 --project=. docs/app.jl build  # Build static site to docs/dist

# Use local Therapy.jl if available (sibling directory)
local_therapy = joinpath(dirname(@__DIR__), "..", "Therapy.jl")
if isdir(local_therapy)
    push!(LOAD_PATH, local_therapy)
end

# Use local Sessions.jl package
push!(LOAD_PATH, dirname(@__DIR__))

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
# Auto-discover Sessions-extracted notebooks
# =============================================================================
# Each .jl file under docs/src/components/notebooks/ is a self-contained
# Therapy component (output of `Sessions.extract_notebook(...)`). They
# live in components/ — not their own tree — because that's exactly
# what they are: regular Therapy components. Shadcn-style.
#
# For every file `Foo.jl` we:
#   1. Include it into Main.TherapyApp so its `function Foo()` is in scope.
#   2. Register a route at /notebooks/<slug>/ pointing at that function.
#   3. Add the slug → function entry to the global `EXTRACTED_NOTEBOOKS`
#      dict the gallery + sidebar iterate (PageComponents.jl).
#
# Slug = lowercased filename without .jl. Dropping a freshly-extracted
# notebook in the dir + restarting picks it up automatically.

const EXTRACTED_NOTEBOOKS = Dict{String, Function}()

let extracted_dir = joinpath(@__DIR__, "src", "components", "notebooks")
    if isdir(extracted_dir)
        host = isdefined(Main, :TherapyApp) ? getfield(Main, :TherapyApp) : Main
        for file in sort(readdir(extracted_dir))
            endswith(file, ".jl") || continue
            path = joinpath(extracted_dir, file)
            name_sym = Symbol(splitext(file)[1])      # "Welcome.jl" → :Welcome
            slug = lowercase(String(name_sym))         # :Welcome → "welcome"
            try
                Base.include(host, path)
                # World-age dance: the function we just `include`d
                # is in a later world than this loop, so a bare
                # `getfield` triggers Julia 1.12's strict-binding
                # warning. invokelatest does the right thing.
                fn = Base.invokelatest(getfield, host, name_sym)
                EXTRACTED_NOTEBOOKS[slug] = fn
                push!(app.routes, "/notebooks/$(slug)/" => fn)
                println("  Registered extracted notebook: /notebooks/$(slug)/  ← $(file)")
            catch e
                @warn "[docs] Failed to load extracted notebook" file=path exception=e
            end
        end
    end
end

# =============================================================================
# Run - dev or build based on args
# =============================================================================

Therapy.run(app)
