# notebook.jl - Notebook route as SPA powered by Therapy router
#
# This is the single notebook route that serves as the main SPA entry point.
# It follows Therapy.jl routing conventions:
# - Define a function that returns the page content (VNode)
# - Layout is applied at the app level, not in the route
# - Returns the function at the end of the file
#
# Route: /notebook or /notebook?path=/path/to/notebook.jl
#
# Future enhancement: Use /notebook/[...path].jl for cleaner URLs like:
#   /notebook/path/to/notebook.jl

using Therapy

"""
    NotebookRoute(params::Dict{Symbol, String})

Render the notebook page content.

# Arguments
- `params`: Route parameters (currently unused, but available for future use)
  - In future: could contain `:path` for `/notebook/[...path].jl` catch-all route

The route uses the existing `render_notebook_content()` function from the server
module, which handles:
- Loading or creating a notebook
- Rendering cells via CellsView
- Setting notebook ID for client JavaScript

# Therapy Router Convention
Routes return VNode content directly. Layout is applied at the app level,
enabling true SPA navigation where only the content changes, not the nav/footer.
"""
function NotebookRoute(params::Dict{Symbol, String}=Dict{Symbol, String}())
    # Get notebook path from params if provided (for catch-all route pattern)
    notebook_path = get(params, :path, nothing)

    # Use existing render_notebook_content logic
    # This function is defined in Server/App.jl and handles:
    # - Getting or creating a notebook
    # - Rendering the notebook header and cells
    # - Setting the notebook ID for client JS

    # Get or create the notebook
    notebook = if !isempty(Sessions.NOTEBOOKS)
        # If path is specified, try to find that notebook
        if notebook_path !== nothing && haskey(Sessions.NOTEBOOKS, notebook_path)
            Sessions.NOTEBOOKS[notebook_path]
        else
            # Otherwise return the first notebook
            first(values(Sessions.NOTEBOOKS))
        end
    else
        # Create a default notebook
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb; code="# Welcome to Sessions.jl\n# A reactive Julia notebook powered by Therapy.jl")
        Sessions.add_cell!(nb; code="1 + 1")
        Sessions.add_cell!(nb; code="x = 42")
        Sessions.add_cell!(nb; code="x * 2")
        Sessions.NOTEBOOKS[nb.id] = nb
        # Register per-cell signals for all cells
        Sessions.register_all_cell_signals!(nb)
        nb
    end

    cells = Sessions.cells_in_order(notebook)

    # Build page content - matches existing render_notebook_content() style
    Div(:class => "space-y-8",
        # Notebook header - elegant, scholarly
        Div(:class => "mb-8 pb-6 border-b border-stone-200/30 dark:border-neutral-800/30",
            H2(:class => "text-2xl font-serif font-medium text-stone-700 dark:text-stone-200 tracking-wide",
                notebook.path === nothing ? "Untitled Notebook" : basename(notebook.path)
            ),
            P(:class => "text-xs text-stone-400 dark:text-stone-500 mt-2 tracking-wider uppercase",
                "$(length(cells)) cells"
            )
        ),

        # Cells
        Sessions.CellsView(cells),

        # Set notebook ID for client
        Script("setNotebookId('$(notebook.id)');")
    )
end

# Export the route function (Therapy router convention)
NotebookRoute
