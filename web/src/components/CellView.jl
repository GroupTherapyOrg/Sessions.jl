# CellView.jl — Single cell component matching the TUI aesthetic
#
# Layout per cell:
#   [◌ state]  code block  [▶ runtime]
#              output area
#   ─────────── + ───────────────────
#
# Uses inline styles for reliability.

const _Sessions = Main.Sessions

# State badge colors
const _STATE_COLORS = Dict(
    _Sessions.cell_idle    => "#4e5157",
    _Sessions.cell_queued  => "#eab308",
    _Sessions.cell_running => "#4063d8",
    _Sessions.cell_done    => "#389826",
    _Sessions.cell_errored => "#cb3c33",
)

function CellView(cell::_Sessions.Cell; index::Int=0)
    code = strip(cell.code)
    isempty(code) && return nothing
    cell.disabled && return nothing

    output = cell.output
    cell_id = string(cell.id)

    # Runtime string
    runtime_ms = output.runtime_ns / 1_000_000
    runtime_str = if output.runtime_ns == 0
        ""
    elseif runtime_ms < 1
        "$(round(output.runtime_ns / 1000, digits=1))μs"
    elseif runtime_ms < 1000
        "$(round(runtime_ms, digits=1))ms"
    else
        "$(round(runtime_ms / 1000, digits=2))s"
    end

    state_color = get(_STATE_COLORS, cell.state, "#4e5157")
    is_pulsing = cell.state in (_Sessions.cell_queued, _Sessions.cell_running)
    is_md = _Sessions._is_markdown_cell(code)

    parts = Any[]

    # --- Markdown cell: render as prose ---
    if is_md && cell.state in (_Sessions.cell_done, _Sessions.cell_errored) && output.output_type == :markdown
        md_html = sprint(io -> Markdown.html(io, output.result))
        push!(parts,
            Div(:style => "display: flex; gap: 12px; padding: 8px 16px;",
                # State dot in left margin
                Div(:style => "width: 16px; padding-top: 6px; flex-shrink: 0; display: flex; justify-content: center;",
                    Div(:style => "width: 7px; height: 7px; border-radius: 50%; background: $(state_color);",
                        :data_cell_state => string(cell.state),
                        :data_cell_id => cell_id)),
                # Prose content
                Div(:style => "flex: 1; min-width: 0;",
                    :class => "nb-prose",
                    RawHtml(md_html))))
        return Div(:data_cell_id => cell_id, parts...)
    end

    # --- Code cell ---
    push!(parts,
        Div(:style => "display: flex; gap: 8px; padding: 4px 16px;",
            # Left margin: state dot
            Div(:style => "width: 16px; padding-top: 12px; flex-shrink: 0; display: flex; justify-content: center;",
                Div(:style => "width: 7px; height: 7px; border-radius: 50%; background: $(state_color);$(is_pulsing ? " animation: pulse 1.5s infinite;" : "")",
                    :data_cell_state => string(cell.state),
                    :data_cell_id => cell_id)),
            # Code block
            Div(:style => "flex: 1; min-width: 0; position: relative;",
                # Code
                Div(:style => "background: #0e0e12; border: 1px solid #2b2d30; border-radius: 6px; overflow: hidden;",
                    Pre(:style => "margin: 0; padding: 12px 16px; font-family: 'JuliaMono', 'Fira Code', monospace; font-size: 13px; line-height: 1.6; color: #bcbec4; overflow-x: auto; white-space: pre;",
                        Code(:style => "display: block;", _Sessions._highlight_julia(String(code))))),
                # Right side: run button + runtime
                Div(:style => "position: absolute; top: 8px; right: 8px; display: flex; align-items: center; gap: 8px;",
                    # Run button
                    Therapy.Button(:style => "background: none; border: none; color: #4e5157; cursor: pointer; font-size: 12px; padding: 2px 6px; border-radius: 3px;",
                        :title => "Run cell (Shift+Enter)",
                        :on_click => "TherapyWS.sendMessage('notebook', {action: 'execute', cell_id: '$(cell_id)'})",
                        "▶"),
                    # Runtime
                    !isempty(runtime_str) ?
                        Span(:style => "font-size: 11px; font-family: 'JuliaMono', monospace; color: #389826;",
                            "▶ " * runtime_str) : nothing))))

    # --- Stdout ---
    if !isempty(output.stdout)
        push!(parts,
            Pre(:style => "margin: 4px 0 0 40px; padding: 8px 12px; font-family: 'JuliaMono', 'Fira Code', monospace; font-size: 12px; color: #7a7e85; white-space: pre-wrap; max-height: 200px; overflow-y: auto;",
                output.stdout))
    end

    # --- Output area ---
    output_html = _render_cell_output_html(cell)
    if !isempty(output_html)
        push!(parts,
            Div(:style => "margin: 4px 0 0 40px;",
                :class => "cell-output",
                :data_cell_id => cell_id,
                RawHtml(output_html)))
    else
        push!(parts,
            Div(:class => "cell-output", :data_cell_id => cell_id))
    end

    Div(:data_cell_id => cell_id, parts...)
end

"""Add-cell divider between cells — thin line with + on left."""
function CellGap(; after_cell_id::String="")
    Div(:style => "display: flex; align-items: center; padding: 2px 16px 2px 28px; opacity: 0.3; transition: opacity 0.15s;",
        :onmouseenter => "this.style.opacity='1'",
        :onmouseleave => "this.style.opacity='0.3'",
        Therapy.Button(:style => "background: none; border: none; color: #4e5157; cursor: pointer; font-size: 14px; padding: 0 8px; line-height: 1;",
            :on_click => "TherapyWS.sendMessage('notebook', {action: 'add_cell', after_cell_id: '$(after_cell_id)'})",
            "+"),
        Div(:style => "flex: 1; height: 1px; background: #2b2d30;"))
end

"""Render cell output to HTML string."""
function _render_cell_output_html(cell)
    if _Sessions._is_markdown_cell(strip(cell.code)) && cell.output.output_type == :markdown
        return ""
    end
    vnode = _Sessions._render_output(cell)
    vnode === nothing && return ""
    Therapy.render_to_string(vnode)
end
