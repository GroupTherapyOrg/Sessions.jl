# Parse.jl - Load Pluto-format .jl notebooks
#
# Parses the Pluto notebook format which stores cells as Julia code
# with special comment markers.

using UUIDs

# Pluto cell marker regex
const CELL_MARKER_REGEX = r"^# ╔═╡ ([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$"
const CELL_ORDER_MARKER = "# ╔═╡ Cell order:"
const PROJECT_TOML_MARKER = "# ╔═╡ Project.toml"
const MANIFEST_TOML_MARKER = "# ╔═╡ Manifest.toml"
const PLUTO_HEADER = "### A Pluto.jl notebook ###"

"""
    load_notebook(path::String) -> Notebook

Load a notebook from a Pluto-format .jl file.
"""
function load_notebook(path::String)
    content = read(path, String)
    lines = split(content, '\n')

    # Verify it's a Pluto notebook
    if !startswith(first(lines), PLUTO_HEADER)
        error("Not a valid Pluto notebook: $path")
    end

    notebook = Notebook(; path=path)

    # Parse cells
    current_cell_id = nothing
    current_cell_lines = String[]
    in_cell_order = false
    in_project_toml = false
    in_manifest_toml = false
    project_lines = String[]
    manifest_lines = String[]
    cell_order_ids = UUID[]

    for line in lines[2:end]  # Skip header
        # Check for cell order section
        if startswith(line, CELL_ORDER_MARKER)
            # Save current cell if any
            if current_cell_id !== nothing
                save_current_cell!(notebook, current_cell_id, current_cell_lines)
            end
            in_cell_order = true
            continue
        end

        # Check for Project.toml section
        if startswith(line, PROJECT_TOML_MARKER)
            in_cell_order = false
            in_project_toml = true
            in_manifest_toml = false
            continue
        end

        # Check for Manifest.toml section
        if startswith(line, MANIFEST_TOML_MARKER)
            in_cell_order = false
            in_project_toml = false
            in_manifest_toml = true
            continue
        end

        if in_cell_order
            # Parse cell order entry: # ╠═uuid or # ╟─uuid
            m = match(r"^# [╠╟][═─]([a-f0-9-]+)$", line)
            if m !== nothing
                push!(cell_order_ids, UUID(m.captures[1]))
            end
            continue
        end

        if in_project_toml
            push!(project_lines, line)
            continue
        end

        if in_manifest_toml
            push!(manifest_lines, line)
            continue
        end

        # Check for new cell marker
        m = match(CELL_MARKER_REGEX, line)
        if m !== nothing
            # Save previous cell
            if current_cell_id !== nothing
                save_current_cell!(notebook, current_cell_id, current_cell_lines)
            end
            # Start new cell
            current_cell_id = UUID(m.captures[1])
            current_cell_lines = String[]
            continue
        end

        # Accumulate cell content
        if current_cell_id !== nothing
            push!(current_cell_lines, line)
        end
    end

    # Save last cell
    if current_cell_id !== nothing
        save_current_cell!(notebook, current_cell_id, current_cell_lines)
    end

    # Set cell order
    notebook.cell_order = cell_order_ids

    # Store package environment
    notebook.project_toml = join(project_lines, '\n')
    notebook.manifest_toml = join(manifest_lines, '\n')

    # Analyze all cells
    for cell in values(notebook.cells)
        analyze_cell!(cell)
    end

    notebook.modified = false
    return notebook
end

"""
Helper to save accumulated cell lines as a cell.
"""
function save_current_cell!(notebook::Notebook, cell_id::UUID, lines::Vector{String})
    # Trim trailing empty lines
    while !isempty(lines) && isempty(strip(last(lines)))
        pop!(lines)
    end

    code = join(lines, '\n')
    cell = Cell(; code=code, id=cell_id)
    notebook.cells[cell_id] = cell
end

"""
    is_pluto_notebook(path::String) -> Bool

Check if a file is a valid Pluto notebook.
"""
function is_pluto_notebook(path::String)
    if !isfile(path)
        return false
    end

    # Check extension
    if !endswith(path, ".jl") && !endswith(path, ".pluto.jl")
        return false
    end

    # Check header
    try
        open(path, "r") do f
            first_line = readline(f)
            return startswith(first_line, PLUTO_HEADER)
        end
    catch
        return false
    end
end
