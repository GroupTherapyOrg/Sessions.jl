# NotebookIsland.jl - Wasm island for notebook UI state
#
# This island handles reactive UI state using Therapy.jl signals.
# The state is managed in WebAssembly for performance.
#
# What this handles:
# - Cell count display
# - Add cell button state
# - Run all / restart button states
#
# What remains in JS:
# - WebSocket connection (network I/O)
# - CodeMirror editors (external JS library)
# - DOM updates for cell content (received from server)

using Therapy

"""
    NotebookIsland

Wasm island for notebook-level UI controls.
Handles cell count, button states with reactive signals.
"""
NotebookIsland = island(:NotebookIsland) do
    # Reactive signals for notebook state
    cell_count, set_cell_count = create_signal(1)
    is_running, set_is_running = create_signal(false)

    Div(:id => "notebook-island", :class => "flex items-center gap-4",
        # Cell count indicator
        Div(:class => "flex items-center gap-2",
            Span(:class => "text-sm text-gray-500", "Cells:"),
            Span(:class => "text-sm text-gray-300 font-mono", cell_count)
        ),

        # Spacer
        Div(:class => "flex-1"),

        # Run All button
        Button(:id => "btn-run-all",
            :class => "px-3 py-1 bg-green-600 hover:bg-green-500 rounded text-sm disabled:opacity-50",
            "Run All"),

        # Restart button
        Button(:id => "btn-restart",
            :class => "px-3 py-1 bg-gray-700 hover:bg-gray-600 rounded text-sm",
            "Restart"),

        # Add Cell button
        Button(:id => "btn-add-cell",
            :class => "px-3 py-1 bg-blue-600 hover:bg-blue-500 rounded text-sm",
            :on_click => () -> set_cell_count(cell_count() + 1),
            "+ Cell")
    )
end

"""
    FileTreeIsland

Wasm island for file explorer state.
"""
FileTreeIsland = island(:FileTreeIsland) do
    current_path, set_current_path = create_signal(0)  # Index into path list
    is_loading, set_is_loading = create_signal(false)

    Div(:id => "file-tree-island",
        # Loading indicator (shown when is_loading is true)
        Div(:class => "text-xs text-gray-500 p-2",
            Symbol("data-show") => is_loading,
            "Loading..."),

        # File list container - populated by server via WebSocket
        Div(:id => "file-list", :class => "text-sm")
    )
end

"""
    TerminalIsland

Wasm island for terminal UI state.
"""
TerminalIsland = island(:TerminalIsland) do
    is_visible, set_is_visible = create_signal(true)
    history_index, set_history_index = create_signal(0)

    Div(:id => "terminal-island",
        Symbol("data-visible") => is_visible,

        # Terminal header
        Div(:class => "h-8 bg-gray-900 border-b border-gray-700 flex items-center px-3 text-sm",
            Span(:class => "text-gray-400", "Terminal"),
            Div(:class => "flex-1"),
            Button(:id => "btn-toggle-terminal",
                :class => "text-gray-500 hover:text-white",
                :on_click => () -> set_is_visible(!is_visible()),
                "×")
        ),

        # Terminal output - populated by server
        Div(:id => "terminal-output",
            :class => "flex-1 overflow-auto p-2 font-mono text-sm text-green-400 bg-gray-900"),

        # Terminal input
        Div(:class => "flex items-center px-2 py-1 bg-gray-900 border-t border-gray-700",
            Span(:class => "text-blue-400 mr-2 font-mono", "julia>"),
            Input(:type => "text",
                :id => "terminal-input",
                :class => "flex-1 bg-transparent outline-none font-mono text-green-400",
                :placeholder => "Enter command...")
        )
    )
end
