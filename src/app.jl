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

# NotebookOptions is defined in Sessions.jl (before IDE includes) so that
# IDECellsView/IDECellCard can reference it at include time.

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

    # Build container attributes
    attrs = Pair{Symbol,String}[
        :class => "sessions-notebook",
        Symbol("data-notebook-id") => string(notebook.id),
    ]
    if options.max_height !== nothing
        push!(attrs, :style => "max-height: $(options.max_height); overflow-y: auto;")
    end
    if options.theme != "default"
        push!(attrs, Symbol("data-theme") => options.theme)
    end

    # Build the component
    Div(attrs...,
        # Optional header
        options.show_header ? notebook_header(notebook, cells) : nothing,

        # Cells — use IDE cell components with options
        IDECellsView(cells; options=options),

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
    Div(:class => "mb-8 pb-6 border-b border-warm-200/30 dark:border-[#252422]/30",
        H2(:class => "text-2xl font-serif font-medium text-warm-700 dark:text-warm-200 tracking-wide",
            notebook.path === nothing ? "Untitled Notebook" : basename(notebook.path)
        ),
        P(:class => "text-xs text-warm-400 dark:text-warm-500 mt-2 tracking-wider uppercase",
            "$(length(cells)) cells"
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
- Sessions styles (Tailwind CSS, CodeMirror theme, cell state styles)
- Suite.jl theme script (FOUC prevention) and runtime script
- Therapy.jl WebSocket client
- External library scripts (CodeMirror, xterm.js)
- Sessions.jl JS bridge (cell execute, add, delete)
- Component-specific CSS (markdown, output, cell state)

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

For the full IDE with sidebar, tabs, terminal, etc., use `Sessions.serve()` instead.
"""
function notebook_head_extra()
    # Core: layout + fonts + CodeMirror + WS client
    base = sessions_head_extra()

    # Component CSS/JS needed by NotebookApp cells
    extras = cell_state_styles() *
             markdown_styles() *
             output_styles() *
             codemirror_sessions_theme() *
             cell_toolbar_script() *
             markdown_cell_script() *
             output_truncation_script()

    base * extras
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
