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

    Div(:class => "border-t border-dashed border-warm-200 dark:border-[#252422] my-1")
end

# =============================================================================
# Code Card
# =============================================================================

"""
    IDECodeCard(cell)

Code card with left accent bar, matching SVG design.
Background: warm-50 / dark:#111110
Left accent bar: 2px, color-coded by state
"""
function IDECodeCard(cell::Cell)
    cell_id_str = string(cell.id)
    state_signal = "cell_state_$(cell_id_str)"
    runtime_signal = "cell_runtime_$(cell_id_str)"
    accent = _accent_color(cell)

    Div(:class => "relative flex",
        # Left accent bar (2px)
        Div(:class => "cell-accent-bar w-0.5 rounded-l flex-shrink-0 $accent"),

        # Code card body
        Suite.Card(
            :class => "flex-1 rounded-l-none border-l-0 bg-warm-50 dark:bg-[#111110] border-warm-200/50 dark:border-[#252422]/50",

            Suite.CardContent(
                :class => "relative p-0",

                # Hover toolbar (run + delete, top-right)
                Div(:class => "absolute top-2 right-2 z-20 flex items-center gap-1.5 opacity-0 group-hover:opacity-100 transition-opacity duration-150",
                    # Runtime badge
                    Span(:class => "text-[10px] font-mono text-warm-400 dark:text-warm-500",
                        Symbol("data-server-signal") => runtime_signal,
                        cell.runtime_ms !== nothing ? "$(round(cell.runtime_ms, digits=1))ms" : ""
                    ),
                    # Run button (green pill)
                    Button(:class => "flex items-center gap-1 px-2 py-1 text-[10px] font-mono rounded bg-accent-500/10 text-accent-600 dark:text-accent-400 hover:bg-accent-500/20 transition-colors",
                        :on_click => "executeCell('$(cell_id_str)')",
                        :title => "Run cell (Shift+Enter)",
                        Svg(:class => "w-2.5 h-2.5", :fill => "currentColor", :viewBox => "0 0 20 20",
                            Path(:d => "M6.3 2.841A1.5 1.5 0 004 4.11v11.78a1.5 1.5 0 002.3 1.269l9.344-5.89a1.5 1.5 0 000-2.538L6.3 2.84z")
                        )
                    ),
                    # Delete button
                    Button(:class => "p-1 text-warm-300 dark:text-warm-600 hover:text-rose-500 transition-colors",
                        :on_click => "deleteCell('$(cell_id_str)')",
                        :title => "Delete cell",
                        Svg(:class => "w-3.5 h-3.5", :fill => "none", :viewBox => "0 0 24 24",
                            :stroke => "currentColor", Symbol("stroke-width") => "1.5",
                            Path(:d => "M6 18L18 6M6 6l12 12")
                        )
                    )
                ),

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
    IDECellCard(cell::Cell)

Complete cell card matching SVG design: output above, dotted separator, code below.

# Structure
1. Output rendered in base layer (if present)
2. Dotted separator (if output present)
3. Code card with left accent bar + CodeMirror + hover toolbar
4. Add cell button (between cells, on hover)

# Left Accent Colors
- Green (#389826): running, queued, or has output
- Purple (#9558b2): markdown cell
- Red (#cb3c33): error state
- Neutral (warm-200): idle with no output
"""
function IDECellCard(cell::Cell)
    cell_id_str = string(cell.id)
    state_signal = "cell_state_$(cell_id_str)"

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

    Div(:class => "cell group relative $state_class",
        Symbol("data-cell-id") => cell_id_str,
        Symbol("data-signal-match") => "$(state_signal):CELL_RUNNING:cell-running;$(state_signal):CELL_QUEUED:cell-queued;$(state_signal):CELL_ERROR:cell-error;$(state_signal):CELL_IDLE:cell-idle",

        # State badge (shown for non-idle states)
        cell.state != CELL_IDLE ?
            Div(:class => "mb-1", CellStateBadge(cell.state)) : nothing,

        # Stale indicator
        cell.state == CELL_STALE ? CellStaleIndicator() : nothing,

        # 1. Output (above code card, in base layer)
        has_error ?
            CellErrorDisplay(cell.output.html; logs=cell.output.error_logs) :
            IDECellOutput(cell),

        # 1b. Running skeleton (shown via CSS when cell-running class is active)
        CellRunningIndicator(),

        # 2. Dotted separator
        CellSeparator(cell),

        # 3. Code card with left accent
        IDECodeCard(cell),

        # 4. Add cell button (between cells)
        CellAddButton(cell_id_str)
    )
end

# =============================================================================
# CellsView (List of cells)
# =============================================================================

"""
    IDECellsView(cells::Vector{Cell})

Renders a list of cells using IDECellCard.
Includes empty state with "Begin your notebook" prompt.
"""
function IDECellsView(cells::Vector{Cell})
    Div(:class => "cells-container space-y-6 pb-20",
        # Empty state
        isempty(cells) ?
            Div(:class => "text-center py-20",
                Div(:class => "inline-block px-12 py-10 rounded-xl bg-warm-100/50 dark:bg-warm-800/30 border border-warm-200/30 dark:border-warm-700/30",
                    P(:class => "text-xl font-serif text-warm-500 dark:text-warm-400 mb-4", "Begin your notebook"),
                    Button(:class => "flex items-center gap-2 mx-auto px-4 py-2 text-sm font-mono text-warm-600 dark:text-warm-300 bg-warm-50 dark:bg-warm-900 rounded-full border border-warm-200 dark:border-warm-700 hover:border-accent-500 transition-colors",
                        :on_click => "addCellAfter(null)",
                        Span(:class => "text-sm", "+"),
                        Span("Add your first cell")
                    )
                )
            ) : nothing,
        # Cell list — markdown cells get special rendering
        [is_markdown(cell) ? IDEMarkdownCell(cell) : IDECellCard(cell) for cell in cells]...
    )
end
