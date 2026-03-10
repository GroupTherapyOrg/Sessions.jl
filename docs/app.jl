#!/usr/bin/env julia
# Sessions.jl Documentation Site
#
# Usage (from Sessions.jl root directory):
#   julia +1.12 --project=. docs/app.jl dev    # Development server with HMR
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
# Execute notebooks and inject as additional routes
# =============================================================================

notebooks_dir = joinpath(@__DIR__, "notebooks")
const EXECUTED_NOTEBOOKS = Dict{String, Sessions.Notebook}()
const NOTEBOOK_PRERENDERED = Dict{String, Dict{UUID, Sessions.PrerenderedGallery}}()

if isdir(notebooks_dir)
    println("\nExecuting notebooks...")
    for file in sort(readdir(notebooks_dir))
        endswith(file, ".jl") || continue
        slug = replace(file, ".jl" => "")
        path = joinpath(notebooks_dir, file)
        println("  $file")

        nb, prerendered = Sessions.execute_notebook_for_web(path; verbose=true)
        EXECUTED_NOTEBOOKS[slug] = nb
        NOTEBOOK_PRERENDERED[slug] = prerendered

        push!(app.routes, "/notebooks/$slug" => let nb=nb, pre=prerendered
            () -> Therapy.NotebooksLayout(
                Therapy.PageHeader(Sessions.notebook_title(nb), ""),
                Sessions.NotebookPage(nb; prerendered=pre))
        end)
    end
    println("  $(length(EXECUTED_NOTEBOOKS)) notebooks ready")
end

# =============================================================================
# Run - dev or build based on args
# =============================================================================

Therapy.run(app)
