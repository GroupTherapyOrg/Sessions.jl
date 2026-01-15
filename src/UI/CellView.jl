# CellView.jl - Cell rendering component
#
# Renders a single notebook cell with code editor and output.
# Uses data-action attributes for action delegation (handled by minimal JS).
# CodeMirror is initialized client-side (required - external JS library).

using Therapy

"""
Render a single cell as HTML.
Uses data-action attributes instead of inline onclick handlers.
The minimal JS bridge reads these attributes and sends channel messages.
"""
function CellView(cell::Cell)
    cell_id_str = string(cell.id)

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
        Symbol("data-state") => string(cell.state),

        # Cell toolbar
        Div(:class => "cell-toolbar flex items-center justify-between px-3 py-1.5 bg-neutral-100 dark:bg-neutral-800 border-b border-neutral-200 dark:border-neutral-700",
            # Left side: Run button
            Div(:class => "flex items-center gap-2",
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
                # Runtime display
                cell.runtime_ms !== nothing ?
                    Span(:class => "runtime-badge text-neutral-500 font-mono text-xs",
                        "$(round(cell.runtime_ms, digits=1))ms"
                    ) : nothing,
                # Delete button - uses data-action for delegation
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
            # This pre/code will be replaced by CodeMirror
            Pre(:class => "cell-code p-4 m-0 text-sm overflow-x-auto",
                :style => "font-family: 'JetBrains Mono', monospace;",
                Code(cell.code)
            )
        ),

        # Output area (only shown if output exists)
        cell.output !== nothing && !isempty(cell.output.html) ?
            Div(:class => "cell-output border-t border-neutral-200 dark:border-neutral-700 p-4 bg-neutral-50 dark:bg-neutral-800/50",
                RawHtml(format_cell_output(cell))
            ) : nothing,

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
