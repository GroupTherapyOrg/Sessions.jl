### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 20000000-0000-0000-0000-000000000000
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

# ╔═╡ 20000000-0000-0000-0000-00000000000f
using Markdown

# ╔═╡ 20000000-0000-0000-0000-000000000002
using SessionsUI: @bind, BoundSlider

# ╔═╡ 20000000-0000-0000-0000-000000000003
# ╠═╡ show_logs = false
import WasmPlot as WP

# ╔═╡ 20000000-0000-0000-0000-000000000001
md"""
# Interactive

A live demo of `@bind` + `BoundSlider` driving two reactive dependents:
a numeric memo and a WasmPlot bar chart. Drag the slider and watch
both update in lockstep.
"""

# ╔═╡ 20000000-0000-0000-0000-000000000004
md"""
!!! info "Same source, three runtimes"
    The `.jl` file you see here runs in three different ways without
    modification:

    - **Sessions IDE** — cells re-run through a live Julia kernel
      over WebSocket. Any Julia value that defines a
      `show(::MIME"text/html", …)` method just works.
    - **Plain script** — `julia interactive.jl` executes straight
      through. Bonds resolve to their default values; no
      interactivity.
    - **WASM publish** *(this page)* — every reactive cell compiles
      to WebAssembly. Sliders drive signals in the browser, dependent
      cells recompute locally, no kernel, no server.
"""

# ╔═╡ 20000000-0000-0000-0000-000000000006
@bind n BoundSlider(2:30; default=8)

# ╔═╡ 1b95c056-9b5a-456f-8007-177b202a1581
n * n

# ╔═╡ 20000000-0000-0000-0000-000000000007
md"""
The memo above is `n * n` — pure integer arithmetic. The bar chart
below is `i²` for `i ∈ 1:n`. Both recompute from the same slider.
"""

# ╔═╡ 20000000-0000-0000-0000-000000000008
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

# ╔═╡ 20000000-0000-0000-0000-000000000009
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

# ╔═╡ 20000000-0000-0000-0000-00000000000c
md"""
!!! info "Under the hood"
    `Sessions.extract_notebook(...)` emits one `@island` per reactive
    cell. Each `@bind` becomes a `create_signal` plus a native Therapy
    `Input(:value => sig, :on_input => set_sig)` — no `<bond>` bridge,
    no WebSocket. Every bond-dependent cell becomes a `create_memo`
    (rendered as a `Span`) or a `create_effect + Canvas` (for plots).
    Bare references to bond names (`n`) are rewritten to signal reads
    (`n()`) so updates flow.

    When WasmTarget can't compile an island, Therapy logs the error
    and renders that island as static SSR — sliders display but stay
    frozen. The rest of the notebook keeps hydrating normally. The
    cell source round-trips 1:1 either way, so a reader can always
    inspect what the notebook meant to do.
"""

# ╔═╡ Cell order:
# ╠═20000000-0000-0000-0000-000000000000
# ╠═20000000-0000-0000-0000-00000000000f
# ╠═20000000-0000-0000-0000-000000000002
# ╠═20000000-0000-0000-0000-000000000003
# ╟─20000000-0000-0000-0000-000000000001
# ╟─20000000-0000-0000-0000-000000000004
# ╟─20000000-0000-0000-0000-000000000006
# ╠═1b95c056-9b5a-456f-8007-177b202a1581
# ╟─20000000-0000-0000-0000-000000000007
# ╟─20000000-0000-0000-0000-000000000008
# ╠═20000000-0000-0000-0000-000000000009
# ╟─20000000-0000-0000-0000-00000000000c
