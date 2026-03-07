### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ aa11bb22-cc33-dd44-ee55-ff6677889900
using Markdown

# ╔═╡ bb22cc33-dd44-ee55-ff66-778899001122
md"""
# Interactive DataFrame Explorer

Explore tabular data interactively — **click** on the table to enter DataTable mode, then:

- **↑/↓** — navigate rows
- **1–9** — sort by column
- **Enter** — view row detail
- **Escape** — exit DataTable mode
"""

# ╔═╡ cc33dd44-ee55-ff66-7788-99aabbccdd00
md"""
### Planets of the Solar System

A table of planetary data. Click on the table to explore!
"""

# ╔═╡ dd44ee55-ff66-7788-99aa-bbccddee0011
planets = [
    (name="Mercury", distance_au=0.39, radius_km=2440, mass_earth=0.055, moons=0, type="Rocky"),
    (name="Venus",   distance_au=0.72, radius_km=6052, mass_earth=0.815, moons=0, type="Rocky"),
    (name="Earth",   distance_au=1.00, radius_km=6371, mass_earth=1.000, moons=1, type="Rocky"),
    (name="Mars",    distance_au=1.52, radius_km=3390, mass_earth=0.107, moons=2, type="Rocky"),
    (name="Jupiter", distance_au=5.20, radius_km=69911, mass_earth=317.8, moons=95, type="Gas Giant"),
    (name="Saturn",  distance_au=9.54, radius_km=58232, mass_earth=95.16, moons=146, type="Gas Giant"),
    (name="Uranus",  distance_au=19.2, radius_km=25362, mass_earth=14.54, moons=28, type="Ice Giant"),
    (name="Neptune", distance_au=30.1, radius_km=24622, mass_earth=17.15, moons=16, type="Ice Giant"),
]

# ╔═╡ ee55ff66-7788-99aa-bbcc-ddeeff001122
md"""
### Element Data

The first 20 elements of the periodic table with atomic properties.
"""

# ╔═╡ ff667788-99aa-bbcc-ddee-ff0011223344
elements = [
    (Z=1,  symbol="H",  name="Hydrogen",   mass=1.008,   group=1,  period=1, category="Nonmetal"),
    (Z=2,  symbol="He", name="Helium",     mass=4.003,   group=18, period=1, category="Noble gas"),
    (Z=3,  symbol="Li", name="Lithium",    mass=6.941,   group=1,  period=2, category="Alkali metal"),
    (Z=4,  symbol="Be", name="Beryllium",  mass=9.012,   group=2,  period=2, category="Alkaline earth"),
    (Z=5,  symbol="B",  name="Boron",      mass=10.81,   group=13, period=2, category="Metalloid"),
    (Z=6,  symbol="C",  name="Carbon",     mass=12.01,   group=14, period=2, category="Nonmetal"),
    (Z=7,  symbol="N",  name="Nitrogen",   mass=14.01,   group=15, period=2, category="Nonmetal"),
    (Z=8,  symbol="O",  name="Oxygen",     mass=16.00,   group=16, period=2, category="Nonmetal"),
    (Z=9,  symbol="F",  name="Fluorine",   mass=19.00,   group=17, period=2, category="Halogen"),
    (Z=10, symbol="Ne", name="Neon",       mass=20.18,   group=18, period=2, category="Noble gas"),
    (Z=11, symbol="Na", name="Sodium",     mass=22.99,   group=1,  period=3, category="Alkali metal"),
    (Z=12, symbol="Mg", name="Magnesium",  mass=24.31,   group=2,  period=3, category="Alkaline earth"),
    (Z=13, symbol="Al", name="Aluminum",   mass=26.98,   group=13, period=3, category="Post-transition"),
    (Z=14, symbol="Si", name="Silicon",    mass=28.09,   group=14, period=3, category="Metalloid"),
    (Z=15, symbol="P",  name="Phosphorus", mass=30.97,   group=15, period=3, category="Nonmetal"),
    (Z=16, symbol="S",  name="Sulfur",     mass=32.07,   group=16, period=3, category="Nonmetal"),
    (Z=17, symbol="Cl", name="Chlorine",   mass=35.45,   group=17, period=3, category="Halogen"),
    (Z=18, symbol="Ar", name="Argon",      mass=39.95,   group=18, period=3, category="Noble gas"),
    (Z=19, symbol="K",  name="Potassium",  mass=39.10,   group=1,  period=4, category="Alkali metal"),
    (Z=20, symbol="Ca", name="Calcium",    mass=40.08,   group=2,  period=4, category="Alkaline earth"),
]

# ╔═╡ 11223344-5566-7788-99aa-bbccddeeff11
md"""
### Slider-Driven Table

Use the slider to control how many rows are generated.
"""

# ╔═╡ 22334455-6677-8899-aabb-ccddeeff0011
@bind n_rows Slider(5:5:50, default=15)

# ╔═╡ 33445566-7788-99aa-bbcc-ddeeff001100
[(i=i, square=i^2, cube=i^3, sqrt=round(sqrt(i); digits=3), even=iseven(i)) for i in 1:n_rows]

# ╔═╡ Cell order:
# ╠═aa11bb22-cc33-dd44-ee55-ff6677889900
# ╟─bb22cc33-dd44-ee55-ff66-778899001122
# ╟─cc33dd44-ee55-ff66-7788-99aabbccdd00
# ╠═dd44ee55-ff66-7788-99aa-bbccddee0011
# ╟─ee55ff66-7788-99aa-bbcc-ddeeff001122
# ╠═ff667788-99aa-bbcc-ddee-ff0011223344
# ╟─11223344-5566-7788-99aa-bbccddeeff11
# ╟─22334455-6677-8899-aabb-ccddeeff0011
# ╠═33445566-7788-99aa-bbcc-ddeeff001100
