#!/usr/bin/env julia
# Sessions.jl Web UI
#
# Usage (from Sessions.jl root directory):
#   julia +1.12 --project=. web/app.jl dev                            # Empty notebook
#   julia +1.12 --project=. web/app.jl dev test/fixtures/basic_notebook.jl  # Load notebook

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

# Change to web directory for relative paths
cd(@__DIR__)

# =============================================================================
# Load notebook from CLI args
# =============================================================================

_notebook_path = let path = nothing
    for arg in ARGS
        arg in ("dev", "build") && continue
        if endswith(arg, ".jl") && isfile(arg)
            path = arg
        elseif endswith(arg, ".jl")
            root_path = joinpath(dirname(@__DIR__), arg)
            if isfile(root_path)
                path = root_path
            end
        end
    end
    path
end

# Global notebook state — accessible from routes and channel handlers
const WEB_STATE = Ref{Any}(nothing)

if _notebook_path !== nothing
    println("[Sessions Web] Loading notebook: $_notebook_path")
    nb = Sessions.load_notebook(_notebook_path)

    # Restore cached outputs from .sessions.toml
    session_data = Sessions.load_session(Sessions.session_path(nb.path))
    if session_data !== nothing
        Sessions.apply_session!(nb, session_data)
        println("[Sessions Web] Restored $(length(nb.cells)) cells from session cache")
    end

    ws = Sessions.Workspace(; notebook_path=nb.path)
    WEB_STATE[] = Sessions.WebNotebookState(nb, ws, false)
else
    println("[Sessions Web] No notebook specified — starting with empty notebook")
    nb = Sessions.Notebook(; path="Untitled.jl")
    Sessions.add_cell!(nb, "# Welcome to Sessions.jl\n# Add cells and start coding!")
    ws = Sessions.Workspace()
    WEB_STATE[] = Sessions.WebNotebookState(nb, ws, false)
end

# =============================================================================
# App Configuration
# =============================================================================

app = App(
    routes_dir = "src/routes",
    components_dir = "src/components",
    title = "Sessions.jl",
    output_dir = "dist",
    layout = :Layout
)

# =============================================================================
# WebSocket: Notebook Channel
# =============================================================================

Sessions.setup_web_notebook!(WEB_STATE[])
Sessions.create_cell_signals!(WEB_STATE[])

on_ws_connect() do conn
    println("[WS] Client connected: $(conn.id)")
    @async try
        Sessions.send_full_state!(WEB_STATE[], conn)
    catch e
        e isa Base.IOError || @warn "[WS] send_full_state! error" exception=e
    end
end

on_ws_disconnect() do conn
    println("[WS] Client disconnected: $(conn.id)")
end

# =============================================================================
# Run
# =============================================================================

Therapy.run(app)
