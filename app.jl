#!/usr/bin/env julia
# Sessions.jl Web UI
#
# Usage:
#   julia +1.12 --project=. app.jl dev                              # Empty notebook
#   julia +1.12 --project=. app.jl dev test/fixtures/basic_notebook.jl  # Load notebook

# Use local Therapy.jl if available (sibling directory)
let local_therapy = joinpath(@__DIR__, "..", "Therapy.jl")
    isdir(local_therapy) && push!(LOAD_PATH, local_therapy)
end
push!(LOAD_PATH, joinpath(@__DIR__, "SessionsUI"))

using Therapy
using Sessions
using SessionsUI
using UUIDs
import HTTP

const USER_CWD = pwd()
cd(@__DIR__)

# --- Load notebook from CLI args ---

_notebook_path = let path = nothing
    for arg in ARGS
        arg in ("dev", "build") && continue
        if endswith(arg, ".jl") && isfile(arg)
            path = arg
        elseif endswith(arg, ".jl")
            root_path = joinpath(@__DIR__, arg)
            isfile(root_path) && (path = root_path)
        end
    end
    path
end

const WEB_STATE = Ref{Any}(nothing)

if _notebook_path !== nothing
    println("[Sessions] Loading notebook: $_notebook_path")
    nb = Sessions.load_notebook(_notebook_path)
    session_data = Sessions.load_session(Sessions.session_path(nb.path))
    if session_data !== nothing
        Sessions.apply_session!(nb, session_data)
        println("[Sessions] Restored $(length(nb.cells)) cells from session cache")
    end
    worker = Sessions.NotebookWorker(; notebook_path=nb.path)
    tab = Sessions.WebTab(uuid4(), nb, worker, basename(nb.path), abspath(nb.path))
    WEB_STATE[] = Sessions.WebNotebookState([tab], 1, false, false)
else
    println("[Sessions] No notebook specified — starting empty")
    nb = Sessions.Notebook(; path="Untitled.jl")
    Sessions.add_cell!(nb, "# Welcome to Sessions.jl\n# Add cells and start coding!")
    worker = Sessions.NotebookWorker()
    tab = Sessions.WebTab(uuid4(), nb, worker, "Untitled.jl", abspath("Untitled.jl"))
    WEB_STATE[] = Sessions.WebNotebookState([tab], 1, false, false)
end

# --- Terminal state (needed before API middleware) ---
const TERM_STATE = Sessions.TerminalState()

# --- API routes middleware ---
# API route files define parameterized route tables; Therapy's page renderer
# can't call them, so we register them as HTTP middleware via create_api_router.

include("src/api/files.jl")
include("src/api/notebook.jl")
include("src/api/terminal.jl")

function _get_root_dir()
    try
        dirname(abspath(Sessions.active_tab(WEB_STATE[]).path))
    catch
        USER_CWD
    end
end

_api_routes = vcat(
    files_api_routes(_get_root_dir),
    notebook_api_routes(() -> WEB_STATE[]),
    terminal_api_routes(() -> TERM_STATE, () -> WEB_STATE[])
)
const _api_handler = create_api_router(_api_routes)

function ApiMiddleware()
    return function(handler)
        return function(req::HTTP.Request)
            path = HTTP.URI(req.target).path
            if startswith(path, "/api/")
                return _api_handler(req)
            end
            return handler(req)
        end
    end
end

# --- App ---

app = App(
    routes_dir = "src/routes",
    components_dir = "src/components",
    title = "Sessions.jl",
    output_dir = "dist",
    layout = :Layout,
    middleware = [ApiMiddleware()]
)

# Mount /static/* via Therapy's Oxygen-style staticfiles. Replaces the
# hand-rolled StaticFilesMiddleware that lived here previously — same
# behaviour (MIME-typed responses + Cache-Control), just delegated to
# the framework so SSG `build(app)` picks it up too.
Therapy.staticfiles(app, joinpath(@__DIR__, "static"), "static";
    headers = ["Cache-Control" => "public, max-age=3600"])

# --- WebSocket channel handlers ---

Sessions.setup_notebook_channel!(WEB_STATE[])
Sessions.setup_files_channel!(WEB_STATE[])
Sessions.create_cell_signals!(WEB_STATE[])
Sessions.start_web_watchers!(WEB_STATE[])

Sessions.setup_terminal_channel!(TERM_STATE, WEB_STATE[])

on_ws_connect() do conn
    println("[WS] Client connected: $(conn.id)")
    Therapy.subscribe(conn, "notebook")
    Therapy.subscribe(conn, "file_explorer")
    Therapy.subscribe(conn, "terminal")
    @async try
        Sessions.send_full_state!(WEB_STATE[], conn)
    catch e
        e isa Base.IOError || @warn "[WS] send_full_state! error" exception=e
    end
end

on_ws_disconnect() do conn
    println("[WS] Client disconnected: $(conn.id)")
end

# --- Run ---

Therapy.run(app)
