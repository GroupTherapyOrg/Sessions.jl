### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 50000000-0000-0000-0000-000000000000
# ╠═╡ show_logs = false
begin
    import Pkg
    Pkg.activate(mktempdir())
    Pkg.add([
        Pkg.PackageSpec(url = "https://github.com/GroupTherapyOrg/WasmTarget.jl.git"),
        Pkg.PackageSpec(url = "https://github.com/GroupTherapyOrg/Sessions.jl.git",
                        subdir = "SessionsUI"),
        Pkg.PackageSpec(name = "Markdown"),
    ])
end

# ╔═╡ 50000000-0000-0000-0000-00000000000f
using Markdown

# ╔═╡ 50000000-0000-0000-0000-000000000002
using SessionsUI: @bind, BoundSlider

# ╔═╡ 50000000-0000-0000-0000-000000000001
md"""
# Reactivity

Two sliders feed two memos — sum and product. No callback wiring, no
subscription plumbing. The reactive analyzer reads each cell body at
extract time, spots `a` and `b` as bound signals, and compiles a
`create_memo(() -> a() + b())` (and the same for the product).
"""

# ╔═╡ 50000000-0000-0000-0000-000000000003
md"""
## Two sliders, two memos
"""

# ╔═╡ 50000000-0000-0000-0000-000000000004
@bind a BoundSlider(0:50; default=10)

# ╔═╡ 50000000-0000-0000-0000-000000000005
@bind b BoundSlider(0:50; default=20)

# ╔═╡ 50000000-0000-0000-0000-000000000006
a + b

# ╔═╡ 50000000-0000-0000-0000-000000000007
a * b

# ╔═╡ 50000000-0000-0000-0000-000000000008
md"""
## Cross-island signals

!!! info "How `a` and `b` reach both memos"
    Each bond and each memo is its own `@island`, independently
    compiled and independently hydrated. The shared `a` and `b`
    signals live at module scope as
    `const _a_signal = create_signal(10)` and get captured by
    closure in every island that reads them. Therapy's analyzer
    detects the shared names and emits a tiny pub/sub bridge
    (`window.__therapy.set('a', v)`) so a slider move broadcasts to
    every subscribed island in roughly one animation frame.
"""

# ╔═╡ 50000000-0000-0000-0000-000000000009
md"""
## Why per-cell islands

!!! tip "Isolation matters"
    If we packed every reactive cell into one monolithic island, a
    single cell WasmTarget can't compile (a `DataFrame` memo, say)
    would drop the whole notebook back to static SSR. Per-cell
    islands let the sum and product memos here keep hydrating even
    if a sibling cell bails out with a red compile-failed banner.
"""

# ╔═╡ Cell order:
# ╠═50000000-0000-0000-0000-000000000000
# ╠═50000000-0000-0000-0000-00000000000f
# ╠═50000000-0000-0000-0000-000000000002
# ╟─50000000-0000-0000-0000-000000000001
# ╟─50000000-0000-0000-0000-000000000003
# ╟─50000000-0000-0000-0000-000000000004
# ╟─50000000-0000-0000-0000-000000000005
# ╠═50000000-0000-0000-0000-000000000006
# ╠═50000000-0000-0000-0000-000000000007
# ╟─50000000-0000-0000-0000-000000000008
# ╟─50000000-0000-0000-0000-000000000009
