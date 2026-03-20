### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 76fc12d5-6bdd-4d55-aa2f-bfe8bf110ea7
begin
    import Pkg
    Pkg.activate(mktempdir())
    Pkg.add("DataFrames")
    Pkg.add("Statistics")
end

# ╔═╡ aa11bb22-cc33-dd44-ee55-ff6677889900
using Markdown

# ╔═╡ a0b1c2d3-e4f5-6789-abcd-ef0123456789
using DataFrames

# ╔═╡ bb22cc33-dd44-ee55-ff66-778899001122
md"""
# Interactive DataFrame Explorer

This notebook demonstrates rich table rendering with **DataFrames.jl**.

DataFrames produce beautiful HTML tables via their built-in `text/html` MIME method — the same output you see in Pluto and Jupyter.
"""

# ╔═╡ cc33dd44-ee55-ff66-7788-99aabbccdd00
md"""
### Planets of the Solar System
"""

# ╔═╡ dd44ee55-ff66-7788-99aa-bbccddee0011
planets = DataFrame(
    name = ["Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"],
    distance_au = [0.39, 0.72, 1.00, 1.52, 5.20, 9.54, 19.2, 30.1],
    radius_km = [2440, 6052, 6371, 3390, 69911, 58232, 25362, 24622],
    mass_earth = [0.055, 0.815, 1.000, 0.107, 317.8, 95.16, 14.54, 17.15],
    moons = [0, 0, 1, 2, 95, 146, 28, 16],
    type = ["Rocky", "Rocky", "Rocky", "Rocky", "Gas Giant", "Gas Giant", "Ice Giant", "Ice Giant"],
    has_rings = [false, false, false, false, true, true, true, true]
)

# ╔═╡ ee55ff66-7788-99aa-bbcc-ddeeff001122
md"""
### Filtering & Transformations

Filter gas giants and compute derived columns:
"""

# ╔═╡ f1a2b3c4-d5e6-7890-abcd-ef1234567890
gas_giants = filter(row -> row.mass_earth > 10, planets)

# ╔═╡ a2b3c4d5-e6f7-8901-bcde-f12345678901
transform(planets, :radius_km => (r -> round.(r ./ 6371, digits=2)) => :radius_earth)

# ╔═╡ ee55ff66-7788-99aa-bbcc-ddeeff001133
md"""
### Element Data

The first 20 elements with atomic properties:
"""

# ╔═╡ ff667788-99aa-bbcc-ddee-ff0011223344
elements = DataFrame(
    Z = 1:20,
    symbol = ["H", "He", "Li", "Be", "B", "C", "N", "O", "F", "Ne",
              "Na", "Mg", "Al", "Si", "P", "S", "Cl", "Ar", "K", "Ca"],
    name = ["Hydrogen", "Helium", "Lithium", "Beryllium", "Boron", "Carbon",
            "Nitrogen", "Oxygen", "Fluorine", "Neon", "Sodium", "Magnesium",
            "Aluminum", "Silicon", "Phosphorus", "Sulfur", "Chlorine", "Argon",
            "Potassium", "Calcium"],
    mass = [1.008, 4.003, 6.941, 9.012, 10.81, 12.01, 14.01, 16.00,
            19.00, 20.18, 22.99, 24.31, 26.98, 28.09, 30.97, 32.07,
            35.45, 39.95, 39.10, 40.08],
    category = ["Nonmetal", "Noble gas", "Alkali metal", "Alkaline earth",
                "Metalloid", "Nonmetal", "Nonmetal", "Nonmetal", "Halogen",
                "Noble gas", "Alkali metal", "Alkaline earth", "Post-transition",
                "Metalloid", "Nonmetal", "Nonmetal", "Halogen", "Noble gas",
                "Alkali metal", "Alkaline earth"]
)

# ╔═╡ b3c4d5e6-f7a8-9012-cdef-234567890123
md"""
### GroupBy & Aggregation

Group elements by category and summarize:
"""

# ╔═╡ c4d5e6f7-a8b9-0123-def0-345678901234
combine(groupby(elements, :category), nrow => :count, :mass => mean => :avg_mass)

# ╔═╡ d5e6f7a8-b9c0-1234-ef01-456789012345
md"""
### Sorting & Selection

Sort planets by mass (descending) and select key columns:
"""

# ╔═╡ e6f7a8b9-c0d1-2345-f012-567890123456
sort(select(planets, :name, :mass_earth, :moons, :type), :mass_earth, rev=true)

# ╔═╡ f7a8b9c0-d1e2-3456-0123-678901234567
md"""
### Descriptive Statistics
"""

# ╔═╡ 08b9c0d1-e2f3-4567-1234-789012345678
describe(planets[:, [:distance_au, :radius_km, :mass_earth, :moons]])

# ╔═╡ 82a0dde9-b888-4332-9bfd-3f069fef4e46
using Statistics

# ╔═╡ Cell order:
# ╠═76fc12d5-6bdd-4d55-aa2f-bfe8bf110ea7
# ╠═82a0dde9-b888-4332-9bfd-3f069fef4e46
# ╠═aa11bb22-cc33-dd44-ee55-ff6677889900
# ╠═a0b1c2d3-e4f5-6789-abcd-ef0123456789
# ╟─bb22cc33-dd44-ee55-ff66-778899001122
# ╟─cc33dd44-ee55-ff66-7788-99aabbccdd00
# ╠═dd44ee55-ff66-7788-99aa-bbccddee0011
# ╟─ee55ff66-7788-99aa-bbcc-ddeeff001122
# ╠═f1a2b3c4-d5e6-7890-abcd-ef1234567890
# ╠═a2b3c4d5-e6f7-8901-bcde-f12345678901
# ╟─ee55ff66-7788-99aa-bbcc-ddeeff001133
# ╠═ff667788-99aa-bbcc-ddee-ff0011223344
# ╟─b3c4d5e6-f7a8-9012-cdef-234567890123
# ╠═c4d5e6f7-a8b9-0123-def0-345678901234
# ╟─d5e6f7a8-b9c0-1234-ef01-456789012345
# ╠═e6f7a8b9-c0d1-2345-f012-567890123456
# ╟─f7a8b9c0-d1e2-3456-0123-678901234567
# ╠═08b9c0d1-e2f3-4567-1234-789012345678
