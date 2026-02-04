# app.jl - Sessions.jl Entry Point
#
# This file provides the NotebookApp component that makes Sessions.jl notebooks
# embeddable in any Therapy.jl application.
#
# Usage:
#   using Therapy, Sessions
#
#   function MyApp()
#       Div(:class => "my-app",
#           Header("My Research Platform"),
#           Sessions.NotebookApp(notebook_path = "/path/to/notebook.jl"),
#           Footer()
#       )
#   end
#
# Gold Standard: Pluto.jl (https://github.com/fonsp/Pluto.jl)
# Framework: Therapy.jl (Leptos.rs-inspired reactive web framework)
#
# See SESSIONS-004 in ralph_loop/prd.json for details.

using Therapy
using UUIDs

# =============================================================================
# NotebookApp Options
# =============================================================================

"""
    NotebookOptions

Configuration options for NotebookApp.

# Fields
- `show_header::Bool`: Whether to show the notebook header (default: true)
- `show_add_first_cell::Bool`: Whether to show "Add your first cell" in empty notebooks (default: true)
- `editable::Bool`: Whether cells can be edited (default: true)
- `runnable::Bool`: Whether cells can be executed (default: true)
"""
Base.@kwdef struct NotebookOptions
    show_header::Bool = true
    show_add_first_cell::Bool = true
    editable::Bool = true
    runnable::Bool = true
end

# =============================================================================
# NotebookApp Component
# =============================================================================

"""
    NotebookApp(; notebook_path=nothing, notebook_id=nothing, options=NotebookOptions())

Embeddable notebook component for use in any Therapy.jl application.

This is the main entry point for embedding Sessions.jl notebooks. It can be used
standalone or composed with other Therapy.jl components.

# Arguments
- `notebook_path::Union{String, Nothing}`: Path to load a notebook from (optional)
- `notebook_id::Union{UUID, String, Nothing}`: ID of an existing notebook to display (optional)
- `options::NotebookOptions`: Display and behavior options

# Examples

Basic usage:
```julia
using Therapy, Sessions

# Create a standalone notebook app
function MyNotebookPage()
    Sessions.NotebookApp()
end
```

Embedded in a larger application:
```julia
using Therapy, Sessions

function ResearchPlatform()
    Div(:class => "research-app",
        Header("My Research Platform"),
        Sessions.NotebookApp(
            notebook_path = "experiments/analysis.jl",
            options = Sessions.NotebookOptions(show_header = false)
        ),
        Sidebar()
    )
end
```

Display an existing notebook by ID:
```julia
using Therapy, Sessions

function NotebookViewer(notebook_id::UUID)
    Sessions.NotebookApp(notebook_id = notebook_id)
end
```

# Notes
- Does not assume global state - creates or fetches notebooks as needed
- Does not include Layout - caller is responsible for page structure
- Does not include head_extra content - use `notebook_head_extra()` for that
"""
function NotebookApp(;
    notebook_path::Union{String, Nothing} = nothing,
    notebook_id::Union{UUID, String, Nothing} = nothing,
    options::NotebookOptions = NotebookOptions()
)
    # Resolve notebook ID if string
    resolved_id = if notebook_id isa String
        UUID(notebook_id)
    else
        notebook_id
    end

    # Get or create the notebook
    notebook = get_or_create_notebook(; path=notebook_path, id=resolved_id)

    # Register signals for all cells (ensures reactivity works)
    register_all_cell_signals!(notebook)

    # Get cells in order
    cells = cells_in_order(notebook)

    # Build the component
    Div(:class => "sessions-notebook space-y-8",
        Symbol("data-notebook-id") => string(notebook.id),

        # Optional header
        options.show_header ? notebook_header(notebook, cells) : nothing,

        # Cells view with options
        notebook_cells_view(cells, options),

        # Script to set notebook ID for client JS
        Script("if (typeof setNotebookId === 'function') { setNotebookId('$(notebook.id)'); }")
    )
end

# =============================================================================
# Helper Functions
# =============================================================================

"""
    get_or_create_notebook(; path=nothing, id=nothing)

Get an existing notebook by ID/path, or create a new one.

This function does not modify global state unless necessary - it first tries
to find an existing notebook matching the criteria.

# Arguments
- `path::Union{String, Nothing}`: Path to load notebook from
- `id::Union{UUID, Nothing}`: ID of existing notebook to retrieve

# Returns
A `Notebook` instance.
"""
function get_or_create_notebook(;
    path::Union{String, Nothing} = nothing,
    id::Union{UUID, Nothing} = nothing
)
    # If ID provided, try to get that specific notebook
    if id !== nothing && haskey(NOTEBOOKS, id)
        return NOTEBOOKS[id]
    end

    # If path provided, try to load from file
    if path !== nothing
        # Check if we already have a notebook for this path
        for (nb_id, nb) in NOTEBOOKS
            if nb.path == path
                return nb
            end
        end

        # Load from file if it exists
        if isfile(path)
            notebook = load_notebook(path)
            NOTEBOOKS[notebook.id] = notebook
            return notebook
        end
    end

    # If no notebooks exist, create a default one
    if isempty(NOTEBOOKS)
        return create_default_notebook!()
    end

    # Otherwise return the first available notebook
    return first(values(NOTEBOOKS))
end

"""
    notebook_header(notebook, cells)

Render the notebook header with title and cell count.
"""
function notebook_header(notebook::Notebook, cells::Vector{Cell})
    Div(:class => "mb-8 pb-6 border-b border-stone-200/30 dark:border-neutral-800/30",
        H2(:class => "text-2xl font-serif font-medium text-stone-700 dark:text-stone-200 tracking-wide",
            notebook.path === nothing ? "Untitled Notebook" : basename(notebook.path)
        ),
        P(:class => "text-xs text-stone-400 dark:text-stone-500 mt-2 tracking-wider uppercase",
            "$(length(cells)) cells"
        )
    )
end

"""
    notebook_cells_view(cells, options)

Render the cells container, respecting display options.
"""
function notebook_cells_view(cells::Vector{Cell}, options::NotebookOptions)
    Div(:class => "cells-container space-y-10 pb-20",
        # Empty state
        isempty(cells) && options.show_add_first_cell ?
            empty_notebook_state(options) : nothing,

        # Cells
        [CellView(cell) for cell in cells]...
    )
end

"""
    empty_notebook_state(options)

Render the empty state for a notebook with no cells.
"""
function empty_notebook_state(options::NotebookOptions)
    Div(:class => "text-center py-20",
        Div(:class => "inline-block px-12 py-10 rounded-xl bg-stone-100/50 dark:bg-neutral-800/30 border border-stone-200/30 dark:border-neutral-700/30",
            P(:class => "text-xl font-serif text-stone-500 dark:text-stone-400 mb-4", "Begin your notebook"),
            options.editable ?
                Button(:class => "flex items-center gap-2 mx-auto px-4 py-2 text-sm font-medium text-stone-600 dark:text-stone-300 bg-white dark:bg-neutral-800 rounded-full shadow-sm hover:shadow-md border border-stone-200 dark:border-neutral-700 transition-all duration-200",
                    :on_click => "addCellAfter(null)",
                    Svg(:class => "w-4 h-4",
                        :fill => "none",
                        :viewBox => "0 0 24 24",
                        :stroke => "currentColor",
                        Symbol("stroke-width") => "2",
                        Path(:d => "M12 4v16m8-8H4")
                    ),
                    Span("Add your first cell")
                ) : nothing
        )
    )
end

# =============================================================================
# Head Extra Content
# =============================================================================

"""
    notebook_head_extra()

Get the head content required for NotebookApp.

This includes:
- Sessions styles (Tailwind config, CodeMirror styles)
- Therapy.jl WebSocket client
- Therapy.jl client router (for SPA)
- External library scripts (CodeMirror)
- Sessions.jl minimal JS bridge

Use this in your page's head_extra when embedding NotebookApp:

```julia
function my_page()
    render_page(
        MyLayout(Sessions.NotebookApp()),
        title = "My Notebook",
        head_extra = Sessions.notebook_head_extra()
    )
end
```
"""
function notebook_head_extra()
    sessions_head_extra()
end

# =============================================================================
# Initialization
# =============================================================================

"""
    init_notebook_server!()

Initialize the Sessions.jl server infrastructure.

Call this once when starting a server that will host NotebookApp components.
This sets up:
- Therapy.jl server signals
- WebSocket channels for cell operations
- Connection lifecycle hooks

Note: This is automatically called by `Sessions.serve()`, but must be called
manually when embedding NotebookApp in a custom server.
"""
function init_notebook_server!()
    initialize_server!()
end
