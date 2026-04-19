# Sessions.jl API Reference
#
# Monolithic single-page reference for the public API surface. Mirrors
# Therapy.jl's /api/ pattern: H2 sections grouped by concept, each
# function gets an H3 signature + short description + code example.
# A right-side TOC rail tracks every H2 anchor.
#
# Only user-facing exports are documented here — IDE-internal surface
# (PTY, LSP client, TerminalTab, WebNotebookState, file-watcher
# plumbing) is deliberately omitted.

function ApiIndex()
    card = "border border-warm-200 dark:border-warm-700 rounded-lg p-5 space-y-3 bg-warm-50 dark:bg-warm-900"
    code_block = "bg-warm-900 dark:bg-warm-950 text-warm-200 p-3 rounded text-xs font-mono overflow-x-auto !m-0"
    inline_code = "text-accent-600 dark:text-accent-400"

    sections = [
        ("cli",          "CLI"),
        ("loading",      "Loading & Saving"),
        ("cells",        "Working with Cells"),
        ("execution",    "Running Cells"),
        ("dependencies", "Dependency Analysis"),
        ("publishing",   "Publishing"),
        ("bonds",        "Bonds & Widgets"),
        ("sessions",     "Session Files"),
    ]

    Fragment(
        # Main content — centered in the viewport the same way
        # /getting-started/ is, so the header lines up visually with
        # the nav above it. The right-rail TOC is a separate fixed
        # element below; content doesn't need to reserve space for
        # it (the TOC floats over the right margin at xl+).
        Div(:class => "max-w-5xl mx-auto px-6 py-12",
            PageHeader("API Reference",
                "Everything Sessions.jl exports — from the `sessions` CLI to the extract_notebook publish pipeline. IDE-internal APIs (PTY, LSP client, file watchers) are omitted."),

            Div(:class => "space-y-14",

                    # ── CLI ────────────────────────────────────────
                    Div(
                        H2(:id => "cli", :class => "text-2xl font-serif font-semibold text-warm-800 dark:text-warm-300 mb-4", "CLI"),
                        P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-6",
                            "The ", Code(:class => inline_code, "sessions"), " binary is installed by ",
                            Code(:class => inline_code, "Pkg.Apps.add"), " into ", Kbd("~/.julia/bin/"),
                            ". Running it launches a local web server (default ", Kbd("http://127.0.0.1:8080"),
                            ") and opens the IDE in the browser."),
                        Div(:class => "space-y-4",
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "sessions"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Launch the IDE with a fresh, empty notebook. The working directory is used as the file-explorer root."),
                                Pre(:class => code_block, Code(:class => "language-bash", "\$ sessions"))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "sessions <notebook.jl>"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Open an existing Pluto-format ", Code(:class => inline_code, ".jl"),
                                    " notebook in the IDE. Missing cached outputs are recomputed in the background."),
                                Pre(:class => code_block, Code(:class => "language-bash", "\$ sessions my_notebook.jl"))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "sessions run <notebook.jl>"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Execute every cell headlessly in a clean worker and exit. Useful for CI pipelines, batch processing, and smoke tests. Writes updated outputs back to the notebook's ",
                                    Code(:class => inline_code, ".sessions.toml"), " cache."),
                                Pre(:class => code_block, Code(:class => "language-bash", "\$ sessions run my_notebook.jl"))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "From the Julia REPL"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "All CLI behaviour is reachable from Julia via ",
                                    Code(:class => inline_code, "Sessions.main"), "."),
                                Pre(:class => code_block, Code(:class => "language-julia", """using Sessions
Sessions.main(["my_notebook.jl"])     # same as: sessions my_notebook.jl
Sessions.main(["run", "my_notebook.jl"])""")))
                        )),

                    # ── Loading & Saving ───────────────────────────
                    Div(
                        H2(:id => "loading", :class => "text-2xl font-serif font-semibold text-warm-800 dark:text-warm-300 mb-4", "Loading & Saving"),
                        P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-6",
                            "Notebooks round-trip 1:1 with Pluto's ", Code(:class => inline_code, ".jl"),
                            " file format. Source of truth is the ", Code(:class => inline_code, ".jl"),
                            " file; cached outputs live in a sibling ", Code(:class => inline_code, ".sessions.toml"), "."),
                        Div(:class => "space-y-4",
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "load_notebook(path)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Parse a ", Code(:class => inline_code, ".jl"), " file into a ",
                                    Code(:class => inline_code, "Notebook"), ". Cell order is taken from the ",
                                    Code(:class => inline_code, "# Cell order:"),
                                    " trailer; missing IDs are regenerated."),
                                Pre(:class => code_block, Code(:class => "language-julia", """nb = Sessions.load_notebook("my_notebook.jl")
length(nb.cells)     # → number of cells
nb.path              # → absolute path the notebook was loaded from"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "save_notebook(notebook, path = notebook.path)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Serialize a ", Code(:class => inline_code, "Notebook"),
                                    " back to a Pluto-format ", Code(:class => inline_code, ".jl"),
                                    " file. Safe to round-trip any file ", Code(:class => inline_code, "load_notebook"), " handles."),
                                Pre(:class => code_block, Code(:class => "language-julia", """Sessions.save_notebook(nb)                  # write to nb.path
Sessions.save_notebook(nb, "copy.jl")        # write elsewhere"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "parse_notebook(text) / serialize_notebook(notebook)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "String-level parsing and serialization. Useful for tests and in-memory transforms without touching the filesystem."),
                                Pre(:class => code_block, Code(:class => "language-julia", """nb  = Sessions.parse_notebook(read("my.jl", String))
str = Sessions.serialize_notebook(nb)"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "is_notebook_file(path)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Cheap header-sniff: returns ", Code(:class => inline_code, "true"),
                                    " if the first line of ", Kbd("path"), " matches Pluto's ",
                                    Code(:class => inline_code, "### A Pluto.jl notebook ###"), " marker."),
                                Pre(:class => code_block, Code(:class => "language-julia", "Sessions.is_notebook_file(\"my.jl\")    # → true")))
                        )),

                    # ── Cells ──────────────────────────────────────
                    Div(
                        H2(:id => "cells", :class => "text-2xl font-serif font-semibold text-warm-800 dark:text-warm-300 mb-4", "Working with Cells"),
                        P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-6",
                            "Each notebook is an ordered ", Code(:class => inline_code, "Vector{Cell}"),
                            ". Mutating helpers keep the dependency graph in sync; prefer them over hand-editing ",
                            Code(:class => inline_code, "nb.cells"), "."),
                        Div(:class => "space-y-4",
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "Cell(code; folded=false, disabled=false)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Construct a new cell. The ", Code(:class => inline_code, "folded"),
                                    " flag controls whether the cell starts hidden in the published view (see the Welcome notebook's ",
                                    Em("Cell visibility"), " section)."),
                                Pre(:class => code_block, Code(:class => "language-julia", """c = Sessions.Cell("x = 1 + 1")
c.id         # → randomly-generated UUID
c.state      # → cell_idle
c.folded     # → false"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "add_cell!(nb, cell) / insert_cell!(nb, index, cell)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Append to the end of the notebook, or insert at an explicit position. Both keep the dependency topology and execution order caches consistent."),
                                Pre(:class => code_block, Code(:class => "language-julia", """Sessions.add_cell!(nb, Sessions.Cell("y = x^2"))
Sessions.insert_cell!(nb, 1, Sessions.Cell("using Dates"))"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "get_cell(nb, id) / ordered_cells(nb) / remove_cell!(nb, id)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Lookup by UUID, iterate in source order, or delete. ",
                                    Code(:class => inline_code, "remove_cell!"),
                                    " also unregisters the cell from the topology."),
                                Pre(:class => code_block, Code(:class => "language-julia", """cell = Sessions.get_cell(nb, "abc-...")
for c in Sessions.ordered_cells(nb)
    println(c.code)
end
Sessions.remove_cell!(nb, cell.id)"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "swap_cell_up! / swap_cell_down! / reorder_cell!"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Reorder by index. The dependency graph doesn't care about source order — reordering only affects how the file serializes."),
                                Pre(:class => code_block, Code(:class => "language-julia", """Sessions.swap_cell_up!(nb, 3)      # cell at index 3 ↔ index 2
Sessions.reorder_cell!(nb, 3, 0)   # move cell at 3 to the front"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "is_stale(cell) / is_never_run(cell) / source_hash(cell)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Staleness queries. A cell is ", Em("stale"),
                                    " when its source hash differs from the hash stored on its last output; ",
                                    Em("never-run"), " when it has no cached output at all."),
                                Pre(:class => code_block, Code(:class => "language-julia", """Sessions.is_stale(cell)       # → true if edited since last run
Sessions.is_never_run(cell)   # → true if never executed
Sessions.source_hash(cell)    # → SHA-ish hash of the cell source""")))
                        )),

                    # ── Execution ──────────────────────────────────
                    Div(
                        H2(:id => "execution", :class => "text-2xl font-serif font-semibold text-warm-800 dark:text-warm-300 mb-4", "Running Cells"),
                        P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-6",
                            "Cells run in a ", Code(:class => inline_code, "Workspace"),
                            " — an isolated ", Code(:class => inline_code, "Module"),
                            " the runtime swaps in/out per execution. Everything about evaluation (globals, includes, using) lives there, so the host Julia session is never polluted."),
                        Div(:class => "space-y-4",
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "Workspace()"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "A fresh anonymous ", Code(:class => inline_code, "Module"),
                                    " with a bond registry attached. Reusing the same workspace across executions preserves top-level bindings; constructing a new one resets."),
                                Pre(:class => code_block, Code(:class => "language-julia", """ws = Sessions.Workspace()
Sessions.execute_cell!(ws, nb, cell)"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "execute_cell!(workspace, notebook, cell)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Evaluate one cell. Captures the return value, stdout, thrown error, and wall-clock runtime into ",
                                    Code(:class => inline_code, "cell.output"),
                                    ". Thrown errors are caught and formatted; they don't escape."),
                                Pre(:class => code_block, Code(:class => "language-julia", """Sessions.execute_cell!(ws, nb, cell)
cell.state         # → cell_done | cell_errored
cell.output.value  # → the return value (or nothing on error)
cell.output.error  # → formatted StructuredError, or nothing"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "execute_notebook!(workspace, notebook) / execute_changed!(workspace, notebook)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Batch runs. ", Code(:class => inline_code, "execute_notebook!"),
                                    " runs every cell; ", Code(:class => inline_code, "execute_changed!"),
                                    " runs only cells the topology flags as stale + their downstream dependents."),
                                Pre(:class => code_block, Code(:class => "language-julia", """Sessions.execute_notebook!(ws, nb)   # full re-run
Sessions.execute_changed!(ws, nb)    # stale + downstream only"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "CellState (enum) / CellOutput (struct)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    Code(:class => inline_code, "CellState"), " values: ",
                                    Code(:class => inline_code, "cell_idle"), ", ",
                                    Code(:class => inline_code, "cell_queued"), ", ",
                                    Code(:class => inline_code, "cell_running"), ", ",
                                    Code(:class => inline_code, "cell_done"), ", ",
                                    Code(:class => inline_code, "cell_errored"), ". ",
                                    Code(:class => inline_code, "CellOutput"),
                                    " carries the execution result plus stdout, timing, MIME type, and the structured error if one was thrown."),
                                Pre(:class => code_block, Code(:class => "language-julia", """cell.output.value      # → the return value
cell.output.stdout     # → captured stdout string
cell.output.runtime_ns # → wall-clock nanoseconds
cell.output.mime       # → "text/html" | "text/plain" | ...
cell.output.error      # → StructuredError (or nothing)""")))
                        )),

                    # ── Dependencies ───────────────────────────────
                    Div(
                        H2(:id => "dependencies", :class => "text-2xl font-serif font-semibold text-warm-800 dark:text-warm-300 mb-4", "Dependency Analysis"),
                        P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-6",
                            "Sessions wraps ",
                            A(:href => "https://github.com/JuliaPluto/ExpressionExplorer.jl", :target => "_blank",
                              :class => "text-accent-600 dark:text-accent-400 hover:underline", "ExpressionExplorer.jl"),
                            " and ",
                            A(:href => "https://github.com/JuliaPluto/PlutoDependencyExplorer.jl", :target => "_blank",
                              :class => "text-accent-600 dark:text-accent-400 hover:underline", "PlutoDependencyExplorer.jl"),
                            " to compute a reactive dependency graph over cells. This is what powers stale-cell detection and the run-in-dependency-order guarantee."),
                        Div(:class => "space-y-4",
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "analyze_cell(cell)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Parse a single cell and return an ExpressionExplorer result with the symbols it defines and references. Used by the IDE to highlight stale dependents."),
                                Pre(:class => code_block, Code(:class => "language-julia", """info = Sessions.analyze_cell(cell)
Sessions.cell_definitions(info)   # → Set of symbols this cell assigns
Sessions.cell_references(info)    # → Set of symbols this cell reads"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "update_topology!(notebook)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Incrementally recompute the dependency graph after edits. Called internally by ",
                                    Code(:class => inline_code, "execute_cell!"),
                                    " whenever a cell's source changes; call it manually if you've mutated cells directly."),
                                Pre(:class => code_block, Code(:class => "language-julia", "Sessions.update_topology!(nb)"))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "execution_order(notebook)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Return cells in topological dependency order. A cell depending on another always comes after it, regardless of where it appears in the source file."),
                                Pre(:class => code_block, Code(:class => "language-julia", """for cell in Sessions.execution_order(nb)
    Sessions.execute_cell!(ws, nb, cell)
end"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "stale_cells(notebook) / never_run_cells(notebook) / downstream_dependents(notebook, cell)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Targeted queries for the IDE's ", Em("Run Stale"), " button and for ",
                                    Code(:class => inline_code, "execute_changed!"), "."),
                                Pre(:class => code_block, Code(:class => "language-julia", """Sessions.stale_cells(nb)                   # stale + never-run
Sessions.never_run_cells(nb)               # just the never-run ones
Sessions.downstream_dependents(nb, cell)   # cells that (transitively) read this cell's defs""")))
                        )),

                    # ── Publishing ─────────────────────────────────
                    Div(
                        H2(:id => "publishing", :class => "text-2xl font-serif font-semibold text-warm-800 dark:text-warm-300 mb-4", "Publishing"),
                        P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-6",
                            "Sessions publishes notebooks to self-contained Therapy components that compile every reactive cell to WebAssembly. Drop the emitted ",
                            Code(:class => inline_code, ".jl"),
                            " into any Therapy project and the notebook hydrates in the browser — no server, no kernel."),
                        Div(:class => "space-y-4",
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "extract_notebook(notebook_path, out_path, component_name; overwrite=false)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Read a notebook, classify its cells, run them once in a clean worker, and emit a single self-contained ",
                                    Code(:class => inline_code, ".jl"),
                                    " file that exposes a top-level Therapy component. Static cells are frozen at extract time; bonds + reactive cells become per-cell ",
                                    Code(:class => inline_code, "@island"), "s."),
                                Pre(:class => code_block, Code(:class => "language-julia", """Sessions.extract_notebook(
    "notebooks/welcome.jl",
    "docs/src/components/Welcome.jl",
    "Welcome";
    overwrite = true,
)"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "classify_cells(notebook)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Classify every cell into ", Code(:class => inline_code, ":static"), ", ",
                                    Code(:class => inline_code, ":bond"), ", or ",
                                    Code(:class => inline_code, ":reactive"),
                                    ". Returns a ", Code(:class => inline_code, "Vector{CellClass}"),
                                    ". The extractor uses this to decide which cells become ",
                                    Code(:class => inline_code, "@island"), "s and which are frozen as ",
                                    Code(:class => inline_code, "RawHtml"), "."),
                                Pre(:class => code_block, Code(:class => "language-julia", """classes = Sessions.classify_cells(nb)
count(c -> c.kind === :bond,     classes)  # slider / textfield cells
count(c -> c.kind === :reactive, classes)  # cells depending on bonds
count(c -> c.kind === :static,   classes)  # everything else"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "CellClass (struct)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "One entry per cell. Fields: ", Code(:class => inline_code, "cell"),
                                    " (the underlying ", Code(:class => inline_code, "Cell"), "), ",
                                    Code(:class => inline_code, "kind"), ", ",
                                    Code(:class => inline_code, "bond_name"),
                                    " (the bound variable if this is a ", Code(:class => inline_code, ":bond"),
                                    " cell), and ", Code(:class => inline_code, "upstream_bonds"),
                                    " (the set of bonds this reactive cell depends on)."),
                                Pre(:class => code_block, Code(:class => "language-julia", """cls = Sessions.classify_cells(nb)[4]
cls.kind             # → :reactive
cls.upstream_bonds   # → Set([:n, :m])"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "validate_component_name(name)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Throws ", Code(:class => inline_code, "ArgumentError"),
                                    " unless the string is a non-empty PascalCase identifier. Used to check the ",
                                    Code(:class => inline_code, "component_name"),
                                    " argument to ", Code(:class => inline_code, "extract_notebook"), "."),
                                Pre(:class => code_block, Code(:class => "language-julia", """Sessions.validate_component_name("MyNotebook")   # ok
Sessions.validate_component_name("my_notebook")  # ArgumentError"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "render_published_notebook(cells...)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "The runtime side of ", Code(:class => inline_code, "extract_notebook"),
                                    " — given a sequence of pre-rendered cell VNodes, wrap them in a ",
                                    Code(:class => inline_code, "<div class=\"notebook-extracted\">"),
                                    " along with the bundled notebook CSS + read-only CodeMirror init. Called from inside every extracted component; you'd only use this yourself if you're hand-rolling a custom extractor."),
                                Pre(:class => code_block, Code(:class => "language-julia", """Sessions.render_published_notebook(
    CellDiv("cell-1", markdown_html),
    CellDiv("cell-2", compiled_island),
    # ...
)""")))
                        )),

                    # ── Bonds & Widgets ────────────────────────────
                    Div(
                        H2(:id => "bonds", :class => "text-2xl font-serif font-semibold text-warm-800 dark:text-warm-300 mb-4", "Bonds & Widgets"),
                        P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-6",
                            "Interactive widgets live in the ",
                            A(:href => "https://github.com/GroupTherapyOrg/Sessions.jl/tree/main/SessionsUI",
                              :target => "_blank",
                              :class => "text-accent-600 dark:text-accent-400 hover:underline", "SessionsUI"),
                            " sub-package — zero heavy dependencies, compiles in ~300 ms. The whole surface is one macro + a catalogue of ",
                            Code(:class => inline_code, "Bound*"), " types."),
                        Div(:class => "space-y-4",
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "@bind name widget"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Bind a widget's value to a symbol. Cells that reference ",
                                    Code(:class => inline_code, "name"),
                                    " re-run whenever the widget emits a new value. Same ergonomics as ",
                                    Code(:class => inline_code, "PlutoUI.@bind"), "."),
                                Pre(:class => code_block, Code(:class => "language-julia", """using SessionsUI: @bind, BoundSlider

@bind n BoundSlider(1:100; default = 20)

n * n     # re-runs every time the slider moves"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "Input widgets"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "The ", Code(:class => inline_code, "Bound*"),
                                    " catalogue covers every common input control. All support a ",
                                    Code(:class => inline_code, "default = …"),
                                    " keyword for the value used in script / SSR mode."),
                                Pre(:class => code_block, Code(:class => "language-julia", """BoundSlider(1:100; default = 10)          # integer or float ranges
BoundRangeSlider(0:100; default = 20:80)   # two-handle range
BoundNumberField(0:100; default = 5)       # numeric input
BoundTextField(default = "")               # plain text
BoundPasswordField(default = "")           # password (masked)
BoundCheckBox(default = false)             # boolean
BoundSelect(["a","b","c"])                 # dropdown
BoundMultiSelect(["a","b","c"])            # multi-select
BoundRadio(["a","b","c"])                  # radio group
BoundColorPicker(default = "#1E88E5")      # colour
BoundDatePicker() / BoundTimePicker()      # date / time
BoundFilePicker()                          # file upload (returns Vector{UInt8})
BoundButton("Go") / BoundCounterButton()   # click events
BoundClock(interval = 1.0)                 # read-only ticking clock"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "Widget protocol"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "A custom widget implements three methods on a subtype of ",
                                    Code(:class => inline_code, "SessionsUI.AbstractWidget"),
                                    ". ", Code(:class => inline_code, "initial_value"),
                                    " is used when the bond hasn't been set yet; ",
                                    Code(:class => inline_code, "possible_values"),
                                    " is optional and powers ", Em("validate-before-dispatch"),
                                    " — if it returns a finite collection, incoming values are checked against it."),
                                Pre(:class => code_block, Code(:class => "language-julia", """using SessionsUI: AbstractWidget, initial_value, possible_values

struct Toggle <: AbstractWidget
    default::Bool
end
SessionsUI.initial_value(t::Toggle)   = t.default
SessionsUI.possible_values(::Toggle)  = (false, true)

# Then <HTML for the widget>. See BoundCheckBox for a full example."""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "TableOfContents()"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Utility widget (also in ", Code(:class => inline_code, "SessionsUI"),
                                    ") that auto-generates a navigable outline from the notebook's markdown headings. Place it in a cell and it updates live as you add/edit headings."),
                                Pre(:class => code_block, Code(:class => "language-julia", """using SessionsUI: TableOfContents

TableOfContents()    # typically in the first markdown cell""")))
                        )),

                    # ── Session Files ──────────────────────────────
                    Div(
                        H2(:id => "sessions", :class => "text-2xl font-serif font-semibold text-warm-800 dark:text-warm-300 mb-4", "Session Files"),
                        P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-6",
                            "Each notebook has an optional sibling ", Code(:class => inline_code, ".sessions.toml"),
                            " that caches the last run's outputs, stdout, runtimes, and errors. It's what lets the IDE open a notebook instantly without re-running every cell, and what ", Code(:class => inline_code, "sessions run"),
                            " writes to. The file is gitignored by convention — the ", Code(:class => inline_code, ".jl"),
                            " is the source of truth."),
                        Div(:class => "space-y-4",
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "session_path(notebook_path)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Return the conventional cache path for a notebook — ",
                                    Kbd("my.jl"), " → ", Kbd("my.sessions.toml"), "."),
                                Pre(:class => code_block, Code(:class => "language-julia", "Sessions.session_path(\"my.jl\")    # → \"my.sessions.toml\""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "save_session!(notebook, path = session_path(notebook.path))"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Freeze each cell's current output to a TOML file alongside the notebook. Run once after every batch execution to keep the cache fresh."),
                                Pre(:class => code_block, Code(:class => "language-julia", "Sessions.save_session!(nb)"))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "load_session(path) / apply_session!(notebook, session)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Read a session file back, then apply it to a fresh notebook. Cells whose source hash matches the cache get their cached output restored; mismatches are left marked stale."),
                                Pre(:class => code_block, Code(:class => "language-julia", """session = Sessions.load_session("my.sessions.toml")
Sessions.apply_session!(nb, session)"""))),
                            Div(:class => card,
                                H3(:class => "font-mono font-semibold text-warm-900 dark:text-warm-100", "load_notebook_with_session(path)"),
                                P(:class => "text-sm text-warm-600 dark:text-warm-400",
                                    "Convenience: ", Code(:class => inline_code, "load_notebook"),
                                    " + ", Code(:class => inline_code, "apply_session!"),
                                    " in one call. Returns a ready-to-render notebook with cached outputs attached."),
                                Pre(:class => code_block, Code(:class => "language-julia", "nb = Sessions.load_notebook_with_session(\"my.jl\")")))
                        )),
            )
        ),

        # Left-rail TOC — fixed position, floats in the left margin
        # on xl+ viewports. Aligned with the other docs sidebars
        # (notebooks list on /notebooks/*), giving the API page the
        # same "wide nav on left" silhouette. Hidden below xl so
        # narrow viewports get the full centered content band.
        Nav(:class => "hidden xl:block fixed left-8 top-24 w-44 z-10",
            Div(:class => "space-y-1.5 border-l border-warm-200 dark:border-warm-800 pl-3",
                P(:class => "text-[11px] font-semibold text-warm-400 dark:text-warm-500 uppercase tracking-wider mb-3",
                    "On this page"),
                map(sections) do (id, label)
                    A(:href => "#$(id)",
                      :class => "block text-[12px] leading-relaxed text-warm-500 dark:text-warm-400 hover:text-accent-500 dark:hover:text-accent-400 transition-colors",
                      label)
                end...
            )
        )
    )
end

ApiIndex
