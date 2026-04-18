### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 40000000-0000-0000-0000-000000000000
# ╠═╡ show_logs = false
begin
    import Pkg
    Pkg.activate(mktempdir())
    Pkg.add([
        Pkg.PackageSpec(url = "https://github.com/GroupTherapyOrg/WasmTarget.jl.git"),
        Pkg.PackageSpec(url = "https://github.com/GroupTherapyOrg/WasmPlot.jl.git"),
        Pkg.PackageSpec(url = "https://github.com/GroupTherapyOrg/Sessions.jl.git",
                        subdir = "SessionsUI"),
        Pkg.PackageSpec(name = "Markdown"),
    ])
end

# ╔═╡ 40000000-0000-0000-0000-00000000000f
using Markdown

# ╔═╡ 40000000-0000-0000-0000-000000000002
using SessionsUI: @bind, BoundSlider

# ╔═╡ 40000000-0000-0000-0000-000000000003
# ╠═╡ show_logs = false
import WasmPlot as WP

# ╔═╡ 40000000-0000-0000-0000-000000000001
md"""
# Plots

WasmPlot figures compile to WebAssembly. Each plot cell becomes a
`create_effect` that paints straight to a `<canvas>` — no SVG, no
React, no server. Drag the sliders and watch both plots redraw
entirely in the browser.
"""

# ╔═╡ 40000000-0000-0000-0000-000000000004
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
nothing;

# ╔═╡ 40000000-0000-0000-0000-000000000005
md"""
## Bar chart
"""

# ╔═╡ 40000000-0000-0000-0000-000000000006
@bind nbars BoundSlider(3:25; default=10)

# ╔═╡ 40000000-0000-0000-0000-000000000007
let
    fig = WP.Figure(size=(750, 360))
    ax  = WP.Axis(fig[1, 1]; xlabel="i", ylabel="i²", title="Squares")
    xs = Float64[]
    ys = Float64[]
    i = Int64(1)
    count = Int64(nbars)
    while i <= count
        xi = Float64(i)
        push!(xs, xi)
        push!(ys, xi * xi)
        i = i + Int64(1)
    end
    WP.barplot!(ax, xs, ys; color=:blue)
    fig
end

# ╔═╡ 40000000-0000-0000-0000-000000000008
md"""
!!! tip "Why canvas, not SVG"
    Canvas lets WasmTarget avoid emitting large trees of DOM nodes
    on every slider tick — a single `ctx.fillRect` call per bar
    beats diffing hundreds of `<rect>` elements. The whole bar-chart
    effect lands in well under 10 KB of WASM.
"""

# ╔═╡ 40000000-0000-0000-0000-000000000009
md"""
## Line chart
"""

# ╔═╡ 40000000-0000-0000-0000-00000000000a
@bind npoints BoundSlider(5:40; default=18)

# ╔═╡ 40000000-0000-0000-0000-00000000000b
let
    fig = WP.Figure(size=(750, 360))
    ax  = WP.Axis(fig[1, 1]; xlabel="i", ylabel="√i", title="Square roots")
    xs = Float64[]
    ys = Float64[]
    i = Int64(1)
    count = Int64(npoints)
    while i <= count
        xi = Float64(i)
        push!(xs, xi)
        push!(ys, sqrt(xi))
        i = i + Int64(1)
    end
    WP.lines!(ax, xs, ys; color=:purple)
    fig
end

# ╔═╡ 40000000-0000-0000-0000-00000000000c
md"""
## How it works

Both plots share the same compile pipeline: the extractor sees a
`create_effect` body that ends in a `WP.Figure`, wraps it in a
`Canvas` island, and lets WasmTarget lower the paint calls. Move
either slider and only the affected island's effect re-runs — the
other plot doesn't re-render, doesn't re-layout, doesn't repaint.
"""

# ╔═╡ Cell order:
# ╠═40000000-0000-0000-0000-000000000000
# ╠═40000000-0000-0000-0000-00000000000f
# ╠═40000000-0000-0000-0000-000000000002
# ╠═40000000-0000-0000-0000-000000000003
# ╟─40000000-0000-0000-0000-000000000001
# ╟─40000000-0000-0000-0000-000000000004
# ╟─40000000-0000-0000-0000-000000000005
# ╟─40000000-0000-0000-0000-000000000006
# ╠═40000000-0000-0000-0000-000000000007
# ╟─40000000-0000-0000-0000-000000000008
# ╟─40000000-0000-0000-0000-000000000009
# ╟─40000000-0000-0000-0000-00000000000a
# ╠═40000000-0000-0000-0000-00000000000b
# ╟─40000000-0000-0000-0000-00000000000c
