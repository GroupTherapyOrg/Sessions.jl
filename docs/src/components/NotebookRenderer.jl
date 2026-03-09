# NotebookRenderer.jl — Convert executed Notebook → Therapy.jl VNodes
#
# Renders Main.Sessions.jl notebooks as static HTML pages using Suite.jl components.
# Each cell becomes a Card (code) or prose section (markdown), with outputs rendered
# inline below the code.

# Markdown is loaded in app.jl (Main module) — reference as Main.Markdown

"""
Top-level notebook page wrapper. Renders an executed Notebook as a full page
with header, prose sections, code cells, and outputs.
"""
function NotebookPage(nb::Main.Sessions.Notebook; title::String="", description::String="")
    # Extract title from first H1 markdown cell if not provided
    if isempty(title)
        title = String(_extract_notebook_title(nb))
    end
    if isempty(description)
        description = "Main.Sessions.jl notebook — $(length(nb)) cells"
    end

    cells = Main.Sessions.ordered_cells(nb)
    rendered = []
    cell_index = 0

    for cell in cells
        node = _render_cell(cell, cell_index)
        if node !== nothing
            push!(rendered, node)
            cell_index += 1
        end
    end

    Fragment(
        PageHeader(title, description),
        Div(:class => "max-w-4xl mx-auto py-8 space-y-6",
            rendered...
        )
    )
end

"""
Dispatch cell rendering by type: folded markdown → prose, visible code → Card, skip others.
"""
function _render_cell(cell::Main.Sessions.Cell, index::Int)
    # Skip disabled cells
    cell.disabled && return nothing

    # Skip empty cells
    isempty(strip(cell.code)) && return nothing

    code = strip(cell.code)

    # Folded markdown cells → prose only (no code card)
    if cell.folded && _is_markdown_cell(code)
        md_content = _extract_markdown_content(code)
        md_obj = Main.Markdown.parse(md_content)
        html_str = sprint(io -> Main.Markdown.html(io, md_obj))
        return Div(:class => "notebook-prose", :data_cell_id => string(cell.id),
            RawHtml(html_str)
        )
    end

    # Folded non-markdown cells → skip (hidden helper code)
    cell.folded && return nothing

    # Visible code cell → Card with code + output
    _render_code_cell(cell, index)
end

"""
Render a visible code cell as a Card with CodeBlock and output.
"""
function _render_code_cell(cell::Main.Sessions.Cell, index::Int)
    code = strip(cell.code)
    output = cell.output

    # Runtime badge
    runtime_ms = output.runtime_ns / 1_000_000
    runtime_str = if runtime_ms < 1
        "$(round(output.runtime_ns / 1000, digits=1)) μs"
    elseif runtime_ms < 1000
        "$(round(runtime_ms, digits=1)) ms"
    else
        "$(round(runtime_ms / 1000, digits=2)) s"
    end

    # Build cell content
    parts = []

    # Code block
    push!(parts, Main.CodeBlock(String(code), language="julia"))

    # Stdout (if non-empty)
    if !isempty(output.stdout)
        push!(parts,
            Div(:class => "mt-2 px-3 py-2 bg-warm-100 dark:bg-warm-900 rounded text-xs font-mono text-warm-600 dark:text-warm-400 whitespace-pre-wrap",
                output.stdout
            )
        )
    end

    # Output rendering
    output_node = _render_output(cell)
    if output_node !== nothing
        push!(parts, Div(:class => "mt-3 px-4 py-3", output_node))
    end

    Div(:data_cell_id => string(cell.id),
        Main.Card(class="overflow-hidden",
            Main.CardHeader(class="py-2 px-4 flex items-center justify-between",
                Span(:class => "text-xs font-mono text-warm-500 dark:text-warm-500",
                    "Cell $(index + 1)"
                ),
                Span(:class => "text-xs font-mono text-warm-400 dark:text-warm-600 runtime-badge",
                    runtime_str
                ),
            ),
            Main.CardContent(class="p-0",
                parts...
            ),
        )
    )
end

"""
Render cell output based on output_type.
"""
function _render_output(cell::Main.Sessions.Cell)
    output = cell.output
    result = output.result

    if output.output_type == :nothing
        return nothing

    elseif output.output_type == :markdown
        # Markdown output (md"..." cells produce Main.Markdown.MD)
        html_str = sprint(io -> Main.Markdown.html(io, result))
        return Div(:class => "notebook-prose", RawHtml(html_str))

    elseif output.output_type == :error
        # Error output with red styling
        err_msg = output.text_representation
        return Div(:class => "bg-accent-secondary-50 dark:bg-accent-secondary-950 border border-accent-secondary-300 dark:border-accent-secondary-800 rounded-lg px-4 py-3",
            Pre(:class => "text-sm font-mono text-accent-secondary-700 dark:text-accent-secondary-400 whitespace-pre-wrap",
                Code(err_msg)
            )
        )

    elseif output.output_type == :dataframe
        # Table output — introspect NamedTuple vector
        return _render_table_output(result)

    elseif output.output_type == :bond
        # Static bond placeholder
        return _render_bond_output(result)

    elseif output.output_type == :text
        # Plain text output
        text = output.text_representation
        isempty(text) && return nothing
        return Pre(:class => "text-sm font-mono text-warm-700 dark:text-warm-300 bg-warm-50 dark:bg-warm-900 rounded px-3 py-2",
            Code(text)
        )
    end

    nothing
end

"""
Render a NamedTuple vector as a Suite.jl Table.
"""
function _render_table_output(result)
    # Handle Vector{<:NamedTuple}
    if result isa AbstractVector && !isempty(result) && first(result) isa NamedTuple
        cols = keys(first(result))

        header = Main.TableHeader(
            Main.TableRow(
                [Main.TableHead(string(col)) for col in cols]...
            )
        )

        rows = [
            Main.TableRow(
                [Main.TableCell(string(getfield(row, col))) for col in cols]...
            )
            for row in result
        ]

        body = Main.TableBody(rows...)

        return Div(:class => "overflow-x-auto",
            Main.Table(header, body)
        )
    end

    # Fallback to text representation
    Pre(:class => "text-sm font-mono text-warm-700 dark:text-warm-300",
        Code(sprint(show, result))
    )
end

"""
Render a Bond as a static placeholder badge.
"""
function _render_bond_output(result)
    if result isa Main.Sessions.Bond
        widget = result.element
        widget_type = nameof(typeof(widget))
        var_name = result.defines
        val = Main.Sessions.initial_value(widget)
        return Main.Badge(variant="outline",
            "$(widget_type) → :$(var_name) = $(val)"
        )
    end
    nothing
end

# --- Helpers ---

"""Check if cell code is a Markdown string macro (md\"...\")."""
function _is_markdown_cell(code::AbstractString)
    stripped = strip(code)
    startswith(stripped, "md\"") || startswith(stripped, "md\"\"\"")
end

"""Extract the markdown content from a md\"...\" or md\"\"\"...\"\"\" cell."""
function _extract_markdown_content(code::AbstractString)
    stripped = strip(code)
    if startswith(stripped, "md\"\"\"") && endswith(stripped, "\"\"\"")
        return stripped[6:end-3]
    elseif startswith(stripped, "md\"") && endswith(stripped, "\"")
        return stripped[4:end-1]
    end
    stripped
end

"""Extract the first H1 heading from markdown cells in a notebook."""
function _extract_notebook_title(nb::Main.Sessions.Notebook)
    for id in nb.cell_order
        cell = get(nb.cells, id, nothing)
        cell === nothing && continue
        code = strip(cell.code)
        if _is_markdown_cell(code)
            content = _extract_markdown_content(code)
            # Look for # Title pattern
            for line in split(content, '\n')
                line = strip(line)
                if startswith(line, "# ") && !startswith(line, "## ")
                    return strip(line[3:end])
                end
            end
        end
    end
    return basename(nb.path)
end

"""Count prose (markdown) sections in a notebook."""
function _count_prose_sections(nb::Main.Sessions.Notebook)
    count = 0
    for id in nb.cell_order
        cell = get(nb.cells, id, nothing)
        cell === nothing && continue
        if _is_markdown_cell(strip(cell.code))
            count += 1
        end
    end
    count
end

"""Count code cells (non-markdown, non-empty, non-disabled) in a notebook."""
function _count_code_cells(nb::Main.Sessions.Notebook)
    count = 0
    for id in nb.cell_order
        cell = get(nb.cells, id, nothing)
        cell === nothing && continue
        cell.disabled && continue
        code = strip(cell.code)
        isempty(code) && continue
        _is_markdown_cell(code) && continue
        count += 1
    end
    count
end
