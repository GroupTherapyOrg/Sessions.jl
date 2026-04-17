### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 20000000-0000-0000-0000-000000000000
# ╠═╡ show_logs = false
# Notebook-local environment — resolves every dep from its public GitHub
# URL so the notebook opens without any monorepo-specific path wiring.
# Markdown is a stdlib but Sessions worker envs don't auto-include them.
begin
    import Pkg
    Pkg.activate(mktempdir())
    # Unregistered transitive deps must be added at the root: WasmPlot
    # depends on WasmTarget, but neither is in the General Registry, so the
    # resolver fails with "WasmTarget has no known versions" unless we list
    # it explicitly here.
    Pkg.add([
        Pkg.PackageSpec(url = "https://github.com/GroupTherapyOrg/WasmTarget.jl.git"),
        Pkg.PackageSpec(url = "https://github.com/GroupTherapyOrg/WasmPlot.jl.git"),
        Pkg.PackageSpec(url = "https://github.com/GroupTherapyOrg/Sessions.jl.git",
                        subdir = "SessionsUI"),
        Pkg.PackageSpec(name = "DataFrames"),
        Pkg.PackageSpec(name = "Markdown"),
    ])
end

# ╔═╡ 20000000-0000-0000-0000-00000000000f
using Markdown

# ╔═╡ 20000000-0000-0000-0000-000000000002
using SessionsUI: @bind, BoundSlider

# ╔═╡ 20000000-0000-0000-0000-000000000003
# ╠═╡ show_logs = false
# Namespace WasmPlot to avoid collisions — Therapy exports `Figure`
# (the HTML5 <figure> element) and so does WasmPlot (the plot type).
# Every call site below uses `WP.Figure`, `WP.Axis`, `WP.barplot!`.
import WasmPlot as WP

# ╔═╡ 20000000-0000-0000-0000-000000000004
# ╠═╡ show_logs = false
using DataFrames

# ╔═╡ 20000000-0000-0000-0000-000000000001
md"""
# Interactive Sessions

A live demo of `@bind` + `BoundSlider` driving a **WasmPlot** figure and a
**DataFrame** that recompute together. Move the slider — both update.

In Sessions IDE this happens via the live Julia kernel; once published to
WASM the same controls drive Therapy signals in the browser, no server
round-trip required.
"""

# ╔═╡ 20000000-0000-0000-0000-000000000005
md"""
### A bond

`BoundSlider(2:30; default=8)` produces a slider over the integer range
`2:30`. The macro `@bind n …` makes `n` reactive — every cell that reads
`n` re-runs when the user moves the slider.
"""

# ╔═╡ 20000000-0000-0000-0000-000000000006
@bind n BoundSlider(2:30; default=8)

# ╔═╡ 1b95c056-9b5a-456f-8007-177b202a1581
# Square of the slider value. Pure integer arithmetic — compiles to WASM
# and stays reactive in the published notebook. (String interpolation
# like `"n = $(n)"` would need `string(::Integer)` which WasmTarget
# doesn't lower yet, so we keep it to a raw numeric memo.)
n * n

# ╔═╡ 20000000-0000-0000-0000-000000000007
md"""
### A reactive plot

A bar chart of `i²` for `i ∈ 1:n`. Move the slider above and the plot
redraws.
"""

# ╔═╡ 20000000-0000-0000-0000-000000000008
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

# ╔═╡ 20000000-0000-0000-0000-000000000009
# Reactive bar chart. Built with the Therapy NotebookStep4 discipline:
# explicit `while` loop in place of `Float64.(1:n)` / `xs.^2` broadcasts
# (broadcast machinery isn't in WasmTarget yet), static title/xlabel/
# ylabel strings (dynamic `subtitle = "n = $(n)"` would need
# `string(::Integer)`), and primitive typed numerics so the extractor's
# reactive-cell translator emits a WASM-safe `create_effect`.
let
    fig = WP.Figure(size=(750, 360))
    ax  = WP.Axis(fig[1, 1]; xlabel="i", ylabel="i²", title="Squares")
    xs = Float64[]
    ys = Float64[]
    i = Int64(1)
    count = Int64(n)
    while i <= count
        xi = Float64(i)
        push!(xs, xi)
        push!(ys, xi * xi)
        i = i + Int64(1)
    end
    WP.barplot!(ax, xs, ys; color=:red)
    fig
end

# ╔═╡ d4e88179-6c23-4713-abe8-5c18e8c94497
@bind l BoundSlider(1:0.5:15; default=7.5)

# ╔═╡ 20000000-0000-0000-0000-00000000000a
md"""
### A reactive table

The same `n` driving the plot also drives this DataFrame. Notice the row
count mirrors the slider exactly.
"""

# ╔═╡ 20000000-0000-0000-0000-00000000000b
# String => column form (rather than kwargs) so we can use unicode column
# names like √i — the parser would otherwise read `√i = …` as the unary
# √ operator applied to `i`, not a keyword name.
DataFrame("i²" => (1:l) .^ 2, "√i" => sqrt.(1:l))

# ╔═╡ 20000000-0000-0000-0000-00000000000c
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

# ╔═╡ Cell order:
# ╠═20000000-0000-0000-0000-000000000000
# ╠═20000000-0000-0000-0000-00000000000f
# ╠═20000000-0000-0000-0000-000000000002
# ╠═20000000-0000-0000-0000-000000000003
# ╠═20000000-0000-0000-0000-000000000004
# ╟─20000000-0000-0000-0000-000000000001
# ╟─20000000-0000-0000-0000-000000000005
# ╟─20000000-0000-0000-0000-000000000006
# ╠═1b95c056-9b5a-456f-8007-177b202a1581
# ╟─20000000-0000-0000-0000-000000000007
# ╟─20000000-0000-0000-0000-000000000008
# ╠═20000000-0000-0000-0000-000000000009
# ╟─d4e88179-6c23-4713-abe8-5c18e8c94497
# ╟─20000000-0000-0000-0000-00000000000a
# ╠═20000000-0000-0000-0000-00000000000b
# ╟─20000000-0000-0000-0000-00000000000c
