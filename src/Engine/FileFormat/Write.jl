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

    # Header (Pluto-compatible)
    println(io, "### A Pluto.jl notebook ###")
    println(io, "# v0.19.0")
    println(io)

    # Sessions.jl metadata (as comments — ignored by Pluto, parsed by Sessions)
    println(io, "# ╔═╡ Sessions.jl metadata")
    println(io, "# sessions_version = \"$(SESSIONS_VERSION)\"")
    if !isempty(notebook.title)
        println(io, "# title = \"$(escape_metadata(notebook.title))\"")
    end
    if !isempty(notebook.author)
        println(io, "# author = \"$(escape_metadata(notebook.author))\"")
    end
    if notebook.created_at !== nothing
        println(io, "# created_at = $(notebook.created_at)")
    end
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
            # ╠═ for visible cells, ╟─ for folded cells
            if cell.folded
                println(io, "# ╟─$(cell_id)")
            else
                println(io, "# ╠═$(cell_id)")
            end
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
    export_to_html(notebook::Notebook)

Export notebook as a standalone HTML string with Sessions.jl warm theme styling.
Self-contained — all CSS inline, no external dependencies.
"""
function export_to_html(notebook::Notebook)
    io = IOBuffer()
    title = notebook.path === nothing ? "Untitled Notebook" : basename(notebook.path)

    println(io, """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>$(escape_html_content(title))</title>
    <style>
        :root {
            --bg-main: #f0ece4; --bg-card: #f8f7f4; --border: #e8e3d9;
            --text-primary: #33302c; --text-secondary: #5c5650; --text-muted: #8a847c;
            --accent: #389826; --accent-secondary: #4063d8;
            --error: #cb3c33; --purple: #9558b2;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg-main: #1a1918; --bg-card: #111110; --border: #252422;
                --text-primary: #e8e3d9; --text-secondary: #a09a92; --text-muted: #6b655e;
            }
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: Optima, Palatino, 'EB Garamond', Georgia, serif;
            background: var(--bg-main); color: var(--text-primary);
            max-width: 900px; margin: 0 auto; padding: 2rem 1.5rem;
            line-height: 1.6;
        }
        h1 { font-size: 1.75rem; font-weight: 400; margin-bottom: 0.25rem; letter-spacing: 0.02em; }
        .subtitle { font-size: 0.7rem; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.1em; margin-bottom: 2rem; }
        .cell { margin-bottom: 1.5rem; }
        .cell-output {
            padding: 0.5rem 0; font-size: 0.8rem;
            color: var(--accent); opacity: 0.55;
            font-family: 'JuliaMono', 'Fira Code', 'SF Mono', monospace;
        }
        .cell-output img { max-width: 100%; border-radius: 6px; }
        .cell-output table { border-collapse: collapse; width: 100%; }
        .cell-output th, .cell-output td { padding: 0.25rem 0.5rem; border: 1px solid var(--border); text-align: left; font-size: 0.75rem; }
        .cell-separator { border-top: 1px dashed var(--border); margin: 0.25rem 0; }
        .cell-code {
            background: var(--bg-card); border: 1px solid var(--border); border-radius: 6px;
            padding: 0.75rem 1rem; font-family: 'JuliaMono', 'Fira Code', 'SF Mono', monospace;
            font-size: 0.78rem; white-space: pre-wrap; word-break: break-word;
            line-height: 1.5; color: var(--text-primary); border-left: 2px solid var(--border);
        }
        .cell-code.has-output { border-left-color: var(--accent); border-left-width: 2px; opacity: 0.85; }
        .cell-code.markdown { border-left-color: var(--purple); opacity: 0.75; }
        .cell-code.error { border-left-color: var(--error); }
        .cell-error { background: rgba(203,60,51,0.05); color: var(--error); padding: 0.5rem 1rem; border-radius: 6px; font-family: monospace; font-size: 0.75rem; white-space: pre-wrap; }
        .markdown-rendered { font-family: Optima, Palatino, 'EB Garamond', Georgia, serif; }
        .markdown-rendered h1 { font-size: 1.75rem; font-weight: 300; margin: 1rem 0 0.5rem; }
        .markdown-rendered h2 { font-size: 1.25rem; font-weight: 400; margin: 0.75rem 0 0.5rem; }
        .markdown-rendered h3 { font-size: 1.05rem; font-weight: 500; margin: 0.5rem 0 0.25rem; }
        .markdown-rendered code { background: rgba(56,152,38,0.06); padding: 0.1rem 0.3rem; border-radius: 3px; font-size: 0.85em; font-family: 'JuliaMono', 'Fira Code', monospace; }
        .markdown-rendered pre code { display: block; background: var(--bg-card); border: 1px solid var(--border); border-radius: 6px; padding: 0.75rem 1rem; }
        .markdown-rendered a { color: var(--accent-secondary); }
        .footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid var(--border); font-size: 0.65rem; color: var(--text-muted); }
    </style>
</head>
<body>
    <h1>$(escape_html_content(title))</h1>
    <div class="subtitle">$(length(notebook.cell_order)) cells &middot; Exported from Sessions.jl</div>
""")

    for cell_id in notebook.cell_order
        cell = get(notebook.cells, cell_id, nothing)
        cell === nothing && continue

        is_md = is_markdown(cell)
        has_output = cell.output !== nothing && !isempty(cell.output.html)
        has_error = cell.state == CELL_ERROR && has_output

        println(io, """    <div class="cell">""")

        # Markdown cells: render as HTML
        if is_md && cell.folded
            println(io, """        <div class="markdown-rendered">$(render_markdown_html(cell.code))</div>""")
        else
            # Output above code (matching IDE layout)
            if has_error
                println(io, """        <div class="cell-error">$(cell.output.html)</div>""")
            elseif has_output
                println(io, """        <div class="cell-output">$(cell.output.html)</div>""")
                println(io, """        <div class="cell-separator"></div>""")
            end

            # Code card
            code_class = if has_error
                "cell-code error"
            elseif is_md
                "cell-code markdown"
            elseif has_output
                "cell-code has-output"
            else
                "cell-code"
            end
            println(io, """        <div class="$(code_class)">$(escape_html_content(cell.code))</div>""")
        end

        println(io, """    </div>""")
    end

    println(io, """    <div class="footer">Generated by Sessions.jl</div>
</body>
</html>""")

    return String(take!(io))
end

# Backward-compatible file export
function export_to_html(notebook::Notebook, path::String)
    write(path, export_to_html(notebook))
end

"""
    export_to_script(notebook::Notebook)

Export notebook as a Julia script. Code cells are included as-is,
markdown cells are converted to block comments.
"""
function export_to_script(notebook::Notebook)
    io = IOBuffer()
    title = notebook.path === nothing ? "Untitled" : basename(notebook.path)

    println(io, "# $(title)")
    println(io, "# Exported from Sessions.jl")
    println(io)

    for cell_id in notebook.cell_order
        cell = get(notebook.cells, cell_id, nothing)
        cell === nothing && continue

        if is_markdown(cell)
            # Convert markdown cell to comment block
            # Strip md""" wrapper if present
            md_text = cell.code
            md_text = replace(md_text, r"^md\"\"\"" => "")
            md_text = replace(md_text, r"\"\"\"$" => "")
            md_text = replace(md_text, r"^md\"" => "")
            md_text = replace(md_text, r"\"$" => "")
            md_text = strip(md_text)
            for line in split(md_text, "\n")
                println(io, "# ", line)
            end
        else
            println(io, cell.code)
        end
        println(io)
    end

    return String(take!(io))
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

"""
Escape string for embedding in metadata comments.
"""
function escape_metadata(s::String)
    replace(s, "\"" => "\\\"")
end
