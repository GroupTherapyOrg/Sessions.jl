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
using Markdown
using UUIDs
using Base64

# Change to docs directory for relative paths
cd(@__DIR__)

# =============================================================================
# Minimal JSON serializer (avoids JSON3 dependency)
# =============================================================================

"""Serialize a value to JSON string. Supports Dict, Array, String, Number, Bool, Nothing."""
function _to_json(x::AbstractDict)
    pairs = [string('"', _json_escape(string(k)), '"', ':', _to_json(v)) for (k, v) in x]
    "{" * join(pairs, ",") * "}"
end
_to_json(x::AbstractVector) = "[" * join((_to_json(v) for v in x), ",") * "]"
_to_json(x::AbstractString) = "\"" * _json_escape(x) * "\""
_to_json(x::Symbol) = "\"" * _json_escape(string(x)) * "\""
_to_json(x::Integer) = string(x)
_to_json(x::AbstractFloat) = isfinite(x) ? string(x) : "null"
_to_json(x::Bool) = x ? "true" : "false"
_to_json(::Nothing) = "null"
_to_json(x::AbstractRange) = _to_json(collect(x))
_to_json(x) = "\"" * _json_escape(string(x)) * "\""

function _json_escape(s::AbstractString)
    s = replace(s, '\\' => "\\\\")
    s = replace(s, '"' => "\\\"")
    s = replace(s, '\n' => "\\n")
    s = replace(s, '\r' => "\\r")
    s = replace(s, '\t' => "\\t")
    s
end

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
# Pre-rendered Gallery Types
# =============================================================================

"""Pre-rendered gallery for a plot cell driven by a slider."""
struct PrerenderedGallery
    slider_cell_id::UUID
    var_name::Symbol
    slider::Sessions.Slider
    images::Dict{Any, Vector{UInt8}}    # slider_value => PNG bytes (fallback)
    plotly_data::Dict{Any, String}      # slider_value => Plotly JSON string
end

# =============================================================================
# Notebook Execution Pipeline
# =============================================================================

"""
Execute a notebook for web publishing with pre-rendered slider galleries.

Returns (notebook, prerendered) where prerendered maps plot cell UUIDs
to PrerenderedGallery structs containing images for each slider value.
"""
function execute_notebook_for_web(path; verbose=false)
    nb = Sessions.load_notebook(path)
    ws = Sessions.Workspace()

    # 1. Execute all cells in topological order
    order = Sessions.execution_order(nb)

    for (cell, err) in order.errable
        cell.state = Sessions.cell_errored
        cell.output = Sessions.CellOutput()
        cell.output.error = CapturedException(
            ErrorException("Reactivity error: $(typeof(err))"),
            backtrace()
        )
        if verbose
            println("    ERROR [$(cell.id)]: reactivity error")
        end
    end

    for (i, cell) in enumerate(order.runnable)
        if verbose
            code_preview = first(cell.code, 40)
            code_preview = replace(code_preview, '\n' => "\\n")
            println("    [$i/$(length(order.runnable))] $(code_preview)")
        end
        Sessions.execute_cell!(ws, cell)
    end

    # 2. Reclassify images (headless mode lacks graphics protocol → images classified as :text)
    for cell in Sessions.ordered_cells(nb)
        if cell.output.output_type == :text && cell.output.result !== nothing
            if Base.invokelatest(showable, MIME"image/png"(), cell.output.result)
                cell.output.output_type = :image_png
                cell.output.image_data = Sessions._capture_png_bytes(cell.output.result)
                if verbose
                    println("    Reclassified cell $(cell.id) as :image_png")
                end
            end
        end
    end

    # 2b. Classify Plotly JSON outputs (Dict with "data" + "layout" keys)
    for cell in Sessions.ordered_cells(nb)
        if cell.output.output_type == :text && cell.output.result isa Dict
            r = cell.output.result
            if haskey(r, "data") && haskey(r, "layout")
                cell.output.output_type = :plotly_json
                if verbose
                    println("    Classified cell $(cell.id) as :plotly_json")
                end
            end
        end
    end

    # 3. Pre-render slider values
    prerendered = Dict{UUID, PrerenderedGallery}()
    for cell in Sessions.ordered_cells(nb)
        cell.output.output_type == :bond || continue
        bond = cell.output.result
        bond isa Sessions.Bond || continue
        slider = bond.element
        slider isa Sessions.Slider || continue

        var_name = bond.defines
        deps = Sessions.downstream_dependents(nb, [cell])
        plot_deps = filter(d -> d.output.output_type in (:image_png, :plotly_json), deps)
        isempty(plot_deps) && continue

        if verbose
            println("    Pre-rendering :$(var_name) slider ($(length(slider.values)) values × $(length(plot_deps)) plots)")
        end

        for dep in plot_deps
            images = Dict{Any, Vector{UInt8}}()
            plotly_data = Dict{Any, String}()
            for val in slider.values
                Sessions.set_bond_value!(var_name, val)
                Core.eval(ws.mod, :($var_name = $val))
                Sessions.execute_cell!(ws, dep)

                # Reclassify if needed (same headless issue)
                if dep.output.output_type == :text && dep.output.result !== nothing
                    if Base.invokelatest(showable, MIME"image/png"(), dep.output.result)
                        dep.output.output_type = :image_png
                        dep.output.image_data = Sessions._capture_png_bytes(dep.output.result)
                    end
                end

                # Capture Plotly JSON if result is a Dict with data+layout
                if dep.output.result isa Dict && haskey(dep.output.result, "data") && haskey(dep.output.result, "layout")
                    dep.output.output_type = :plotly_json
                    plotly_data[val] = _to_json(dep.output.result)
                end

                # Capture PNG fallback
                if dep.output.image_data !== nothing
                    images[val] = copy(dep.output.image_data)
                end
            end

            # Restore default value
            Sessions.set_bond_value!(var_name, slider.default)
            Core.eval(ws.mod, :($var_name = $(slider.default)))
            Sessions.execute_cell!(ws, dep)

            # Reclassify restored default too
            if dep.output.output_type == :text && dep.output.result !== nothing
                if Base.invokelatest(showable, MIME"image/png"(), dep.output.result)
                    dep.output.output_type = :image_png
                    dep.output.image_data = Sessions._capture_png_bytes(dep.output.result)
                end
            end
            if dep.output.result isa Dict && haskey(dep.output.result, "data") && haskey(dep.output.result, "layout")
                dep.output.output_type = :plotly_json
            end

            prerendered[dep.id] = PrerenderedGallery(
                cell.id, var_name, slider, images, plotly_data
            )

            if verbose
                n_img = length(images)
                n_plotly = length(plotly_data)
                println("      Plot $(dep.id): $(n_img) images, $(n_plotly) plotly datasets captured")
            end
        end
    end

    return nb, prerendered
end

# =============================================================================
# Load file-based routes + components first
# =============================================================================

Therapy.load_app!(app)

# =============================================================================
# Execute notebooks and inject as additional routes
# =============================================================================

notebooks_dir = joinpath(@__DIR__, "notebooks")
const EXECUTED_NOTEBOOKS = Dict{String, Sessions.Notebook}()
const NOTEBOOK_PRERENDERED = Dict{String, Dict{UUID, PrerenderedGallery}}()

if isdir(notebooks_dir)
    println("\nExecuting notebooks...")
    for file in sort(readdir(notebooks_dir))
        endswith(file, ".jl") || continue
        slug = replace(file, ".jl" => "")
        path = joinpath(notebooks_dir, file)
        println("  $file")

        nb, prerendered = execute_notebook_for_web(path; verbose=true)
        EXECUTED_NOTEBOOKS[slug] = nb
        NOTEBOOK_PRERENDERED[slug] = prerendered

        push!(app.routes, "/notebooks/$slug" => let nb=nb, pre=prerendered
            () -> Therapy.NotebookPage(nb; prerendered=pre)
        end)
    end
    println("  $(length(EXECUTED_NOTEBOOKS)) notebooks ready")
end

# =============================================================================
# Run - dev or build based on args
# =============================================================================

Therapy.run(app)
