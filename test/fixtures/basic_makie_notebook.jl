### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 53b310fb-2274-4c2f-949f-3cf6b964e26e
using Markdown

# ╔═╡ b2c3d4e5-6f7a-8b9c-0d1e-f2a3b4c5d6e7
using CairoMakie

# ╔═╡ a1b2c3d4-5e6f-7a8b-9c0d-e1f2a3b4c5d6
md"""
# CairoMakie Demo

Inline **raster image rendering** via Sixel/Kitty terminal graphics.

Any package that defines `show(::IO, ::MIME"image/png", x)` renders inline automatically — CairoMakie, Plots.jl, Gadfly, etc.
"""

# ╔═╡ c3d4e5f6-7a8b-9c0d-1e2f-a3b4c5d6e7f8
md"""
### Damped Ripple Surface

A 3D surface of `cos(w * sqrt(x^2 + y^2)) * exp(-0.3 * sqrt(x^2 + y^2))`.

Use the slider to control wave frequency **w**.
"""

# ╔═╡ d4e5f6a7-8b9c-0d1e-2f3a-b4c5d6e7f8a9
@bind w Slider(2:20, default = 8)

# ╔═╡ e5f6a7b8-9c0d-1e2f-3a4b-c5d6e7f8a9b0
let
    xs = -2:0.05:2
    ys = -2:0.05:2
    zs = [cos(w / 3 * sqrt(x^2 + y^2)) * exp(-0.3 * sqrt(x^2 + y^2)) for x in xs, y in ys]

    fig = Figure(size = (400, 200))
    ax = Axis3(fig[1, 1]; title = "$(w)-fold ripple", xlabel = "x", ylabel = "y", zlabel = "z")
    surface!(ax, xs, ys, zs; colormap = :viridis)
    fig
end

# ╔═╡ f6a7b8c9-0d1e-2f3a-4b5c-d6e7f8a9b0c1
md"""
### Line Plot

Slider controls the number of visible periods.
"""

# ╔═╡ 11223344-5566-7788-99aa-bbccddeeff00
@bind periods Slider(1:8, default = 2)

# ╔═╡ a7b8c9d0-1e2f-3a4b-5c6d-e7f8a9b0c1d2
let
    x = range(0, periods * 2pi; length = 200)

    fig = Figure(size = (600, 300))
    ax = Axis(fig[1, 1]; title = "$(periods) period(s)", xlabel = "x", ylabel = "y")
    lines!(ax, x, sin.(x); label = "sin(x)")
    lines!(ax, x, cos.(x); label = "cos(x)", linestyle = :dash)
    axislegend(ax)
    fig
end

# ╔═╡ b8c9d0e1-2f3a-4b5c-6d7e-f8a9b0c1d2e3
md"""
### Heatmap

Slider controls the frequency multiplier **k** in `sin(k*x) * cos(k*y)`.
"""

# ╔═╡ aabbccdd-1122-3344-5566-778899001122
@bind k Slider(1:10, default = 1)

# ╔═╡ c9d0e1f2-3a4b-5c6d-7e8f-a9b0c1d2e3f4
let
    xs = range(-pi, pi; length = 100)
    ys = range(-pi, pi; length = 100)
    zs = [sin(k * x) * cos(k * y) for x in xs, y in ys]

    fig = Figure(size = (500, 400))
    ax = Axis(fig[1, 1]; title = "sin($(k)x) * cos($(k)y)", xlabel = "x", ylabel = "y")
    heatmap!(ax, xs, ys, zs; colormap = :inferno)
    Colorbar(fig[1, 2]; colormap = :inferno, limits = (-1, 1))
    fig
end

# ╔═╡ d0e1f2a3-4b5c-6d7e-8f9a-b0c1d2e3f4a5
md"""
### Scatter Plot

Slider controls the number of points **n**.
"""

# ╔═╡ 00112233-4455-6677-8899-aabbccddeeff
@bind n_pts Slider(50:50:1000, default = 200)

# ╔═╡ e1f2a3b4-5c6d-7e8f-9a0b-c1d2e3f4a5b6
let
    x = randn(n_pts)
    y = randn(n_pts)
    c = sqrt.(x .^ 2 .+ y .^ 2)

    fig = Figure(size = (500, 400))
    ax = Axis(fig[1, 1]; title = "Scatter (n=$(n_pts))", xlabel = "x", ylabel = "y")
    scatter!(ax, x, y; color = c, colormap = :plasma, markersize = 8)
    fig
end

# ╔═╡ Cell order:
# ╠═53b310fb-2274-4c2f-949f-3cf6b964e26e
# ╠═b2c3d4e5-6f7a-8b9c-0d1e-f2a3b4c5d6e7
# ╟─a1b2c3d4-5e6f-7a8b-9c0d-e1f2a3b4c5d6
# ╟─c3d4e5f6-7a8b-9c0d-1e2f-a3b4c5d6e7f8
# ╟─d4e5f6a7-8b9c-0d1e-2f3a-b4c5d6e7f8a9
# ╟─e5f6a7b8-9c0d-1e2f-3a4b-c5d6e7f8a9b0
# ╟─f6a7b8c9-0d1e-2f3a-4b5c-d6e7f8a9b0c1
# ╟─11223344-5566-7788-99aa-bbccddeeff00
# ╟─a7b8c9d0-1e2f-3a4b-5c6d-e7f8a9b0c1d2
# ╟─b8c9d0e1-2f3a-4b5c-6d7e-f8a9b0c1d2e3
# ╟─aabbccdd-1122-3344-5566-778899001122
# ╟─c9d0e1f2-3a4b-5c6d-7e8f-a9b0c1d2e3f4
# ╟─d0e1f2a3-4b5c-6d7e-8f9a-b0c1d2e3f4a5
# ╟─00112233-4455-6677-8899-aabbccddeeff
# ╟─e1f2a3b4-5c6d-7e8f-9a0b-c1d2e3f4a5b6
