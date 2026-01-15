# CellView.jl - Cell rendering component
#
# Renders a single notebook cell with code editor and output.
# Design: Elegant, minimal, scholarly aesthetic inspired by Pluto.jl
#
# Signal Architecture (Per-Cell):
# - cell_state_{id}: "CELL_IDLE"|"CELL_RUNNING"|"CELL_QUEUED"|"CELL_ERROR"
# - cell_output_{id}: HTML string of cell output
# - cell_runtime_{id}: Runtime in ms (string)

using Therapy

"""
Render a single cell as HTML.
Uses per-cell server signals for reactive updates.

Design philosophy:
- Clean, minimal borders with subtle shadows
- Code area with distinct, light background for readability
- Refined typography and spacing
- Hover-reveal for secondary actions
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

    # Cell container - parchment card with subtle warmth
    Div(:class => "cell group relative mb-8 bg-stone-50 dark:bg-neutral-900 rounded-lg border border-stone-200/50 dark:border-neutral-800/50 shadow-sm hover:shadow-lg transition-all duration-300 $state_class",
        Symbol("data-cell-id") => cell_id_str,
        Symbol("data-cell-state-signal") => state_signal,
        Symbol("data-cell-output-signal") => output_signal,
        Symbol("data-cell-runtime-signal") => runtime_signal,

        # Subtle left accent bar for state indication
        Div(:class => "cell-state-bar absolute left-0 top-0 bottom-0 w-0.5 rounded-l-lg transition-colors duration-300"),

        # Code editor area - warm parchment in light, rich leather in dark
        Div(:class => "cell-code-container relative bg-amber-50/40 dark:bg-neutral-800/60 rounded-t-lg",
            Symbol("data-initial-code") => cell.code,

            # Floating run button (top-right, appears on hover)
            Div(:class => "absolute top-3 right-3 flex items-center gap-2 opacity-0 group-hover:opacity-100 transition-opacity duration-150",
                # Runtime badge
                Span(:class => "text-xs font-mono text-neutral-400",
                    Symbol("data-server-signal") => runtime_signal,
                    cell.runtime_ms !== nothing ? "$(round(cell.runtime_ms, digits=1))ms" : ""
                ),
                # Run button - elegant pill shape
                Button(:class => "run-btn flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-white rounded-full shadow-sm hover:shadow transition-all duration-150",
                    Symbol("data-action") => "execute",
                    Symbol("data-cell-id") => cell_id_str,
                    :title => "Run cell (Shift+Enter)",
                    Svg(:class => "w-3 h-3",
                        :fill => "currentColor",
                        :viewBox => "0 0 20 20",
                        Path(:d => "M6.3 2.841A1.5 1.5 0 004 4.11v11.78a1.5 1.5 0 002.3 1.269l9.344-5.89a1.5 1.5 0 000-2.538L6.3 2.84z")
                    ),
                    Span("Run")
                ),
                # Delete button - subtle, appears on hover
                Button(:class => "p-1.5 text-neutral-300 hover:text-red-400 transition-colors",
                    Symbol("data-action") => "delete",
                    Symbol("data-cell-id") => cell_id_str,
                    :title => "Delete cell",
                    Svg(:class => "w-4 h-4",
                        :fill => "none",
                        :viewBox => "0 0 24 24",
                        :stroke => "currentColor",
                        Symbol("stroke-width") => "1.5",
                        Path(:d => "M6 18L18 6M6 6l12 12")
                    )
                )
            ),

            # Dirty indicator (yellow dot, top-left)
            Span(:class => "dirty-indicator absolute top-3 left-3 w-2 h-2 rounded-full bg-amber-400 hidden",
                Symbol("data-dirty") => "false"
            ),

            # Code area - will be replaced by CodeMirror
            Pre(:class => "cell-code m-0 p-5 text-sm font-mono min-h-20 overflow-x-auto bg-transparent",
                Code(cell.code)
            )
        ),

        # Output area - subtle separation
        Div(:class => "cell-output px-6 py-5 bg-stone-50 dark:bg-neutral-900 border-t border-stone-200/30 dark:border-neutral-800/30 rounded-b-lg font-mono text-sm text-stone-700 dark:text-stone-300" *
                      ((cell.output === nothing || isempty(cell.output.html)) ? " hidden" : ""),
            Symbol("data-output-container") => "true",
            cell.output !== nothing && !isempty(cell.output.html) ?
                RawHtml(format_cell_output(cell)) : nothing
        ),

        # Add cell button - delicate, appears on hover
        Div(:class => "add-cell-btn absolute -bottom-5 left-1/2 transform -translate-x-1/2 opacity-0 group-hover:opacity-100 transition-all duration-200 z-10",
            Button(:class => "flex items-center gap-1.5 px-3 py-1.5 text-xs text-stone-400 hover:text-amber-600 dark:hover:text-amber-400 bg-stone-50 dark:bg-neutral-900 rounded-full shadow-sm hover:shadow-md border border-stone-200/50 dark:border-neutral-700/50 transition-all duration-200",
                Symbol("data-action") => "add-cell",
                Symbol("data-after-cell-id") => cell_id_str,
                Svg(:class => "w-3 h-3",
                    :fill => "none",
                    :viewBox => "0 0 24 24",
                    :stroke => "currentColor",
                    Symbol("stroke-width") => "2",
                    Path(:d => "M12 4v16m8-8H4")
                ),
                Span("Add cell")
            )
        )
    )
end

"""
Render a list of cells.
"""
function CellsView(cells::Vector{Cell})
    Div(:class => "cells-container space-y-10 pb-20",
        # Empty state - refined, inviting
        isempty(cells) ?
            Div(:class => "text-center py-20",
                Div(:class => "inline-block px-12 py-10 rounded-xl bg-stone-100/50 dark:bg-neutral-800/30 border border-stone-200/30 dark:border-neutral-700/30",
                    P(:class => "text-xl font-serif text-stone-500 dark:text-stone-400 mb-3", "Begin your notebook"),
                    P(:class => "text-sm text-stone-400 dark:text-stone-500 tracking-wide", "Add a cell to start writing Julia")
                )
            ) : nothing,
        # Cell list
        [CellView(cell) for cell in cells]...
    )
end
