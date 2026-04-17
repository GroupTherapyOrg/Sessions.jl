# ── Sessions.jl extracted notebook ─────────────────────────
#
# Source : /Users/daleblack/Documents/dev/GroupTherapyOrg/Sessions.jl/test/fixtures/interactive.jl
# Date   : 2026-04-17T09:25:05.565
#
# This file is a self-contained Therapy component. The user's
# cell SOURCE is preserved verbatim — markdown stays markdown,
# code stays code. Each cell evaluates once at module load and
# its value is rendered through Base.show(MIME"text/html"(),…)
# (the same pipeline the Sessions IDE uses live).
#
# Architecture:
#   - Outer `function Interactive()` is plain Julia.
#     It just lays out cells in document order; it always works
#     regardless of WASM compile state.
#   - Each @bind cell becomes a tiny @island that wraps the
#     SessionsUI widget. Bond signals are module-level shared
#     signals so cross-island sync is automatic.
#   - Each reactive cell becomes a tiny @island that captures
#     its upstream bond signals. v1 renders the frozen value
#     computed at module load (using the bond defaults). v2
#     re-executes the body in WASM as WasmTarget grows.
#
# Edit by hand to restyle Tailwind classes, change cell content,
# remove cells, etc. Re-running `Sessions.extract_notebook` with
# the same out_path overwrites the file.
# ───────────────────────────────────────────────────────────

module InteractiveMod

    using Therapy: Div, RawHtml, create_signal, @island
    using Markdown
    using SessionsUI: @bind, BoundSlider
    import WasmPlot as WP
    using DataFrames

"""
Render any cell value to an HTML string. Priority matches the
Sessions IDE's output classifier (see Sessions/.../boot.jl):
  1. Exceptions → styled error block
  2. `showable(MIME"text/html"(), x)` → use that show method.
     This covers Markdown.MD, DataFrames.DataFrame, WasmPlot.Figure,
     SessionsUI.Bond, and anything else that opts in.
  3. Dict / Set / struct that Sessions marks as tree-like → tree
     renderer (only if Sessions is loaded in Main — the IDE path).
  4. Fallback: `sprint(print, x)`.
The order is critical: Markdown.MD has BOTH a text/html show AND
is "tree-like" per Sessions, and we want the HTML form.
"""
function _render(x)::String
    x isa Exception && return string("<pre style='color:#c33;font-family:monospace;font-size:12px;padding:8px;background:#fee;border-radius:4px'>", sprint(showerror, x), "</pre>")
    try
        if Base.showable(MIME"text/html"(), x)
            return sprint(io -> show(io, MIME"text/html"(), x))
        end
    catch
    end
    if isdefined(Main, :Sessions)
        try
            sess = Main.Sessions
            if Base.invokelatest(getfield(sess, :_is_tree_value), x)
                return Base.invokelatest(getfield(sess, :_render_tree_html), x)
            end
        catch
        end
    end
    sprint(print, x)
end


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
    end    # ── Cell 20000000-0000-0000-0000-000000000005 (static) ──
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
    end    # ── Cell 20000000-0000-0000-0000-000000000006 (bond) ──
    const _cell__20000000_0000_0000_0000_000000000006 = try
        let
            @bind n BoundSlider(2:30; default=8)
        end
    catch _e
        _e
    end    # ── Cell 1b95c056-9b5a-456f-8007-177b202a1581 (reactive) ──
    const _cell__1b95c056_9b5a_456f_8007_177b202a1581 = try
        let
            "This is n: $(n)"
        end
    catch _e
        _e
    end    # ── Cell 20000000-0000-0000-0000-000000000007 (static) ──
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
    end    # ── Cell 20000000-0000-0000-0000-000000000008 (static) ──
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
    end    # ── Cell 20000000-0000-0000-0000-000000000009 (reactive) ──
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
    end    # ── Cell d4e88179-6c23-4713-abe8-5c18e8c94497 (bond) ──
    const _cell_d4e88179_6c23_4713_abe8_5c18e8c94497 = try
        let
            @bind l BoundSlider(1:0.5:15; default=7.5)
        end
    catch _e
        _e
    end    # ── Cell 20000000-0000-0000-0000-00000000000a (static) ──
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
    end    # ── Cell 20000000-0000-0000-0000-00000000000b (reactive) ──
    const _cell__20000000_0000_0000_0000_00000000000b = try
        let
            # String => column form (rather than kwargs) so we can use unicode column
            # names like √i — the parser would otherwise read `√i = …` as the unary
            # √ operator applied to `i`, not a keyword name.
            DataFrame("i²" => (1:l) .^ 2, "√i" => sqrt.(1:l))
        end
    catch _e
        _e
    end    # ── Cell 20000000-0000-0000-0000-00000000000c (static) ──
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
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__20000000_0000_0000_0000_000000000006)))
end
    # TODO[extract-v2]: re-execute this cell body in WASM on bond change.
    # v1 freezes the output at the bond defaults; the bond widget itself
    # remains interactive.
    @island function _Cell__1b95c056_9b5a_456f_8007_177b202a1581()
        n, _ = n_signal
        Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
            RawHtml(_render(_cell__1b95c056_9b5a_456f_8007_177b202a1581)))
    end
    # TODO[extract-v2]: re-execute this cell body in WASM on bond change.
    # v1 freezes the output at the bond defaults; the bond widget itself
    # remains interactive.
    @island function _Cell__20000000_0000_0000_0000_000000000009()
        n, _ = n_signal
        Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
            RawHtml(_render(_cell__20000000_0000_0000_0000_000000000009)))
    end
@island function _Bond_l_d4e88179_6c23_4713_abe8_5c18e8c94497()
    l, set_l = l_signal
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell_d4e88179_6c23_4713_abe8_5c18e8c94497)))
end
    # TODO[extract-v2]: re-execute this cell body in WASM on bond change.
    # v1 freezes the output at the bond defaults; the bond widget itself
    # remains interactive.
    @island function _Cell__20000000_0000_0000_0000_00000000000b()
        l, _ = l_signal
        Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
            RawHtml(_render(_cell__20000000_0000_0000_0000_00000000000b)))
    end
    function Interactive()
        Div(:class => "notebook-extracted",
            Div(:class => "nb-cell-list",
                :style => "max-width:900px;margin:0 auto;padding-left:28px;padding-right:28px;position:relative;",
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__20000000_0000_0000_0000_000000000001))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__20000000_0000_0000_0000_000000000005))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    _Bond_n__20000000_0000_0000_0000_000000000006())),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    _Cell__1b95c056_9b5a_456f_8007_177b202a1581())),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__20000000_0000_0000_0000_000000000007))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__20000000_0000_0000_0000_000000000008))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    _Cell__20000000_0000_0000_0000_000000000009())),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    _Bond_l_d4e88179_6c23_4713_abe8_5c18e8c94497())),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__20000000_0000_0000_0000_00000000000a))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    _Cell__20000000_0000_0000_0000_00000000000b())),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__20000000_0000_0000_0000_00000000000c)))))
            )
        )
    end
end  # module InteractiveMod

# Surface the function at top scope so the docs registry
# (or any caller) can grab it directly.
const Interactive = InteractiveMod.Interactive
