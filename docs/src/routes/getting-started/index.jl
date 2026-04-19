# Getting Started with Sessions.jl
#
# Installation, quick start, notebook API, architecture overview.
# Code blocks use the same inline Pre+Code pattern the /api/ page
# uses (no language badge, p-3, text-xs) so the two pages read as
# part of the same visual system.

function GettingStartedIndex()
    code_block  = "bg-warm-900 dark:bg-warm-950 text-warm-200 p-3 rounded text-xs font-mono overflow-x-auto !m-0"
    inline_code = "text-accent-600 dark:text-accent-400"

    Div(:class => "max-w-5xl mx-auto px-6 py-12",
        PageHeader("Getting Started", "Install Sessions.jl and start working with reactive Julia notebooks in the browser."),

        Div(:class => "prose max-w-none space-y-12",

            # Installation
            Div(
                SectionH2("Installation"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "Sessions.jl requires Julia 1.12+. Install it as a Julia app:"
                ),
                Pre(:class => "$(code_block) mb-4", Code(:class => "language-julia", """using Pkg
Pkg.Apps.add(url="https://github.com/GroupTherapyOrg/Sessions.jl")""")),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "This installs the ", Code(:class => inline_code, "sessions"),
                    " command to ", Kbd("~/.julia/bin/"),
                    ". Make sure this directory is in your ",
                    Code(:class => inline_code, "PATH"), "."
                ),
            ),

            # Quick Start
            Div(
                SectionH2("Quick Start"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "The ", Code(:class => inline_code, "sessions"),
                    " command opens a web IDE in your browser:"
                ),

                SectionH3("Open a notebook"),
                Pre(:class => "$(code_block) mb-6", Code(:class => "language-bash", """# Open an existing notebook
sessions my_notebook.jl

# Start fresh (new empty notebook)
sessions

# Start in a project directory (file explorer shows that directory)
cd my_project/ && sessions""")),

                SectionH3("Run headlessly"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "Execute all cells in a notebook without the web UI. Useful for CI pipelines, batch processing, and automation."
                ),
                Pre(:class => "$(code_block) mb-6", Code(:class => "language-bash", "sessions run my_notebook.jl")),

                SectionH3("From the Julia REPL"),
                Pre(:class => "$(code_block) mb-6", Code(:class => "language-julia", """using Sessions
Sessions.main(["my_notebook.jl"])""")),
            ),

            # SessionsUI for notebooks
            Div(
                SectionH2("Using SessionsUI in Notebooks"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "SessionsUI is a lightweight package (zero heavy dependencies) that provides the ",
                    Code(:class => inline_code, "@bind"),
                    " macro and interactive widgets for notebook cells."
                ),

                SectionH3("Installation"),
                Pre(:class => "$(code_block) mb-4", Code(:class => "language-julia", """using Pkg
Pkg.add(url="https://github.com/GroupTherapyOrg/Sessions.jl", subdir="SessionsUI")""")),

                SectionH3("Usage"),
                Pre(:class => "$(code_block) mb-4", Code(:class => "language-julia", """using SessionsUI: @bind, BoundSlider, BoundCheckBox, BoundTextField, BoundSelect

@bind x BoundSlider(1:100)
@bind name BoundTextField(default="world")
@bind flag BoundCheckBox()
@bind choice BoundSelect(["A", "B", "C"])""")),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "SessionsUI compiles in ~300ms because it only depends on UUIDs (stdlib). The heavy dependencies (Therapy.jl, Malt.jl, etc.) live in Sessions.jl (the app), not in SessionsUI."
                ),
            ),

            # Web IDE overview
            Div(
                SectionH2("The Web IDE"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "When you run ", Code(:class => inline_code, "sessions"),
                    ", a local web server starts and the IDE opens in your browser at ",
                    Kbd("http://127.0.0.1:8080"), "."
                ),

                SectionH3("Activity bar"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "The left sidebar has toggle buttons for the file explorer, diagnostics panel, and integrated terminal."
                ),

                SectionH3("File explorer"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "Browse your project directory, open .jl notebooks, create/rename/delete files and folders via right-click context menu. Directories load lazily."
                ),

                SectionH3("Integrated terminal"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "A real PTY-backed shell via xterm.js. Multiple tabs supported. Type ",
                    Code(:class => inline_code, "julia"),
                    " to get a REPL, run build commands, or install packages. Terminal sessions survive page refreshes."
                ),

                SectionH3("Notebook toolbar"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "The toolbar provides:"
                ),
                Ul(:class => "list-disc list-inside space-y-2 text-warm-600 dark:text-warm-400 mb-4",
                    Li(Strong("Run All"), " executes every cell in dependency order"),
                    Li(Strong("Run Stale"), " executes only cells whose code changed since last run"),
                    Li(Strong("Stop"), " interrupts the currently running cell (sends SIGINT to the worker)"),
                    Li(Strong("Save"), " writes the .jl file and updates the .sessions.toml cache"),
                    Li(Strong("Format"), " formats all cells with Runic.jl (individual cells via the cell menu)"),
                ),

                SectionH3("Cell menu"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "Click the ", Kbd("⋮"),
                    " button on any cell to access: Move up, Move down, Format cell, Delete cell. Deleted cells can be restored with ",
                    Kbd("Ctrl+Z"), " (undo toast appears at bottom left)."
                ),
            ),

            # Code/State separation
            Div(
                SectionH2("Code/State Separation"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "Every notebook produces two files:"
                ),
                Ul(:class => "list-disc list-inside space-y-2 text-warm-600 dark:text-warm-400 mb-4",
                    Li(Code(:class => inline_code, "notebook.jl"),
                        " contains cell code, cell order, and fold/disabled metadata. This is the source of truth — safe to edit from any tool."),
                    Li(Code(:class => inline_code, "notebook.sessions.toml"),
                        " contains cached outputs, stdout, runtimes, and error messages. It is optional, gitignored, and auto-regenerated when you run cells."),
                ),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "The .jl file uses the same format as Pluto.jl, so you can open the same notebook in either tool."
                ),
            ),

            # Collaborative editing
            Div(
                SectionH2("Collaborative Editing"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "Since notebooks are plain .jl files, they work naturally with any external tool — other editors, AI assistants, scripts, or CI pipelines:"
                ),
                Ol(:class => "list-decimal list-inside space-y-2 text-warm-600 dark:text-warm-400 mb-4",
                    Li("Edit code in the browser IDE"),
                    Li("Modify the .jl file from any editor or terminal"),
                    Li("The file watcher detects changes in under a second"),
                    Li("Modified cells are marked stale with an orange indicator"),
                    Li("Click Run Stale or run ",
                        Code(:class => inline_code, "sessions run"), " to re-execute"),
                ),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "The integrated terminal lets you run commands, install packages, and interact with your project without leaving the IDE."
                ),
            ),

            # Dependencies / Built on
            Div(
                SectionH2("Built On"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "Sessions.jl builds on the Julia and Pluto ecosystems:"
                ),
                Ul(:class => "list-disc list-inside space-y-2 text-warm-600 dark:text-warm-400",
                    Li(A(:href => "https://github.com/fonsp/Pluto.jl", :class => "text-accent-600 dark:text-accent-400 hover:underline", :target => "_blank", "Pluto.jl"), " file format and reactivity model"),
                    Li(A(:href => "https://github.com/JuliaPluto/ExpressionExplorer.jl", :class => "text-accent-600 dark:text-accent-400 hover:underline", :target => "_blank", "ExpressionExplorer.jl"), " reactive dependency analysis"),
                    Li(A(:href => "https://github.com/JuliaPluto/PlutoDependencyExplorer.jl", :class => "text-accent-600 dark:text-accent-400 hover:underline", :target => "_blank", "PlutoDependencyExplorer.jl"), " topological cell ordering"),
                    Li(A(:href => "https://github.com/GroupTherapyOrg/Therapy.jl", :class => "text-accent-600 dark:text-accent-400 hover:underline", :target => "_blank", "Therapy.jl"), " web framework (SSR, WebSocket channels, @island hydration)"),
                    Li(A(:href => "https://github.com/JuliaPluto/Malt.jl", :class => "text-accent-600 dark:text-accent-400 hover:underline", :target => "_blank", "Malt.jl"), " isolated worker processes"),
                    Li(A(:href => "https://github.com/fredrikekre/Runic.jl", :class => "text-accent-600 dark:text-accent-400 hover:underline", :target => "_blank", "Runic.jl"), " code formatting"),
                    Li(A(:href => "https://codemirror.net/", :class => "text-accent-600 dark:text-accent-400 hover:underline", :target => "_blank", "CodeMirror"), " code editor"),
                    Li(A(:href => "https://shoelace.style/", :class => "text-accent-600 dark:text-accent-400 hover:underline", :target => "_blank", "Shoelace"), " web components (file explorer)"),
                    Li(A(:href => "https://xtermjs.org/", :class => "text-accent-600 dark:text-accent-400 hover:underline", :target => "_blank", "xterm.js"), " terminal emulator"),
                ),
            ),
        )
    )
end

GettingStartedIndex
