# IDE/MarkdownCell.jl - Markdown cell rendering
#
# Markdown cells have two modes matching the SVG design:
#
# CLOSED (default): Only rendered output visible — no code card.
#   Heading text in Optima/Palatino serif font, paragraphs, lists, etc.
#
# OPEN (click to edit): Rendered output on top, dotted separator,
#   code card below with md"""...""" source and purple left accent bar.
#
# Toggle between modes on click.
#
# SESSIONS-3503: Markdown cell rendering

import Suite

# =============================================================================
# Markdown Rendering
# =============================================================================

"""
    render_markdown_html(md_source::String)

Render markdown source to HTML using Julia's built-in Markdown parser.
Strips the md\"\"\"...\"\"\" wrapper if present.

Returns HTML string with appropriate CSS classes for Sessions.jl typography.
"""
function render_markdown_html(md_source::String)
    # Strip md string wrapper
    source = strip(md_source)
    if startswith(source, "md\"\"\"") && endswith(source, "\"\"\"")
        source = source[6:end-3]
    elseif startswith(source, "md\"") && endswith(source, "\"")
        source = source[4:end-1]
    end

    source = strip(source)

    if isempty(source)
        return ""
    end

    # Use Julia's built-in Markdown parser
    try
        md = Base.Markdown.parse(source)
        io = IOBuffer()
        Base.Markdown.html(io, md)
        return String(take!(io))
    catch e
        # Fallback: escape and wrap in paragraph
        return "<p>$(escape_html(source))</p>"
    end
end

# =============================================================================
# Markdown Typography CSS
# =============================================================================

"""
    markdown_styles()

CSS for markdown cell output rendering.
Uses Optima/Palatino serif fonts matching the SVG design.
"""
function markdown_styles()
    """
    <style>
    /* Markdown cell typography — matches SVG design */
    .sessions-markdown {
        font-family: 'EB Garamond', 'Optima', 'Palatino Linotype', 'Book Antiqua', serif;
        line-height: 1.7;
    }

    .sessions-markdown h1 {
        font-size: 1.75rem;
        font-weight: 300;
        letter-spacing: 0.5px;
        margin-bottom: 0.75rem;
    }
    .sessions-markdown h2 {
        font-size: 1.25rem;
        font-weight: 300;
        letter-spacing: 0.3px;
        margin-bottom: 0.5rem;
    }
    .sessions-markdown h3 {
        font-size: 1.05rem;
        font-weight: 400;
        letter-spacing: 0.2px;
        margin-bottom: 0.4rem;
    }
    .sessions-markdown h4,
    .sessions-markdown h5,
    .sessions-markdown h6 {
        font-size: 0.95rem;
        font-weight: 500;
        margin-bottom: 0.3rem;
    }

    :root:not(.dark) .sessions-markdown h1,
    :root:not(.dark) .sessions-markdown h2,
    :root:not(.dark) .sessions-markdown h3 { color: #2a2520; }
    .dark .sessions-markdown h1,
    .dark .sessions-markdown h2,
    .dark .sessions-markdown h3 { color: #d4d0c8; }

    .sessions-markdown p {
        font-size: 0.8125rem;
        margin-bottom: 0.5rem;
    }
    :root:not(.dark) .sessions-markdown p { color: #6b6560; }
    .dark .sessions-markdown p { color: #8a8680; }

    .sessions-markdown strong { font-weight: 600; }
    .sessions-markdown em { font-style: italic; }

    .sessions-markdown a {
        text-decoration: underline;
        text-underline-offset: 2px;
    }
    :root:not(.dark) .sessions-markdown a { color: #4063d8; }
    .dark .sessions-markdown a { color: #6889f2; }

    .sessions-markdown code {
        font-family: var(--font-mono, 'JetBrains Mono', 'SF Mono', monospace);
        font-size: 0.75rem;
        padding: 0.1rem 0.3rem;
        border-radius: 3px;
    }
    :root:not(.dark) .sessions-markdown code {
        background: rgba(56, 152, 38, 0.06);
        color: #2c2a28;
    }
    .dark .sessions-markdown code {
        background: rgba(56, 152, 38, 0.1);
        color: #d4d0c8;
    }

    .sessions-markdown pre {
        font-family: var(--font-mono, 'JetBrains Mono', 'SF Mono', monospace);
        font-size: 0.75rem;
        line-height: 1.6;
        padding: 0.75rem 1rem;
        border-radius: 6px;
        overflow-x: auto;
        margin: 0.5rem 0;
    }
    :root:not(.dark) .sessions-markdown pre {
        background: #f8f7f4;
        border: 1px solid #e8e3d9;
    }
    .dark .sessions-markdown pre {
        background: #111110;
        border: 1px solid #252422;
    }
    .sessions-markdown pre code {
        background: none;
        padding: 0;
    }

    .sessions-markdown ul,
    .sessions-markdown ol {
        padding-left: 1.5rem;
        margin-bottom: 0.5rem;
        font-size: 0.8125rem;
    }
    :root:not(.dark) .sessions-markdown ul,
    :root:not(.dark) .sessions-markdown ol { color: #6b6560; }
    .dark .sessions-markdown ul,
    .dark .sessions-markdown ol { color: #8a8680; }

    .sessions-markdown li { margin-bottom: 0.25rem; }

    .sessions-markdown blockquote {
        padding-left: 1rem;
        margin: 0.5rem 0;
        font-style: italic;
    }
    :root:not(.dark) .sessions-markdown blockquote {
        border-left: 2px solid #e8e3d9;
        color: #9a9590;
    }
    .dark .sessions-markdown blockquote {
        border-left: 2px solid #252422;
        color: #5a5855;
    }

    .sessions-markdown hr {
        border: none;
        margin: 1rem 0;
    }
    :root:not(.dark) .sessions-markdown hr { border-top: 1px solid #e8e3d9; }
    .dark .sessions-markdown hr { border-top: 1px solid #252422; }

    .sessions-markdown img {
        max-width: 100%;
        height: auto;
        border-radius: 6px;
    }

    .sessions-markdown table {
        width: 100%;
        border-collapse: collapse;
        font-size: 0.8125rem;
        margin: 0.5rem 0;
    }
    .sessions-markdown th,
    .sessions-markdown td {
        padding: 0.4rem 0.75rem;
        text-align: left;
    }
    :root:not(.dark) .sessions-markdown th {
        border-bottom: 2px solid #e8e3d9;
        color: #2a2520;
        font-weight: 500;
    }
    :root:not(.dark) .sessions-markdown td {
        border-bottom: 1px solid #e8e3d9;
        color: #6b6560;
    }
    .dark .sessions-markdown th {
        border-bottom: 2px solid #252422;
        color: #d4d0c8;
        font-weight: 500;
    }
    .dark .sessions-markdown td {
        border-bottom: 1px solid #252422;
        color: #8a8680;
    }

    /* LaTeX (KaTeX/MathJax support) */
    .sessions-markdown .math { font-size: 1rem; }
    </style>
    """
end

# =============================================================================
# Markdown Cell Components
# =============================================================================

"""
    MarkdownCellClosed(cell::Cell)

Closed markdown cell — only rendered output visible, no code card.
Click to open for editing.
"""
function MarkdownCellClosed(cell::Cell)
    cell_id_str = string(cell.id)
    rendered_html = render_markdown_html(cell.code)

    Div(:class => "cell group relative cursor-pointer",
        Symbol("data-cell-id") => cell_id_str,
        Symbol("data-cell-mode") => "closed",
        :onclick => "toggleMarkdownCell('$(cell_id_str)')",

        # Rendered markdown output
        Div(:class => "sessions-markdown",
            RawHtml(rendered_html)
        ),

        # Add cell button (between cells, on hover)
        CellAddButton(cell_id_str)
    )
end

"""
    MarkdownCellOpen(cell::Cell)

Open markdown cell — rendered output on top, dotted separator, code card below.
Purple left accent bar on the code card.
"""
function MarkdownCellOpen(cell::Cell)
    cell_id_str = string(cell.id)
    state_signal = "cell_state_$(cell_id_str)"
    runtime_signal = "cell_runtime_$(cell_id_str)"
    rendered_html = render_markdown_html(cell.code)

    Div(:class => "cell group relative",
        Symbol("data-cell-id") => cell_id_str,
        Symbol("data-cell-mode") => "open",

        # 1. Rendered output (click to close)
        Div(:class => "sessions-markdown cursor-pointer",
            :onclick => "toggleMarkdownCell('$(cell_id_str)')",
            RawHtml(rendered_html)
        ),

        # 2. Dotted separator
        Div(:class => "border-t border-dashed border-warm-200 dark:border-[#252422] my-1"),

        # 3. Code card with purple left accent
        Div(:class => "relative flex",
            # Purple accent bar
            Div(:class => "w-0.5 rounded-l flex-shrink-0 bg-[#9558b2] opacity-25"),

            # Code card
            Suite.Card(
                :class => "flex-1 rounded-l-none border-l-0 bg-warm-50 dark:bg-[#111110] border-warm-200/50 dark:border-[#252422]/50",

                Suite.CardContent(
                    :class => "relative p-0",

                    # Close button (top-right)
                    Div(:class => "absolute top-2 right-2 z-20 flex items-center gap-1.5 opacity-0 group-hover:opacity-100 transition-opacity duration-150",
                        Span(:class => "text-[10px] font-mono text-warm-400 dark:text-warm-500",
                            Symbol("data-server-signal") => runtime_signal,
                            cell.runtime_ms !== nothing ? "$(round(cell.runtime_ms, digits=1))ms" : ""
                        ),
                        Button(:class => "p-1 text-warm-300 dark:text-warm-600 hover:text-warm-600 dark:hover:text-warm-400 transition-colors",
                            :onclick => "event.stopPropagation(); toggleMarkdownCell('$(cell_id_str)')",
                            :title => "Close editor",
                            Svg(:class => "w-3.5 h-3.5", :fill => "none", :viewBox => "0 0 24 24",
                                :stroke => "currentColor", Symbol("stroke-width") => "1.5",
                                Path(:d => "M4.5 15.75l7.5-7.5 7.5 7.5")  # Chevron up
                            )
                        )
                    ),

                    # Code area (CodeMirror target)
                    Div(
                        Symbol("data-codemirror") => "true",
                        Symbol("data-code") => cell.code,
                        Symbol("data-cell-id") => cell_id_str,

                        Pre(:class => "cell-code m-0 px-4 py-3 text-[12.5px] font-mono min-h-[40px] overflow-x-auto bg-transparent text-warm-800 dark:text-warm-200 leading-relaxed",
                            Code(cell.code)
                        )
                    )
                )
            )
        ),

        # 4. Add cell button
        CellAddButton(cell_id_str)
    )
end

# =============================================================================
# Main Markdown Cell Component
# =============================================================================

"""
    IDEMarkdownCell(cell::Cell)

Render a markdown cell in the appropriate mode.
- Folded cells (default for markdown): closed mode (rendered output only)
- Unfolded cells: open mode (rendered + code card with purple accent)
"""
function IDEMarkdownCell(cell::Cell)
    if cell.folded
        MarkdownCellClosed(cell)
    else
        MarkdownCellOpen(cell)
    end
end

# =============================================================================
# Markdown Toggle JavaScript
# =============================================================================

"""
    markdown_cell_script()

JavaScript for toggling markdown cells between closed and open modes.
"""
function markdown_cell_script()
    """
    // Markdown cell toggle
    window.toggleMarkdownCell = function(cellId) {
        var cell = document.querySelector('[data-cell-id="' + cellId + '"]');
        if (!cell) return;

        var mode = cell.getAttribute('data-cell-mode');
        if (mode === 'closed') {
            // Open: send to server to get open mode HTML
            sendAction('toggle_markdown', { notebook_id: getNotebookId(), cell_id: cellId, mode: 'open' });
        } else {
            // Close: send to server to get closed mode HTML
            sendAction('toggle_markdown', { notebook_id: getNotebookId(), cell_id: cellId, mode: 'closed' });
        }
    };
    """
end
