# Sessions sysimage precompile workload.
#
# Executed by PackageCompiler.create_sysimage(; precompile_execution_file=…)
# to capture every compile event the normal `sessions` boot path produces.
# The goal is to bake every method we call during cold start into the
# sysimage so the user never pays a JIT-compile cost for:
#   - Therapy server + component loading
#   - Sessions notebook parsing + topology
#   - WebSocket channel registration
#   - The first SSR render
#
# This file is NOT run at `sessions` launch — only during sysimage build.
# Keep it small enough that PackageCompiler completes in <~60s.

import Pkg
let root = dirname(@__DIR__)
    if Base.active_project() != joinpath(root, "Project.toml")
        Pkg.activate(root; io = devnull)
    end
end

using Therapy
using Sessions
using SessionsUI
using UUIDs

const ROOT = dirname(@__DIR__)

# ── Package load (biggest TTFB contributor) ────────────────────
# `using` alone triggers precompile-load; exercise the public
# surface so the sysimage captures the first-call methods too.

# ── Notebook IO ────────────────────────────────────────────────
const FIX = joinpath(ROOT, "test", "fixtures", "welcome.jl")
if isfile(FIX)
    nb = Sessions.load_notebook(FIX)
    Sessions.serialize_notebook(nb)
    Sessions.update_topology!(nb)
    Sessions.execution_order(nb)
    Sessions.stale_cells(nb)
    for c in Sessions.ordered_cells(nb)
        Sessions.is_stale(c)
        Sessions.is_never_run(c)
        Sessions.source_hash(c)
    end
end

# ── App construction + component discovery ─────────────────────
app = Therapy.App(
    routes_dir     = joinpath(ROOT, "src", "routes"),
    components_dir = joinpath(ROOT, "src", "components"),
    title          = "Sessions.jl",
    output_dir     = joinpath(ROOT, "dist"),
    layout         = :Layout,
    prebaked_dir   = joinpath(ROOT, "static", "islands"),
)
try
    Therapy.load_app!(app)
    Therapy.compile_interactive_components(app)
catch e
    @warn "Workload boot failed (non-fatal, sysimage still builds)" exception = e
end

# ── Cell state enumerations + output helpers ───────────────────
Sessions.CellState
Sessions.cell_idle
Sessions.cell_done
Sessions.CellOutput()
Sessions.classify_output(nothing)
Sessions.classify_output("hi")
Sessions.classify_output(42)

println("[precompile] workload complete")
