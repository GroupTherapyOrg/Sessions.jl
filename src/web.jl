# web.jl — Web export: notebook → Therapy.jl VNodes with WASM interactivity
#
# Provides: PrerenderedGallery, execute_notebook_for_web, NotebookPage,
#           CellToggle @island, syntax highlighting, notebook helpers.

using Therapy
import Markdown
import Base64

# =============================================================================
# Pre-rendered Gallery
# =============================================================================

"""
Pre-rendered variants for a cell driven by a slider.

Used by `execute_notebook_for_web` to capture output variants
for each slider value, enabling client-side switching without server roundtrips.
"""
struct PrerenderedGallery
    slider_cell_id::UUID
    var_name::Symbol
    slider::Slider
    images::Dict{Any, Vector{UInt8}}    # slider_value → PNG bytes (fallback)
    plotly_data::Dict{Any, String}      # slider_value → Plotly JSON string
    html_variants::Dict{Any, String}    # slider_value → rendered HTML string (text/dataframe/etc.)
end

# =============================================================================
# CellToggle @island — wasm-compiled code visibility toggle
# =============================================================================

@island function CellToggle(; initial_open=1)
    is_open, set_is_open = create_signal(initial_open)

    Div(:class => "flex items-start gap-2",
        # Left gutter — eye icon toggle
        Div(:class => "flex items-center pt-4 shrink-0",
            Therapy.Button(:class => "group/eye p-1 rounded hover:bg-warm-800/50 transition-colors cursor-pointer opacity-0 group-hover/cell:opacity-100",
                :on_click => () -> begin
                    if is_open() == Int32(1)
                        set_is_open(Int32(0))
                    else
                        set_is_open(Int32(1))
                    end
                end,
                # Stacked eye icons — closed eye always rendered, open eye layered on top via Show
                Div(:class => "relative w-3.5 h-3.5",
                    # Closed eye (always in DOM, visible when open eye is hidden)
                    Svg(:class => "w-3.5 h-3.5 text-warm-600 group-hover/eye:text-warm-400 transition-colors",
                        :viewBox => "0 0 24 24",
                        :fill => "none",
                        :stroke => "currentColor",
                        :stroke_width => "2",
                        :stroke_linecap => "round",
                        :stroke_linejoin => "round",
                        Path(:d => "M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"),
                        Path(:d => "M1 1L23 23")),
                    # Open eye (layered on top, hidden when code is folded)
                    Show(is_open) do
                        Svg(:class => "absolute inset-0 w-3.5 h-3.5 text-warm-500 group-hover/eye:text-warm-300 transition-colors bg-warm-950",
                            :viewBox => "0 0 24 24",
                            :fill => "none",
                            :stroke => "currentColor",
                            :stroke_width => "2",
                            :stroke_linecap => "round",
                            :stroke_linejoin => "round",
                            Path(:d => "M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"),
                            Circle(:cx => "12", :cy => "12", :r => "3"))
                    end))),
        # Code block — takes remaining width, visibility controlled by signal
        Div(:class => "flex-1 min-w-0",
            Show(is_open) do
                children
            end)
    )
end

# =============================================================================
# WebSlider @island — wasm-compiled interactive slider for @bind
# =============================================================================

@island function WebSlider(; min_val=0, max_val=100, value=50, step_val=1)
    current, set_current = create_signal(value)

    Div(:class => "flex items-center gap-3",
        Input(:type => "range",
            :min => string(min_val),
            :max => string(max_val),
            :value => string(value),
            :step => string(step_val),
            :class => "w-48 accent-accent-600 cursor-pointer",
            :on_input => () -> set_current(unsafe_trunc(Int32, get_target_value_f64()))),
        Span(:class => "text-sm font-mono text-warm-600 dark:text-warm-400 min-w-[3ch] text-right",
            current))
end

# =============================================================================
# Julia Syntax Highlighting (build-time tokenizer)
# =============================================================================

const _JULIA_KEYWORDS = Set([
    "function", "end", "if", "else", "elseif", "for", "while", "return",
    "begin", "let", "do", "try", "catch", "finally", "struct", "mutable",
    "abstract", "primitive", "module", "import", "using", "export", "const",
    "local", "global", "true", "false", "nothing", "in", "isa", "where",
    "new", "break", "continue", "quote", "macro", "type", "baremodule",
])

const _JULIA_TOKEN_RE = Regex(join([
    raw"(\#=(?:[^=]|=[^\#])*=\#)",
    raw"(\#[^\n]*)",
    raw"(\"\"\"[\s\S]*?\"\"\")",
    raw"(\"(?:[^\"\\]|\\.)*\")",
    raw"('(?:[^'\\]|\\.)?')",
    raw"(@[a-zA-Z_]\w*!?)",
    raw"(\b(?:" * join(collect(_JULIA_KEYWORDS), "|") * raw")\b)",
    raw"(\b\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?\b)",
    raw"(\b[a-zA-Z_]\w*!?(?=\s*[\({]))",
    raw"(\b[A-Z]\w*\b)",
    raw"(:[a-zA-Z_]\w*)",
    raw"([+\-*/\\^%&|!<>=~≤≥≠÷∈∉⊆]+|\.{2,3}|=>|->|\|>|::)",
    raw"([a-zA-Z_]\w*!?)",
    raw"(\s+)",
    raw"(.)",
], "|"), "s")

const _HL_CLASS_MAP = Dict{Symbol,String}(
    :comment  => "hl-comment",
    :string   => "hl-string",
    :macro    => "hl-macro",
    :keyword  => "hl-keyword",
    :number   => "hl-number",
    :funcall  => "hl-funcall",
    :type     => "hl-type",
    :symbol   => "hl-symbol",
    :operator => "hl-operator",
)

"""Highlight Julia source code into VNodes with CSS syntax classes."""
function _highlight_julia(code::String)
    parts = []
    for m in eachmatch(_JULIA_TOKEN_RE, code)
        text = m.match
        kind = if     m.captures[1] !== nothing; :comment
        elseif m.captures[2] !== nothing; :comment
        elseif m.captures[3] !== nothing; :string
        elseif m.captures[4] !== nothing; :string
        elseif m.captures[5] !== nothing; :string
        elseif m.captures[6] !== nothing; :macro
        elseif m.captures[7] !== nothing; :keyword
        elseif m.captures[8] !== nothing; :number
        elseif m.captures[9] !== nothing; :funcall
        elseif m.captures[10] !== nothing; :type
        elseif m.captures[11] !== nothing; :symbol
        elseif m.captures[12] !== nothing; :operator
        else; :plain
        end

        cls = get(_HL_CLASS_MAP, kind, "")
        if isempty(cls)
            push!(parts, text)
        else
            push!(parts, Span(:class => cls, text))
        end
    end
    Fragment(Any[parts...])
end

# =============================================================================
# Table Styling
# =============================================================================

const _WEB_TH_CLS = "px-4 py-3 text-left text-xs font-medium text-warm-500 dark:text-warm-400 uppercase tracking-wider"
const _WEB_TR_CLS = "border-b border-warm-200 dark:border-warm-700"
const _WEB_TD_CLS = "px-4 py-3 text-sm text-warm-700 dark:text-warm-300"

# =============================================================================
# Badge Component (for bond output rendering)
# =============================================================================

function _WebBadge(children...; variant::String="default", class::String="")
    base = "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium"
    vc = variant == "outline" ? "border border-warm-300 dark:border-warm-600 text-warm-700 dark:text-warm-300" :
        "bg-accent-100 dark:bg-accent-900 text-accent-700 dark:text-accent-300"
    Span(:class => "$(base) $(vc) $(class)", children...)
end

# =============================================================================
# Notebook Helpers
# =============================================================================

"""Extract the first H1 heading from markdown cells in a notebook."""
function notebook_title(nb::Notebook)
    for id in nb.cell_order
        cell = get(nb.cells, id, nothing)
        cell === nothing && continue
        code = strip(cell.code)
        if _is_markdown_cell(code)
            content = _extract_markdown_content(code)
            for line in split(content, '\n')
                line = strip(line)
                if startswith(line, "# ") && !startswith(line, "## ")
                    return String(strip(line[3:end]))
                end
            end
        end
    end
    return basename(nb.path)
end

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

# =============================================================================
# Cell Rendering
# =============================================================================

"""Dispatch cell rendering by type."""
function _render_cell(cell::Cell, index::Int, prerendered)
    cell.disabled && return nothing
    isempty(strip(cell.code)) && return nothing
    # All cells (code + markdown) get CellToggle — initial state from cell.folded
    _render_code_cell(cell, index, prerendered)
end

"""Render a visible code cell — scan-line design with CellToggle island."""
function _render_code_cell(cell::Cell, index::Int, prerendered)
    code = strip(cell.code)
    output = cell.output

    # Runtime string
    runtime_ms = output.runtime_ns / 1_000_000
    runtime_str = if runtime_ms < 1
        "$(round(output.runtime_ns / 1000, digits=1)) μs"
    elseif runtime_ms < 1000
        "$(round(runtime_ms, digits=1)) ms"
    else
        "$(round(runtime_ms / 1000, digits=2)) s"
    end

    parts = []

    # Code block wrapped in CellToggle island (wasm-based hide/show)
    code_block = Div(:class => "group relative rounded-lg bg-warm-950 ring-1 ring-warm-800 overflow-hidden",
        Symbol("data-codeblock") => "",
        Pre(:class => "overflow-x-auto p-5 font-mono text-sm leading-6 text-warm-200",
            Code(:class => "block", _highlight_julia(String(code)))),
        Div(:class => "absolute bottom-[10px] left-3 right-3 h-px bg-warm-700/30 opacity-0 group-hover:opacity-100 transition-opacity duration-150"),
        Span(:class => "absolute bottom-3 right-3 text-[10px] font-mono text-warm-600 opacity-0 group-hover:opacity-100 transition-opacity duration-300 delay-100",
            runtime_str))

    # Pass folded state to CellToggle island — determines initial visibility
    # Always pass initial_open explicitly so the wasm prop hydration receives the value
    push!(parts, CellToggle(; initial_open = cell.folded ? 0 : 1) do
        code_block
    end)

    # Stdout — indented to align with code block (past the gutter)
    if !isempty(output.stdout)
        push!(parts,
            Pre(:class => "mt-3 ml-7 pl-5 text-xs font-mono text-warm-500 whitespace-pre-wrap",
                output.stdout))
    end

    # Output — indented to align with code block
    output_node = _render_output(cell, prerendered)
    if output_node !== nothing
        push!(parts, Div(:class => "mt-3 ml-7 pl-5", output_node))
    end

    Div(:data_cell_id => string(cell.id), :class => "group/cell", parts...)
end

"""
Render pre-rendered HTML variants for a slider-dependent cell.

Returns a container with all slider value variants embedded as hidden/shown divs.
The interaction script toggles visibility client-side when the slider moves.
"""
function _render_html_gallery(cell::Cell, prerendered)
    gallery = get(prerendered, cell.id, nothing)
    gallery === nothing && return nothing
    isempty(gallery.html_variants) && return nothing

    slider_id = string(gallery.slider_cell_id)
    variant_divs = []
    for val in gallery.slider.values
        html_str = get(gallery.html_variants, val, nothing)
        html_str === nothing && continue
        is_default = val == gallery.slider.default
        push!(variant_divs,
            Div(:data_slider_value => string(val),
                :style => is_default ? "display:block" : "display:none",
                RawHtml(html_str)))
    end
    isempty(variant_divs) && return nothing

    Div(:class => "notebook-html-gallery",
        :data_slider_html => slider_id,
        variant_divs...)
end

"""Render cell output based on output_type."""
function _render_output(cell::Cell, prerendered=Dict{UUID, PrerenderedGallery}())
    output = cell.output
    result = output.result

    if output.output_type == :nothing
        return nothing

    elseif output.output_type == :markdown
        html_str = sprint(io -> Markdown.html(io, result))
        return Div(:class => "notebook-prose", RawHtml(html_str))

    elseif output.output_type == :error
        err_msg = output.text_representation
        return Div(:class => "bg-accent-secondary-50 dark:bg-accent-secondary-950 border border-accent-secondary-300 dark:border-accent-secondary-800 rounded-lg px-4 py-3",
            Pre(:class => "text-sm font-mono text-accent-secondary-700 dark:text-accent-secondary-400 whitespace-pre-wrap",
                Code(err_msg)))

    elseif output.output_type == :dataframe
        gallery_node = _render_html_gallery(cell, prerendered)
        gallery_node !== nothing && return gallery_node
        return _render_table_output(result)

    elseif output.output_type == :bond
        return _render_bond_output(result, cell, prerendered)

    elseif output.output_type == :plotly_json
        return _render_plotly_output(cell, prerendered)

    elseif output.output_type == :image_png
        return _render_image_output(cell, prerendered)

    elseif output.output_type == :text
        gallery_node = _render_html_gallery(cell, prerendered)
        gallery_node !== nothing && return gallery_node
        text = output.text_representation
        isempty(text) && return nothing
        return Pre(:class => "text-sm font-mono text-warm-600 dark:text-warm-500 whitespace-pre-wrap",
            Code(text))
    end

    nothing
end

function _render_image_output(cell::Cell, prerendered)
    gallery = get(prerendered, cell.id, nothing)

    if gallery !== nothing
        slider_id = string(gallery.slider_cell_id)
        img_tags = []
        for val in gallery.slider.values
            bytes = get(gallery.images, val, nothing)
            bytes === nothing && continue
            b64 = Base64.base64encode(bytes)
            is_default = val == gallery.slider.default
            push!(img_tags,
                Img(:src => "data:image/png;base64,$b64",
                    :alt => "Plot for $(gallery.var_name) = $val",
                    :data_slider_value => string(val),
                    :style => is_default ? "display:block" : "display:none",
                    :class => "rounded-lg max-w-full"))
        end
        return Div(:class => "notebook-plot-gallery",
            :data_slider_images => slider_id, img_tags...)
    end

    if cell.output.image_data !== nothing
        b64 = Base64.base64encode(cell.output.image_data)
        return Img(:src => "data:image/png;base64,$b64",
            :alt => "Plot output", :class => "rounded-lg max-w-full")
    end

    nothing
end

function _render_plotly_output(cell::Cell, prerendered)
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
            scripts...)
    end

    json_str = _to_json(cell.output.result)
    return Div(:class => "notebook-plotly",
        Div(:id => plot_id, :class => "w-full rounded-lg", :style => "min-height:400px;"),
        RawHtml("""<script type="application/json" data-plotly-for="$plot_id">$json_str</script>"""),
        RawHtml("""<script>(function(){var el=document.getElementById('$plot_id');var s=document.querySelector('[data-plotly-for="$plot_id"]');if(el&&s&&window.Plotly){var d=JSON.parse(s.textContent);Plotly.newPlot(el,d.data,d.layout,{responsive:true})}})();</script>"""))
end

function _render_bond_output(result, cell::Cell, prerendered)
    if result isa Bond
        widget = result.element
        var_name = result.defines

        if widget isa Slider
            vals = widget.values
            min_v = Int(first(vals))
            max_v = Int(last(vals))
            step_v = length(vals) > 1 ? Int(vals[2] - vals[1]) : 1
            def_v = Int(widget.default)

            slider_id = string(cell.id)
            return Div(:class => "notebook-slider flex items-center gap-3 py-2",
                :data_bind_var => string(var_name),
                :data_bind_slider_id => slider_id,
                Span(:class => "text-sm font-mono text-warm-500 dark:text-warm-400",
                    string(var_name), " = "),
                WebSlider(min_val=min_v, max_val=max_v, value=def_v, step_val=step_v))
        end

        widget_type = nameof(typeof(widget))
        val = initial_value(widget)
        return _WebBadge(variant="outline", "$(widget_type) → :$(var_name) = $(val)")
    end
    nothing
end

function _render_table_output(result)
    if result isa AbstractVector && !isempty(result) && first(result) isa NamedTuple
        cols = keys(first(result))
        header = Thead(Tr([Th(:class => _WEB_TH_CLS, string(col)) for col in cols]...))
        rows = [
            Tr(:class => _WEB_TR_CLS,
                [Td(:class => _WEB_TD_CLS, string(getfield(row, col))) for col in cols]...)
            for row in result
        ]
        return Div(:class => "overflow-x-auto",
            Table(:class => "w-full text-sm", header, Tbody(rows...)))
    end

    Pre(:class => "text-sm font-mono text-warm-700 dark:text-warm-300",
        Code(sprint(show, result)))
end

function _slider_interaction_script()
    RawHtml("""<script>
(function() {
  // Initialize Plotly datasets
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

  // Bind slider interactions — works with WASM island sliders
  document.querySelectorAll('[data-bind-slider-id]').forEach(function(bondEl) {
    var sliderId = bondEl.dataset.bindSliderId;
    var rangeInput = bondEl.querySelector('therapy-island input[type="range"]');
    if (!rangeInput) rangeInput = bondEl.querySelector('input[type="range"]');
    if (!rangeInput) return;

    rangeInput.addEventListener('input', function() {
      var val = rangeInput.value;

      // Swap image galleries
      document.querySelectorAll('[data-slider-images="' + sliderId + '"] img').forEach(function(img) {
        img.style.display = img.dataset.sliderValue === val ? 'block' : 'none';
      });

      // Swap Plotly plots
      var plotEl = document.querySelector('[data-plotly-plot="' + sliderId + '"]');
      if (plotEl && plotEl._plotlyDatasets && plotEl._plotlyDatasets[val] && window.Plotly) {
        Plotly.react(plotEl, plotEl._plotlyDatasets[val].data, plotEl._plotlyDatasets[val].layout);
      }

      // Swap pre-rendered HTML variants (text, dataframe, etc.)
      document.querySelectorAll('[data-slider-html="' + sliderId + '"] > [data-slider-value]').forEach(function(div) {
        div.style.display = div.dataset.sliderValue === val ? 'block' : 'none';
      });
    });
  });
})();
</script>""")
end

# =============================================================================
# Notebook Execution Pipeline
# =============================================================================

"""
    execute_notebook_for_web(path; verbose=false) -> (Notebook, Dict{UUID, PrerenderedGallery})

Execute a notebook for web publishing with pre-rendered slider galleries.

Returns `(notebook, prerendered)` where `prerendered` maps plot cell UUIDs
to `PrerenderedGallery` structs containing images for each slider value.
"""
function execute_notebook_for_web(path; verbose=false)
    nb = load_notebook(path)
    ws = Workspace()

    # 1. Execute all cells in topological order
    order = execution_order(nb)

    for (cell, err) in order.errable
        cell.state = cell_errored
        cell.output = CellOutput()
        cell.output.error = CapturedException(
            ErrorException("Reactivity error: $(typeof(err))"),
            backtrace()
        )
        verbose && println("    ERROR [$(cell.id)]: reactivity error")
    end

    for (i, cell) in enumerate(order.runnable)
        if verbose
            code_preview = first(cell.code, 40)
            code_preview = replace(code_preview, '\n' => "\\n")
            println("    [$i/$(length(order.runnable))] $(code_preview)")
        end
        execute_cell!(ws, cell)
    end

    # 2. Reclassify images (headless mode lacks graphics protocol → images classified as :text)
    for cell in ordered_cells(nb)
        if cell.output.output_type == :text && cell.output.result !== nothing
            if Base.invokelatest(showable, MIME"image/png"(), cell.output.result)
                cell.output.output_type = :image_png
                cell.output.image_data = _capture_png_bytes(cell.output.result)
                verbose && println("    Reclassified cell $(cell.id) as :image_png")
            end
        end
    end

    # 2b. Classify Plotly JSON outputs (Dict with "data" + "layout" keys)
    for cell in ordered_cells(nb)
        if cell.output.output_type == :text && cell.output.result isa Dict
            r = cell.output.result
            if haskey(r, "data") && haskey(r, "layout")
                cell.output.output_type = :plotly_json
                verbose && println("    Classified cell $(cell.id) as :plotly_json")
            end
        end
    end

    # 3. Pre-render slider-dependent cell outputs for all values
    #    This enables client-side switching of text, tables, images, and plots
    #    without server roundtrips — the foundation for interactive notebooks.
    prerendered = Dict{UUID, PrerenderedGallery}()
    for cell in ordered_cells(nb)
        cell.output.output_type == :bond || continue
        bond = cell.output.result
        bond isa Bond || continue
        slider = bond.element
        slider isa Slider || continue

        var_name = bond.defines
        deps = downstream_dependents(nb, [cell])
        # Include ALL dependent cells with visible output, not just plots
        reactive_deps = filter(d -> d.output.output_type in (
            :image_png, :plotly_json, :text, :dataframe
        ), deps)
        isempty(reactive_deps) && continue

        if verbose
            println("    Pre-rendering :$(var_name) slider ($(length(slider.values)) values × $(length(reactive_deps)) deps)")
        end

        for dep in reactive_deps
            images = Dict{Any, Vector{UInt8}}()
            plotly_data = Dict{Any, String}()
            html_variants = Dict{Any, String}()

            for val in slider.values
                set_bond_value!(var_name, val)
                Core.eval(ws.mod, :($var_name = $val))
                execute_cell!(ws, dep)

                # Reclassify if needed (headless mode lacks graphics protocol)
                if dep.output.output_type == :text && dep.output.result !== nothing
                    if Base.invokelatest(showable, MIME"image/png"(), dep.output.result)
                        dep.output.output_type = :image_png
                        dep.output.image_data = _capture_png_bytes(dep.output.result)
                    end
                end

                # Capture Plotly JSON
                if dep.output.result isa Dict && haskey(dep.output.result, "data") && haskey(dep.output.result, "layout")
                    dep.output.output_type = :plotly_json
                    plotly_data[val] = _to_json(dep.output.result)
                end

                # Capture PNG fallback
                if dep.output.image_data !== nothing
                    images[val] = copy(dep.output.image_data)
                end

                # Capture rendered HTML for text/dataframe outputs
                if dep.output.output_type in (:text, :dataframe)
                    vnode = _render_output(dep)  # no prerendered arg → plain render
                    if vnode !== nothing
                        html_variants[val] = render_to_string(vnode)
                    end
                end
            end

            # Restore default value
            set_bond_value!(var_name, slider.default)
            Core.eval(ws.mod, :($var_name = $(slider.default)))
            execute_cell!(ws, dep)

            # Reclassify restored default too
            if dep.output.output_type == :text && dep.output.result !== nothing
                if Base.invokelatest(showable, MIME"image/png"(), dep.output.result)
                    dep.output.output_type = :image_png
                    dep.output.image_data = _capture_png_bytes(dep.output.result)
                end
            end
            if dep.output.result isa Dict && haskey(dep.output.result, "data") && haskey(dep.output.result, "layout")
                dep.output.output_type = :plotly_json
            end

            prerendered[dep.id] = PrerenderedGallery(
                cell.id, var_name, slider, images, plotly_data, html_variants
            )

            if verbose
                n_img = length(images)
                n_plotly = length(plotly_data)
                n_html = length(html_variants)
                println("      Dep $(dep.id): $(n_img) images, $(n_plotly) plotly, $(n_html) html variants")
            end
        end
    end

    return nb, prerendered
end

# =============================================================================
# NotebookPage — main entry point
# =============================================================================

"""
    NotebookPage(nb::Notebook; prerendered=Dict()) -> VNode

Render a notebook as Therapy.jl VNodes (cells + outputs + interactivity scripts).

Returns a `Div` containing all rendered cells. Wrap in your own layout:

```julia
using Sessions

nb, pre = Sessions.execute_notebook_for_web("notebook.jl")
MyLayout(Sessions.NotebookPage(nb; prerendered=pre))
```
"""
function NotebookPage(nb::Notebook;
        prerendered=Dict{UUID, PrerenderedGallery}())
    cells = ordered_cells(nb)
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
    has_sliders = any(c -> c.output.output_type == :bond && c.output.result isa Bond && c.output.result.element isa Slider, cells)
    has_plotly = any(c -> c.output.output_type == :plotly_json, cells)

    content_parts = rendered
    if has_sliders || has_plotly
        push!(content_parts, _slider_interaction_script())
    end

    Div(:class => "space-y-6", content_parts...)
end
