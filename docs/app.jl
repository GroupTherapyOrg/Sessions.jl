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

# Use local Suite.jl if available (sibling directory)
local_suite = joinpath(dirname(@__DIR__), "..", "Suite.jl")
if isdir(local_suite)
    push!(LOAD_PATH, local_suite)
end

# Use local Sessions.jl package
push!(LOAD_PATH, dirname(@__DIR__))

using Therapy
using Suite
using Sessions
using Markdown

# Resolve name conflicts: Suite components take precedence over Therapy HTML elements
import Suite: Button, Input, Label, P, H1, H2, H3, H4, CodeBlock, Table, Kbd

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
# Notebook Execution Pipeline
# =============================================================================

# Load file-based routes + components first
Therapy.load_app!(app)

# Execute notebooks and inject as additional routes
notebooks_dir = joinpath(@__DIR__, "notebooks")
const EXECUTED_NOTEBOOKS = Dict{String, Sessions.Notebook}()

if isdir(notebooks_dir)
    println("\nExecuting notebooks...")
    for file in sort(readdir(notebooks_dir))
        endswith(file, ".jl") || continue
        slug = replace(file, ".jl" => "")
        path = joinpath(notebooks_dir, file)
        println("  $file")
        nb = Sessions.run(path; verbose=true)
        EXECUTED_NOTEBOOKS[slug] = nb
        # NotebookPage is defined in Therapy's module (via load_app! include)
        push!(app.routes, "/notebooks/$slug" => let nb=nb; () -> Therapy.NotebookPage(nb); end)
    end
    println("  $(length(EXECUTED_NOTEBOOKS)) notebooks ready")
end

# =============================================================================
# Run - dev or build based on args
# =============================================================================

Therapy.run(app)
