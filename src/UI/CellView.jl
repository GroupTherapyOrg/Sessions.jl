# CellView.jl - Cell rendering component
#
# Renders a single notebook cell with code editor and output.
#
# Signal Architecture (Per-Cell):
# - cell_state_{id}: "CELL_IDLE"|"CELL_RUNNING"|"CELL_QUEUED"|"CELL_ERROR"
# - cell_output_{id}: HTML string of cell output
# - cell_runtime_{id}: Runtime in ms (string)
#
# The data-cell-state-signal, data-cell-output-signal, data-cell-runtime-signal
# attributes tell the client which signal to subscribe to for this cell.
# Therapy.jl's data-server-signal works for simple text (runtime), but we need
# custom handlers for CSS class updates (state) and innerHTML (output).

using Therapy

"""
Render a single cell as HTML.
Uses per-cell server signals for reactive updates.
"""
function CellView(cell::Cell)
    cell_id_str = string(cell.id)

    # Signal names for this cell
    state_signal = "cell_state_$(cell_id_str)"
    output_signal = "cell_output_$(cell_id_str)"
    runtime_signal = "cell_runtime_$(cell_id_str)"

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
        # Per-cell signal names for client to subscribe to
        Symbol("data-cell-state-signal") => state_signal,
        Symbol("data-cell-output-signal") => output_signal,
        Symbol("data-cell-runtime-signal") => runtime_signal,

        # Cell toolbar
        Div(:class => "cell-toolbar flex items-center justify-between px-3 py-1.5 bg-neutral-100 dark:bg-neutral-800 border-b border-neutral-200 dark:border-neutral-700",
            # Left side: Run button with dirty indicator
            Div(:class => "flex items-center gap-2",
                # Dirty indicator (yellow dot when code changed but not run)
                Span(:class => "dirty-indicator w-2 h-2 rounded-full hidden",
                    Symbol("data-dirty") => "false"
                ),
                # Run button - uses data-action for delegation
                Button(:class => "run-btn px-2.5 py-1 text-xs text-white rounded font-medium flex items-center gap-1",
                    Symbol("data-action") => "execute",
                    Symbol("data-cell-id") => cell_id_str,
                    :title => "Run cell (Shift+Enter)",
                    Span("▶"),
                    Span(:class => "hidden sm:inline", "Run")
                )
            ),
            # Right side: Runtime and actions
            Div(:class => "flex items-center gap-3",
                # Runtime display - uses data-server-signal for auto-update
                Span(:class => "runtime-badge text-neutral-500 font-mono text-xs",
                    Symbol("data-server-signal") => runtime_signal,
                    cell.runtime_ms !== nothing ? "$(round(cell.runtime_ms, digits=1))ms" : ""
                ),
                # Delete button - uses data-action for delegation
                Button(:class => "px-2 py-1 text-neutral-400 hover:text-red-500 transition-colors",
                    Symbol("data-action") => "delete",
                    Symbol("data-cell-id") => cell_id_str,
                    :title => "Delete cell",
                    "✕"
                )
            )
        ),

        # Code editor area (CodeMirror initialized by hydration script)
        # Distinct background with subtle border to clearly show editable area
        Div(:class => "cell-code-container bg-stone-50 dark:bg-neutral-900 border-b border-neutral-200 dark:border-neutral-700",
            Symbol("data-initial-code") => cell.code,
            # This pre/code will be replaced by CodeMirror
            Pre(:class => "cell-code p-4 m-0 text-sm overflow-x-auto bg-stone-50 dark:bg-neutral-900",
                :style => "font-family: 'JetBrains Mono', monospace; min-height: 60px;",
                Code(cell.code)
            )
        ),

        # Output area - uses cell-specific output signal
        # HTML content updates via therapy:signal:{output_signal} event
        Div(:class => "cell-output border-t border-neutral-200 dark:border-neutral-700 p-4 bg-neutral-50 dark:bg-neutral-800/50",
            :style => (cell.output === nothing || isempty(cell.output.html)) ? "display: none;" : "",
            Symbol("data-output-container") => "true",
            cell.output !== nothing && !isempty(cell.output.html) ?
                RawHtml(format_cell_output(cell)) : nothing
        ),

        # Add cell button - uses data-action for delegation
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
Render a list of cells.
"""
function CellsView(cells::Vector{Cell})
    Div(:class => "cells-container notebook-container",
        # Empty state
        isempty(cells) ?
            Div(:class => "text-center py-12 text-neutral-500",
                P(:class => "text-lg", "No cells yet"),
                P(:class => "text-sm", "Click \"+ Add Cell\" below to get started")
            ) : nothing,
        # Cell list
        [CellView(cell) for cell in cells]...
    )
end
