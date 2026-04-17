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

A live demo of `@bind` + `BoundSlider` driving three reactive dependents:
a **numeric memo**, a **WasmPlot bar chart**, and a **DataFrame** table.

Depending on how the notebook is run they behave differently — that's
intentional, so you can see where the WASM-publish pipeline holds the
full reactive promise and where it runs up against WasmTarget's
current compile coverage.

| Mode | Kernel | Numeric memo (`n*n`) | Bar chart | DataFrame |
|---|---|---|---|---|
| **Sessions IDE** | Live Julia | ✅ reactive | ✅ reactive | ✅ reactive |
| **Plain script** | Single-pass Julia | runs once at `default` | runs once | runs once |
| **WASM publish** | In-browser, no server | ✅ reactive (compiles) | ✅ reactive (compiles) | ⚠️ fails to compile |

In **WASM publish** mode every reactive cell is translated to a
Therapy `create_memo` / `create_effect` and handed to WasmTarget. No
preemptive pattern-matching at extract time — the translator emits
the reactive shape for every bond-dependent cell and lets WasmTarget
decide. If the whole `@island` compile fails (because one cell uses a
path WasmTarget can't lower yet — DataFrames today, say), Therapy
logs the compile error and falls back to rendering the SSR output as
plain static HTML: slider widgets still display, but their dependents
freeze at the default value.

The cell source round-trips 1:1 from the `.jl` file either way — the
reader can always inspect what the notebook was trying to do.
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
# WasmPlot Figures need a Base.show MIME"text/html" method to render in
# Sessions IDE's output pipeline (the live kernel renders cell values
# via `show(::IO, ::MIME"text/html", x)`). In the published WASM
# notebook this method isn't called — the extractor translates the
# reactive bar chart cell into a `create_effect + Canvas + render!(fig)`
# pattern that writes straight to the canvas element. Keeping the show
# method here keeps the fixture self-contained for IDE mode.
#
# Trailing `nothing;` suppresses this cell's cell-output slot — the
# method is registered as a side effect of module load; there's no
# meaningful value to render below it.
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
### A reactive table — where WASM currently runs out of road

The same slider that drives the bar chart also drives this DataFrame.

- **In Sessions IDE** the cell reruns through the live Julia kernel
  every time you move the slider, and the rendered table updates row-
  by-row.
- **In WASM publish mode** the extractor emits this cell as a
  `create_memo(() -> DataFrame(…))` just like any other reactive cell
  — no preemptive pattern-matching. When WasmTarget then tries to
  compile the `@island`, DataFrames.jl pulls in column storage,
  PrettyTables dispatch, and `show(::MIME"text/html", ::DataFrame)`
  methods that aren't in WasmTarget's lowering coverage yet. The
  compile fails, Therapy logs the error, and the notebook renders as
  SSR-only: sliders display but stay frozen.

That all-or-nothing granularity is a current limitation. Options as
WasmTarget grows: (a) lower more Base/stdlib so today's failing
cells start compiling; (b) split the notebook into multiple
`@island`s so one failing cell doesn't pin the rest to static mode;
(c) rewrite specific cells to use only WASM-safe patterns (see the
bar chart cell for an example). For now, this cell intentionally
stays as a DataFrame to demonstrate the fail-mode.

The cell source still round-trips 1:1 regardless of compile
outcome, so readers can always see what the notebook *meant*.
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

The same `@bind` macro drives three different runtimes from the same
source — no "publish mode" variant of the file, no fake-bind
injection, the `.jl` you see here is the same one the extractor
consumes byte-for-byte.

**Sessions IDE** — the slider sends a WebSocket message to the live
Julia kernel, which re-runs every cell that references `n` and streams
output back. Any value the cell produces (DataFrames, Markdown, custom
`show` methods — anything with a `MIME"text/html"` method) just works
because full Julia is available server-side.

**Plain script** (`julia interactive.jl` with `using SessionsUI` on
your load path) — `@bind` uses the widget's `initial_value` and the
notebook runs straight through as a normal program. No interactivity,
just a single-pass script.

**WASM publish** — `Sessions.extract_notebook(...)` emits a single
self-contained `.jl` component:
- ONE `@island` per notebook wrapping every cell position.
- Each `@bind` becomes a `create_signal` bound into a native Therapy
  `Input(:value=>sig, :on_input=>set_sig)` — no `<bond>` bridge, no
  WebSocket.
- Every bond-dependent cell becomes a `create_memo` (value cell,
  rendered via `Span(memo)`) or a `create_effect` + `Canvas` (plot
  cell). Bare bond references inside the body (`n`) get rewritten to
  signal reads (`n()`) so updates flow. No preemptive pattern-
  matching at extract time — WasmTarget is the sole gatekeeper.
- If WasmTarget rejects the `@island`, Therapy's build pipeline
  skips WASM emission for that component and the notebook renders
  as SSR-only. Sliders display but stay frozen (no hydration). The
  reader can inspect cell source to see what was attempted.

When the `@island` DOES compile, the slider drives a signal in the
browser and dependent islands recompute locally. No server.
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
