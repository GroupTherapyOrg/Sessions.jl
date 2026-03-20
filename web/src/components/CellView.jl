# CellView.jl — Single cell component for the Sessions.jl web IDE
#
# Each cell: output (above, on canvas) + CellFold @island (eye toggle + code-cell)
# CellFold manages fold state via WASM signal — no JS for toggle.
# Output stays visible when code is folded (Pluto-style).

const _Sessions = Main.Sessions

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

"""Format runtime nanoseconds into a compact human string."""
function _format_runtime(ns::UInt64)
    ns == 0 && return ""
    ms = ns / 1_000_000
    if ms < 1
        return "$(round(ns / 1000, digits=1))μs"
    elseif ms < 1000
        return "$(round(ms, digits=1))ms"
    else
        return "$(round(ms / 1000, digits=2))s"
    end
end

"""Render cell output to an HTML string."""
function _render_cell_output_html(cell)
    output = cell.output
    if output.output_type == :markdown && output.result !== nothing
        html = try
            sprint(io -> Main.Sessions.Markdown.html(io, output.result))
        catch
            sprint(show, output.result)
        end
        return """<div class="md-prose">$(html)</div>"""
    end
    vnode = _Sessions._render_output(cell)
    vnode === nothing && return ""
    Therapy.render_to_string(vnode)
end

# ---------------------------------------------------------------------------
# SVG constants
# ---------------------------------------------------------------------------

const _SVG_RUN = """<svg width="10" height="10" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2.5v11l10-5.5z"/></svg>"""
const _SVG_MENU = """<svg width="11" height="11" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="8" cy="3" r="1.2"/><circle cx="8" cy="8" r="1.2"/><circle cx="8" cy="13" r="1.2"/></svg>"""
const _SVG_PLUS = """<svg width="8" height="8" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M8 2v12M2 8h12"/></svg>"""

# ---------------------------------------------------------------------------
# CellView
# ---------------------------------------------------------------------------

function CellView(cell::_Sessions.Cell; index::Int=0)
    code = strip(cell.code)
    isempty(code) && return nothing
    cell.disabled && return nothing

    output = cell.output
    cell_id = string(cell.id)

    # =======================================================================
    # Code cell content (goes inside CellFold @island)
    # =======================================================================

    runtime_str = _format_runtime(output.runtime_ns)
    is_idle = cell.state == _Sessions.cell_idle
    cell_stale = _Sessions.is_stale(cell)

    # -- Hover controls (top-right) --
    ctrl_children = Any[]
    if !isempty(runtime_str)
        push!(ctrl_children,
            Span(:class => "rt-badge text-[10px] font-mono px-[7px] py-px rounded-full",
                :style => "color:#56d4a0;opacity:.8;background:rgba(86,212,160,.08);border:1px solid rgba(86,212,160,.12)",
                runtime_str))
    end
    push!(ctrl_children,
        Button(:class => "run-btn w-[22px] h-[22px] flex items-center justify-center rounded-full border-0 cursor-pointer text-jg hover:brightness-125",
            :style => "background:rgba(86,212,160,.1)",
            :title => "Run cell (Shift+Enter)",
            :on_click => "window._sessionsRunCell('$(cell_id)')",
            RawHtml(_SVG_RUN)))
    # Menu button (⋮) — wired to actions later
    push!(ctrl_children,
        Button(:class => "menu-btn w-[22px] h-[22px] flex items-center justify-center rounded-full border-0 cursor-pointer text-t4 hover:text-t3",
            :style => "background:rgba(255,255,255,.04)",
            :title => "Cell actions",
            RawHtml(_SVG_MENU)))

    # Delete button (×)
    push!(ctrl_children,
        Button(:class => "del-btn w-[22px] h-[22px] flex items-center justify-center rounded-full border-0 cursor-pointer text-t4 hover:text-jr transition-colors",
            :style => "background:rgba(255,255,255,.04)",
            :title => "Delete cell",
            :on_click => "if(confirm('Delete this cell?'))TherapyWS.sendMessage('notebook',{action:'delete_cell',cell_id:'$(cell_id)'})",
            RawHtml("""<svg width="10" height="10" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 4l8 8M12 4l-8 8"/></svg>""")))

    ctrls = Div(:class => "cell-ctrls absolute top-1 right-1.5 flex items-center gap-1.5 z-10",
        ctrl_children...)

    # CM editor host
    cm_div = Div(:class => "cm-cell",
        :data_cell_id => cell_id,
        :data_src => String(code))

    # Code cell classes
    code_cell_classes = "code-cell relative rounded-lg border border-b1 bg-island overflow-hidden transition-all duration-200 hover:border-b2"
    is_idle && (code_cell_classes *= " idle")
    cell_stale && (code_cell_classes *= " stale")

    # The code-cell div (passed as children to CellIsland)
    code_cell = Div(:class => code_cell_classes, ctrls, cm_div)

    # =======================================================================
    # Output area (ABOVE code, on canvas — stays visible when folded)
    # =======================================================================

    has_text_output = !isempty(output.text_representation) && output.output_type != :nothing && output.output_type != :markdown
    output_html = _render_cell_output_html(cell)
    has_output = has_text_output || !isempty(output_html)
    is_md_output = output.output_type == :markdown

    out_div = if has_output
        out_content = !isempty(output_html) ? RawHtml(output_html) :
                      has_text_output ? output.text_representation : nothing

        if out_content !== nothing
            if is_md_output
                Div(:class => "cell-out",
                    :data_cell_id => cell_id,
                    :style => "padding:4px 0 8px;overflow-x:auto;",
                    out_content)
            else
                Div(:class => "cell-out font-mono text-xs text-tout whitespace-pre overflow-x-auto",
                    :data_cell_id => cell_id,
                    :style => "padding:6px 0 10px;line-height:1.5;",
                    out_content)
            end
        else
            Div(:class => "cell-out", :data_cell_id => cell_id, :style => "display:none;")
        end
    else
        Div(:class => "cell-out", :data_cell_id => cell_id, :style => "display:none;")
    end

    # =======================================================================
    # Assemble: output + CellFold @island (eye toggle + code-cell)
    # =======================================================================

    Div(:class => "cell-wrap relative", :style => "margin-left:28px",
        :data_cell_id => cell_id,
        out_div,
        CellIsland(code_cell; initial_open = cell.folded ? 0 : 1))
end

# ---------------------------------------------------------------------------
# CellGap — divider between cells with "+ Code" button
# ---------------------------------------------------------------------------

function CellGap(; after_cell_id::String="")
    Div(:class => "cdiv h-[18px] flex items-center justify-center",
        Div(:class => "cdiv-inner flex items-center gap-1 opacity-0 transition-opacity",
            Div(:class => "h-px w-14 bg-b2"),
            Button(:class => "flex items-center gap-1 rounded-full text-[10px] font-sans px-2.5 py-px bg-island border border-b2 text-t3 cursor-pointer hover:text-t1 hover:bg-hov",
                :on_click => "TherapyWS.sendMessage('notebook', {action: 'add_cell', after_cell_id: '$(after_cell_id)'})",
                RawHtml(_SVG_PLUS),
                "Code"),
            Div(:class => "h-px w-14 bg-b2")))
end
