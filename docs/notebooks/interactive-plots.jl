### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 00000001-0000-0000-0000-000000000001
using Markdown

# ╔═╡ 10000001-0000-0000-0000-000000000001
import CairoMakie as Mke

# ╔═╡ a0a0a0a0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
md"""
# Interactive Plots

This notebook demonstrates **pre-rendered reactivity**: slider widgets with CairoMakie plots, all computed at build time. Drag the sliders to swap between pre-rendered images — no server required.
"""

# ╔═╡ b0b0b0b0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
md"""
## Surface Ripple

Adjust the **wavelength** parameter to change the ripple frequency of a 3D surface.
"""

# ╔═╡ c0c0c0c0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
@bind w Slider(2:12, default=6)

# ╔═╡ d0d0d0d0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
let
	fig = Mke.Figure(size=(400, 250))
	ax = Mke.Axis3(fig[1,1], title="w = $w")
	xs = range(-2, 2, length=40)
	ys = range(-2, 2, length=40)
	zs = [sin(w * sqrt(x^2 + y^2)) * exp(-0.3 * (x^2 + y^2)) for x in xs, y in ys]
	Mke.surface!(ax, xs, ys, zs, colormap=:viridis)
	fig
end

# ╔═╡ e0e0e0e0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
md"""
## Trigonometric Curves

Adjust the number of **periods** to see more or fewer oscillations of sin and cos.
"""

# ╔═╡ f0f0f0f0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
@bind periods Slider(1:6, default=3)

# ╔═╡ a1a1a1a1-b1b1-c2c2-d3d3-e4e4e4e4e4e4
let
	fig = Mke.Figure(size=(400, 250))
	ax = Mke.Axis(fig[1,1], title="periods = $periods", xlabel="x", ylabel="y")
	xs = range(0, 2π * periods, length=200)
	Mke.lines!(ax, xs, sin.(xs), label="sin(x)")
	Mke.lines!(ax, xs, cos.(xs), label="cos(x)", linestyle=:dash)
	Mke.axislegend(ax, position=:rt)
	fig
end

# ╔═╡ Cell order:
# ╠═00000001-0000-0000-0000-000000000001
# ╠═10000001-0000-0000-0000-000000000001
# ╟─a0a0a0a0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
# ╟─b0b0b0b0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
# ╠═c0c0c0c0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
# ╠═d0d0d0d0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
# ╟─e0e0e0e0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
# ╠═f0f0f0f0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
# ╠═a1a1a1a1-b1b1-c2c2-d3d3-e4e4e4e4e4e4
