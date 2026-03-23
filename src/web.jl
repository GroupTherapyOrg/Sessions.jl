# web.jl — Web export: notebook → Therapy.jl VNodes with WASM interactivity
#
# Provides: PrerenderedGallery, execute_notebook_for_web, NotebookPage,
#           CellToggle @island, CodeMirror read-only viewer, notebook helpers.

using Therapy
import Markdown
import Base64

# Load CodeMirror 6 bundle at include time (same pattern as app Layout.jl)
const _EDITOR_BUNDLE_JS = let
    p = joinpath(@__DIR__, "web", "static", "editor.js")
    isfile(p) ? read(p, String) : "/* editor.js not found */"
end

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

@island function CellToggle(children...; initial_open=1)
    is_open, set_is_open = create_signal(Int32(initial_open))

    Div(:class => "cell-island",
        # Eye toggle — matches app CellIsland structure
        Div(:class => "cell-eye",
            :on_click => () -> begin
                if is_open() == Int32(1)
                    set_is_open(Int32(0))
                else
                    set_is_open(Int32(1))
                end
            end,
            Div(:style => "position:relative;width:14px;height:14px;",
                # Closed eye (always in DOM)
                RawHtml("""<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19M1 1l22 22"/></svg>"""),
                # Open eye (layered on top, hidden when folded)
                Show(is_open) do
                    Div(:style => "position:absolute;inset:0;background:var(--bg-primary);",
                        RawHtml("""<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>"""))
                end)),

        # Code cell — shown/hidden by is_open signal
        Show(is_open) do
            Div(children...)
        end)
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
# BoundValue @island — live WASM display for a bound variable
#
# First step toward true WASM-compiled notebook cells: instead of pre-rendering
# all slider values at build time, the value updates live via a WASM signal.
# A hidden input acts as the bridge — the interaction script dispatches events
# to it, and the WASM handler updates the signal.
#
# Future: replace the hidden-input bridge with direct cross-island signal
# sharing or compile the entire cell logic to WASM.
# =============================================================================

@island function BoundValue(; value=0)
    current, set_current = create_signal(value)

    Div(:class => "inline-flex items-baseline",
        Input(:type => "hidden", :value => string(value),
            :on_input => () -> set_current(unsafe_trunc(Int32, get_target_value_f64()))),
        Span(:class => "text-sm font-mono text-warm-600 dark:text-warm-500",
            current))
end

# Syntax highlighting is handled by CodeMirror 6 (editor.js bundle).
# No build-time tokenizer needed — CM provides proper Julia grammar parsing.

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

"""Render a visible code cell — matches app CellView visual structure."""
function _render_code_cell(cell::Cell, index::Int, prerendered)
    code = strip(cell.code)
    output = cell.output

    # Runtime string (matches app _format_runtime)
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

    parts = []

    # Output area — ABOVE code (matches app: cell-out before cell-island)
    output_node = _render_output(cell, prerendered)
    if output_node !== nothing
        push!(parts, Div(:class => "cell-out", :style => "padding:4px 0 8px;overflow-x:auto;",
            output_node))
    end

    # Stdout
    if !isempty(output.stdout)
        push!(parts,
            Div(:class => "cell-out font-mono text-xs whitespace-pre overflow-x-auto",
                :style => "padding:6px 0 10px;line-height:1.5;color:#7ca0bf;",
                output.stdout))
    end

    # Hover controls (top-right) — runtime badge only (no run/menu in static export)
    ctrl_children = Any[]
    if !isempty(runtime_str)
        push!(ctrl_children,
            Span(:class => "rt-badge", runtime_str))
    end
    ctrls = Div(:class => "cell-ctrls absolute top-1 right-1.5 flex items-center gap-1.5 z-10",
        ctrl_children...)

    # Code block — CM editor host (same as app CellView: cm-cell with data-src)
    code_cell = Div(:class => "code-cell relative rounded-lg overflow-hidden",
        ctrls,
        Div(:class => "cm-cell",
            :data_cell_id => string(cell.id),
            :data_src => String(code)))

    # CellToggle island (eye toggle + fold) wrapping the code-cell
    push!(parts, CellToggle(; initial_open = cell.folded ? 0 : 1) do
        code_cell
    end)

    Div(:data_cell_id => string(cell.id), :class => "cell-wrap relative", parts...)
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
        return Div(:class => "md-prose", RawHtml(html_str))

    elseif output.output_type == :error
        err_msg = output.text_representation
        return Div(:class => "bg-accent-secondary-50 dark:bg-accent-secondary-950 border border-accent-secondary-300 dark:border-accent-secondary-800 rounded-lg px-4 py-3",
            Pre(:class => "text-sm font-mono text-accent-secondary-700 dark:text-accent-secondary-400 whitespace-pre-wrap",
                Code(err_msg)))

    elseif output.output_type == :dataframe
        gallery = get(prerendered, cell.id, nothing)
        if gallery !== nothing
            return _render_reactive_table(result, gallery)
        end
        return _render_table_output(result)

    elseif output.output_type == :bond
        return _render_bond_output(result, cell, prerendered)

    elseif output.output_type == :plotly_json
        return _render_plotly_output(cell, prerendered)

    elseif output.output_type == :image_png
        return _render_image_output(cell, prerendered)

    elseif output.output_type == :image_svg
        # SVG: render as inline SVG or img tag
        svg_src = output.text_representation
        if !isempty(svg_src)
            return Div(:class => "overflow-x-auto", RawHtml(svg_src))
        end
        return nothing

    elseif output.output_type == :html
        # Raw HTML output (from packages with text/html MIME method)
        html_str = output.text_representation
        if !isempty(html_str)
            return Div(:class => "overflow-x-auto", RawHtml(html_str))
        end
        return nothing

    elseif output.output_type == :text
        # Live WASM binding for trivial numeric cells downstream of a slider
        gallery = get(prerendered, cell.id, nothing)
        if gallery !== nothing && result isa Integer
            slider_id = string(gallery.slider_cell_id)
            return Div(:class => "notebook-bound-value",
                :data_bound_to => slider_id,
                BoundValue(value=Int(result)))
        end
        # Pre-rendered gallery fallback for non-numeric text
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

"""Render a table (DataFrames, NamedTuple vectors, any Tables.jl type) as a Pluto-style HTML table."""
function _render_table_output(result)
    # Extract rows via Tables.jl interface or NamedTuple fallback
    rows_data = try
        Base.invokelatest(Tables.rowtable, result)
    catch
        if result isa AbstractVector && !isempty(result) && first(result) isa NamedTuple
            result
        else
            nothing
        end
    end

    rows_data === nothing && return Pre(:class => "text-sm font-mono text-tout", Code(sprint(show, result)))
    isempty(rows_data) && return Span(:class => "text-sm text-t3", "0 rows")

    cols = keys(first(rows_data))
    nrows = length(rows_data)
    max_display = 25  # Pluto-style: show first N rows, collapse the rest

    # Dimension label (e.g. "8×7 DataFrame")
    ncols = length(cols)
    type_name = nameof(typeof(result))
    dim_label = Div(:style => "font-size:12px;color:#6b7d93;font-family:'JetBrains Mono',monospace;margin-bottom:6px;",
        "$(nrows)×$(ncols) $(type_name)")

    # Column type names (if available via Tables.schema)
    col_types = try
        schema = Base.invokelatest(Tables.schema, result)
        schema !== nothing ? [string(T) for T in schema.types] : nothing
    catch
        nothing
    end

    # Header row
    header_cells = Any[Th(:class => "sst-th sst-row-label", "#")]
    for col in cols
        push!(header_cells, Th(:class => "sst-th", string(col)))
    end

    # Type row (under header)
    type_cells = if col_types !== nothing
        tc = Any[Th(:class => "sst-type-th", "")]
        for t in col_types
            push!(tc, Th(:class => "sst-type-th", t))
        end
        Tr(:class => "sst-type-row", tc...)
    else
        nothing
    end

    # Data rows (show first max_display, hide the rest)
    show_all = nrows <= max_display
    visible_rows = Any[]
    for (i, row) in enumerate(rows_data)
        is_hidden = !show_all && i > max_display && i < nrows  # hide middle rows
        is_last = i == nrows
        row_style = (is_hidden && !is_last) ? "display:none;" : ""

        cells = Any[Td(:class => "sst-td sst-row-label", string(i))]
        for col in cols
            val = getfield(row, col)
            push!(cells, Td(:class => "sst-td", string(val)))
        end
        push!(visible_rows, Tr(:class => "sst-row", :style => row_style,
            :data_row_idx => string(i), cells...))
    end

    # "⋮ more" expand button (if rows truncated)
    expand_btn = if !show_all
        hidden_count = nrows - max_display - 1
        Tr(Td(:class => "sst-more",
            :colspan => string(ncols + 1),
            :on_click => "var t=this.closest('table');t.querySelectorAll('tr[style*=none]').forEach(function(r){r.style.display=''});this.closest('tr').style.display='none'",
            "⋮ $(hidden_count) more rows"))
    else
        nothing
    end

    thead_children = Any[Tr(header_cells...)]
    type_cells !== nothing && push!(thead_children, type_cells)

    tbody_children = Any[]
    for (i, row_el) in enumerate(visible_rows)
        push!(tbody_children, row_el)
        # Insert expand button after visible rows
        if !show_all && i == max_display
            expand_btn !== nothing && push!(tbody_children, expand_btn)
        end
    end

    Div(:class => "sst-wrap",
        dim_label,
        Div(:style => "overflow-x:auto;",
            Table(:class => "sst-table",
                Thead(thead_children...),
                Tbody(tbody_children...))))
end

"""
Render a slider-bound table with all rows present and data-row-index attributes.

Instead of pre-rendering N separate tables (one per slider value), render the
full table once. JavaScript toggles row visibility: rows with index ≤ slider
value are shown, others are hidden. This eliminates build-time pre-rendering
for dataframe outputs.
"""
function _render_reactive_table(result, gallery::PrerenderedGallery)
    slider_id = string(gallery.slider_cell_id)

    if result isa AbstractVector && !isempty(result) && first(result) isa NamedTuple
        cols = keys(first(result))
        header = Thead(Tr([Th(:class => _WEB_TH_CLS, string(col)) for col in cols]...))
        default_val = Int(gallery.slider.default)
        rows = [
            Tr(:class => _WEB_TR_CLS, :data_row_index => string(i),
                :style => i <= default_val ? "" : "display:none",
                [Td(:class => _WEB_TD_CLS, string(getfield(row, col))) for col in cols]...)
            for (i, row) in enumerate(result)
        ]
        return Div(:class => "overflow-x-auto notebook-reactive-table",
            :data_slider_table => slider_id,
            Table(:class => "w-full text-sm", header, Tbody(rows...)))
    end

    # Fallback for non-NamedTuple dataframes — static render
    _render_table_output(result)
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

      // Swap pre-rendered HTML variants (text, etc.)
      document.querySelectorAll('[data-slider-html="' + sliderId + '"] > [data-slider-value]').forEach(function(div) {
        div.style.display = div.dataset.sliderValue === val ? 'block' : 'none';
      });

      // Toggle reactive table rows — show rows where index ≤ slider value
      document.querySelectorAll('[data-slider-table="' + sliderId + '"] tbody tr[data-row-index]').forEach(function(tr) {
        tr.style.display = parseInt(tr.dataset.rowIndex) <= parseInt(val) ? '' : 'none';
      });

      // Live WASM bridge: dispatch input event to BoundValue islands
      // The hidden input inside each BoundValue island receives the value,
      // triggering the WASM handler which updates the signal → DOM binding.
      document.querySelectorAll('[data-bound-to="' + sliderId + '"] therapy-island input[type="hidden"]').forEach(function(hidden) {
        hidden.value = val;
        hidden.dispatchEvent(new Event('input', { bubbles: true }));
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
            # Dataframe deps use reactive table (SSR all rows + JS row toggling)
            # instead of pre-rendering separate tables for each slider value.
            # The cell was already executed at the default value, so result has all rows.
            if dep.output.output_type == :dataframe
                prerendered[dep.id] = PrerenderedGallery(
                    cell.id, var_name, slider,
                    Dict{Any,Vector{UInt8}}(), Dict{Any,String}(), Dict{Any,String}()
                )
                verbose && println("      Dep $(dep.id): reactive table (no pre-rendering)")
                continue
            end

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
# NotebookPage — main entry point (self-contained: includes all CSS/fonts/JS)
# =============================================================================

"""Google Fonts needed by notebook rendering (DM Sans, Fraunces, JetBrains Mono)."""
function _notebook_fonts()
    RawHtml("""<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,100..1000;1,9..40,100..1000&family=JetBrains+Mono:ital,wght@0,100..800;1,100..800&family=Fraunces:ital,opsz,wght@0,9..144,100..900;1,9..144,100..900&display=swap" rel="stylesheet">""")
end

"""
Self-contained CSS for notebook rendering — identical to the app's Layout.jl styles.

Includes: cell chrome, accent bar, eye toggle, runtime badge, markdown prose,
Pluto-style tables (sst-*), CodeMirror overrides, slider widgets.
Any Therapy.jl app that calls NotebookPage() gets the full app experience.
"""
function _notebook_stylesheet()
    RawHtml("""<style id="sessions-notebook-css">
/* Cell chrome */
.code-cell{background:#1a2332;border:1px solid #1c2736;transition:border-color .2s;}
.code-cell:hover{border-color:#2a3a4f;}
.code-cell::before{content:'';position:absolute;left:0;top:0;bottom:0;width:2px;background:#56d4a0;opacity:.4;transition:opacity .2s;border-radius:2px 0 0 2px;}
.code-cell:hover::before{opacity:.7;}
.cell-ctrls{opacity:0;transform:translateY(-3px);transition:opacity .15s,transform .15s;pointer-events:none;}
.code-cell:hover .cell-ctrls{opacity:1;transform:translateY(0);pointer-events:auto;}
.rt-badge{font-size:10px;font-family:'JetBrains Mono','Fira Code',monospace;padding:1px 7px;border-radius:9999px;color:#56d4a0;opacity:.8;background:rgba(86,212,160,.08);border:1px solid rgba(86,212,160,.12);}
.cell-eye{position:absolute;left:-28px;top:0;bottom:0;width:24px;display:flex;align-items:center;justify-content:center;opacity:0;transition:opacity .15s;cursor:pointer;z-index:5;}
.cell-wrap:hover .cell-eye{opacity:1;}
.cell-eye svg{color:#3d5068;transition:color .15s;}
.cell-eye:hover svg{color:#56d4a0;}
.cell-out{overflow-x:auto;}
/* Notebook slider */
.notebook-slider{display:flex;align-items:center;gap:12px;padding:8px 0;}
.notebook-plotly{border-radius:8px;overflow:hidden;}
/* Markdown prose (matches app md-prose) */
.md-prose{font-family:'DM Sans',system-ui,sans-serif;color:#9baabd;line-height:1.7;font-size:14.5px;}
.md-prose h1{font-family:'Fraunces',Georgia,serif;font-size:2.2rem;font-weight:700;color:#d4dce8;margin:0.3em 0 0.6em;letter-spacing:-0.01em;padding-bottom:0.3em;border-bottom:3px solid #2a3a4f;}
.md-prose h2{font-family:'Fraunces',Georgia,serif;font-size:1.8rem;font-weight:700;color:#d4dce8;margin:1.2em 0 0.4em;padding-bottom:0.3em;border-bottom:2px dotted #2a3a4f;}
.md-prose h3{font-family:'Fraunces',Georgia,serif;font-size:1.4rem;font-weight:600;color:#d4dce8;margin:1em 0 0.3em;}
.md-prose h4{font-family:'Fraunces',Georgia,serif;font-size:1.15rem;font-weight:600;color:#d4dce8;margin:0.8em 0 0.2em;}
.md-prose p{margin:0 0 1em;color:#9baabd;}
.md-prose ul,.md-prose ol{margin:0 0 1em;padding-left:1.5em;color:#9baabd;line-height:1.6em;}
.md-prose li{margin:0.25em 0;}
.md-prose li p{margin:0 0 0.4em;}
.md-prose blockquote{border-left:3px solid #b08fd8;padding:0.4em 0 0.4em 1em;margin:1em 0;color:#6b7d93;background:rgba(176,143,216,.04);border-radius:0 4px 4px 0;}
.md-prose code{font-family:'JetBrains Mono',monospace;font-size:0.85em;background:#0a0e14;padding:0.15em 0.4em;border-radius:4px;color:#7bb8e8;}
.md-prose pre{background:#0a0e14;border-radius:6px;padding:0.8em 1em;margin:1em 0;overflow-x:auto;tab-size:4;white-space:pre-wrap;}
.md-prose pre code{background:none;padding:0;font-size:0.8rem;color:#d4dce8;white-space:pre;}
.md-prose strong{color:#d4dce8;font-weight:600;}
.md-prose em{font-style:italic;}
.md-prose a{color:#56d4a0;text-decoration:none;}
.md-prose a:hover{text-decoration:underline;}
.md-prose hr{border:none;border-top:3px solid #2a3a4f;margin:1.5em 0;}
.md-prose img{max-width:100%;border-radius:6px;}
.md-prose table{border-collapse:collapse;margin:1em 0;width:auto;}
.md-prose th{padding:6px 12px;border-bottom:2px solid #2a3a4f;color:#d4dce8;font-weight:600;text-align:left;}
.md-prose td{padding:6px 12px;border-bottom:1px solid rgba(42,58,79,.4);color:#9baabd;}
/* Sessions Table (sst-*) — Pluto-style */
.sst-wrap{font-family:'JetBrains Mono','Fira Code',monospace;font-size:14px;overflow-x:auto;max-width:100%;}
.sst-table{border-collapse:collapse;width:auto;border-top:2px solid #56d4a0;border-bottom:1px solid #2a3a4f;}
.sst-th{padding:12px 20px;color:#56d4a0;font-weight:700;font-size:14px;text-align:left;border-bottom:1px solid #2a3a4f;white-space:nowrap;}
.sst-type-row .sst-type-th{padding:0 20px 8px;color:#3d5068;font-weight:400;font-size:11px;font-style:italic;text-align:left;border-bottom:1px solid #2a3a4f;opacity:0;transition:opacity .15s;}
.sst-table thead:hover .sst-type-row .sst-type-th{opacity:1;}
.sst-row-label{color:#d4dce8;font-weight:700;font-size:13px;text-align:right;padding:10px 16px 10px 12px;width:1%;white-space:nowrap;border-bottom:1px solid rgba(42,58,79,.3);}
.sst-td{padding:10px 20px;color:#d4dce8;border-bottom:1px solid rgba(42,58,79,.3);text-align:left;white-space:nowrap;max-width:300px;overflow:auto;}
.sst-row:hover .sst-td,.sst-row:hover .sst-row-label{background:rgba(86,212,160,.04);}
.sst-more{padding:10px 20px;color:#6b7d93;font-size:13px;text-align:center;cursor:pointer;border-bottom:1px solid rgba(42,58,79,.3);transition:color .15s;}
.sst-more:hover{color:#56d4a0;}
/* CodeMirror overrides (matches app Layout.jl) */
.cm-cell .cm-editor{background:transparent!important;}
.cm-cell .cm-scroller{overflow-x:auto;}
.cm-cell .cm-focused{outline:none!important;}
</style>""")
end

"""CodeMirror 6 bundle (inlined) + read-only init script for static notebooks."""
function _notebook_editor_bundle()
    Fragment(
        RawHtml(string("<script>", _EDITOR_BUNDLE_JS, "</script>")),
        RawHtml("""<script>
(function() {
  if (typeof C === 'undefined' || !C.EditorView) return;

  var hlTheme = C.HighlightStyle.define([
    {tag:C.t.keyword,color:"#e06b65"},{tag:C.t.controlKeyword,color:"#e06b65"},
    {tag:C.t.operatorKeyword,color:"#e06b65"},{tag:C.t.definitionKeyword,color:"#e06b65"},
    {tag:C.t.moduleKeyword,color:"#e06b65"},
    {tag:C.t.string,color:"#56d4a0"},{tag:C.t.character,color:"#56d4a0"},
    {tag:C.t.comment,color:"#4a6178",fontStyle:"italic"},
    {tag:C.t.lineComment,color:"#4a6178",fontStyle:"italic"},
    {tag:C.t.number,color:"#d4a056"},{tag:C.t.integer,color:"#d4a056"},
    {tag:C.t.float,color:"#d4a056"},{tag:C.t.bool,color:"#d4a056"},
    {tag:C.t.function(C.t.variableName),color:"#7bb8e8"},
    {tag:C.t.definition(C.t.variableName),color:"#7bb8e8"},
    {tag:C.t.typeName,color:"#b08fd8"},{tag:C.t.className,color:"#b08fd8"},
    {tag:C.t.variableName,color:"#d4dce8"},
    {tag:C.t.punctuation,color:"#6b7d93"},{tag:C.t.paren,color:"#6b7d93"},
    {tag:C.t.squareBracket,color:"#6b7d93"},{tag:C.t.brace,color:"#6b7d93"},
    {tag:C.t.operator,color:"#d4dce8"},{tag:C.t.special(C.t.string),color:"#7bb8e8"},
    {tag:C.t.macroName,color:"#d4a056"},
  ]);

  var edTheme = C.EditorView.theme({
    "&":{backgroundColor:"transparent",color:"#d4dce8"},
    ".cm-gutters":{backgroundColor:"transparent",color:"#3d5068",border:"none",minWidth:"38px"},
    ".cm-activeLine":{backgroundColor:"transparent"},
    ".cm-activeLineGutter":{backgroundColor:"transparent",color:"#3d5068"},
    ".cm-content":{fontFamily:"'JetBrains Mono',monospace",fontSize:"13px",lineHeight:"1.65",padding:"8px 0"},
    ".cm-scroller":{fontFamily:"'JetBrains Mono',monospace"},
    ".cm-line":{paddingLeft:"4px"},
    ".cm-cursor":{display:"none"},
  },{dark:true});

  document.querySelectorAll('.cm-cell').forEach(function(host) {
    if (host.querySelector('.cm-editor')) return;
    var src = host.dataset.src || '';
    var ev = new C.EditorView({
      state: C.EditorState.create({
        doc: src,
        extensions: [
          C.lineNumbers(),
          C.highlightSpecialChars(),
          C.drawSelection(),
          C.bracketMatching(),
          C.julia(),
          C.syntaxHighlighting(hlTheme),
          edTheme,
          C.EditorState.readOnly.of(true),
          C.EditorView.editable.of(false),
        ]
      }),
      parent: host
    });
  });
})();
</script>"""))
end

"""
    NotebookPage(nb::Notebook; prerendered=Dict()) -> VNode

Render a notebook as Therapy.jl VNodes with self-contained CSS, fonts, and JS.

Any Therapy.jl app that calls this gets the full Sessions.jl notebook experience —
cell chrome, accent bars, CodeMirror syntax highlighting, Pluto-style tables,
markdown prose, interactive sliders — without any additional setup.

```julia
using Sessions

nb, pre = Sessions.execute_notebook_for_web("notebook.jl")
MyLayout(Sessions.NotebookPage(nb; prerendered=pre))
```
"""
function NotebookPage(nb::Notebook;
        prerendered=Dict{UUID, PrerenderedGallery}())
    cells = ordered_cells(nb)
    rendered = Any[
        _notebook_fonts(),
        _notebook_stylesheet(),
    ]
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

    if has_sliders || has_plotly
        push!(rendered, _slider_interaction_script())
    end

    # CodeMirror bundle + init (after cells so DOM exists)
    push!(rendered, _notebook_editor_bundle())

    Div(:class => "space-y-4 pl-8", rendered...)
end
