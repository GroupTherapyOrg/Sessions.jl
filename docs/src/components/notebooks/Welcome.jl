# ── Sessions.jl extracted notebook ─────────────────────────
#
# Source : /Users/daleblack/Documents/dev/GroupTherapyOrg/Sessions.jl/test/fixtures/welcome.jl
# Date   : 2026-04-16T22:17:14.827
#
# This file is a self-contained Therapy component. The user's
# cell SOURCE is preserved verbatim — markdown stays markdown,
# code stays code. Each cell evaluates once at module load and
# its value is rendered through Base.show(MIME"text/html"(),…)
# (the same pipeline the Sessions IDE uses live).
#
# Architecture:
#   - Outer `function Welcome()` is plain Julia.
#     It just lays out cells in document order; it always works
#     regardless of WASM compile state.
#   - Each @bind cell becomes a tiny @island that wraps the
#     SessionsUI widget. Bond signals are module-level shared
#     signals so cross-island sync is automatic.
#   - Each reactive cell becomes a tiny @island that captures
#     its upstream bond signals. v1 renders the frozen value
#     computed at module load (using the bond defaults). v2
#     re-executes the body in WASM as WasmTarget grows.
#
# Edit by hand to restyle Tailwind classes, change cell content,
# remove cells, etc. Re-running `Sessions.extract_notebook` with
# the same out_path overwrites the file.
# ───────────────────────────────────────────────────────────

module WelcomeMod

    using Therapy
    using Markdown
    using Dates

"""
Render any cell value to an HTML string. Tries Sessions's tree
renderer for Dicts/Sets/structs (if the host loaded it), then
`Base.show(MIME"text/html"(), …)` for everything else (Markdown,
DataFrames, plots — they all define their own show methods),
falling back to `print` for plain values.
"""
function _render(x)::String
    x isa Exception && return string("<pre style='color:#c33;font-family:monospace;font-size:12px;padding:8px;background:#fee;border-radius:4px'>", sprint(showerror, x), "</pre>")
    if isdefined(Main, :Sessions)
        try
            sess = Main.Sessions
            if Base.invokelatest(getfield(sess, :_is_tree_value), x)
                return Base.invokelatest(getfield(sess, :_render_tree_html), x)
            end
        catch
        end
    end
    try
        sprint(io -> show(io, MIME"text/html"(), x))
    catch
        sprint(print, x)
    end
end


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
    end    # ── Cell 10000000-0000-0000-0000-000000000002 (static) ──
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
    end    # ── Cell 10000000-0000-0000-0000-000000000003 (static) ──
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
    end    # ── Cell 10000000-0000-0000-0000-000000000004 (static) ──
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
    end    # ── Cell 10000000-0000-0000-0000-000000000006 (static) ──
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
    end    # ── Cell 10000000-0000-0000-0000-000000000007 (static) ──
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
    end    # ── Cell 10000000-0000-0000-0000-000000000008 (static) ──
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
    end    # ── Cell 10000000-0000-0000-0000-000000000009 (static) ──
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
    end    # ── Cell 10000000-0000-0000-0000-00000000000a (static) ──
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
    end    # ── Cell 10000000-0000-0000-0000-00000000000c (static) ──
    const _cell__10000000_0000_0000_0000_00000000000c = try
        let
            greeting = "Hello, Sessions.jl 👋"
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-000000000010 (static) ──
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
    end    # ── Cell 10000000-0000-0000-0000-000000000011 (static) ──
    const _cell__10000000_0000_0000_0000_000000000011 = try
        let
            md"### Numbers"
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-000000000012 (static) ──
    const _cell__10000000_0000_0000_0000_000000000012 = try
        let
            2^100
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-000000000013 (static) ──
    const _cell__10000000_0000_0000_0000_000000000013 = try
        let
            md"### Strings"
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-000000000014 (static) ──
    const _cell__10000000_0000_0000_0000_000000000014 = try
        let
            "The quick brown fox jumps over the lazy dog."
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-000000000015 (static) ──
    const _cell__10000000_0000_0000_0000_000000000015 = try
        let
            md"### Vectors and ranges"
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-000000000016 (static) ──
    const _cell__10000000_0000_0000_0000_000000000016 = try
        let
            xx = collect(1:25)
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-000000000017 (static) ──
    const _cell__10000000_0000_0000_0000_000000000017 = try
        let
            md"### Dictionaries"
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-000000000018 (static) ──
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
    end    # ── Cell 10000000-0000-0000-0000-000000000019 (static) ──
    const _cell__10000000_0000_0000_0000_000000000019 = try
        let
            md"### Tuples and named tuples"
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-00000000001a (static) ──
    const _cell__10000000_0000_0000_0000_00000000001a = try
        let
            (1, "two", 3.0, :four, [5, 6])
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-00000000001b (static) ──
    const _cell__10000000_0000_0000_0000_00000000001b = try
        let
            (name = "Alice", age = 30, roles = [:admin, :editor], active = true)
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-00000000001c (static) ──
    const _cell__10000000_0000_0000_0000_00000000001c = try
        let
            md"### Structs"
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-00000000001d (static) ──
    const _cell__10000000_0000_0000_0000_00000000001d = try
        let
            struct Point
                x::Float64
                y::Float64
            end
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-00000000001e (static) ──
    const _cell__10000000_0000_0000_0000_00000000001e = try
        let
            Point(3.14, 2.71)
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-00000000001f (static) ──
    const _cell__10000000_0000_0000_0000_00000000001f = try
        let
            md"### Sets"
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-000000000020 (static) ──
    const _cell__10000000_0000_0000_0000_000000000020 = try
        let
            Set([rand(100)...])
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-000000000021 (static) ──
    const _cell__10000000_0000_0000_0000_000000000021 = try
        let
            md"### Errors"
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-000000000022 (static) ──
    const _cell__10000000_0000_0000_0000_000000000022 = try
        let
            md"""Errors render with the exception type, message, and a collapsed
            stack trace — click the trace to expand. Try uncommenting the line below:"""
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-000000000023 (static) ──
    const _cell__10000000_0000_0000_0000_000000000023 = try
        let
            sqrt(-1)
        end
    catch _e
        _e
    end    # ── Cell 10000000-0000-0000-0000-00000000000d (static) ──
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
        Div(:class => "notebook-extracted",
            Div(:class => "nb-cell-list",
                :style => "max-width:900px;margin:0 auto;padding-left:28px;padding-right:28px;position:relative;",
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000001))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000002))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000003))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000004))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000006))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000007))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000008))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000009))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_00000000000a))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_00000000000c))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000010))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000011))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000012))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000013))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000014))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000015))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000016))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000017))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000018))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000019))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_00000000001a))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_00000000001b))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_00000000001c))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_00000000001d))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_00000000001e))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_00000000001f))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000020))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000021))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000022))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_000000000023))))),
                Div(:class => "cell-wrap relative",
Div(:class => "cell-body",
    Div(:class => "cell-out", :style => "padding:4px 0 2px;overflow-x:auto;",
        RawHtml(_render(_cell__10000000_0000_0000_0000_00000000000d)))))
            )
        )
    end
end  # module WelcomeMod

# Surface the function at top scope so the docs registry
# (or any caller) can grab it directly.
const Welcome = WelcomeMod.Welcome
