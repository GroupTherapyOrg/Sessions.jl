# CellEditor.jl - Interactive cell editor components using Therapy.jl islands
#
# Islands compile to WebAssembly for client-side interactivity.
# Server communication uses bidirectional signals and channels.
#
# This file contains the interactive island versions of cell components
# that will be compiled to Wasm by Therapy.jl.

using Therapy

# =============================================================================
# Cell State Signal (per-cell)
# =============================================================================

"""
Create a cell state island - handles the visual state indicators.
The actual execution is triggered via JavaScript channel messaging,
but the state display is pure Wasm.
"""
CellStateIndicator = island(:CellStateIndicator) do
    # 0 = idle, 1 = running, 2 = queued, 3 = error
    state, set_state = create_signal(0)

    Div(:class => "cell-state-indicator",
        # Visual indicator changes based on state
        Span(
            Symbol("data-format") => "cell-state",
            :class => "w-2 h-2 rounded-full inline-block",
            state
        )
    )
end

"""
Run button island - purely visual feedback.
Actual execution trigger is via data attribute that JS reads.
"""
RunButton = island(:RunButton) do
    # 0 = ready, 1 = running
    running, set_running = create_signal(0)

    Button(
        :class => "run-btn px-2.5 py-1 text-xs text-white rounded font-medium flex items-center gap-1",
        # When clicked, set to running state (visual feedback)
        # The actual execution is triggered by JS reading the click event
        :on_click => () -> set_running(1),
        Symbol("data-running") => running,
        Span("▶"),
        Span(:class => "hidden sm:inline",
             Show(() -> running() == 0) do
                 "Run"
             end,
             Show(() -> running() == 1) do
                 "..."
             end
        )
    )
end

# =============================================================================
# Cell Editor Island
# =============================================================================

"""
Interactive cell editor island.

This island handles the code editing experience with:
- Visual state feedback (running, error, etc.)
- Run button with loading state
- Delete confirmation

Note: The actual CodeMirror integration is handled by Therapy.jl's
external library pattern. This island provides the visual feedback layer.
"""
CellEditor = island(:CellEditor) do
    # Cell state: 0 = idle, 1 = running, 2 = queued, 3 = error
    state, set_state = create_signal(Int32(0))
    # Running indicator for button
    running, set_running = create_signal(Int32(0))

    Div(:class => "cell-editor-island",
        Symbol("data-state") => state,

        # Run button with visual feedback
        Button(
            :class => "run-btn px-2.5 py-1 text-xs text-white rounded font-medium flex items-center gap-1",
            :on_click => () -> begin
                set_running(Int32(1))
                # Actual execution is triggered by JS bridge
            end,
            Symbol("data-running") => running,
            Span("▶"),
            Span(:class => "hidden sm:inline",
                Show(() -> running() == Int32(0)) do
                    "Run"
                end,
                Show(() -> running() == Int32(1)) do
                    "..."
                end
            )
        )
    )
end
