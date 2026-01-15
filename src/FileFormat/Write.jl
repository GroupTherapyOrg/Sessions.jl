# Write.jl - Save notebooks in Pluto format
#
# Writes notebooks to .jl files in Pluto's format for compatibility.

using UUIDs

"""
    save_notebook(notebook::Notebook, path::String)

Save a notebook to a Pluto-format .jl file.
"""
function save_notebook(notebook::Notebook, path::String)
    io = IOBuffer()

    # Header
    println(io, "### A Pluto.jl notebook ###")
    println(io, "# v0.19.0")
    println(io)

    # Write cells in topological order (so file can be run directly)
    cells_in_topo_order = try
        get_all_execution_order(notebook)
    catch
        # Fallback to display order if topo sort fails
        cells_in_order(notebook)
    end

    for cell in cells_in_topo_order
        write_cell(io, cell)
    end

    # Cell order section (display order)
    println(io, "# ╔═╡ Cell order:")
    for cell_id in notebook.cell_order
        cell = get(notebook.cells, cell_id, nothing)
        if cell !== nothing
            # ╠═ for code cells, ╟─ for markdown (we treat all as code for now)
            println(io, "# ╠═$(cell_id)")
        end
    end
    println(io)

    # Project.toml
    if !isempty(notebook.project_toml)
        println(io, "# ╔═╡ Project.toml")
        println(io, notebook.project_toml)
        println(io)
    end

    # Manifest.toml
    if !isempty(notebook.manifest_toml)
        println(io, "# ╔═╡ Manifest.toml")
        println(io, notebook.manifest_toml)
    end

    # Write to file
    content = String(take!(io))
    write(path, content)

    # Update notebook state
    notebook.path = path
    notebook.modified = false
end

"""
Write a single cell to the IO buffer.
"""
function write_cell(io::IO, cell::Cell)
    println(io, "# ╔═╡ $(cell.id)")
    if !isempty(cell.code)
        println(io, cell.code)
    end
    println(io)
end

"""
    export_to_html(notebook::Notebook, path::String)

Export notebook as a standalone HTML file (for static viewing).
"""
function export_to_html(notebook::Notebook, path::String)
    io = IOBuffer()

    println(io, """<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>$(notebook.path === nothing ? "Untitled" : basename(notebook.path))</title>
    <style>
        body { font-family: system-ui, sans-serif; max-width: 900px; margin: 0 auto; padding: 2rem; }
        .cell { margin-bottom: 1.5rem; border: 1px solid #e5e7eb; border-radius: 8px; overflow: hidden; }
        .cell-code { background: #f9fafb; padding: 1rem; font-family: monospace; white-space: pre-wrap; }
        .cell-output { padding: 1rem; border-top: 1px solid #e5e7eb; }
        .cell-error { background: #fef2f2; color: #991b1b; }
    </style>
</head>
<body>
    <h1>$(notebook.path === nothing ? "Untitled Notebook" : basename(notebook.path))</h1>
""")

    for cell_id in notebook.cell_order
        cell = get(notebook.cells, cell_id, nothing)
        if cell === nothing
            continue
        end

        println(io, """    <div class="cell">""")
        println(io, """        <div class="cell-code">$(escape_html_content(cell.code))</div>""")

        if cell.output !== nothing && !isempty(cell.output.html)
            css_class = cell.state == CELL_ERROR ? "cell-output cell-error" : "cell-output"
            println(io, """        <div class="$css_class">$(cell.output.html)</div>""")
        end

        println(io, """    </div>""")
    end

    println(io, """</body>
</html>""")

    write(path, String(take!(io)))
end

"""
Escape HTML content for safe embedding.
"""
function escape_html_content(s::String)
    s = replace(s, "&" => "&amp;")
    s = replace(s, "<" => "&lt;")
    s = replace(s, ">" => "&gt;")
    return s
end
