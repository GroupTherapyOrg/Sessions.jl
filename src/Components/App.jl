# =============================================================================
# App Components (Therapy.jl-based)
# =============================================================================
# These are the Therapy.jl components that will eventually replace the
# inline HTML/JS approach. For now, we use the HTML version for quick iteration.

using Therapy

# =============================================================================
# Pluto Notebook Compatibility
# =============================================================================
# Goal: Users should be able to copy-paste cells from Pluto notebooks into
# Sessions and have them work correctly.
#
# Pluto notebooks are .jl files with cell markers like:
#   # ╔═╡ cell_id
#   code here
#   # ╔═╡ another_cell_id
#   more code
#
# We parse these markers to extract individual cells.

"""
    parse_pluto_notebook(content::String) -> Vector{Cell}

Parse a Pluto notebook (.jl file) into cells.
Supports both Pluto format (# ╔═╡ markers) and simple format (# %% markers).
"""
function parse_pluto_notebook(content::String)::Vector{Cell}
    cells = Cell[]

    # Check for Pluto format (# ╔═╡ markers)
    if contains(content, "# ╔═╡")
        # Split by Pluto cell markers
        parts = split(content, r"# ╔═╡ [a-f0-9-]+")

        for part in parts
            code = strip(part)
            # Skip empty parts and Pluto metadata
            if !isempty(code) && !startswith(code, "# ╟─")
                push!(cells, Cell(code))
            end
        end
    # Check for Sessions/VSCode format (# %% markers)
    elseif contains(content, "# %%")
        parts = split(content, r"^# %%"m)

        for part in parts
            code = strip(part)
            if !isempty(code)
                push!(cells, Cell(code))
            end
        end
    else
        # Treat entire file as single cell
        if !isempty(strip(content))
            push!(cells, Cell(strip(content)))
        end
    end

    # Ensure at least one cell
    if isempty(cells)
        push!(cells, Cell(""))
    end

    cells
end

"""
    load_notebook_file(path::String) -> Vector{Cell}

Load a notebook file and parse it into cells.
"""
function load_notebook_file(path::String)::Vector{Cell}
    if !isfile(path)
        error("File not found: $path")
    end

    content = read(path, String)
    parse_pluto_notebook(content)
end

"""
    save_notebook_file(cells::Vector{Cell}, path::String)

Save cells to a notebook file in Sessions format.
"""
function save_notebook_file(cells::Vector{Cell}, path::String)
    io = IOBuffer()

    for (i, cell) in enumerate(cells)
        if i > 1
            println(io)  # Blank line between cells
        end
        println(io, "# %%")
        println(io, cell.code)
    end

    write(path, String(take!(io)))
end

# =============================================================================
# Therapy.jl Components (for future Wasm-compiled version)
# =============================================================================

"""
Sessions app as a Therapy.jl island.
This will be compiled to Wasm for the full interactive experience.
"""
SessionsApp = island(:SessionsApp) do
    # State
    cells_state, set_cells = create_signal(Cell[])

    Div(:class => "sessions-app h-screen flex flex-col bg-gray-900 text-gray-200",
        # Header
        Header(:class => "h-10 bg-gray-800 border-b border-gray-700 flex items-center px-4",
            Span(:class => "font-bold", "Sessions.jl")
        ),

        # Main content
        Div(:class => "flex-1 flex overflow-hidden",
            # Sidebar placeholder
            Div(:class => "w-64 bg-gray-800 border-r border-gray-700",
                Div(:class => "p-2 text-sm text-gray-500", "File Explorer")
            ),

            # Editor area
            Div(:class => "flex-1 overflow-auto p-4",
                NotebookView(:cells => cells_state)
            )
        )
    )
end

"""
Notebook view component.
"""
NotebookView = component(:NotebookView) do props
    cells = get_prop(props, :cells, () -> Cell[])

    Div(:class => "notebook space-y-4",
        For(cells) do cell, index
            CellView(:cell => cell, :index => index)
        end
    )
end

"""
Single cell view component.
"""
CellView = component(:CellView) do props
    cell = get_prop(props, :cell)
    index = get_prop(props, :index, 1)

    status_class = if cell.status == RUNNING
        "border-l-4 border-yellow-500"
    elseif cell.status == COMPLETED
        "border-l-4 border-green-500"
    elseif cell.status == ERRORED
        "border-l-4 border-red-500"
    else
        "border-l-4 border-transparent"
    end

    Div(:class => "cell bg-gray-850 rounded-lg overflow-hidden $status_class",
        # Header
        Div(:class => "flex items-center h-8 px-3 bg-gray-800 text-sm",
            Span(:class => "text-gray-500", "[$(cell.execution_count)]"),
            Div(:class => "flex-1"),
            Button(:class => "text-gray-500 hover:text-white px-2", "Run")
        ),

        # Code
        Div(:class => "p-3",
            Pre(:class => "bg-gray-800 rounded p-3 text-sm text-gray-200 overflow-x-auto",
                Code(cell.code)
            )
        ),

        # Output
        Show(() -> cell.output !== nothing) do
            Div(:class => "px-3 pb-3",
                Div(:class => "bg-gray-800 rounded p-2 text-sm text-blue-400",
                    string(cell.output)
                )
            )
        end,

        # Error
        Show(() -> cell.status == ERRORED) do
            Div(:class => "px-3 pb-3",
                Div(:class => "bg-red-900 bg-opacity-30 rounded p-2 text-sm text-red-400",
                    cell.error_msg
                )
            )
        end
    )
end
