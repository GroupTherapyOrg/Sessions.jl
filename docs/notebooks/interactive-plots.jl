### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 00000001-0000-0000-0000-000000000001
using Markdown

# ╔═╡ 00000001-0000-0000-0000-000000000002
using SessionsUI: @bind, BoundSlider

# ╔═╡ a0a0a0a0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
md"""
# Interactive Plots

This notebook demonstrates **interactive Plotly.js plots** with slider widgets. Julia computes the data at build time, and Plotly.js renders interactive charts in the browser — zoom, pan, and orbit with no server required.
"""

# ╔═╡ b0b0b0b0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
md"""
## Surface Ripple

Adjust the **wavelength** parameter to change the ripple frequency of a 3D surface.
"""

# ╔═╡ c0c0c0c0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
@bind w BoundSlider(2:12, default=6)

# ╔═╡ d0d0d0d0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
let
	xs = collect(range(-2, 2, length=40))
	ys = collect(range(-2, 2, length=40))
	zs = [sin(w * sqrt(x^2 + y^2)) * exp(-0.3 * (x^2 + y^2)) for x in xs, y in ys]
	Dict(
		"data" => [Dict(
			"type" => "surface",
			"x" => xs,
			"y" => ys,
			"z" => [collect(zs[i, :]) for i in 1:size(zs, 1)],
			"colorscale" => "Viridis"
		)],
		"layout" => Dict(
			"title" => "w = $w",
			"width" => 600,
			"height" => 400,
			"margin" => Dict("l" => 0, "r" => 0, "t" => 40, "b" => 0)
		)
	)
end

# ╔═╡ e0e0e0e0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
md"""
## Trigonometric Curves

Adjust the number of **periods** to see more or fewer oscillations of sin and cos.
"""

# ╔═╡ f0f0f0f0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
@bind periods BoundSlider(1:6, default=3)

# ╔═╡ a1a1a1a1-b1b1-c2c2-d3d3-e4e4e4e4e4e4
let
	xs = collect(range(0, 2π * periods, length=200))
	Dict(
		"data" => [
			Dict("type" => "scatter", "x" => xs, "y" => sin.(xs), "name" => "sin(x)"),
			Dict("type" => "scatter", "x" => xs, "y" => cos.(xs), "name" => "cos(x)",
				"line" => Dict("dash" => "dash"))
		],
		"layout" => Dict(
			"title" => "periods = $periods",
			"xaxis" => Dict("title" => "x"),
			"yaxis" => Dict("title" => "y"),
			"width" => 600,
			"height" => 400
		)
	)
end

# ╔═╡ Cell order:
# ╠═00000001-0000-0000-0000-000000000001
# ╠═00000001-0000-0000-0000-000000000002
# ╟─a0a0a0a0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
# ╟─b0b0b0b0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
# ╠═c0c0c0c0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
# ╠═d0d0d0d0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
# ╟─e0e0e0e0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
# ╠═f0f0f0f0-b1b1-c2c2-d3d3-e4e4e4e4e4e4
# ╠═a1a1a1a1-b1b1-c2c2-d3d3-e4e4e4e4e4e4
