#!/usr/bin/env julia
# Sessions.jl App Entry Point
#
# Usage (from Sessions.jl root):
#   julia --project=. src/app.jl dev    # Development server
#   julia --project=. src/app.jl        # Same as dev
#
# This follows the Therapy.jl App pattern with:
# - File-based routing from src/routes/
# - Components from src/components/
# - WebSocket API for Julia code execution

# Ensure we can load the Sessions package
push!(LOAD_PATH, dirname(@__DIR__))

using Sessions
using Therapy

# Change to src directory for relative paths
cd(@__DIR__)

# =============================================================================
# Sessions App Configuration
# =============================================================================

# Sessions.jl uses a custom server since it needs WebSocket for code execution
# The UI is 100% Therapy.jl components, execution happens server-side

if length(ARGS) == 0 || ARGS[1] == "dev"
    Sessions.dev()
else
    println("Usage: julia src/app.jl [dev]")
    println("  dev - Start development server (default)")
end
