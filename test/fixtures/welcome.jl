### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 10000000-0000-0000-0000-000000000000
# ╠═╡ show_logs = false
begin
    import Pkg
    Pkg.activate(mktempdir())
    Pkg.add(["Markdown", "Dates"])
end

# ╔═╡ 10000000-0000-0000-0000-00000000000f
using Markdown

# ╔═╡ 10000000-0000-0000-0000-00000000000b
using Dates

# ╔═╡ 10000000-0000-0000-0000-000000000001
md"""
# Sessions.jl

A reactive Julia notebook for the terminal *and* the browser.
"""

# ╔═╡ 10000000-0000-0000-0000-000000000002
md"""
## What this is

!!! info "You're reading a live notebook"
    This page isn't static HTML. Each reactive cell is compiled to
    WebAssembly and runs directly in your browser — no server, no
    round-trip, no Jupyter. Open the devtools network tab and move a
    slider in the **Interactive** notebook: nothing leaves the page.
"""

# ╔═╡ 10000000-0000-0000-0000-000000000003
md"""
## Cell visibility

Notebooks have two kinds of cells, with different visibility rules:

- **Hidden by default** (markdown cells, like this one). These are
  *always* hidden in the published view — there's no reveal toggle
  because authors sometimes hide cells to keep implementation details
  private. Every markdown cell on this page is one of these.
- **Visible by default** (code cells). You'll see the source and the
  output side-by-side. An eye icon appears on the left — click it
  to hide the source if you want to focus on the output only, and
  click again to bring it back.

The `greeting` cell below is visible by default. Try toggling the eye
next to it.
"""

# ╔═╡ 10000000-0000-0000-0000-000000000004
greeting = "Hello from a real Julia kernel."

# ╔═╡ 10000000-0000-0000-0000-000000000005
md"""
Markdown cells can interpolate live Julia with `\$(…)`. As of this
render, Julia is **$(VERSION)** and today is
**$(Dates.dayname(Dates.today())), $(Dates.monthname(Dates.today())) $(Dates.day(Dates.today()))**.
"""

# ╔═╡ 10000000-0000-0000-0000-000000000006
md"""
## Where to next

!!! tip "Pick a notebook"
    - **Markdown** — every markdown feature Sessions renders, with
      admonitions, tables, math, and live interpolation.
    - **Interactive** — `@bind`, sliders, and reactive cells driven
      by the same signal engine that powers the IDE.
    - **Plots** — slider-linked WasmPlot figures that redraw entirely
      in the browser.
    - **Reactivity** — multiple widgets feeding a single computed
      output, zero callback wiring.
"""

# ╔═╡ Cell order:
# ╠═10000000-0000-0000-0000-000000000000
# ╠═10000000-0000-0000-0000-00000000000f
# ╠═10000000-0000-0000-0000-00000000000b
# ╟─10000000-0000-0000-0000-000000000001
# ╟─10000000-0000-0000-0000-000000000002
# ╟─10000000-0000-0000-0000-000000000003
# ╠═10000000-0000-0000-0000-000000000004
# ╟─10000000-0000-0000-0000-000000000005
# ╟─10000000-0000-0000-0000-000000000006
