# ── Sessions.jl extracted notebook ─────────────────────────
#
# Source : /Users/daleblack/Documents/dev/GroupTherapyOrg/Sessions.jl/test/fixtures/interactive.jl
# Date   : 2026-04-17T10:05:30.935
#
# This file is a self-contained Therapy component. Cell SOURCE
# is preserved verbatim and rendered through a read-only
# CodeMirror editor (the docs site's Layout picks up every
# .cm-cell element on load + SPA navigation). Each cell value
# is computed once at module load and rendered through
# `Sessions.render_value` — the same MIME classifier the live
# IDE output pipeline uses, so Markdown/DataFrames/WasmPlot/
# SessionsUI.Bond all render identically to the IDE.
#
# Architecture:
#   - Cell chrome (cell-wrap > cell-body > [cell-out, cm-cell])
#     flows through `Sessions.render_published_cell` — single
#     source of truth with the live IDE's `render_cell`.
#   - Outer `function Interactive()` is plain Julia.
#     It just calls `render_published_notebook` with the cells
#     in document order; it always works regardless of WASM
#     compile state.
#   - Each @bind cell becomes a tiny @island that wraps the
#     SessionsUI widget. Bond signals are module-level shared
#     signals so cross-island sync is automatic.
#   - Each reactive cell becomes a tiny @island that captures
#     its upstream bond signals. v1 renders the frozen value
#     computed at module load (using the bond defaults). v2
#     re-executes the body in WASM as WasmTarget grows.
#
# Re-running `Sessions.extract_notebook` with the same out_path
# overwrites the file. Hand-edits survive until the next
# extraction, so prefer editing the source notebook fixture.
# ───────────────────────────────────────────────────────────

module InteractiveMod

    using Therapy: @island, create_signal, RawHtml
    using Sessions: render_value, render_published_cell, render_published_notebook
    using Markdown
    using SessionsUI: @bind, BoundSlider
    import WasmPlot as WP
    using DataFrames

    # ── Shared signals (one per @bind in the source) ──
    const n_signal = create_signal(8)
    const n = 8
    const l_signal = create_signal(7.5)
    const l = 7.5

    # ── Cell values (source preserved, evaluated at module load) ──
    # ── Cell 20000000-0000-0000-0000-000000000001 (static) ──
    const _cell__20000000_0000_0000_0000_000000000001 = try
        let
            md"""
            # Interactive Sessions
            
            A live demo of `@bind` + `BoundSlider` driving a **WasmPlot** figure and a
            **DataFrame** that recompute together. Move the slider — both update.
            
            In Sessions IDE this happens via the live Julia kernel; once published to
            WASM the same controls drive Therapy signals in the browser, no server
            round-trip required.
            """
        end
    catch _e
        _e
    end
    # ── Cell 20000000-0000-0000-0000-000000000005 (static) ──
    const _cell__20000000_0000_0000_0000_000000000005 = try
        let
            md"""
            ### A bond
            
            `BoundSlider(2:30; default=8)` produces a slider over the integer range
            `2:30`. The macro `@bind n …` makes `n` reactive — every cell that reads
            `n` re-runs when the user moves the slider.
            """
        end
    catch _e
        _e
    end
    # ── Cell 20000000-0000-0000-0000-000000000006 (bond) ──
    const _cell__20000000_0000_0000_0000_000000000006 = try
        let
            @bind n BoundSlider(2:30; default=8)
        end
    catch _e
        _e
    end
    # ── Cell 1b95c056-9b5a-456f-8007-177b202a1581 (reactive) ──
    const _cell__1b95c056_9b5a_456f_8007_177b202a1581 = try
        let
            "This is n: $(n)"
        end
    catch _e
        _e
    end
    # ── Cell 20000000-0000-0000-0000-000000000007 (static) ──
    const _cell__20000000_0000_0000_0000_000000000007 = try
        let
            md"""
            ### A reactive plot
            
            A bar chart of `i²` for `i ∈ 1:n`. Move the slider above and the plot
            redraws.
            """
        end
    catch _e
        _e
    end
    # ── Cell 20000000-0000-0000-0000-000000000008 (static) ──
    const _cell__20000000_0000_0000_0000_000000000008 = try
        let
            # WasmPlot Figures need a Base.show MIME"text/html" method to render in the
            # notebook output area. Defining it here keeps the fixture self-contained;
            # this hook lives in WasmPlot itself once Phase 3 of the SessionsUI build
            # wires per-cell @island compilation.
            function Base.show(io::IO, ::MIME"text/html", fig::WP.Figure)
                glue = WP.canvas2d_js_glue()
                js   = WP.generate_js_render(fig)
                id   = "wp_" * string(hash(fig); base=16)
                print(io, """
                <canvas id="$(id)" width="$(fig.width)" height="$(fig.height)"
                        style="border:1px solid var(--cell-border);border-radius:8px;background:#fff"></canvas>
                <script>(function(){
                  $(glue)
                  var c = document.getElementById('$(id)');
                  var dpr = window.devicePixelRatio||1;
                  c.width = $(fig.width)*dpr; c.height = $(fig.height)*dpr;
                  c.style.width='$(fig.width)px'; c.style.height='$(fig.height)px';
                  var ctx = c.getContext('2d'); ctx.scale(dpr,dpr);
                  var c2d = canvas2d_imports(ctx);
                  $(js)
                })();</script>
                """)
            end
        end
    catch _e
        _e
    end
    # ── Cell 20000000-0000-0000-0000-000000000009 (reactive) ──
    const _cell__20000000_0000_0000_0000_000000000009 = try
        let
            let
                fig = WP.Figure(size=(750, 360))
                ax  = WP.Axis(fig[1, 1]; xlabel="i", ylabel="i²", title="Squares", subtitle = "n = $(n)")
                xs  = Float64.(1:n)
                WP.barplot!(ax, xs, xs.^2; color=:red)
                fig
            end
        end
    catch _e
        _e
    end
    # ── Cell d4e88179-6c23-4713-abe8-5c18e8c94497 (bond) ──
    const _cell_d4e88179_6c23_4713_abe8_5c18e8c94497 = try
        let
            @bind l BoundSlider(1:0.5:15; default=7.5)
        end
    catch _e
        _e
    end
    # ── Cell 20000000-0000-0000-0000-00000000000a (static) ──
    const _cell__20000000_0000_0000_0000_00000000000a = try
        let
            md"""
            ### A reactive table
            
            The same `n` driving the plot also drives this DataFrame. Notice the row
            count mirrors the slider exactly.
            """
        end
    catch _e
        _e
    end
    # ── Cell 20000000-0000-0000-0000-00000000000b (reactive) ──
    const _cell__20000000_0000_0000_0000_00000000000b = try
        let
            # String => column form (rather than kwargs) so we can use unicode column
            # names like √i — the parser would otherwise read `√i = …` as the unary
            # √ operator applied to `i`, not a keyword name.
            DataFrame("i²" => (1:l) .^ 2, "√i" => sqrt.(1:l))
        end
    catch _e
        _e
    end
    # ── Cell 20000000-0000-0000-0000-00000000000c (static) ──
    const _cell__20000000_0000_0000_0000_00000000000c = try
        let
            md"""
            ---
            
            ### What's happening under the hood
            
            In **dev mode** (this view), the slider sends a value to the live Julia
            kernel, which re-runs every cell that reads `n`.
            
            In **script mode** (`julia interactive.jl` with `using SessionsUI` in your
            env), `@bind` falls back to the slider's default value (`8`) and the
            notebook runs straight through as a normal program.
            
            In **WASM publish mode**, this whole notebook becomes static HTML with
            each `<bond>` widget and each cell that reads `n` wrapped in a Therapy
            `@island`. The slider drives a signal in the browser; dependent islands
            recompute locally. No server.
            """
        end
    catch _e
        _e
    end

    @island function _Bond_n__20000000_0000_0000_0000_000000000006()
        n, set_n = n_signal
        RawHtml(render_value(_cell__20000000_0000_0000_0000_000000000006))
    end

    # TODO[extract-v2]: re-execute this cell body in WASM on bond change.
    # v1 freezes the output at the bond defaults; the bond widget itself
    # remains interactive.
    @island function _Cell__1b95c056_9b5a_456f_8007_177b202a1581()
        n, _ = n_signal
        RawHtml(render_value(_cell__1b95c056_9b5a_456f_8007_177b202a1581))
    end

    # TODO[extract-v2]: re-execute this cell body in WASM on bond change.
    # v1 freezes the output at the bond defaults; the bond widget itself
    # remains interactive.
    @island function _Cell__20000000_0000_0000_0000_000000000009()
        n, _ = n_signal
        RawHtml(render_value(_cell__20000000_0000_0000_0000_000000000009))
    end

    @island function _Bond_l_d4e88179_6c23_4713_abe8_5c18e8c94497()
        l, set_l = l_signal
        RawHtml(render_value(_cell_d4e88179_6c23_4713_abe8_5c18e8c94497))
    end

    # TODO[extract-v2]: re-execute this cell body in WASM on bond change.
    # v1 freezes the output at the bond defaults; the bond widget itself
    # remains interactive.
    @island function _Cell__20000000_0000_0000_0000_00000000000b()
        l, _ = l_signal
        RawHtml(render_value(_cell__20000000_0000_0000_0000_00000000000b))
    end

    function Interactive()
        render_published_notebook(
            render_published_cell(
                cell_id = "20000000-0000-0000-0000-000000000001",
                source_code = "md\"\"\"\n# Interactive Sessions\n\nA live demo of `@bind` + `BoundSlider` driving a **WasmPlot** figure and a\n**DataFrame** that recompute together. Move the slider — both update.\n\nIn Sessions IDE this happens via the live Julia kernel; once published to\nWASM the same controls drive Therapy signals in the browser, no server\nround-trip required.\n\"\"\"",
                output_content = RawHtml(render_value(_cell__20000000_0000_0000_0000_000000000001)),
            ),
            render_published_cell(
                cell_id = "20000000-0000-0000-0000-000000000005",
                source_code = "md\"\"\"\n### A bond\n\n`BoundSlider(2:30; default=8)` produces a slider over the integer range\n`2:30`. The macro `@bind n …` makes `n` reactive — every cell that reads\n`n` re-runs when the user moves the slider.\n\"\"\"",
                output_content = RawHtml(render_value(_cell__20000000_0000_0000_0000_000000000005)),
            ),
            render_published_cell(
                cell_id = "20000000-0000-0000-0000-000000000006",
                source_code = "@bind n BoundSlider(2:30; default=8)",
                output_content = _Bond_n__20000000_0000_0000_0000_000000000006(),
            ),
            render_published_cell(
                cell_id = "1b95c056-9b5a-456f-8007-177b202a1581",
                source_code = "\"This is n: \$(n)\"",
                output_content = _Cell__1b95c056_9b5a_456f_8007_177b202a1581(),
            ),
            render_published_cell(
                cell_id = "20000000-0000-0000-0000-000000000007",
                source_code = "md\"\"\"\n### A reactive plot\n\nA bar chart of `i²` for `i ∈ 1:n`. Move the slider above and the plot\nredraws.\n\"\"\"",
                output_content = RawHtml(render_value(_cell__20000000_0000_0000_0000_000000000007)),
            ),
            render_published_cell(
                cell_id = "20000000-0000-0000-0000-000000000008",
                source_code = "# WasmPlot Figures need a Base.show MIME\"text/html\" method to render in the\n# notebook output area. Defining it here keeps the fixture self-contained;\n# this hook lives in WasmPlot itself once Phase 3 of the SessionsUI build\n# wires per-cell @island compilation.\nfunction Base.show(io::IO, ::MIME\"text/html\", fig::WP.Figure)\n    glue = WP.canvas2d_js_glue()\n    js   = WP.generate_js_render(fig)\n    id   = \"wp_\" * string(hash(fig); base=16)\n    print(io, \"\"\"\n    <canvas id=\"\$(id)\" width=\"\$(fig.width)\" height=\"\$(fig.height)\"\n            style=\"border:1px solid var(--cell-border);border-radius:8px;background:#fff\"></canvas>\n    <script>(function(){\n      \$(glue)\n      var c = document.getElementById('\$(id)');\n      var dpr = window.devicePixelRatio||1;\n      c.width = \$(fig.width)*dpr; c.height = \$(fig.height)*dpr;\n      c.style.width='\$(fig.width)px'; c.style.height='\$(fig.height)px';\n      var ctx = c.getContext('2d'); ctx.scale(dpr,dpr);\n      var c2d = canvas2d_imports(ctx);\n      \$(js)\n    })();</script>\n    \"\"\")\nend",
                output_content = RawHtml(render_value(_cell__20000000_0000_0000_0000_000000000008)),
            ),
            render_published_cell(
                cell_id = "20000000-0000-0000-0000-000000000009",
                source_code = "let\n    fig = WP.Figure(size=(750, 360))\n    ax  = WP.Axis(fig[1, 1]; xlabel=\"i\", ylabel=\"i²\", title=\"Squares\", subtitle = \"n = \$(n)\")\n    xs  = Float64.(1:n)\n    WP.barplot!(ax, xs, xs.^2; color=:red)\n    fig\nend",
                output_content = _Cell__20000000_0000_0000_0000_000000000009(),
            ),
            render_published_cell(
                cell_id = "d4e88179-6c23-4713-abe8-5c18e8c94497",
                source_code = "@bind l BoundSlider(1:0.5:15; default=7.5)",
                output_content = _Bond_l_d4e88179_6c23_4713_abe8_5c18e8c94497(),
            ),
            render_published_cell(
                cell_id = "20000000-0000-0000-0000-00000000000a",
                source_code = "md\"\"\"\n### A reactive table\n\nThe same `n` driving the plot also drives this DataFrame. Notice the row\ncount mirrors the slider exactly.\n\"\"\"",
                output_content = RawHtml(render_value(_cell__20000000_0000_0000_0000_00000000000a)),
            ),
            render_published_cell(
                cell_id = "20000000-0000-0000-0000-00000000000b",
                source_code = "# String => column form (rather than kwargs) so we can use unicode column\n# names like √i — the parser would otherwise read `√i = …` as the unary\n# √ operator applied to `i`, not a keyword name.\nDataFrame(\"i²\" => (1:l) .^ 2, \"√i\" => sqrt.(1:l))",
                output_content = _Cell__20000000_0000_0000_0000_00000000000b(),
            ),
            render_published_cell(
                cell_id = "20000000-0000-0000-0000-00000000000c",
                source_code = "md\"\"\"\n---\n\n### What's happening under the hood\n\nIn **dev mode** (this view), the slider sends a value to the live Julia\nkernel, which re-runs every cell that reads `n`.\n\nIn **script mode** (`julia interactive.jl` with `using SessionsUI` in your\nenv), `@bind` falls back to the slider's default value (`8`) and the\nnotebook runs straight through as a normal program.\n\nIn **WASM publish mode**, this whole notebook becomes static HTML with\neach `<bond>` widget and each cell that reads `n` wrapped in a Therapy\n`@island`. The slider drives a signal in the browser; dependent islands\nrecompute locally. No server.\n\"\"\"",
                output_content = RawHtml(render_value(_cell__20000000_0000_0000_0000_00000000000c)),
            ),
        )
    end
end  # module InteractiveMod

# Surface the function at top scope so the docs registry
# (or any caller) can grab it directly.
const Interactive = InteractiveMod.Interactive
