# IDE/CellCard.jl - Cell card component (Suite.jl rewrite)
#
# Matches the SVG design: output above, dotted separator, code card below.
#
#   Output rendered in base layer (plain text, serif for markdown)
#   ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ (dotted separator)
#   ┃ Code card with left accent bar
#   ┃ - warm-50 / dark:#111110 background
#   ┃ - Left accent: green (output), purple (markdown), neutral (idle), red (error)
#   ┃ - Hover: run button (top-right), delete button
#
# SESSIONS-3500: CellCard component — output above, code below

import Suite

# =============================================================================
# Left Accent Bar Colors
# =============================================================================

"""
Get left accent bar color class based on cell state and type.
- Green (#389826): running or has output
- Purple (#9558b2): markdown cell
- Red: error state
- Neutral (warm-200): idle with no output
"""
function _accent_color(cell::Cell)
    if cell.state == CELL_ERROR
        return "bg-[#cb3c33]"
    elseif cell.cell_type == :markdown
        return "bg-[#9558b2] opacity-25"
    elseif cell.state == CELL_RUNNING || cell.state == CELL_QUEUED
        return "bg-accent-500"
    elseif cell.output !== nothing && !isempty(cell.output.html)
        return "bg-accent-500 opacity-35"
    else
        return "bg-warm-200 dark:bg-warm-700"
    end
end

# =============================================================================
# Output Section (above code)
# =============================================================================

"""
    CellOutput(cell)

Output rendered in the base layer above the code card.
Uses serif typography for markdown, mono for code output.
"""
function IDECellOutput(cell::Cell)
    has_output = cell.output !== nothing && !isempty(cell.output.html)

    if !has_output
        return nothing
    end

    # Output container
    Div(:class => "cell-output px-0 py-2 text-sm text-warm-700 dark:text-warm-300",
        Symbol("data-signal-html") => "cell_output_$(cell.id)",
        Symbol("data-signal-hide-empty") => "true",
        RawHtml(format_cell_output(cell))
    )
end

# =============================================================================
# Dotted Separator
# =============================================================================

"""
Dashed separator line between output and code card.
Only shown when there is output.
"""
function CellSeparator(cell::Cell)
    has_output = cell.output !== nothing && !isempty(cell.output.html)

    if !has_output
        return nothing
    end

    Div(:class => "cell-separator border-t border-dashed border-warm-200 dark:border-[#252422] my-1")
end

# =============================================================================
# Code Card
# =============================================================================

"""
    IDECodeCard(cell; show_toolbar=true)

Code card with left accent bar, matching SVG design.
Background: warm-50 / dark:#111110
Left accent bar: 2px, color-coded by state

When `show_toolbar=false`, the drag handle and cell toolbar are hidden
(used by embedded NotebookApp in read-only or minimal mode).
"""
function IDECodeCard(cell::Cell; show_toolbar::Bool=true)
    cell_id_str = string(cell.id)
    state_signal = "cell_state_$(cell_id_str)"
    runtime_signal = "cell_runtime_$(cell_id_str)"
    accent = _accent_color(cell)

    Div(:class => "cell-code-card relative flex",
        # Drag handle (grip icon, visible on hover) — hidden when toolbar disabled
        show_toolbar ?
            Div(:class => "cell-drag-handle flex-shrink-0 w-4 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity cursor-grab active:cursor-grabbing",
                :draggable => "true",
                Symbol("data-drag-cell") => cell_id_str,
                :title => "Drag to reorder",
                Svg(:class => "w-3 h-3 text-warm-300 dark:text-warm-600", :fill => "currentColor", :viewBox => "0 0 16 16",
                    Circle(:cx => "5", :cy => "3", :r => "1"),
                    Circle(:cx => "11", :cy => "3", :r => "1"),
                    Circle(:cx => "5", :cy => "8", :r => "1"),
                    Circle(:cx => "11", :cy => "8", :r => "1"),
                    Circle(:cx => "5", :cy => "13", :r => "1"),
                    Circle(:cx => "11", :cy => "13", :r => "1")
                )
            ) : nothing,

        # Left accent bar (2px)
        Div(:class => "cell-accent-bar w-0.5 rounded-l flex-shrink-0 $accent"),

        # Code card body
        Suite.Card(
            :class => "flex-1 rounded-l-none border-l-0 bg-warm-50 dark:bg-[#111110] border-warm-200/50 dark:border-[#252422]/50",

            Suite.CardContent(
                :class => "relative p-0",

                # Cell toolbar (run, move, fold, delete) — hidden when disabled
                show_toolbar ?
                    IDECellToolbar(cell_id_str;
                        runtime_ms=cell.runtime_ms,
                        is_folded=cell.folded
                    ) : nothing,

                # Code area (CodeMirror target)
                Div(
                    Symbol("data-codemirror") => "true",
                    Symbol("data-code") => cell.code,
                    Symbol("data-cell-id") => cell_id_str,

                    # Fallback pre for SSR
                    Pre(:class => "cell-code m-0 px-4 py-3 text-[12.5px] font-mono min-h-[40px] overflow-x-auto bg-transparent text-warm-800 dark:text-warm-200 leading-relaxed",
                        Code(cell.code)
                    )
                )
            )
        )
    )
end

# =============================================================================
# Add Cell Button (between cells)
# =============================================================================

"""
    CellAddButton(cell_id)

Add cell button between cells: dashed line + "+" pill.
Matches SVG design with centered pill on dashed line.
"""
function CellAddButton(cell_id::String)
    Div(:class => "add-cell-zone relative flex items-center justify-center py-2 opacity-0 group-hover:opacity-100 transition-opacity duration-200",
        # Left dashed line
        Div(:class => "flex-1 border-t border-dashed border-warm-300/35 dark:border-warm-700/35"),
        # '+' pill button
        Button(:class => "flex items-center justify-center w-8 h-4 mx-2 rounded-full bg-warm-100 dark:bg-warm-800 border border-warm-200/50 dark:border-warm-700/50 text-warm-400 dark:text-warm-500 hover:text-warm-600 dark:hover:text-warm-400 text-xs font-mono transition-colors",
            :on_click => "addCellAfter('$(cell_id)')",
            :title => "Add cell below",
            "+"
        ),
        # Right dashed line
        Div(:class => "flex-1 border-t border-dashed border-warm-300/35 dark:border-warm-700/35")
    )
end

# =============================================================================
# CellCard (Main Component)
# =============================================================================

"""
    IDECellCard(cell::Cell; options=nothing)

Complete cell card matching SVG design: output above, dotted separator, code below.

When `options::NotebookOptions` is provided, controls:
- `show_toolbar`: Show/hide cell toolbar (run, move, fold, delete)
- `show_add_cell`: Show/hide add-cell button between cells
- `show_output`: Show/hide cell output
- `editable`: Enable/disable code editing
- `runnable`: Enable/disable cell execution

# Structure
1. Output rendered in base layer (if present)
2. Dotted separator (if output present)
3. Code card with left accent bar + CodeMirror + hover toolbar
4. Add cell button (between cells, on hover)
"""
function IDECellCard(cell::Cell; options::Union{NotebookOptions, Nothing}=nothing)
    cell_id_str = string(cell.id)
    state_signal = "cell_state_$(cell_id_str)"

    # Options defaults (nil = full IDE mode)
    show_toolbar = options === nothing || options.show_toolbar
    show_add = options === nothing || options.show_add_cell
    show_output = options === nothing || options.show_output

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

    # Error output
    has_error = cell.state == CELL_ERROR && cell.output !== nothing && !isempty(cell.output.html)

    fold_class = cell.folded ? "cell-folded" : ""

    Div(:class => "cell group relative $state_class $fold_class",
        Symbol("data-cell-id") => cell_id_str,
        Symbol("data-folded") => cell.folded ? "true" : "false",
        Symbol("data-signal-match") => "$(state_signal):CELL_RUNNING:cell-running;$(state_signal):CELL_QUEUED:cell-queued;$(state_signal):CELL_ERROR:cell-error;$(state_signal):CELL_IDLE:cell-idle",

        # State badge (shown for non-idle states)
        cell.state != CELL_IDLE ?
            Div(:class => "mb-1", CellStateBadge(cell.state)) : nothing,

        # Stale indicator
        cell.state == CELL_STALE ? CellStaleIndicator() : nothing,

        # 1. Output (above code card, in base layer)
        show_output ? (
            has_error ?
                CellErrorDisplay(cell.output.html; logs=cell.output.error_logs) :
                IDECellOutput(cell)
        ) : nothing,

        # 1b. Running skeleton (shown via CSS when cell-running class is active)
        CellRunningIndicator(),

        # 2. Dotted separator (CSS-hidden when folded)
        show_output ? CellSeparator(cell) : nothing,

        # 3. Code card with left accent (CSS-hidden when folded)
        show_toolbar ?
            IDECodeCard(cell) :
            IDECodeCard(cell; show_toolbar=false),

        # 3b. Fold indicator (CSS-shown only when folded)
        CellFoldedIndicator(cell_id_str),

        # 4. Add cell button (between cells)
        show_add ? CellAddButton(cell_id_str) : nothing
    )
end

# =============================================================================
# Folded Cell Indicator
# =============================================================================

"""
    CellFoldedIndicator(cell_id)

Small indicator shown when a cell's code is folded (hidden).
Click to unfold.
"""
function CellFoldedIndicator(cell_id::String)
    Div(:class => "cell-fold-indicator items-center gap-2 py-1 px-2 cursor-pointer text-warm-400 dark:text-warm-500 hover:text-warm-600 dark:hover:text-warm-400 transition-colors",
        :on_click => "toggleCellFold('$(cell_id)')",
        :title => "Show code",
        # Unfold icon
        Svg(:class => "w-3 h-3", :fill => "none", :viewBox => "0 0 24 24",
            :stroke => "currentColor", Symbol("stroke-width") => "1.5",
            Path(:stroke_linecap => "round", :stroke_linejoin => "round",
                :d => "M19.5 8.25l-7.5 7.5-7.5-7.5")
        ),
        Span(:class => "text-[10px] font-mono", "code hidden")
    )
end

# =============================================================================
# CellsView (List of cells)
# =============================================================================

"""
    IDECellsView(cells::Vector{Cell}; options=nothing)

Renders a list of cells using IDECellCard.
Includes empty state with "Begin your notebook" prompt.

When `options::NotebookOptions` is provided, it controls visibility of
toolbar, add-cell buttons, output, and editability for embedded use.
"""
function IDECellsView(cells::Vector{Cell}; options::Union{NotebookOptions, Nothing}=nothing)
    last_cell_id = isempty(cells) ? nothing : string(cells[end].id)
    show_add = options === nothing || options.show_add_cell
    is_editable = options === nothing || options.editable

    Div(:class => "cells-container space-y-6 pb-20",
        # Empty state
        isempty(cells) ?
            Div(:class => "text-center py-20",
                Div(:class => "inline-block px-12 py-10 rounded-xl bg-warm-100/50 dark:bg-warm-800/30 border border-warm-200/30 dark:border-warm-700/30",
                    P(:class => "text-xl font-serif text-warm-500 dark:text-warm-400 mb-4", "Begin your notebook"),
                    is_editable ?
                        Button(:class => "flex items-center gap-2 mx-auto px-4 py-2 text-sm font-mono text-warm-600 dark:text-warm-300 bg-warm-50 dark:bg-warm-900 rounded-full border border-warm-200 dark:border-warm-700 hover:border-accent-500 transition-colors",
                            :on_click => "addCellAfter(null)",
                            Span(:class => "text-sm", "+"),
                            Span("Add your first cell")
                        ) : nothing
                )
            ) : nothing,
        # Cell list — markdown cells get special rendering
        [is_markdown(cell) ? IDEMarkdownCell(cell) : IDECellCard(cell; options=options) for cell in cells]...,
        # Bottom add-cell button (always visible after last cell)
        last_cell_id !== nothing && show_add ?
            Div(:class => "flex items-center justify-center pt-4",
                Button(:class => "flex items-center gap-2 px-4 py-2 text-xs font-mono text-warm-400 dark:text-warm-500 hover:text-warm-600 dark:hover:text-warm-400 bg-warm-50 dark:bg-warm-900 rounded-full border border-dashed border-warm-200/50 dark:border-warm-700/50 hover:border-accent-500/50 transition-colors",
                    :on_click => "addCellAfter('$(last_cell_id)')",
                    :title => "Add cell at end",
                    Span("+"),
                    Span("Add cell")
                )
            ) : nothing
    )
end
