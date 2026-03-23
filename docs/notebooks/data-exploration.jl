### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 00000002-0000-0000-0000-000000000001
using Markdown

# ╔═╡ 00000002-0000-0000-0000-000000000002
using SessionsUI: @bind, BoundSlider

# ╔═╡ 11223344-5566-7788-99aa-bbccddeeff00
md"""
# Data Exploration

This notebook demonstrates working with tabular data using Julia's built-in types. No external packages required — just NamedTuples and standard library functions.
"""

# ╔═╡ 22334455-6677-8899-aabb-ccddeeff0011
planets = [
    (name="Mercury", diameter_km=4879, distance_au=0.39, moons=0, has_rings=false),
    (name="Venus", diameter_km=12104, distance_au=0.72, moons=0, has_rings=false),
    (name="Earth", diameter_km=12756, distance_au=1.00, moons=1, has_rings=false),
    (name="Mars", diameter_km=6792, distance_au=1.52, moons=2, has_rings=false),
    (name="Jupiter", diameter_km=142984, distance_au=5.20, moons=95, has_rings=true),
    (name="Saturn", diameter_km=120536, distance_au=9.54, moons=146, has_rings=true),
    (name="Uranus", diameter_km=51118, distance_au=19.19, moons=28, has_rings=true),
    (name="Neptune", diameter_km=49528, distance_au=30.07, moons=16, has_rings=true),
]

# ╔═╡ aabb0011-2233-4455-6677-8899aabbcc01
md"""
## Interactive Slider

Move the slider to select how many planets to show:
"""

# ╔═╡ aabb0011-2233-4455-6677-8899aabbcc02
@bind n BoundSlider(1:8, default=8)

# ╔═╡ 71db0b27-9617-425e-8f2a-42295ba69b11
n

# ╔═╡ aabb0011-2233-4455-6677-8899aabbcc03
planets[1:n]

# ╔═╡ aabb0011-2233-4455-6677-8899aabbcc04
md"""
## How the Interactivity Works

This notebook uses three different strategies to make the slider reactive — each chosen based on what the output needs.

The **slider** and the **`n` display cell** are both **real WASM islands**. The `WebSlider` component is compiled from Julia to WebAssembly via [WasmTarget.jl](https://github.com/GroupTherapyOrg/WasmTarget.jl). Moving the slider updates a WASM signal, which updates the displayed value — no JavaScript needed for the slider logic. The `n` cell works the same way: a `BoundValue` island receives the slider value through an event bridge, and the WASM handler updates its own signal. This is live, reactive WASM — not pre-rendered.

The **planets table**, on the other hand, is **server-rendered HTML with JavaScript row toggling**. All 8 rows are rendered at build time with `data-row-index` attributes. When the slider moves, JavaScript shows or hides rows based on the slider value. No WASM here — the table involves Julia's full I/O and display pipeline, which can't yet be compiled, so we use the simplest approach: render once, toggle visibility.

The architecture is *"compile what you can, render what you can't"* — WASM for interactive logic (sliders, signals, simple values), server-rendering for complex outputs (tables, plots). As WasmTarget.jl gains more Julia coverage, more cells will move from server-rendered to true WASM.

### Where This Is Headed

The gap between "WASM island" and "server-rendered" isn't permanent — it's a function of how much of Julia's runtime WasmTarget.jl can compile. Today, WasmTarget compiles a substantial subset: arithmetic, control flow, structs, named tuples, array operations, and the reactive signal system. What it *can't* yet compile is Julia's full I/O and display machinery — `show`, `print`, string interpolation with dynamic dispatch, and the type-driven method tables that power generic rendering.

The roadmap is to progressively close that gap.

**First: NamedTuple to HTML rendering in WASM.** The `planets[1:n]` expression is pure Julia (array slicing, named tuple access). If WasmTarget can compile a simple table renderer (iterate rows, access fields, emit DOM nodes), the entire cell becomes a WASM island. No server rendering, no row toggling tricks — just reactive WASM that re-renders the table when `n` changes.

**Second: cross-island signal sharing.** Today, the slider and `BoundValue` communicate via a JavaScript bridge (hidden input + event dispatch). With shared WASM memory or a signal registry, islands could share signals directly — slider changes `n`, all downstream islands react, no JS bridge needed.

**Third: full notebook as a single WASM module.** The end goal. Every cell in this notebook — the slider, the `n` display, the table, the filter, the sort — compiled into one WASM module with shared signals. The notebook becomes a self-contained interactive application that runs entirely in the browser with zero server dependency. Julia's type system, multiple dispatch, and composability — all running as WebAssembly.

This is fundamentally different from approaches like Pyodide or webR that ship an entire language runtime to the browser. WasmTarget.jl compiles *your specific Julia code* ahead of time, producing small, fast WASM modules (the slider is ~3KB). The result is native-speed interactivity with instant load times.
"""

# ╔═╡ 33445566-7788-99aa-bbcc-ddeeff001122
md"""
## Filtering and Analysis

Let's explore the data using Julia's functional programming tools.
"""

# ╔═╡ 44556677-8899-aabb-ccdd-eeff00112233
large_planets = filter(p -> p.diameter_km > 10000, planets)

# ╔═╡ 55667788-99aa-bbcc-ddee-ff0011223344
total_moons = sum(p -> p.moons, planets)

# ╔═╡ 66778899-aabb-ccdd-eeff-001122334455
md"""
## Summary Statistics

The solar system has **$(length(planets))** planets with a total of **$(total_moons)** known moons.
"""

# ╔═╡ 77889900-aabb-ccdd-eeff-112233445566
sorted_by_size = sort(planets, by=p -> p.diameter_km, rev=true)

# ╔═╡ Cell order:
# ╠═00000002-0000-0000-0000-000000000001
# ╠═00000002-0000-0000-0000-000000000002
# ╟─11223344-5566-7788-99aa-bbccddeeff00
# ╠═22334455-6677-8899-aabb-ccddeeff0011
# ╟─aabb0011-2233-4455-6677-8899aabbcc01
# ╟─aabb0011-2233-4455-6677-8899aabbcc02
# ╠═71db0b27-9617-425e-8f2a-42295ba69b11
# ╠═aabb0011-2233-4455-6677-8899aabbcc03
# ╟─aabb0011-2233-4455-6677-8899aabbcc04
# ╟─33445566-7788-99aa-bbcc-ddeeff001122
# ╠═44556677-8899-aabb-ccdd-eeff00112233
# ╠═55667788-99aa-bbcc-ddee-ff0011223344
# ╟─66778899-aabb-ccdd-eeff-001122334455
# ╠═77889900-aabb-ccdd-eeff-112233445566
