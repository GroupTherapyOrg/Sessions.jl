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

# Cell order delimiters (Pluto uses these to indicate folded/visible state)
const CELL_ORDER_DELIMITER = "# ╠═"           # Visible/expanded cell
const CELL_ORDER_DELIMITER_FOLDED = "# ╟─"    # Folded/hidden cell

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
    folded_cells = Set{UUID}()  # Track which cells are folded

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
            # Parse cell order entry: # ╠═uuid (visible) or # ╟─uuid (folded)
            m = match(r"^# [╠╟][═─]([a-f0-9-]+)$", line)
            if m !== nothing
                cell_uuid = UUID(m.captures[1])
                push!(cell_order_ids, cell_uuid)
                # Check if this is a folded cell (╟─)
                if startswith(line, CELL_ORDER_DELIMITER_FOLDED)
                    push!(folded_cells, cell_uuid)
                end
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

    # Set folded state on cells
    for cell_id in folded_cells
        cell = get(notebook.cells, cell_id, nothing)
        if cell !== nothing
            cell.folded = true
        end
    end

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

# =============================================================================
# Paste Content Parsing (for clipboard paste of Pluto notebooks)
# =============================================================================

"""
    parse_pluto_content(content::String) -> Vector{Tuple{String, String}}

Parse pasted Pluto notebook content into cells.
Returns a Vector of (uuid_string, code) tuples in display order.

If the content is not a Pluto notebook format, treats it as a single cell.

# Pluto Format
```
### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ abc12345-...
x = 1

# ╔═╡ def67890-...
y = x + 1

# ╔═╡ Cell order:
# ╠═abc12345-...
# ╠═def67890-...
```

# Usage
```julia
cells = parse_pluto_content(clipboard_content)
for (uuid, code) in cells
    add_cell!(notebook; code=code)
end
```
"""
function parse_pluto_content(content::String)
    # Check if it's a Pluto notebook
    if !startswith(strip(content), PLUTO_HEADER)
        # Not a Pluto notebook - treat as single cell with raw code
        stripped = strip(content)
        if isempty(stripped)
            return Tuple{String, String}[]
        end
        return [(string(uuid4()), stripped)]
    end

    # Parse Pluto format
    cells = Dict{String, Vector{String}}()  # uuid => code lines
    cell_order = String[]

    lines = split(content, '\n')
    current_uuid = nothing
    current_lines = String[]
    in_cell_order = false
    in_pkg_section = false  # Skip Project.toml/Manifest.toml sections

    for line in lines
        # Check for cell order section
        if startswith(line, CELL_ORDER_MARKER)
            # Save current cell
            if current_uuid !== nothing && !isempty(current_lines)
                cells[current_uuid] = copy(current_lines)
            end
            in_cell_order = true
            in_pkg_section = false
            current_uuid = nothing
            continue
        end

        # Check for package sections (skip them)
        if startswith(line, PROJECT_TOML_MARKER) || startswith(line, MANIFEST_TOML_MARKER)
            if current_uuid !== nothing && !isempty(current_lines)
                cells[current_uuid] = copy(current_lines)
            end
            in_pkg_section = true
            in_cell_order = false
            current_uuid = nothing
            continue
        end

        if in_pkg_section
            continue  # Skip package environment lines
        end

        if in_cell_order
            # Parse cell order entry: # ╠═uuid or # ╟─uuid
            m = match(r"^# [╠╟][═─]([a-f0-9-]+)$", line)
            if m !== nothing
                push!(cell_order, m.captures[1])
            end
            continue
        end

        # Check for new cell marker
        m = match(CELL_MARKER_REGEX, line)
        if m !== nothing
            # Save previous cell
            if current_uuid !== nothing && !isempty(current_lines)
                cells[current_uuid] = copy(current_lines)
            end
            # Start new cell
            current_uuid = m.captures[1]
            current_lines = String[]
            continue
        end

        # Skip header lines
        if startswith(line, "### A Pluto") || startswith(line, "# v0.")
            continue
        end

        # Accumulate cell content
        if current_uuid !== nothing
            push!(current_lines, line)
        end
    end

    # Save last cell
    if current_uuid !== nothing && !isempty(current_lines)
        cells[current_uuid] = copy(current_lines)
    end

    # Return cells in display order
    result = Tuple{String, String}[]
    for uuid in cell_order
        if haskey(cells, uuid)
            # Trim trailing empty lines and join
            code_lines = cells[uuid]
            while !isempty(code_lines) && isempty(strip(last(code_lines)))
                pop!(code_lines)
            end
            code = join(code_lines, '\n')
            if !isempty(strip(code))
                push!(result, (uuid, strip(code)))
            end
        end
    end

    # If no cell order found, return cells in dict order
    if isempty(result) && !isempty(cells)
        for (uuid, code_lines) in cells
            while !isempty(code_lines) && isempty(strip(last(code_lines)))
                pop!(code_lines)
            end
            code = join(code_lines, '\n')
            if !isempty(strip(code))
                push!(result, (uuid, strip(code)))
            end
        end
    end

    return result
end

"""
    is_pluto_content(content::String) -> Bool

Check if a string looks like Pluto notebook content.
"""
function is_pluto_content(content::String)
    startswith(strip(content), PLUTO_HEADER)
end
