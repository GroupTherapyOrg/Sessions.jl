# CellIsland.jl - Interactive cell components using Therapy.jl islands
#
# Islands compile to WebAssembly for client-side interactivity.
# Server communication uses bidirectional signals and channels.

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
# Cell View with Islands
# =============================================================================

"""
CellView using islands for interactive elements.
The cell toolbar buttons use Wasm for visual state,
while execution is triggered via JS channel messaging.
"""
function CellViewIsland(cell::Cell; notebook_id::UUID)
    cell_id_str = string(cell.id)
    notebook_id_str = string(notebook_id)

    state_class = if cell.state == CELL_RUNNING
        "cell-running"
    elseif cell.state == CELL_QUEUED
        "cell-queued"
    elseif cell.state == CELL_ERROR
        "cell-error"
    else
        "cell-idle"
    end

    Div(:class => "cell relative mb-4 border border-neutral-200 dark:border-neutral-700 rounded-lg overflow-hidden $state_class",
        Symbol("data-cell-id") => cell_id_str,
        Symbol("data-notebook-id") => notebook_id_str,
        Symbol("data-state") => string(cell.state),

        # Cell toolbar - mix of islands and static elements
        Div(:class => "cell-toolbar flex items-center justify-between px-3 py-1.5 bg-neutral-100 dark:bg-neutral-800 border-b border-neutral-200 dark:border-neutral-700",
            # Left side: Run button (static for now - JS handles execution)
            Div(:class => "flex items-center gap-2",
                Button(:class => "run-btn px-2.5 py-1 text-xs text-white rounded font-medium flex items-center gap-1",
                    Symbol("data-action") => "execute",
                    Symbol("data-cell-id") => cell_id_str,
                    :title => "Run cell (Shift+Enter)",
                    Span("▶"),
                    Span(:class => "hidden sm:inline", "Run")
                )
            ),
            # Right side: Runtime and delete
            Div(:class => "flex items-center gap-3",
                # Runtime display
                cell.runtime_ms !== nothing ?
                    Span(:class => "runtime-badge text-neutral-500 font-mono text-xs",
                        "$(round(cell.runtime_ms, digits=1))ms"
                    ) : nothing,
                # Delete button
                Button(:class => "px-2 py-1 text-neutral-400 hover:text-red-500 transition-colors",
                    Symbol("data-action") => "delete",
                    Symbol("data-cell-id") => cell_id_str,
                    :title => "Delete cell",
                    "✕"
                )
            )
        ),

        # Code editor area (CodeMirror initialized by minimal JS)
        Div(:class => "cell-code-container bg-white dark:bg-neutral-900",
            Pre(:class => "cell-code p-4 m-0 text-sm overflow-x-auto",
                :style => "font-family: 'JetBrains Mono', monospace;",
                Code(cell.code)
            )
        ),

        # Output area
        cell.output !== nothing && !isempty(cell.output.html) ?
            Div(:class => "cell-output border-t border-neutral-200 dark:border-neutral-700 p-4 bg-neutral-50 dark:bg-neutral-800/50",
                RawHtml(format_cell_output(cell))
            ) : nothing,

        # Add cell button
        Div(:class => "add-cell-btn text-center py-2",
            Button(:class => "text-xs text-neutral-400 hover:text-neutral-600 dark:hover:text-neutral-300 px-3 py-1 rounded hover:bg-neutral-200 dark:hover:bg-neutral-700 transition-colors",
                Symbol("data-action") => "add-cell",
                Symbol("data-after-cell-id") => cell_id_str,
                "+ Add cell below"
            )
        )
    )
end

"""
Render cells using the island-based view.
"""
function CellsViewIsland(cells::Vector{Cell}; notebook_id::UUID)
    Div(:class => "cells-container notebook-container",
        isempty(cells) ?
            Div(:class => "text-center py-12 text-neutral-500",
                P(:class => "text-lg", "No cells yet"),
                P(:class => "text-sm", "Click \"+ Add Cell\" below to get started")
            ) : nothing,
        [CellViewIsland(cell; notebook_id=notebook_id) for cell in cells]...
    )
end
