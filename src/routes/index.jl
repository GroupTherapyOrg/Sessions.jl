# index.jl - Root route for Sessions.jl
#
# This serves as the main entry point when accessing /
# Following Therapy.jl routing conventions.
#
# Route: /

using Therapy

"""
    IndexRoute(params::Dict{Symbol, String})

Render the root page, which displays the notebook content directly.

The index route serves the same content as the notebook route, making
the notebook the default view. This follows the Pluto.jl pattern where
the notebook is the primary interface.

For multi-notebook support in the future, this could instead show a
notebook picker/file browser.
"""
function IndexRoute(params::Dict{Symbol, String}=Dict{Symbol, String}())
    # Get or create the default notebook
    notebook = if !isempty(Sessions.NOTEBOOKS)
        first(values(Sessions.NOTEBOOKS))
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

    # Build page content
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

        # Terminal panel (SESSIONS-2110)
        Div(:class => "mt-12 pt-8 border-t border-stone-200/30 dark:border-neutral-800/30",
            H3(:class => "text-lg font-serif font-medium text-stone-600 dark:text-stone-300 mb-4", "Terminal"),
            Sessions.TerminalPanel(title="Julia REPL", height="250px")
        ),

        # Set notebook ID for client
        Script("setNotebookId('$(notebook.id)');")
    )
end

# Export the route function (Therapy router convention)
IndexRoute
