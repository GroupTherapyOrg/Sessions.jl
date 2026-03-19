# CellView.jl — Single cell component (code + state badge + output + controls)
#
# Renders a notebook cell with:
# - State badge (colored dot: idle/queued/running/done/errored)
# - Syntax-highlighted code block
# - Output area (HTML from _render_output or server broadcasts)
# - Action buttons: Run (▶), Delete (×)
# - "+" gap between cells for adding new cells
#
# Note: Components are included in Therapy's module context by load_app!,
# so we access Sessions via Main.Sessions.

const _Sessions = Main.Sessions

function CellView(cell::_Sessions.Cell; index::Int=0)
    code = strip(cell.code)
    isempty(code) && return nothing
    cell.disabled && return nothing

    output = cell.output
    cell_id = string(cell.id)

    # Runtime string
    runtime_ms = output.runtime_ns / 1_000_000
    runtime_str = if runtime_ms < 1
        "$(round(output.runtime_ns / 1000, digits=1)) μs"
    elseif runtime_ms < 1000
        "$(round(runtime_ms, digits=1)) ms"
    else
        "$(round(runtime_ms / 1000, digits=2)) s"
    end

    # State badge CSS class
    state_class = if cell.state == _Sessions.cell_idle
        "cell-state-idle"
    elseif cell.state == _Sessions.cell_queued
        "cell-state-queued"
    elseif cell.state == _Sessions.cell_running
        "cell-state-running"
    elseif cell.state == _Sessions.cell_done
        "cell-state-done"
    elseif cell.state == _Sessions.cell_errored
        "cell-state-errored"
    else
        "cell-state-idle"
    end

    # Is this a markdown cell?
    is_md = _Sessions._is_markdown_cell(code)

    parts = Any[]

    # --- Cell header with state badge + action buttons ---
    push!(parts,
        Div(:class => "flex items-center gap-2 mb-1 px-1",
            # State badge
            Div(:class => state_class,
                :data_cell_state => string(cell.state),
                :data_cell_id => cell_id),
            # Cell index
            Span(:class => "text-[10px] font-mono text-warm-400 dark:text-warm-600",
                "[$index]"),
            # Spacer
            Div(:class => "flex-1"),
            # Action buttons (visible on hover)
            Div(:class => "flex items-center gap-1 opacity-0 group-hover/cell:opacity-100 transition-opacity",
                # Run button
                Therapy.Button(:class => "text-xs text-warm-400 hover:text-accent-600 dark:hover:text-accent-400 cursor-pointer px-1.5 py-0.5 rounded hover:bg-warm-100 dark:hover:bg-warm-800 transition-colors",
                    :title => "Run cell",
                    :on_click => "TherapyWS.sendMessage('notebook', {action: 'execute', cell_id: '$(cell_id)'})",
                    "▶"),
                # Delete button
                Therapy.Button(:class => "text-xs text-warm-400 hover:text-accent-secondary-600 dark:hover:text-accent-secondary-400 cursor-pointer px-1.5 py-0.5 rounded hover:bg-warm-100 dark:hover:bg-warm-800 transition-colors",
                    :title => "Delete cell",
                    :on_click => "TherapyWS.sendMessage('notebook', {action: 'delete_cell', cell_id: '$(cell_id)'})",
                    "×"))))

    # --- Code block ---
    if is_md && cell.state in (_Sessions.cell_done, _Sessions.cell_errored) && output.output_type == :markdown
        # Markdown cell: show rendered prose (code hidden unless hovered)
        md_html = sprint(io -> Markdown.html(io, output.result))
        push!(parts,
            Div(:class => "group/code",
                # Rendered markdown (always visible)
                Div(:class => "notebook-prose px-2", RawHtml(md_html)),
                # Raw code (visible on hover)
                Div(:class => "hidden group-hover/code:block mt-2",
                    Div(:class => "relative rounded-lg bg-warm-950 ring-1 ring-warm-800 overflow-hidden",
                        Pre(:class => "overflow-x-auto p-4 font-mono text-sm leading-6 text-warm-200",
                            Code(:class => "block", _Sessions._highlight_julia(String(code))))))))
    else
        # Code cell: show highlighted code
        push!(parts,
            Div(:class => "relative rounded-lg bg-warm-950 ring-1 ring-warm-800 overflow-hidden",
                Pre(:class => "overflow-x-auto p-4 font-mono text-sm leading-6 text-warm-200",
                    Code(:class => "block", _Sessions._highlight_julia(String(code)))),
                # Runtime display (bottom-right, on hover)
                output.runtime_ns > 0 ?
                    Span(:class => "absolute bottom-2 right-3 text-[10px] font-mono text-warm-600 opacity-0 group-hover/cell:opacity-100 transition-opacity",
                        runtime_str) : nothing))
    end

    # --- Stdout ---
    if !isempty(output.stdout)
        push!(parts,
            Pre(:class => "mt-2 px-4 text-xs font-mono text-warm-500 whitespace-pre-wrap max-h-48 overflow-y-auto",
                output.stdout))
    end

    # --- Output area ---
    output_html = _render_cell_output_html(cell)
    if !isempty(output_html)
        push!(parts,
            Div(:class => "mt-2 cell-output",
                :data_cell_id => cell_id,
                RawHtml(output_html)))
    else
        # Empty output container for server to fill later
        push!(parts,
            Div(:class => "cell-output",
                :data_cell_id => cell_id))
    end

    # --- Cell container ---
    Div(:class => "cell-container group/cell",
        :data_cell_id => cell_id,
        Div(:class => "px-4 py-2", parts...))
end

"""Add-cell gap between cells — a "+" button to insert a new cell."""
function CellGap(; after_cell_id::String="")
    Div(:class => "cell-gap",
        Therapy.Button(:class => "cell-gap-button",
            :on_click => "TherapyWS.sendMessage('notebook', {action: 'add_cell', after_cell_id: '$(after_cell_id)'})",
            "+ Add cell"))
end

"""Render cell output to HTML string using the existing _render_output pipeline."""
function _render_cell_output_html(cell)
    # Skip rendering for markdown cells (output shown as prose above code)
    if _Sessions._is_markdown_cell(strip(cell.code)) && cell.output.output_type == :markdown
        return ""
    end
    vnode = _Sessions._render_output(cell)
    vnode === nothing && return ""
    Therapy.render_to_string(vnode)
end
