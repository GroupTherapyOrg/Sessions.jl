### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 10000000-0000-0000-0000-000000000000
# ╠═╡ show_logs = false
# Notebook-local environment so this notebook is self-contained — nothing
# it imports leaks into the host project. Markdown + Dates are stdlibs;
# Sessions worker envs don't auto-include stdlibs, so we Pkg.add them.
begin
    import Pkg
    Pkg.activate(mktempdir())
    Pkg.add(["Markdown", "Dates"])
end

# ╔═╡ 10000000-0000-0000-0000-00000000000f
using Markdown

# ╔═╡ 10000000-0000-0000-0000-00000000000b
using Dates

# ╔═╡ 10000000-0000-0000-0000-000000000001
md"""
# Welcome to **Sessions.jl**

A reactive Julia notebook for the terminal *and* the browser.

This notebook is a tour of the **markdown features** Sessions supports out of
the box — modeled on
[Pluto's basic markdown showcase](https://featured.plutojl.org/basic/markdown).
Every cell below is hidden, so what you see is the rendered output. Toggle
the eye icon on the left of any cell to see the source.
"""

# ╔═╡ 10000000-0000-0000-0000-000000000002
md"""
---

## Headings

Six levels of `#`, just like ordinary markdown.

# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
"""

# ╔═╡ 10000000-0000-0000-0000-000000000003
md"""
## Text formatting

You can write **bold**, *italic*, ***bold italic***, `inline code`, and
~~strikethrough~~ all in the natural way.

Inline code is great for keyboard shortcuts: press `Ctrl+Enter` to run the
current cell, `Shift+Enter` to run-and-advance, or `Ctrl+S` to save.
"""

# ╔═╡ 10000000-0000-0000-0000-000000000004
md"""
## Lists

A bullet list:

- Reactive execution — cells re-run when their dependencies change
- Pluto-compatible `.jl` file format
- Rich output: markdown, tables, images, plots

A numbered list:

1. Open the file explorer (the folder icon, top-left)
2. Pick a notebook
3. Edit any cell and press `Ctrl+Enter`
"""

# ╔═╡ 10000000-0000-0000-0000-000000000005
md"""
## Blockquotes & admonitions

> "The best way to predict the future is to invent it."
> — Alan Kay

!!! info "Tip"
    Hidden cells (the markdown ones in this notebook) are marked with a
    `╟─` in the source `.jl` file. Visible code cells are marked with `╠═`.

!!! warning "Heads up"
    Cells run in **dependency order**, not source order. Sessions figures out
    the topology automatically — same as Pluto.

!!! danger "Don't"
    `Pkg.add` heavy packages mid-cell. Add them once at the top of the
    notebook so the full re-run path stays fast.
"""

# ╔═╡ 10000000-0000-0000-0000-000000000006
md"""
## Code blocks

You get fenced blocks with language tags:

```julia
function fib(n)
    n < 2 && return n
    return fib(n - 1) + fib(n - 2)
end
```

…and bare ones for shell or plain text:

```
$ julia +1.12 --project=. app.jl dev welcome.jl
```
"""

# ╔═╡ 10000000-0000-0000-0000-000000000007
md"""
## Math

Inline math via double-backticks: ``e^{i\pi} + 1 = 0`` (Euler's identity).

Display math via `…`:

∫−∞∞e−x2dx=π

The renderer is MathJax under the hood, so anything LaTeX understands works:
``\sum_{k=0}^{\infty} \frac{x^k}{k!}``.
"""

# ╔═╡ 10000000-0000-0000-0000-000000000008
md"""
## Tables

| Symbol | Meaning            | Example                  |
|:------:|:-------------------|:-------------------------|
| `╠═`   | visible code cell  | `using Markdown`         |
| `╟─`   | hidden / markdown  | `md"# Title"`            |
| `🔁`   | reactive re-run    | bonds, cell deps         |

Alignment is controlled by the `:` placement in the header separator.
"""

# ╔═╡ 10000000-0000-0000-0000-000000000009
md"""
## Links & footnotes

Find Sessions on [GitHub](https://github.com/GroupTherapyOrg/Sessions.jl) or
read the [Pluto markdown reference][pluto] for a wider tour.

[pluto]: https://featured.plutojl.org/basic/markdown

You can also footnote inline like this[^why-pluto-style] for asides.

[^why-pluto-style]: We mirror Pluto's notebook-file format so notebooks are
    portable between the two.
"""

# ╔═╡ 10000000-0000-0000-0000-00000000000a
md"""
## Live values

Markdown cells can interpolate live Julia with `$(…)`:

The current Julia version is **$(VERSION)**, the day of the week is
**$(Dates.dayname(Dates.today()))**, and 2 + 2 = $(2 + 2).
"""

# ╔═╡ 10000000-0000-0000-0000-00000000000c
greeting = "Hello, Sessions.jl 👋"

# ╔═╡ 10000000-0000-0000-0000-000000000010
md"""
---

## Output inspection

Sessions inspects most Julia values automatically. Below is a tour of
the kinds of output you'll see — every cell is hidden by default, toggle
the eye on the left to peek at the source.
"""

# ╔═╡ 10000000-0000-0000-0000-000000000011
md"### Numbers"

# ╔═╡ 10000000-0000-0000-0000-000000000012
2^100

# ╔═╡ 10000000-0000-0000-0000-000000000013
md"### Strings"

# ╔═╡ 10000000-0000-0000-0000-000000000014
"The quick brown fox jumps over the lazy dog."

# ╔═╡ 10000000-0000-0000-0000-000000000015
md"### Vectors and ranges"

# ╔═╡ 10000000-0000-0000-0000-000000000016
xx = collect(1:25)

# ╔═╡ 10000000-0000-0000-0000-000000000017
md"### Dictionaries"

# ╔═╡ 10000000-0000-0000-0000-000000000018
Dict(
    :name => "Sessions.jl",
    :version => v"0.1.0",
    :status => :alpha,
    :stars => 0,
    :langs => ["Julia", "JavaScript", "WASM"],
)

# ╔═╡ 10000000-0000-0000-0000-000000000019
md"### Tuples and named tuples"

# ╔═╡ 10000000-0000-0000-0000-00000000001a
(1, "two", 3.0, :four, [5, 6])

# ╔═╡ 10000000-0000-0000-0000-00000000001b
(name = "Alice", age = 30, roles = [:admin, :editor], active = true)

# ╔═╡ 10000000-0000-0000-0000-00000000001c
md"### Structs"

# ╔═╡ 10000000-0000-0000-0000-00000000001d
struct Point
    x::Float64
    y::Float64
end

# ╔═╡ 10000000-0000-0000-0000-00000000001e
Point(3.14, 2.71)

# ╔═╡ 10000000-0000-0000-0000-00000000001f
md"### Sets"

# ╔═╡ 10000000-0000-0000-0000-000000000020
Set([rand(100)...])

# ╔═╡ 10000000-0000-0000-0000-000000000021
md"### Errors"

# ╔═╡ 10000000-0000-0000-0000-000000000022
md"""Errors render with the exception type, message, and a collapsed
stack trace — click the trace to expand. Try uncommenting the line below:"""

# ╔═╡ 10000000-0000-0000-0000-000000000023
sqrt(-1)

# ╔═╡ 10000000-0000-0000-0000-00000000000d
md"""
---

That's the tour. Try editing any of the hidden cells (toggle the eye on the
left) to see the markdown source — and welcome aboard.
"""

# ╔═╡ Cell order:
# ╟─10000000-0000-0000-0000-000000000001
# ╠═10000000-0000-0000-0000-000000000000
# ╠═10000000-0000-0000-0000-00000000000f
# ╠═10000000-0000-0000-0000-00000000000b
# ╟─10000000-0000-0000-0000-000000000002
# ╟─10000000-0000-0000-0000-000000000003
# ╟─10000000-0000-0000-0000-000000000004
# ╟─10000000-0000-0000-0000-000000000005
# ╟─10000000-0000-0000-0000-000000000006
# ╟─10000000-0000-0000-0000-000000000007
# ╟─10000000-0000-0000-0000-000000000008
# ╟─10000000-0000-0000-0000-000000000009
# ╟─10000000-0000-0000-0000-00000000000a
# ╠═10000000-0000-0000-0000-00000000000c
# ╟─10000000-0000-0000-0000-000000000010
# ╟─10000000-0000-0000-0000-000000000011
# ╠═10000000-0000-0000-0000-000000000012
# ╟─10000000-0000-0000-0000-000000000013
# ╠═10000000-0000-0000-0000-000000000014
# ╟─10000000-0000-0000-0000-000000000015
# ╠═10000000-0000-0000-0000-000000000016
# ╟─10000000-0000-0000-0000-000000000017
# ╠═10000000-0000-0000-0000-000000000018
# ╟─10000000-0000-0000-0000-000000000019
# ╠═10000000-0000-0000-0000-00000000001a
# ╠═10000000-0000-0000-0000-00000000001b
# ╟─10000000-0000-0000-0000-00000000001c
# ╠═10000000-0000-0000-0000-00000000001d
# ╠═10000000-0000-0000-0000-00000000001e
# ╟─10000000-0000-0000-0000-00000000001f
# ╠═10000000-0000-0000-0000-000000000020
# ╟─10000000-0000-0000-0000-000000000021
# ╟─10000000-0000-0000-0000-000000000022
# ╠═10000000-0000-0000-0000-000000000023
# ╟─10000000-0000-0000-0000-00000000000d
