### A Pluto.jl notebook ###
# v0.19.0

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
# ╟─11223344-5566-7788-99aa-bbccddeeff00
# ╠═22334455-6677-8899-aabb-ccddeeff0011
# ╟─33445566-7788-99aa-bbcc-ddeeff001122
# ╠═44556677-8899-aabb-ccdd-eeff00112233
# ╠═55667788-99aa-bbcc-ddee-ff0011223344
# ╟─66778899-aabb-ccdd-eeff-001122334455
# ╠═77889900-aabb-ccdd-eeff-112233445566
