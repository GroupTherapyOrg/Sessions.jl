# NotebookRenderer.jl — Convert executed Notebook → Therapy.jl VNodes
#
# Renders Main.Sessions.jl notebooks as static HTML pages using Suite.jl components.
# Each cell becomes a Card (code) or prose section (markdown), with outputs rendered
# inline below the code.
#
# Supports pre-rendered reactivity: slider widgets with CairoMakie plots rendered
# as image galleries, swapped via inline JavaScript.

# Markdown is loaded in app.jl (Main module) — reference as Main.Markdown

"""
Top-level notebook page wrapper. Renders an executed Notebook as a full page
with header, prose sections, code cells, and outputs.

Pass `prerendered` dict (UUID → PrerenderedGallery) from execute_notebook_for_web
to enable interactive slider+plot galleries.
"""
function NotebookPage(nb::Main.Sessions.Notebook; title::String="", description::String="", prerendered=Dict{Main.UUID, Main.PrerenderedGallery}())
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
        node = _render_cell(cell, cell_index, prerendered)
        if node !== nothing
            push!(rendered, node)
            cell_index += 1
        end
    end

    # Add inline JS for slider/plotly interactivity
    has_sliders = any(c -> c.output.output_type == :bond && c.output.result isa Main.Sessions.Bond && c.output.result.element isa Main.Sessions.Slider, cells)
    has_plotly = any(c -> c.output.output_type == :plotly_json, cells)

    content_parts = rendered
    if has_sliders || has_plotly
        push!(content_parts, _slider_interaction_script())
    end

    Fragment(
        PageHeader(title, description),
        Div(:class => "max-w-4xl mx-auto py-8 space-y-6",
            content_parts...
        )
    )
end

"""
Dispatch cell rendering by type: folded markdown → prose, visible code → Card, skip others.
"""
function _render_cell(cell::Main.Sessions.Cell, index::Int, prerendered)
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
    _render_code_cell(cell, index, prerendered)
end

"""
Render a visible code cell as a Card with CodeBlock and output.
"""
function _render_code_cell(cell::Main.Sessions.Cell, index::Int, prerendered)
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
    output_node = _render_output(cell, prerendered)
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
function _render_output(cell::Main.Sessions.Cell, prerendered=Dict{Main.UUID, Main.PrerenderedGallery}())
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
        # Interactive bond rendering (slider with HTML input, others as badge)
        return _render_bond_output(result, cell, prerendered)

    elseif output.output_type == :plotly_json
        # Plotly.js interactive plot
        return _render_plotly_output(cell, prerendered)

    elseif output.output_type == :image_png
        # Image output — may be pre-rendered gallery or single image
        return _render_image_output(cell, prerendered)

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
Render an image output. If the cell has a pre-rendered gallery, render all images
as hidden <img> tags with the default visible. Otherwise render a single base64 image.
"""
function _render_image_output(cell::Main.Sessions.Cell, prerendered)
    gallery = get(prerendered, cell.id, nothing)

    if gallery !== nothing
        # Pre-rendered gallery — one <img> per slider value, default visible
        slider_id = string(gallery.slider_cell_id)
        img_tags = []
        for val in gallery.slider.values
            bytes = get(gallery.images, val, nothing)
            bytes === nothing && continue
            b64 = Main.Base64.base64encode(bytes)
            is_default = val == gallery.slider.default
            push!(img_tags,
                Img(:src => "data:image/png;base64,$b64",
                    :alt => "Plot for $(gallery.var_name) = $val",
                    :data_slider_value => string(val),
                    :style => is_default ? "display:block" : "display:none",
                    :class => "rounded-lg max-w-full")
            )
        end
        return Div(:class => "notebook-plot-gallery",
            :data_slider_images => slider_id,
            img_tags...
        )
    end

    # Single image — base64 inline
    if cell.output.image_data !== nothing
        b64 = Main.Base64.base64encode(cell.output.image_data)
        return Img(:src => "data:image/png;base64,$b64",
            :alt => "Plot output",
            :class => "rounded-lg max-w-full")
    end

    nothing
end

"""
Render a Plotly.js plot. If the cell has a pre-rendered gallery, embed JSON
per slider value. Otherwise render a single standalone plot.
"""
function _render_plotly_output(cell::Main.Sessions.Cell, prerendered)
    gallery = get(prerendered, cell.id, nothing)
    plot_id = "plotly-" * string(cell.id)[1:8]

    if gallery !== nothing && !isempty(gallery.plotly_data)
        slider_id = string(gallery.slider_cell_id)
        scripts = [
            RawHtml("""<script type="application/json" data-plotly-for="$plot_id" data-plotly-value="$val">$(gallery.plotly_data[val])</script>""")
            for val in gallery.slider.values if haskey(gallery.plotly_data, val)
        ]
        return Div(:class => "notebook-plotly",
            Div(:id => plot_id,
                :data_plotly_plot => slider_id,
                :data_plotly_default => string(gallery.slider.default),
                :class => "w-full rounded-lg",
                :style => "min-height:400px;"),
            scripts...,
            Noscript(_render_png_gallery_fallback(gallery))
        )
    end

    # Standalone plot (no slider)
    json_str = Main._to_json(cell.output.result)
    return Div(:class => "notebook-plotly",
        Div(:id => plot_id, :class => "w-full rounded-lg", :style => "min-height:400px;"),
        RawHtml("""<script type="application/json" data-plotly-for="$plot_id">$json_str</script>"""),
        RawHtml("""<script>(function(){var el=document.getElementById('$plot_id');var s=document.querySelector('[data-plotly-for="$plot_id"]');if(el&&s&&window.Plotly){var d=JSON.parse(s.textContent);Plotly.newPlot(el,d.data,d.layout,{responsive:true})}})();</script>""")
    )
end

"""PNG fallback for <noscript> when Plotly.js is unavailable."""
function _render_png_gallery_fallback(gallery)
    bytes = get(gallery.images, gallery.slider.default, nothing)
    if bytes !== nothing
        b64 = Main.Base64.base64encode(bytes)
        return Img(:src => "data:image/png;base64,$b64",
            :alt => "Plot (JS disabled)", :class => "rounded-lg max-w-full")
    end
    Span("Plot requires JavaScript")
end

"""
Render a Bond output. Sliders become interactive HTML range inputs.
Other widget types render as static badges.
"""
function _render_bond_output(result, cell::Main.Sessions.Cell, prerendered)
    if result isa Main.Sessions.Bond
        widget = result.element
        var_name = result.defines

        # Sliders → interactive <input type="range">
        if widget isa Main.Sessions.Slider
            slider_id = string(cell.id)
            vals = widget.values
            min_val = first(vals)
            max_val = last(vals)
            step_val = length(vals) > 1 ? vals[2] - vals[1] : 1

            return Div(:class => "notebook-slider",
                Span(:class => "slider-label", string(var_name)),
                Input(:type => "range",
                    :min => string(min_val),
                    :max => string(max_val),
                    :value => string(widget.default),
                    :step => string(step_val),
                    :data_notebook_slider => slider_id,
                    :data_slider_var => string(var_name)),
                Span(:class => "slider-value",
                    :data_slider_display => slider_id,
                    string(widget.default))
            )
        end

        # Other widgets → static badge
        widget_type = nameof(typeof(widget))
        val = Main.Sessions.initial_value(widget)
        return Main.Badge(variant="outline",
            "$(widget_type) → :$(var_name) = $(val)"
        )
    end
    nothing
end

"""Inline JavaScript for slider interactivity — Plotly init + swap + PNG fallback."""
function _slider_interaction_script()
    RawHtml("""<script>
(function() {
  // Init Plotly plots from embedded JSON
  document.querySelectorAll('[data-plotly-plot]').forEach(function(el) {
    var plotId = el.id;
    var def = el.dataset.plotlyDefault;
    var scripts = document.querySelectorAll('[data-plotly-for="' + plotId + '"]');
    el._plotlyDatasets = {};
    scripts.forEach(function(s) {
      var val = s.dataset.plotlyValue || 'default';
      el._plotlyDatasets[val] = JSON.parse(s.textContent);
    });
    if (el._plotlyDatasets[def] && window.Plotly) {
      var d = el._plotlyDatasets[def];
      Plotly.newPlot(el, d.data, d.layout, {responsive:true});
    }
  });
  // Slider interaction — update label + swap Plotly or PNG
  document.querySelectorAll('[data-notebook-slider]').forEach(function(slider) {
    slider.addEventListener('input', function() {
      var id = slider.dataset.notebookSlider;
      var val = slider.value;
      var display = document.querySelector('[data-slider-display="' + id + '"]');
      if (display) display.textContent = val;
      var plotEl = document.querySelector('[data-plotly-plot="' + id + '"]');
      if (plotEl && plotEl._plotlyDatasets && plotEl._plotlyDatasets[val] && window.Plotly) {
        var d = plotEl._plotlyDatasets[val];
        Plotly.react(plotEl, d.data, d.layout);
      }
      document.querySelectorAll('[data-slider-images="' + id + '"] img').forEach(function(img) {
        img.style.display = img.dataset.sliderValue === val ? 'block' : 'none';
      });
    });
  });
})();
</script>""")
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
