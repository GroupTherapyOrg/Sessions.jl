# ── Sessions.jl extracted notebook ─────────────────────────
#
# Source : /Users/daleblack/Documents/dev/GroupTherapyOrg/Sessions.jl/test/fixtures/welcome.jl
# Date   : 2026-04-17T10:32:36.667
#
# This file is a self-contained Therapy component. Cell SOURCE
# is preserved verbatim and rendered through a read-only
# CodeMirror editor (the docs site's Layout picks up every
# .cm-cell element on load + SPA navigation). Each cell value
# is computed once at module load and rendered through
# `Sessions.render_value` — the same MIME classifier the live
# IDE output pipeline uses, so Markdown/DataFrames/WasmPlot/
# SessionsUI.Bond all render identically to the IDE.
#
# Architecture:
#   - Cell chrome (cell-wrap > cell-body > [cell-out, cm-cell])
#     flows through `Sessions.render_published_cell` — single
#     source of truth with the live IDE's `render_cell`.
#   - Outer `function Welcome()` is plain Julia.
#     It just calls `render_published_notebook` with the cells
#     in document order; it always works regardless of WASM
#     compile state.
#   - Each @bind cell becomes a tiny @island that wraps the
#     SessionsUI widget. Bond signals are module-level shared
#     signals so cross-island sync is automatic.
#   - Each reactive cell becomes a tiny @island that captures
#     its upstream bond signals. v1 renders the frozen value
#     computed at module load (using the bond defaults). v2
#     re-executes the body in WASM as WasmTarget grows.
#
# Re-running `Sessions.extract_notebook` with the same out_path
# overwrites the file. Hand-edits survive until the next
# extraction, so prefer editing the source notebook fixture.
# ───────────────────────────────────────────────────────────

module WelcomeMod

    using Therapy: @island, create_signal, RawHtml
    using Sessions: render_value, render_published_cell, render_published_notebook
    using Markdown
    using Dates

    # ── Shared signals (one per @bind in the source) ──
    # (none)

    # ── Cell values (source preserved, evaluated at module load) ──
    # ── Cell 10000000-0000-0000-0000-000000000001 (static) ──
    const _cell__10000000_0000_0000_0000_000000000001 = try
        let
            md"""
            # Welcome to **Sessions.jl**
            
            A reactive Julia notebook for the terminal *and* the browser.
            
            This notebook is a tour of the **markdown features** Sessions supports out of
            the box — modeled on
            [Pluto's basic markdown showcase](https://featured.plutojl.org/basic/markdown).
            Every cell below is hidden, so what you see is the rendered output. Toggle
            the eye icon on the left of any cell to see the source.
            """
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000002 (static) ──
    const _cell__10000000_0000_0000_0000_000000000002 = try
        let
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
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000003 (static) ──
    const _cell__10000000_0000_0000_0000_000000000003 = try
        let
            md"""
            ## Text formatting
            
            You can write **bold**, *italic*, ***bold italic***, `inline code`, and
            ~~strikethrough~~ all in the natural way.
            
            Inline code is great for keyboard shortcuts: press `Ctrl+Enter` to run the
            current cell, `Shift+Enter` to run-and-advance, or `Ctrl+S` to save.
            """
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000004 (static) ──
    const _cell__10000000_0000_0000_0000_000000000004 = try
        let
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
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000006 (static) ──
    const _cell__10000000_0000_0000_0000_000000000006 = try
        let
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
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000007 (static) ──
    const _cell__10000000_0000_0000_0000_000000000007 = try
        let
            md"""
            ## Math
            
            Inline math via double-backticks: ``e^{i\pi} + 1 = 0`` (Euler's identity).
            
            Display math via `…`:
            
            ∫−∞∞e−x2dx=π
            
            The renderer is MathJax under the hood, so anything LaTeX understands works:
            ``\sum_{k=0}^{\infty} \frac{x^k}{k!}``.
            """
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000008 (static) ──
    const _cell__10000000_0000_0000_0000_000000000008 = try
        let
            md"""
            ## Tables
            
            | Symbol | Meaning            | Example                  |
            |:------:|:-------------------|:-------------------------|
            | `╠═`   | visible code cell  | `using Markdown`         |
            | `╟─`   | hidden / markdown  | `md"# Title"`            |
            | `🔁`   | reactive re-run    | bonds, cell deps         |
            
            Alignment is controlled by the `:` placement in the header separator.
            """
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000009 (static) ──
    const _cell__10000000_0000_0000_0000_000000000009 = try
        let
            md"""
            ## Links & footnotes
            
            Find Sessions on [GitHub](https://github.com/GroupTherapyOrg/Sessions.jl) or
            read the [Pluto markdown reference][pluto] for a wider tour.
            
            [pluto]: https://featured.plutojl.org/basic/markdown
            
            You can also footnote inline like this[^why-pluto-style] for asides.
            
            [^why-pluto-style]: We mirror Pluto's notebook-file format so notebooks are
                portable between the two.
            """
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-00000000000a (static) ──
    const _cell__10000000_0000_0000_0000_00000000000a = try
        let
            md"""
            ## Live values
            
            Markdown cells can interpolate live Julia with `$(…)`:
            
            The current Julia version is **$(VERSION)**, the day of the week is
            **$(Dates.dayname(Dates.today()))**, and 2 + 2 = $(2 + 2).
            """
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-00000000000c (static) ──
    const _cell__10000000_0000_0000_0000_00000000000c = try
        let
            greeting = "Hello, Sessions.jl 👋"
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000010 (static) ──
    const _cell__10000000_0000_0000_0000_000000000010 = try
        let
            md"""
            ---
            
            ## Output inspection
            
            Sessions inspects most Julia values automatically. Below is a tour of
            the kinds of output you'll see — every cell is hidden by default, toggle
            the eye on the left to peek at the source.
            """
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000011 (static) ──
    const _cell__10000000_0000_0000_0000_000000000011 = try
        let
            md"### Numbers"
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000012 (static) ──
    const _cell__10000000_0000_0000_0000_000000000012 = try
        let
            2^100
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000013 (static) ──
    const _cell__10000000_0000_0000_0000_000000000013 = try
        let
            md"### Strings"
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000014 (static) ──
    const _cell__10000000_0000_0000_0000_000000000014 = try
        let
            "The quick brown fox jumps over the lazy dog."
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000015 (static) ──
    const _cell__10000000_0000_0000_0000_000000000015 = try
        let
            md"### Vectors and ranges"
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000016 (static) ──
    const _cell__10000000_0000_0000_0000_000000000016 = try
        let
            xx = collect(1:25)
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000017 (static) ──
    const _cell__10000000_0000_0000_0000_000000000017 = try
        let
            md"### Dictionaries"
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000018 (static) ──
    const _cell__10000000_0000_0000_0000_000000000018 = try
        let
            Dict(
                :name => "Sessions.jl",
                :version => v"0.1.0",
                :status => :alpha,
                :stars => 0,
                :langs => ["Julia", "JavaScript", "WASM"],
            )
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000019 (static) ──
    const _cell__10000000_0000_0000_0000_000000000019 = try
        let
            md"### Tuples and named tuples"
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-00000000001a (static) ──
    const _cell__10000000_0000_0000_0000_00000000001a = try
        let
            (1, "two", 3.0, :four, [5, 6])
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-00000000001b (static) ──
    const _cell__10000000_0000_0000_0000_00000000001b = try
        let
            (name = "Alice", age = 30, roles = [:admin, :editor], active = true)
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-00000000001c (static) ──
    const _cell__10000000_0000_0000_0000_00000000001c = try
        let
            md"### Structs"
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-00000000001d (static) ──
    const _cell__10000000_0000_0000_0000_00000000001d = try
        let
            struct Point
                x::Float64
                y::Float64
            end
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-00000000001e (static) ──
    const _cell__10000000_0000_0000_0000_00000000001e = try
        let
            Point(3.14, 2.71)
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-00000000001f (static) ──
    const _cell__10000000_0000_0000_0000_00000000001f = try
        let
            md"### Sets"
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000020 (static) ──
    const _cell__10000000_0000_0000_0000_000000000020 = try
        let
            Set([rand(100)...])
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000021 (static) ──
    const _cell__10000000_0000_0000_0000_000000000021 = try
        let
            md"### Errors"
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000022 (static) ──
    const _cell__10000000_0000_0000_0000_000000000022 = try
        let
            md"""Errors render with the exception type, message, and a collapsed
            stack trace — click the trace to expand. Try uncommenting the line below:"""
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-000000000023 (static) ──
    const _cell__10000000_0000_0000_0000_000000000023 = try
        let
            sqrt(-1)
        end
    catch _e
        _e
    end
    # ── Cell 10000000-0000-0000-0000-00000000000d (static) ──
    const _cell__10000000_0000_0000_0000_00000000000d = try
        let
            md"""
            ---
            
            That's the tour. Try editing any of the hidden cells (toggle the eye on the
            left) to see the markdown source — and welcome aboard.
            """
        end
    catch _e
        _e
    end

    # (no bond / reactive cells — notebook is fully static)
    function Welcome()
        render_published_notebook(
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000001",
                source_code = "md\"\"\"\n# Welcome to **Sessions.jl**\n\nA reactive Julia notebook for the terminal *and* the browser.\n\nThis notebook is a tour of the **markdown features** Sessions supports out of\nthe box — modeled on\n[Pluto's basic markdown showcase](https://featured.plutojl.org/basic/markdown).\nEvery cell below is hidden, so what you see is the rendered output. Toggle\nthe eye icon on the left of any cell to see the source.\n\"\"\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000001)),
                runtime_ns = 2696541,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000002",
                source_code = "md\"\"\"\n---\n\n## Headings\n\nSix levels of `#`, just like ordinary markdown.\n\n# Heading 1\n## Heading 2\n### Heading 3\n#### Heading 4\n##### Heading 5\n\"\"\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000002)),
                runtime_ns = 1276000,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000003",
                source_code = "md\"\"\"\n## Text formatting\n\nYou can write **bold**, *italic*, ***bold italic***, `inline code`, and\n~~strikethrough~~ all in the natural way.\n\nInline code is great for keyboard shortcuts: press `Ctrl+Enter` to run the\ncurrent cell, `Shift+Enter` to run-and-advance, or `Ctrl+S` to save.\n\"\"\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000003)),
                runtime_ns = 377625,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000004",
                source_code = "md\"\"\"\n## Lists\n\nA bullet list:\n\n- Reactive execution — cells re-run when their dependencies change\n- Pluto-compatible `.jl` file format\n- Rich output: markdown, tables, images, plots\n\nA numbered list:\n\n1. Open the file explorer (the folder icon, top-left)\n2. Pick a notebook\n3. Edit any cell and press `Ctrl+Enter`\n\"\"\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000004)),
                runtime_ns = 496667,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000006",
                source_code = "md\"\"\"\n## Code blocks\n\nYou get fenced blocks with language tags:\n\n```julia\nfunction fib(n)\n    n < 2 && return n\n    return fib(n - 1) + fib(n - 2)\nend\n```\n\n…and bare ones for shell or plain text:\n\n```\n\$ julia +1.12 --project=. app.jl dev welcome.jl\n```\n\"\"\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000006)),
                runtime_ns = 291833,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000007",
                source_code = "md\"\"\"\n## Math\n\nInline math via double-backticks: ``e^{i\\pi} + 1 = 0`` (Euler's identity).\n\nDisplay math via `…`:\n\n∫−∞∞e−x2dx=π\n\nThe renderer is MathJax under the hood, so anything LaTeX understands works:\n``\\sum_{k=0}^{\\infty} \\frac{x^k}{k!}``.\n\"\"\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000007)),
                runtime_ns = 1200208,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000008",
                source_code = "md\"\"\"\n## Tables\n\n| Symbol | Meaning            | Example                  |\n|:------:|:-------------------|:-------------------------|\n| `╠═`   | visible code cell  | `using Markdown`         |\n| `╟─`   | hidden / markdown  | `md\"# Title\"`            |\n| `🔁`   | reactive re-run    | bonds, cell deps         |\n\nAlignment is controlled by the `:` placement in the header separator.\n\"\"\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000008)),
                runtime_ns = 123536125,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000009",
                source_code = "md\"\"\"\n## Links & footnotes\n\nFind Sessions on [GitHub](https://github.com/GroupTherapyOrg/Sessions.jl) or\nread the [Pluto markdown reference][pluto] for a wider tour.\n\n[pluto]: https://featured.plutojl.org/basic/markdown\n\nYou can also footnote inline like this[^why-pluto-style] for asides.\n\n[^why-pluto-style]: We mirror Pluto's notebook-file format so notebooks are\n    portable between the two.\n\"\"\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000009)),
                runtime_ns = 346875,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-00000000000a",
                source_code = "md\"\"\"\n## Live values\n\nMarkdown cells can interpolate live Julia with `\$(…)`:\n\nThe current Julia version is **\$(VERSION)**, the day of the week is\n**\$(Dates.dayname(Dates.today()))**, and 2 + 2 = \$(2 + 2).\n\"\"\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_00000000000a)),
                runtime_ns = 18855666,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-00000000000c",
                source_code = "greeting = \"Hello, Sessions.jl 👋\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_00000000000c)),
                runtime_ns = 207959,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000010",
                source_code = "md\"\"\"\n---\n\n## Output inspection\n\nSessions inspects most Julia values automatically. Below is a tour of\nthe kinds of output you'll see — every cell is hidden by default, toggle\nthe eye on the left to peek at the source.\n\"\"\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000010)),
                runtime_ns = 264417,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000011",
                source_code = "md\"### Numbers\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000011)),
                runtime_ns = 172084,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000012",
                source_code = "2^100",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000012)),
                runtime_ns = 1362834,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000013",
                source_code = "md\"### Strings\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000013)),
                runtime_ns = 210708,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000014",
                source_code = "\"The quick brown fox jumps over the lazy dog.\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000014)),
                runtime_ns = 71708,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000015",
                source_code = "md\"### Vectors and ranges\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000015)),
                runtime_ns = 162459,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000016",
                source_code = "xx = collect(1:25)",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000016)),
                runtime_ns = 4281583,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000017",
                source_code = "md\"### Dictionaries\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000017)),
                runtime_ns = 211917,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000018",
                source_code = "Dict(\n    :name => \"Sessions.jl\",\n    :version => v\"0.1.0\",\n    :status => :alpha,\n    :stars => 0,\n    :langs => [\"Julia\", \"JavaScript\", \"WASM\"],\n)",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000018)),
                runtime_ns = 59904792,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000019",
                source_code = "md\"### Tuples and named tuples\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000019)),
                runtime_ns = 233125,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-00000000001a",
                source_code = "(1, \"two\", 3.0, :four, [5, 6])",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_00000000001a)),
                runtime_ns = 197250,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-00000000001b",
                source_code = "(name = \"Alice\", age = 30, roles = [:admin, :editor], active = true)",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_00000000001b)),
                runtime_ns = 2463666,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-00000000001c",
                source_code = "md\"### Structs\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_00000000001c)),
                runtime_ns = 214708,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-00000000001d",
                source_code = "struct Point\n    x::Float64\n    y::Float64\nend",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_00000000001d)),
                runtime_ns = 697250,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-00000000001e",
                source_code = "Point(3.14, 2.71)",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_00000000001e)),
                runtime_ns = 1283291,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-00000000001f",
                source_code = "md\"### Sets\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_00000000001f)),
                runtime_ns = 3135542,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000020",
                source_code = "Set([rand(100)...])",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000020)),
                runtime_ns = 79868333,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000021",
                source_code = "md\"### Errors\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000021)),
                runtime_ns = 214041,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000022",
                source_code = "md\"\"\"Errors render with the exception type, message, and a collapsed\nstack trace — click the trace to expand. Try uncommenting the line below:\"\"\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000022)),
                runtime_ns = 165333,
                state = :done,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-000000000023",
                source_code = "sqrt(-1)",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_000000000023)),
                runtime_ns = 497080125,
                state = :errored,
            ),
            render_published_cell(
                cell_id = "10000000-0000-0000-0000-00000000000d",
                source_code = "md\"\"\"\n---\n\nThat's the tour. Try editing any of the hidden cells (toggle the eye on the\nleft) to see the markdown source — and welcome aboard.\n\"\"\"",
                output_content = RawHtml(render_value(_cell__10000000_0000_0000_0000_00000000000d)),
                runtime_ns = 245083,
                state = :done,
            ),
        )
    end
end  # module WelcomeMod

# Surface the function at top scope so the docs registry
# (or any caller) can grab it directly.
const Welcome = WelcomeMod.Welcome
