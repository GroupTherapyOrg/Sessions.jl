### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ a1b2c3d4-e5f6-7890-abcd-ef1234567890
md"""
# Hello, Sessions.jl

Welcome to your first Sessions.jl notebook! This notebook demonstrates the basics of reactive notebooks in Julia.

Sessions.jl notebooks are **Pluto-compatible** — they use the same `.jl` file format and reactive execution model. You can write them in the terminal TUI or export them as static web pages like this one.
"""

# ╔═╡ b2c3d4e5-f6a7-8901-bcde-f12345678901
x = 1 + 1

# ╔═╡ c3d4e5f6-a7b8-9012-cdef-123456789012
greeting = "The answer is $(x)"

# ╔═╡ d4e5f6a7-b8c9-0123-defa-234567890123
md"""
## Reactive Execution

When you change a cell, Sessions.jl automatically re-runs all cells that depend on it. This is powered by **ExpressionExplorer.jl** and **PlutoDependencyExplorer.jl** from the Pluto ecosystem.

Try thinking of each cell as a node in a dependency graph — upstream changes flow downstream automatically.
"""

# ╔═╡ e5f6a7b8-c9d0-1234-efab-345678901234
function fibonacci(n)
	if n <= 1
		return n
	end
	a, b = 0, 1
	for _ in 2:n
		a, b = b, a + b
	end
	return b
end

# ╔═╡ f6a7b8c9-d0e1-2345-fabc-456789012345
fibonacci(10)

# ╔═╡ a7b8c9d0-e1f2-3456-abcd-567890123456
fib_sequence = [fibonacci(i) for i in 1:10]

# ╔═╡ Cell order:
# ╟─a1b2c3d4-e5f6-7890-abcd-ef1234567890
# ╠═b2c3d4e5-f6a7-8901-bcde-f12345678901
# ╠═c3d4e5f6-a7b8-9012-cdef-123456789012
# ╟─d4e5f6a7-b8c9-0123-defa-234567890123
# ╠═e5f6a7b8-c9d0-1234-efab-345678901234
# ╠═f6a7b8c9-d0e1-2345-fabc-456789012345
# ╠═a7b8c9d0-e1f2-3456-abcd-567890123456
