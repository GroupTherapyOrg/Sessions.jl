### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 66ef225a-dd9b-4b36-880c-5e777688f37a
using Markdown

# ╔═╡ f7a1b2c3-4d5e-6f78-9a0b-c1d2e3f4a5b6
md"""
# Welcome to Sessions.jl

A **reactive notebook** for Julia, built for the terminal.

## Features

- Reactive execution — cells re-run when dependencies change
- Pluto-compatible `.jl` file format
- Rich output: *markdown*, tables, and more

### Getting Started

Try editing a cell and pressing `Ctrl+R` to run it!

> "The best way to predict the future is to invent it." — Alan Kay
"""

# ╔═╡ 5ea37984-1433-4bb8-bff0-1784bbf52986
# using SessionsUI: @bind, Slider

# ╔═╡ 0b7a9ca3-5430-4e6a-9894-cd2339447be5
md"""
### Damped Ripple Surface

A 3D surface plot of `cos(ω√(x²+y²)) · e^(−0.3√(x²+y²))` — a radial ripple with exponential decay. The slider controls the wave frequency ω.

- **2–4** — smooth dome
- **8–12** — concentric ripples
- **16–20** — fine oscillations
"""

# ╔═╡ 1a2b3c4d-5e6f-7a8b-9c0d-e1f2a3b4c5d6
# @bind n Slider(2:20, default = 8)

# ╔═╡ 3d413fde-745c-4222-836a-24e5a6e7a481
# surfaceplot(-2:0.05:2, -2:0.05:2, (x, y) -&amp;gt; cos(n / 3 * sqrt(x^2 + y^2)) * exp(-0.3 * sqrt(x^2 + y^2)); width = 50, height = 20, title = &amp;quot;$(n)-fold ripple&amp;quot;)

# ╔═╡ 6e7bfb3a-23f5-499a-92b3-66207a5d898f
function add_2(x)
    return x + 10
end

# ╔═╡ 4eeecaeb-7813-4abc-8ed3-8a98d6a29e69
add_2(20)

# ╔═╡ 16b64a46-205f-45e0-839a-79ae9d0398ce
add_2(40)

# ╔═╡ 00000001-0000-0000-0000-000000000001
x = 20

# ╔═╡ 00000002-0000-0000-0000-000000000002
y = x + 42

# ╔═╡ 00000003-0000-0000-0000-000000000003
z = x * y

# ╔═╡ d0af9a99-dfe9-4f7a-b2a2-2a72241e77d7
a = x + y + z

# ╔═╡ d8f99fd1-c355-4ea8-b049-fe02fef97966
b = a^2

# ╔═╡ bc4437d0-89f5-4862-8c07-32cf149cb296
c = string("Result: ", b)

# ╔═╡ a6194bff-a34c-4e43-b2d7-e62997ccbf34
begin
    l = 10
    sleep(4)
end

# ╔═╡ 2c624f59-53d4-462a-8ed1-fb6a0d982c64
begin
    m = 2 * l
    sleep(2)
end

# ╔═╡ b236809c-50e5-45e4-8158-f41bad0e9103
md"""

# Heading 1

## Heading 2

### Heading 3

#### Heading 4

**Bold**

Normal

1. Line

* Bullet
"""

# ╔═╡ bc9c0418-fe44-47a5-a7fa-c6c26c776d3c
function strict_undef()
    println(i)  # Variable `i` is used before it is defined (JETLS lowering/undef-local-var)
    # Severity: Warning (strict undef)
    i = 1       # RelatedInformation: `i` is defined here
    return i
end

# ╔═╡ 0ab3d0c8-b8c7-4723-8d53-e50d221ec3a7

# ╔═╡ 265a22e7-9448-4e94-a667-bcbed2268af6

# ╔═╡ Cell order:
# ╟─f7a1b2c3-4d5e-6f78-9a0b-c1d2e3f4a5b6
# ╠═66ef225a-dd9b-4b36-880c-5e777688f37a
# ╠═5ea37984-1433-4bb8-bff0-1784bbf52986
# ╠═0b7a9ca3-5430-4e6a-9894-cd2339447be5
# ╠═1a2b3c4d-5e6f-7a8b-9c0d-e1f2a3b4c5d6
# ╠═3d413fde-745c-4222-836a-24e5a6e7a481
# ╠═6e7bfb3a-23f5-499a-92b3-66207a5d898f
# ╠═4eeecaeb-7813-4abc-8ed3-8a98d6a29e69
# ╠═16b64a46-205f-45e0-839a-79ae9d0398ce
# ╠═00000001-0000-0000-0000-000000000001
# ╠═00000002-0000-0000-0000-000000000002
# ╠═00000003-0000-0000-0000-000000000003
# ╠═d0af9a99-dfe9-4f7a-b2a2-2a72241e77d7
# ╠═d8f99fd1-c355-4ea8-b049-fe02fef97966
# ╠═bc4437d0-89f5-4862-8c07-32cf149cb296
# ╠═a6194bff-a34c-4e43-b2d7-e62997ccbf34
# ╠═2c624f59-53d4-462a-8ed1-fb6a0d982c64
# ╟─b236809c-50e5-45e4-8158-f41bad0e9103
# ╠═bc9c0418-fe44-47a5-a7fa-c6c26c776d3c
# ╠═0ab3d0c8-b8c7-4723-8d53-e50d221ec3a7
# ╠═265a22e7-9448-4e94-a667-bcbed2268af6
