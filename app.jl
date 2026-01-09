#!/usr/bin/env julia

# Sessions.jl Entry Point
# Run with: julia --project=. app.jl

using Sessions

# Start the development server
Sessions.dev(port=8080)
