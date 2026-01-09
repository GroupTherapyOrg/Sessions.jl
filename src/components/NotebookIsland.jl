# NotebookIsland.jl - Interactive notebook component (Wasm island)
#
# This file defines a Therapy.jl island for notebook UI state management.
# The island handles:
# - Cell visibility (show/hide)
# - Cell status indicators
# - Add cell button state
#
# Note: Cell CODE and OUTPUT are handled separately by the JS bridge
# because they involve dynamic strings which WasmTarget doesn't support well.
# This is the recommended hybrid approach:
# - Wasm island: UI state (numeric signals)
# - JS bridge: Dynamic content (code text, outputs)
# - WebSocket: Server compute (execution, filesystem)
#
# Status codes:
#   0 = hidden
#   1 = idle (visible, ready)
#   2 = running
#   3 = completed
#   4 = error

using Therapy

# Maximum number of cell slots (fixed due to WasmTarget limitations)
const MAX_CELLS = 10

"""
    CellStatusBar component - displays status indicator for a cell.

This is a presentational component that shows the cell status.
The actual status value comes from a signal.

Props:
- :status - Signal getter for cell status (0-4)
- :exec_count - Execution count number
"""
CellStatusBar = component(:CellStatusBar) do props
    status = get_prop(props, :status)
    exec_count = get_prop(props, :exec_count)

    # Status indicator with data-format for JS to style
    Div(:class => "flex items-center h-10 px-3 bg-gray-700",
        # Status icon container - JS will update based on data-status
        Div(:class => "cell-status-icon w-6 h-6 flex items-center justify-center mr-2",
            Symbol("data-format") => "status-icon",
            Span(status)
        ),

        # Execution count
        Span(:class => "text-xs text-gray-500",
            "[", Span(exec_count), "]"
        ),

        # Spacer
        Div(:class => "flex-1"),

        # Run and Delete buttons - events handled by JS bridge
        Button(:class => "btn-run px-3 py-1 text-xs text-gray-400 hover:text-white hover:bg-gray-600 rounded mr-1",
               "Run"),
        Button(:class => "btn-delete px-2 py-1 text-xs text-gray-400 hover:text-red-400 hover:bg-gray-600 rounded",
               "×")
    )
end

"""
    NotebookControlsIsland - Wasm island for notebook-level controls.

Handles:
- Cell count state
- Add Cell button with max limit
"""
NotebookControlsIsland = island(:NotebookControlsIsland) do
    # Number of active cells
    cell_count, set_cell_count = create_signal(1)

    Div(:id => "notebook-controls", :class => "mt-4 flex justify-center items-center gap-4",
        # Cell count display
        Span(:class => "text-sm text-gray-500",
            "Cells: ", Span(cell_count)
        ),

        # Add Cell button
        # Note: The actual add logic is handled by JS bridge via WebSocket
        # This island just tracks the count for UI display
        Button(:id => "btn-add-cell-island",
               :class => "px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded text-sm disabled:opacity-50",
               # Disable when at max
               # Note: This would need computed signal support
               "+ Add Cell"
        )
    )
end

# =============================================================================
# Integration Notes
# =============================================================================
#
# To integrate this island with Sessions.jl:
#
# 1. In WebSocketServer.jl, compile the island:
#    ```julia
#    using Therapy: compile_component
#    compiled = compile_component(NotebookControlsIsland)
#    ```
#
# 2. Include the Wasm bytes and hydration JS in generate_page():
#    - Add Wasm as base64: `<script>const wasm = atob("...");</script>`
#    - Add hydration JS: compiled.hydration.js
#
# 3. In the page HTML, include the island element:
#    ```julia
#    page = Layout(
#        Div(:class => "...",
#            NotebookControlsIsland()  # Renders as <therapy-island>
#        )
#    )
#    ```
#
# 4. The hydration JS will:
#    - Load the Wasm module
#    - Connect event handlers
#    - Initialize signals from DOM state
#
# Current Status:
# - The JS bridge handles all notebook UI for now
# - This island is ready for future integration
# - The hybrid approach (Wasm state + JS content) is intentional
#
# =============================================================================
