# Layer 1: Pluto-compatible .jl notebook parser/writer

const PLUTO_HEADER = "### A Pluto.jl notebook ###"
const PLUTO_VERSION = "# v0.19.0"
const CELL_MARKER = "# ╔═╡ "
const CELL_ORDER_MARKER = "# ╔═╡ Cell order:"
const CELL_VISIBLE_PREFIX = "# ╠═"
const CELL_FOLDED_PREFIX = "# ╟─"
const PROJECT_TOML_MARKER = "# ╔═╡ Project.toml"
const MANIFEST_TOML_MARKER = "# ╔═╡ Manifest.toml"

"""Parse a Pluto .jl notebook file into a Notebook."""
function load_notebook(path::String)
    content = read(path, String)
    parse_notebook(content; path)
end

"""Parse notebook content string into a Notebook."""
function parse_notebook(content::String; path::String="Untitled.jl")
    lines = split(content, '\n')
    nb = Notebook(; path)

    # Parse cell bodies: collect UUID → code mappings
    cell_codes = Dict{UUID, String}()
    current_uuid = nothing
    current_lines = String[]
    in_cell_order = false
    in_project_toml = false
    in_manifest_toml = false

    for line in lines
        sline = String(line)

        # Skip header lines
        if sline == PLUTO_HEADER || startswith(sline, "# v")
            continue
        end

        # Check for cell order section
        if sline == CELL_ORDER_MARKER
            # Save any current cell
            if current_uuid !== nothing
                cell_codes[current_uuid] = _strip_trailing_empty(current_lines)
            end
            in_cell_order = true
            continue
        end

        # Check for Project.toml/Manifest.toml sections
        if sline == PROJECT_TOML_MARKER
            if current_uuid !== nothing
                cell_codes[current_uuid] = _strip_trailing_empty(current_lines)
                current_uuid = nothing
            end
            in_project_toml = true
            in_manifest_toml = false
            continue
        end
        if sline == MANIFEST_TOML_MARKER
            in_project_toml = false
            in_manifest_toml = true
            continue
        end

        # Skip Project.toml/Manifest.toml content
        if in_project_toml || in_manifest_toml
            continue
        end

        if in_cell_order
            # Parse cell order entries
            if startswith(sline, CELL_VISIBLE_PREFIX)
                uuid_str = strip(sline[ncodeunits(CELL_VISIBLE_PREFIX)+1:end])
                id = UUID(uuid_str)
                code = get(cell_codes, id, "")
                cell = Cell(; id, code, folded=false)
                add_cell!(nb, cell)
            elseif startswith(sline, CELL_FOLDED_PREFIX)
                uuid_str = strip(sline[ncodeunits(CELL_FOLDED_PREFIX)+1:end])
                id = UUID(uuid_str)
                code = get(cell_codes, id, "")
                cell = Cell(; id, code, folded=true)
                add_cell!(nb, cell)
            end
        elseif startswith(sline, CELL_MARKER) && !startswith(sline, CELL_ORDER_MARKER)
            # New cell definition
            if current_uuid !== nothing
                cell_codes[current_uuid] = _strip_trailing_empty(current_lines)
            end
            uuid_str = sline[ncodeunits(CELL_MARKER)+1:end]
            current_uuid = UUID(uuid_str)
            current_lines = String[]
        elseif current_uuid !== nothing
            # Accumulate cell code lines (skip metadata comments like produced_by_hash)
            if startswith(sline, "# ╠═╡ ")
                continue  # Skip metadata lines within cell body
            end
            push!(current_lines, sline)
        end
    end

    # Save last cell if not yet saved (no cell order section)
    if current_uuid !== nothing && !in_cell_order
        cell_codes[current_uuid] = _strip_trailing_empty(current_lines)
    end

    nb
end

"""Strip trailing empty lines and join into a single string."""
function _strip_trailing_empty(lines::Vector{String})
    # Remove trailing empty lines
    while !isempty(lines) && isempty(strip(lines[end]))
        pop!(lines)
    end
    join(lines, '\n')
end

"""Save a Notebook to a Pluto-compatible .jl file."""
function save_notebook(nb::Notebook)
    content = serialize_notebook(nb)
    write(nb.path, content)
    nb.path
end

"""Save a Notebook to a specific path."""
function save_notebook(nb::Notebook, path::String)
    content = serialize_notebook(nb)
    write(path, content)
    path
end

"""Serialize a Notebook to a Pluto-compatible .jl string."""
function serialize_notebook(nb::Notebook)
    io = IOBuffer()

    # Header
    println(io, PLUTO_HEADER)
    println(io, PLUTO_VERSION)

    # Cell bodies
    for id in nb.cell_order
        cell = nb.cells[id]
        println(io)
        println(io, CELL_MARKER, cell.id)
        if !isempty(cell.code)
            println(io, cell.code)
        end
    end

    # Cell order section
    println(io)
    println(io, CELL_ORDER_MARKER)
    for id in nb.cell_order
        cell = nb.cells[id]
        if cell.folded
            println(io, CELL_FOLDED_PREFIX, cell.id)
        else
            println(io, CELL_VISIBLE_PREFIX, cell.id)
        end
    end

    String(take!(io))
end
