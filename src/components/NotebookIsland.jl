# NotebookIsland.jl - Wasm islands for Sessions.jl
#
# These islands are defined using Therapy.jl's island() function.
# They are registered at runtime via register_islands!() to avoid precompilation issues.

using Therapy

# Flag to track if islands have been registered
const ISLANDS_REGISTERED = Ref(false)

"""
Register all Sessions.jl islands with Therapy.jl's registry.
Must be called at runtime (not during precompilation).
"""
function register_islands!()
    ISLANDS_REGISTERED[] && return

    # NotebookControlsIsland - displays cell count
    island(:NotebookControlsIsland) do
        cell_count, set_cell_count = create_signal(1)

        Div(:id => "notebook-controls-island",
            :class => "flex items-center gap-2 text-sm text-gray-400",
            Span("Cells: "),
            Span(:class => "text-gray-200 font-mono", cell_count)
        )
    end

    # TerminalToggleIsland - toggle terminal visibility
    island(:TerminalToggleIsland) do
        visible, set_visible = create_signal(1)

        Button(:id => "terminal-toggle",
            :class => "text-gray-500 hover:text-white px-2",
            :on_click => () -> set_visible(visible() == 0 ? 1 : 0),
            "×")
    end

    ISLANDS_REGISTERED[] = true
    println("Registered $(length(get_islands())) islands")
end
