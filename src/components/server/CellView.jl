# CellView.jl - Cell rendering component (SSR)
#
# Renders a single notebook cell with code editor and output.
# Design: Elegant, minimal, scholarly aesthetic inspired by Pluto.jl
#
# Signal Architecture (Per-Cell):
# - cell_state_{id}: "CELL_IDLE"|"CELL_RUNNING"|"CELL_QUEUED"|"CELL_ERROR"
# - cell_output_{id}: HTML string of cell output
# - cell_runtime_{id}: Runtime in ms (string)
#
# This is an SSR (server-side rendered) component. For interactive
# cell editing islands, see components/islands/CellEditor.jl

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
    elseif cell.state == CELL_STALE
        "cell-stale"
    else
        "cell-idle"
    end

    # Cell container - parchment card with subtle warmth
    # Uses Therapy.jl reactive bindings:
    # - data-signal-match for CSS class changes based on state
    Div(:class => "cell group relative mb-8 bg-stone-50 dark:bg-neutral-900 rounded-lg border border-stone-200/50 dark:border-neutral-800/50 shadow-sm hover:shadow-lg transition-all duration-300 $state_class",
        Symbol("data-cell-id") => cell_id_str,
        Symbol("data-notebook-id") => "",  # Will be set by parent
        # Reactive class bindings for cell state
        Symbol("data-signal-match") => "$(state_signal):CELL_RUNNING:cell-running;$(state_signal):CELL_QUEUED:cell-queued;$(state_signal):CELL_ERROR:cell-error;$(state_signal):CELL_IDLE:cell-idle",

        # Subtle left accent bar for state indication
        Div(:class => "cell-state-bar absolute left-0 top-0 bottom-0 w-0.5 rounded-l-lg transition-colors duration-300"),

        # Code editor area - uses Therapy.jl's CodeMirror external library pattern
        # data-codemirror triggers Therapy.jl's registered CodeMirror initialization
        Div(:class => "cell-code-container relative bg-amber-50/40 dark:bg-neutral-800/60 rounded-t-lg",
            Symbol("data-codemirror") => "true",
            Symbol("data-code") => cell.code,
            Symbol("data-cell-id") => cell_id_str,

            # Floating run button (top-right, appears on hover, z-20 to be above CodeMirror)
            Div(:class => "absolute top-3 right-3 z-20 flex items-center gap-2 opacity-0 group-hover:opacity-100 transition-opacity duration-150",
                # Runtime badge
                Span(:class => "text-xs font-mono text-neutral-400",
                    Symbol("data-server-signal") => runtime_signal,
                    cell.runtime_ms !== nothing ? "$(round(cell.runtime_ms, digits=1))ms" : ""
                ),
                # Run button - elegant pill shape
                # TODO: Convert to island with Julia closure once Therapy.jl has Wasm imports for CodeMirror
                # For now uses string handler as SSR bridge to JS infrastructure
                Button(:class => "run-btn flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-white rounded-full shadow-sm hover:shadow transition-all duration-150",
                    :on_click => "executeCell('$(cell_id_str)')",
                    :title => "Run cell (Shift+Enter)",
                    Svg(:class => "w-3 h-3",
                        :fill => "currentColor",
                        :viewBox => "0 0 20 20",
                        Path(:d => "M6.3 2.841A1.5 1.5 0 004 4.11v11.78a1.5 1.5 0 002.3 1.269l9.344-5.89a1.5 1.5 0 000-2.538L6.3 2.84z")
                    ),
                    Span("Run")
                ),
                # Delete button - subtle, appears on hover
                # TODO: Convert to island with Julia closure once Therapy.jl has channel message Wasm imports
                Button(:class => "p-1.5 text-neutral-300 hover:text-red-400 transition-colors",
                    :on_click => "deleteCell('$(cell_id_str)')",
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

            # Dirty indicator (yellow dot, top-left, z-20 to be above CodeMirror)
            Span(:class => "dirty-indicator absolute top-3 left-3 z-20 w-2 h-2 rounded-full bg-amber-400 hidden",
                Symbol("data-dirty") => "false"
            ),

            # Code area - will be replaced by CodeMirror
            Pre(:class => "cell-code m-0 p-5 text-sm font-mono min-h-20 overflow-x-auto bg-transparent",
                Code(cell.code)
            )
        ),

        # Output area - uses Therapy.jl data-signal-html for reactive updates
        Div(:class => "cell-output px-6 py-5 bg-stone-50 dark:bg-neutral-900 border-t border-stone-200/30 dark:border-neutral-800/30 rounded-b-lg font-mono text-sm text-stone-700 dark:text-stone-300" *
                      ((cell.output === nothing || isempty(cell.output.html)) ? " hidden" : ""),
            # Therapy.jl reactive HTML binding - auto-updates when signal changes
            Symbol("data-signal-html") => output_signal,
            Symbol("data-signal-hide-empty") => "true",
            cell.output !== nothing && !isempty(cell.output.html) ?
                RawHtml(format_cell_output(cell)) : nothing
        ),

        # Add cell button - delicate, appears on hover
        # TODO: Convert to island with Julia closure once Therapy.jl has channel message Wasm imports
        Div(:class => "add-cell-btn absolute -bottom-5 left-1/2 transform -translate-x-1/2 opacity-0 group-hover:opacity-100 transition-all duration-200 z-10",
            Button(:class => "flex items-center gap-1.5 px-3 py-1.5 text-xs text-stone-400 hover:text-amber-600 dark:hover:text-amber-400 bg-stone-50 dark:bg-neutral-900 rounded-full shadow-sm hover:shadow-md border border-stone-200/50 dark:border-neutral-700/50 transition-all duration-200",
                :on_click => "addCellAfter('$(cell_id_str)')",
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
        # Empty state - refined, inviting with action button
        isempty(cells) ?
            Div(:class => "text-center py-20",
                Div(:class => "inline-block px-12 py-10 rounded-xl bg-stone-100/50 dark:bg-neutral-800/30 border border-stone-200/30 dark:border-neutral-700/30",
                    P(:class => "text-xl font-serif text-stone-500 dark:text-stone-400 mb-4", "Begin your notebook"),
                    Button(:class => "flex items-center gap-2 mx-auto px-4 py-2 text-sm font-medium text-stone-600 dark:text-stone-300 bg-white dark:bg-neutral-800 rounded-full shadow-sm hover:shadow-md border border-stone-200 dark:border-neutral-700 transition-all duration-200",
                        :on_click => "addCellAfter(null)",
                        Svg(:class => "w-4 h-4",
                            :fill => "none",
                            :viewBox => "0 0 24 24",
                            :stroke => "currentColor",
                            Symbol("stroke-width") => "2",
                            Path(:d => "M12 4v16m8-8H4")
                        ),
                        Span("Add your first cell")
                    )
                )
            ) : nothing,
        # Cell list
        [CellView(cell) for cell in cells]...
    )
end
