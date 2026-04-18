### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 30000000-0000-0000-0000-000000000000
# ╠═╡ show_logs = false
begin
    import Pkg
    Pkg.activate(mktempdir())
    Pkg.add(["Markdown", "Dates"])
end

# ╔═╡ 30000000-0000-0000-0000-00000000000f
using Markdown

# ╔═╡ 30000000-0000-0000-0000-00000000000b
using Dates

# ╔═╡ 30000000-0000-0000-0000-000000000001
md"""
# Markdown

Everything Julia's built-in `Markdown` module understands — plus live
interpolation, syntax-highlighted code, LaTeX math, and admonition
cards.
"""

# ╔═╡ 30000000-0000-0000-0000-000000000002
md"""
## Text & lists

You can write **bold**, *italic*, ***bold italic***, `inline code`, and
~~strikethrough~~ all in the natural way. Inline code is great for
keyboard shortcuts: `Ctrl+Enter` to run a cell, `Shift+Enter` to run
and advance, `Ctrl+S` to save.

Bullet list:

- Reactive execution — cells re-run when their dependencies change
- Pluto-compatible `.jl` file format — portable between notebook tools
- Rich output: markdown, tables, images, plots, custom HTML

Numbered list:

1. Open the file explorer
2. Pick a notebook
3. Edit any cell and press `Ctrl+Enter`
"""

# ╔═╡ 30000000-0000-0000-0000-000000000003
md"""
## Quotes & admonitions

> "The best way to predict the future is to invent it."
> — Alan Kay

!!! info "Hidden cells"
    Hidden markdown cells are marked `╟─` in the source `.jl` file.
    Visible code cells are marked `╠═`. Sessions hides markdown by
    default because you usually want to see the rendered output, not
    the source.

!!! warning "Dependency order, not source order"
    Cells run in topological order of their data dependencies, not
    the order they appear in the file. Sessions figures out the
    topology automatically — just like Pluto.

!!! danger "Don't add heavy packages mid-notebook"
    Put `Pkg.add` in the first cell so the full re-run path stays
    fast. Resolving a 40-dep package halfway through a notebook stalls
    every dependent cell.
"""

# ╔═╡ 30000000-0000-0000-0000-000000000004
md"""
## Code & math

Fenced code blocks with language tags get syntax highlighting:

```julia
function fib(n)
    n < 2 && return n
    fib(n - 1) + fib(n - 2)
end
```

Bare fences pass through unstyled — useful for shell or plain text:

```
\$ julia +1.12 --project=. app.jl dev
```

Inline math via double-backticks: ``e^{iπ} + 1 = 0`` (Euler's identity).

Display math:

``\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}``

Anything LaTeX understands works: ``\\sum_{k=0}^{\\infty} \\frac{x^k}{k!}``.
The renderer is MathJax under the hood.
"""

# ╔═╡ 30000000-0000-0000-0000-000000000005
md"""
## Tables & links

| Symbol | Meaning           | Example          |
|:------:|:------------------|:-----------------|
| `╠═`   | visible code cell | `using Markdown` |
| `╟─`   | hidden / markdown | `md"# Title"`    |
| `🔁`   | reactive re-run   | bonds, cell deps |

Alignment follows the `:` placement in the header separator. Find
Sessions on [GitHub](https://github.com/GroupTherapyOrg/Sessions.jl).
Inline footnotes[^fmt] keep asides out of the main flow.

[^fmt]: Sessions mirrors Pluto's `.jl` notebook format so notebooks are
    portable between the two.
"""

# ╔═╡ 30000000-0000-0000-0000-000000000006
md"""
## Output inspection

Sessions inspects most Julia values automatically. The cells below
render a few samples — toggle the eye on each to see the source.
"""

# ╔═╡ 30000000-0000-0000-0000-000000000007
2^100

# ╔═╡ 30000000-0000-0000-0000-000000000008
Dict(
    :name => "Sessions.jl",
    :version => v"0.1.0",
    :status => :alpha,
    :langs => ["Julia", "JavaScript", "WASM"],
)

# ╔═╡ 30000000-0000-0000-0000-000000000009
(name = "Alice", age = 30, roles = [:admin, :editor], active = true)

# ╔═╡ 30000000-0000-0000-0000-00000000000a
md"""
## Errors

When a cell throws, Sessions renders the error inline with the
exception type, the message, and a collapsed stack trace. Click the
trace to expand it. The cell below deliberately throws — it's the
same rendering a typo in your own code would produce.
"""

# ╔═╡ 30000000-0000-0000-0000-00000000000c
sqrt(-1)

# ╔═╡ 30000000-0000-0000-0000-00000000000d
md"""
!!! warning "WASM compile errors look different"
    In published notebooks, some cells compile to WebAssembly. If
    WasmTarget can't lower a cell (an unsupported Base method, a
    package with no WASM coverage), Therapy skips WASM emission for
    that `@island` and paints a red **'⚠ WASM compile failed'**
    banner over the cell at runtime. The cell's last known output
    still renders as static SSR, but interactive updates from
    upstream bonds stop propagating to it. Sibling islands keep
    hydrating normally.
"""

# ╔═╡ Cell order:
# ╠═30000000-0000-0000-0000-000000000000
# ╠═30000000-0000-0000-0000-00000000000f
# ╠═30000000-0000-0000-0000-00000000000b
# ╟─30000000-0000-0000-0000-000000000001
# ╟─30000000-0000-0000-0000-000000000002
# ╟─30000000-0000-0000-0000-000000000003
# ╟─30000000-0000-0000-0000-000000000004
# ╟─30000000-0000-0000-0000-000000000005
# ╟─30000000-0000-0000-0000-000000000006
# ╠═30000000-0000-0000-0000-000000000007
# ╠═30000000-0000-0000-0000-000000000008
# ╠═30000000-0000-0000-0000-000000000009
# ╟─30000000-0000-0000-0000-00000000000a
# ╠═30000000-0000-0000-0000-00000000000c
# ╟─30000000-0000-0000-0000-00000000000d
