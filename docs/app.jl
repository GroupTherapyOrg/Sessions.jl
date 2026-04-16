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
# Notebook publishing — DISABLED until the new build pipeline lands
# =============================================================================
# The previous notebook-as-route flow used `execute_notebook_for_web` +
# `NotebookPage` + `PrerenderedGallery`, a slider-prerendering scheme
# (PlutoSliderServer-style). That whole pipeline was removed because
# the project's publish target is Therapy + WASM @islands instead.
# When the new `app.jl build` pipeline lands (Phase 3), this section
# will become a thin call into it.

# =============================================================================
# Run - dev or build based on args
# =============================================================================

Therapy.run(app)
