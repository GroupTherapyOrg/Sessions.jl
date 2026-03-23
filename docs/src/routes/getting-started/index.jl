# Getting Started with Sessions.jl
#
# Installation, quick start, notebook API, architecture overview.
# Uses local components from PageComponents.jl (no Suite.jl).

function GettingStartedIndex()
    Fragment(
        # Header
        PageHeader("Getting Started", "Install Sessions.jl and start working with reactive Julia notebooks in the browser."),

        Div(:class => "prose max-w-none space-y-12",

            # Installation
            Div(
                SectionH2("Installation"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "Sessions.jl requires Julia 1.12+. Install it as a Julia app:"
                ),
                Div(:class => "bg-warm-900 dark:bg-warm-950 rounded-lg p-5 mb-4 overflow-x-auto",
                    CodeBlock(language="julia", """using Pkg
Pkg.Apps.add(url="https://github.com/GroupTherapyOrg/Sessions.jl")""")
                ),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "This installs the ", Kbd("sessions"), " command to ", Kbd("~/.julia/bin/"),
                    ". Make sure this directory is in your ", Kbd("PATH"), "."
                ),
            ),

            # Quick Start
            Div(
                SectionH2("Quick Start"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "The ", Kbd("sessions"), " command opens a web IDE in your browser:"
                ),

                SectionH3("Open a notebook"),
                Div(:class => "bg-warm-900 dark:bg-warm-950 rounded-lg p-5 mb-6 overflow-x-auto",
                    CodeBlock(language="bash", """# Open an existing notebook
sessions my_notebook.jl

# Start fresh (new empty notebook)
sessions

# Start in a project directory (file explorer shows that directory)
cd my_project/ && sessions""")
                ),

                SectionH3("Run headlessly"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "Execute all cells in a notebook without the web UI. Useful for CI pipelines, batch processing, and agent workflows."
                ),
                Div(:class => "bg-warm-900 dark:bg-warm-950 rounded-lg p-5 mb-6 overflow-x-auto",
                    CodeBlock(language="bash", "sessions run my_notebook.jl")
                ),

                SectionH3("From the Julia REPL"),
                Div(:class => "bg-warm-900 dark:bg-warm-950 rounded-lg p-5 mb-6 overflow-x-auto",
                    CodeBlock(language="julia", """using Sessions
Sessions.main(["my_notebook.jl"])""")
                ),
            ),

            # SessionsUI for notebooks
            Div(
                SectionH2("Using SessionsUI in Notebooks"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "SessionsUI is a lightweight package (zero heavy dependencies) that provides the ", Kbd("@bind"), " macro and interactive widgets for notebook cells."
                ),

                SectionH3("Installation"),
                Div(:class => "bg-warm-900 dark:bg-warm-950 rounded-lg p-5 mb-4 overflow-x-auto",
                    CodeBlock(language="julia", """using Pkg
Pkg.add(url="https://github.com/GroupTherapyOrg/Sessions.jl", subdir="SessionsUI")""")
                ),

                SectionH3("Usage"),
                Div(:class => "bg-warm-900 dark:bg-warm-950 rounded-lg p-5 mb-4 overflow-x-auto",
                    CodeBlock(language="julia", """using SessionsUI: @bind, BoundSlider, BoundCheckBox, BoundTextField, BoundSelect

@bind x BoundSlider(1:100)
@bind name BoundTextField(default="world")
@bind flag BoundCheckBox()
@bind choice BoundSelect(["A", "B", "C"])""")
                ),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "SessionsUI compiles in ~300ms because it only depends on UUIDs (stdlib). The heavy dependencies (Therapy.jl, Malt.jl, etc.) live in Sessions.jl (the app), not in SessionsUI."
                ),
            ),

            # Web IDE overview
            Div(
                SectionH2("The Web IDE"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "When you run ", Kbd("sessions"), ", a local web server starts and the IDE opens in your browser at ", Kbd("http://127.0.0.1:8080"), "."
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
                    "A real PTY-backed shell via xterm.js. Multiple tabs supported. Type ", Kbd("julia"), " to get a REPL, run build commands, or use agent tools. Terminal sessions survive page refreshes."
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
                    "Click the \u22EE button on any cell to access: Move up, Move down, Format cell, Delete cell. Deleted cells can be restored with Ctrl+Z (undo toast appears at bottom left)."
                ),
            ),

            # Code/State separation
            Div(
                SectionH2("Code/State Separation"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "Every notebook produces two files:"
                ),
                Ul(:class => "list-disc list-inside space-y-2 text-warm-600 dark:text-warm-400 mb-4",
                    Li(Kbd("notebook.jl"), " contains cell code, cell order, and fold/disabled metadata. This is the source of truth. Both humans and agents can edit it safely."),
                    Li(Kbd("notebook.sessions.toml"), " contains cached outputs, stdout, runtimes, and error messages. It is optional, gitignored, and auto-regenerated when you run cells."),
                ),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "The .jl file uses the same format as Pluto.jl, so you can open the same notebook in either tool."
                ),
            ),

            # Human + Agent workflow
            Div(
                SectionH2("Human + Agent Collaboration"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "Sessions.jl is designed for workflows where you and AI agents (Claude Code, Cursor, etc.) work on the same notebook simultaneously:"
                ),
                Ol(:class => "list-decimal list-inside space-y-2 text-warm-600 dark:text-warm-400 mb-4",
                    Li("You edit code in the browser IDE"),
                    Li("An agent edits the .jl file from the terminal"),
                    Li("The file watcher detects both kinds of changes in under a second"),
                    Li("Modified cells are marked stale with an orange indicator"),
                    Li("Either you or the agent triggers execution (Run Stale button or ", Kbd("sessions run"), ")"),
                    Li("Outputs update for everyone"),
                ),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "The integrated terminal means agents can run commands, install packages, and interact with your project without leaving the IDE."
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

# --- Helpers ---

GettingStartedIndex
