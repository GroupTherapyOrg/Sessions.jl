# NotebookIsland.jl - Wasm islands for Sessions.jl
#
# These islands are defined using Therapy.jl's island() function.
# They are registered at runtime via register_islands!() to avoid precompilation issues.
#
# Islands handle reactive UI state in WebAssembly:
# - Signals for state management
# - Show component for conditional rendering
# - Event handlers compiled to Wasm

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

    # TerminalIsland - terminal with toggle visibility
    # Uses Show component for conditional rendering via Wasm
    # Note: Show() requires direct signal getter, so we use visible for terminal content
    # and always show a clickable header bar
    island(:TerminalIsland) do
        visible, set_visible = create_signal(1)  # 1 = visible, 0 = hidden

        Div(:id => "terminal-island", :class => "border-t border-gray-700",
            # Header bar - always visible, click to toggle
            Div(:class => "h-8 bg-gray-900 flex items-center px-3 text-sm cursor-pointer hover:bg-gray-800",
                :on_click => () -> set_visible(visible() == 0 ? 1 : 0),
                Span(:class => "text-gray-400", "Terminal"),
                Div(:class => "flex-1"),
                # Toggle indicator changes based on visibility
                Span(:class => "text-gray-500", visible)),

            # Terminal content - conditionally shown (use SignalGetter directly)
            Show(visible) do
                Div(:id => "terminal-panel", :class => "h-40 bg-gray-800 flex flex-col",
                    # Output
                    Div(:id => "terminal-output",
                        :class => "flex-1 overflow-auto p-2 font-mono text-sm text-green-400 bg-gray-900"),
                    # Input
                    Div(:class => "flex items-center px-2 py-1 bg-gray-900 border-t border-gray-700",
                        Span(:class => "text-blue-400 mr-2 font-mono", "julia>"),
                        Input(:type => "text",
                              :id => "terminal-input",
                              :class => "flex-1 bg-transparent outline-none font-mono text-green-400",
                              :placeholder => "Enter command..."))
                )
            end
        )
    end

    ISLANDS_REGISTERED[] = true
    println("Registered $(length(get_islands())) islands")
end
