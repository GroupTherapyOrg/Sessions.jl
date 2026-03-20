# CellView.jl — Single cell component for the Sessions.jl web IDE
#
# Two cell types:
#   Code cell  — CodeMirror host (.cm-cell with data-src), output area, hover controls
#   Markdown   — Rendered prose with purple accent divider
#
# Between cells: CellGap divider with "+ Code" button
#
# Color palette:
#   deep=#0a0e14 base=#0f1419 surf=#151c25 island=#1a2332 hov=#1f2b3d
#   b1=#1c2736 b2=#2a3a4f
#   t1=#d4dce8 t2=#9baabd t3=#6b7d93 t4=#3d5068 tout=#7ca0bf
#   accent/jg=#56d4a0 jr=#e06b65 jp=#b08fd8

const _Sessions = Main.Sessions

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

"""HTML-escape a string for safe embedding in an attribute (e.g. data-src)."""
function _html_escape(s::AbstractString)
    s = replace(s, "&"  => "&amp;")
    s = replace(s, "\"" => "&quot;")
    s = replace(s, "'"  => "&#39;")
    s = replace(s, "<"  => "&lt;")
    s = replace(s, ">"  => "&gt;")
    s
end

"""Format runtime nanoseconds into a compact human string."""
function _format_runtime(ns::UInt64)
    ns == 0 && return ""
    ms = ns / 1_000_000
    if ms < 1
        return "$(round(ns / 1000, digits=1))\u03bcs"   # μs
    elseif ms < 1000
        return "$(round(ms, digits=1))ms"
    else
        return "$(round(ms / 1000, digits=2))s"
    end
end

"""Render cell output to an HTML string (for embedding inside cell-out div)."""
function _render_cell_output_html(cell)
    output = cell.output
    # Markdown output → render as styled prose HTML
    if output.output_type == :markdown && output.result !== nothing
        html = try
            sprint(io -> Main.Sessions.Markdown.html(io, output.result))
        catch
            sprint(show, output.result)
        end
        return """<div class="md-prose">$(html)</div>"""
    end
    # All other output types → use Sessions._render_output pipeline
    vnode = _Sessions._render_output(cell)
    vnode === nothing && return ""
    Therapy.render_to_string(vnode)
end

# ---------------------------------------------------------------------------
# SVG constants
# ---------------------------------------------------------------------------

const _SVG_EYE_OPEN = """<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>"""

const _SVG_EYE_CLOSED = """<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19M1 1l22 22"/></svg>"""

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
    # --- Eye toggle (positioned to the left of the cell) ---
    eye_svg = cell.folded ? _SVG_EYE_CLOSED : _SVG_EYE_OPEN
    eye_div = Div(:class => "cell-eye",
        RawHtml(eye_svg))

    # =======================================================================
    # Code cell
    # =======================================================================

    runtime_str = _format_runtime(output.runtime_ns)
    is_idle = cell.state == _Sessions.cell_idle

    # Stale / never-run detection
    cell_stale = _Sessions.is_stale(cell)
    cell_never_run = _Sessions.is_never_run(cell)

    # -- Hover controls (top-right) --
    ctrl_children = Any[]

    # Runtime badge (class rt-badge so the channel handler JS can find and replace it)
    if !isempty(runtime_str)
        push!(ctrl_children,
            Span(:class => "rt-badge text-[10px] font-mono px-[7px] py-px rounded-full",
                :style => "color:#56d4a0;opacity:.8;background:rgba(86,212,160,.08);border:1px solid rgba(86,212,160,.12)",
                runtime_str))
    end

    # Run button (reads code from CM editor before sending)
    push!(ctrl_children,
        Button(:class => "run-btn w-[22px] h-[22px] flex items-center justify-center rounded-full border-0 cursor-pointer text-jg hover:brightness-125",
            :style => "background:rgba(86,212,160,.1)",
            :title => "Run cell (Shift+Enter)",
            :on_click => "window._sessionsRunCell('$(cell_id)')",
            RawHtml(_SVG_RUN)))

    # Menu button
    push!(ctrl_children,
        Button(:class => "menu-btn w-[22px] h-[22px] flex items-center justify-center rounded-full border-0 cursor-pointer text-t4 hover:text-t3",
            :style => "background:rgba(255,255,255,.04)",
            RawHtml(_SVG_MENU)))

    ctrls = Div(:class => "cell-ctrls absolute top-1 right-1.5 flex items-center gap-1.5 z-10",
        ctrl_children...)

    # State tracked via data attribute on the code-cell div (for CSS left accent bar).
    # No visible badge dot — the left accent bar (green/orange/red via CSS ::before) is sufficient.

    # -- CodeMirror host (data-cell-id lets JS find editor for this cell) --
    # NOTE: Do NOT html-escape data_src — Therapy's render_to_string handles attribute escaping.
    cm_div = Div(:class => "cm-cell",
        :data_cell_id => cell_id,
        :data_src => String(code))

    # -- Output area (only if cell has output) --
    has_text_output = !isempty(output.text_representation) && output.output_type != :nothing && output.output_type != :markdown
    output_html = _render_cell_output_html(cell)
    has_output = has_text_output || !isempty(output_html)

    # Build inner children
    code_cell_classes = "code-cell relative rounded-lg border border-b1 bg-island overflow-hidden transition-all duration-200 hover:border-b2"
    if is_idle
        code_cell_classes *= " idle"
    end
    if cell_stale
        code_cell_classes *= " stale"
    end
    if cell.folded
        code_cell_classes *= " cell-collapsed"
    end

    # Code cell inner children (controls + CM editor)
    inner_children = Any[ctrls, cm_div]

    # ── Output area: ABOVE the code cell, directly on canvas (Pluto-style).
    # When the eye hides the code-cell, output stays visible.
    # Markdown output uses md-prose styling. Text output uses monospace.
    # Always present (hidden when empty) so server broadcasts can fill it.
    is_md_output = output.output_type == :markdown
    out_div = if has_output
        out_content = if !isempty(output_html)
            RawHtml(output_html)
        elseif has_text_output
            output.text_representation
        else
            nothing
        end

        if out_content !== nothing
            if is_md_output
                # Markdown: clean prose, no box, flows on canvas
                Div(:class => "cell-out",
                    :data_cell_id => cell_id,
                    :style => "padding:4px 0 8px;overflow-x:auto;",
                    out_content)
            else
                # Code/text output: monospace, subtle style, horizontal scroll
                Div(:class => "cell-out font-mono text-xs text-tout whitespace-pre overflow-x-auto",
                    :data_cell_id => cell_id,
                    :style => "padding:6px 0 10px;line-height:1.5;",
                    out_content)
            end
        else
            Div(:class => "cell-out",
                :data_cell_id => cell_id,
                :style => "display:none;")
        end
    else
        # No output yet — hidden container, server will populate and show it
        Div(:class => "cell-out",
            :data_cell_id => cell_id,
            :style => "display:none;")
    end

    # ── Assemble: output ABOVE, then eye + code-cell BELOW
    Div(:class => "cell-wrap relative", :style => "margin-left:28px",
        :data_cell_id => cell_id,
        # Output (directly on canvas, not inside code-cell box)
        out_div,
        # Eye toggle + code cell (eye hides code-cell, output stays)
        eye_div,
        Div(:class => code_cell_classes,
            inner_children...))
end

# ---------------------------------------------------------------------------
# CellGap — divider between cells with "+ Code" button
# ---------------------------------------------------------------------------

"""Add-cell divider between cells."""
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
