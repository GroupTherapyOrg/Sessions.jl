### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 00000010-0000-0000-0000-000000000001
using Markdown

# ╔═╡ 00000010-0000-0000-0000-000000000002
using SessionsUI: @bind, BoundSlider

# ╔═╡ 00000010-0000-0000-0000-000000000003
import CairoMakie as Mke

# ╔═╡ 00000010-0000-0000-0000-000000000004
md"""
# Makie Interactive Plots

Backend-swappable: `import CairoMakie as Mke` for static (PNG), `import WGLMakie as Mke` for web (WebGL).

Each slider pre-renders all frames at build time — no server round-trip needed.
"""

# ╔═╡ 00000010-0000-0000-0000-000000000010
md"""
## Damped Ripple Surface

A 3D surface: `cos(w * r) * exp(-0.3r)` where `r = sqrt(x² + y²)`.

Drag the slider to change wave frequency **w**.
"""

# ╔═╡ 00000010-0000-0000-0000-000000000011
@bind w BoundSlider(2:2:16, default=6)

# ╔═╡ 00000010-0000-0000-0000-000000000012
let
    xs = range(-2, 2; length=60)
    ys = range(-2, 2; length=60)
    zs = [cos(w * sqrt(x^2 + y^2)) * exp(-0.3 * sqrt(x^2 + y^2)) for x in xs, y in ys]

    fig = Mke.Figure(; size=(480, 320))
    ax = Mke.Axis3(fig[1, 1]; title="w = $w ripple", xlabel="x", ylabel="y", zlabel="z")
    Mke.surface!(ax, xs, ys, zs; colormap=:magma)
    fig
end

# ╔═╡ 00000010-0000-0000-0000-000000000020
md"""
## Sine/Cosine Curves

Adjust the number of visible **periods**.
"""

# ╔═╡ 00000010-0000-0000-0000-000000000021
@bind periods BoundSlider(1:6, default=2)

# ╔═╡ 00000010-0000-0000-0000-000000000022
let
    x = range(0, periods * 2π; length=300)

    fig = Mke.Figure(; size=(560, 280))
    ax = Mke.Axis(fig[1, 1]; title="$(periods) period(s)", xlabel="x", ylabel="y")
    Mke.lines!(ax, x, sin.(x); label="sin(x)", linewidth=2)
    Mke.lines!(ax, x, cos.(x); label="cos(x)", linestyle=:dash, linewidth=2)
    Mke.axislegend(ax)
    fig
end

# ╔═╡ 00000010-0000-0000-0000-000000000030
md"""
## Heatmap

Slider controls frequency multiplier **k** in `sin(kx) * cos(ky)`.
"""

# ╔═╡ 00000010-0000-0000-0000-000000000031
@bind k BoundSlider(1:8, default=2)

# ╔═╡ 00000010-0000-0000-0000-000000000032
let
    xs = range(-π, π; length=100)
    ys = range(-π, π; length=100)
    zs = [sin(k * x) * cos(k * y) for x in xs, y in ys]

    fig = Mke.Figure(; size=(420, 360))
    ax = Mke.Axis(fig[1, 1]; title="sin($(k)x) · cos($(k)y)", xlabel="x", ylabel="y")
    Mke.heatmap!(ax, xs, ys, zs; colormap=:magma)
    Mke.Colorbar(fig[1, 2]; colormap=:magma, limits=(-1, 1))
    fig
end

# ╔═╡ 00000010-0000-0000-0000-000000000040
md"""
## Scatter Cloud

Slider controls point count **n**.
"""

# ╔═╡ 00000010-0000-0000-0000-000000000041
@bind n_pts BoundSlider(50:50:500, default=200)

# ╔═╡ 00000010-0000-0000-0000-000000000042
let
    x = randn(n_pts)
    y = randn(n_pts)
    c = sqrt.(x .^ 2 .+ y .^ 2)

    fig = Mke.Figure(; size=(420, 360))
    ax = Mke.Axis(fig[1, 1]; title="Scatter (n=$n_pts)", xlabel="x", ylabel="y")
    Mke.scatter!(ax, x, y; color=c, colormap=:magma, markersize=8)
    fig
end

# ╔═╡ Cell order:
# ╠═00000010-0000-0000-0000-000000000001
# ╠═00000010-0000-0000-0000-000000000002
# ╠═00000010-0000-0000-0000-000000000003
# ╟─00000010-0000-0000-0000-000000000004
# ╟─00000010-0000-0000-0000-000000000010
# ╟─00000010-0000-0000-0000-000000000011
# ╟─00000010-0000-0000-0000-000000000012
# ╟─00000010-0000-0000-0000-000000000020
# ╟─00000010-0000-0000-0000-000000000021
# ╟─00000010-0000-0000-0000-000000000022
# ╟─00000010-0000-0000-0000-000000000030
# ╟─00000010-0000-0000-0000-000000000031
# ╟─00000010-0000-0000-0000-000000000032
# ╟─00000010-0000-0000-0000-000000000040
# ╟─00000010-0000-0000-0000-000000000041
# ╟─00000010-0000-0000-0000-000000000042
