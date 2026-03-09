# Getting Started — Sessions.jl
#
# Installation, quick start, keyboard shortcuts, architecture overview.
# Uses local components from PageComponents.jl (no Suite.jl).

function GettingStartedIndex()
    Fragment(
        # Header
        PageHeader("Getting Started", "Install Sessions.jl and start working with reactive Julia notebooks in your terminal."),

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
                    ". On first launch, JETLS (real-time diagnostics) is auto-installed."
                ),
            ),

            # Quick Start
            Div(
                SectionH2("Quick Start"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "Sessions.jl can be used in three ways:"
                ),

                SectionH3("CLI (recommended)"),
                Div(:class => "bg-warm-900 dark:bg-warm-950 rounded-lg p-5 mb-6 overflow-x-auto",
                    CodeBlock(language="bash", """# Open a notebook
sessions my_notebook.jl

# Create a new notebook
sessions

# Run headlessly (CI, scripts)
sessions run my_notebook.jl""")
                ),

                SectionH3("Julia REPL"),
                Div(:class => "bg-warm-900 dark:bg-warm-950 rounded-lg p-5 mb-6 overflow-x-auto",
                    CodeBlock(language="julia", """using Sessions
Sessions.main("my_notebook.jl")""")
                ),

                SectionH3("Headless execution"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "Run all cells in a notebook without the TUI. Useful for CI pipelines and batch processing."
                ),
                Div(:class => "bg-warm-900 dark:bg-warm-950 rounded-lg p-5 mb-6 overflow-x-auto",
                    CodeBlock(language="bash", "sessions run my_notebook.jl")
                ),
            ),

            # Keyboard Shortcuts
            Div(
                SectionH2("Keyboard Shortcuts"),

                KeyboardTable("Normal Mode",
                    KeyRow("j / k", "Navigate cells down/up"),
                    KeyRow("i / Enter", "Enter insert mode (edit cell)"),
                    KeyRow("Ctrl+R", "Run current cell"),
                    KeyRow("Shift+Enter", "Run cell and move to next"),
                    KeyRow("Ctrl+Shift+Enter", "Run all cells"),
                    KeyRow("o / O", "Add cell below/above"),
                    KeyRow("dd", "Delete cell"),
                    KeyRow("J / K", "Move cell down/up"),
                    KeyRow("Ctrl+S", "Save notebook"),
                    KeyRow("Ctrl+Q", "Quit"),
                    KeyRow("1 - 4", "Toggle sidebar panels"),
                ),

                KeyboardTable("Insert Mode",
                    KeyRow("Escape", "Return to normal mode"),
                    KeyRow("Ctrl+R", "Run cell"),
                    KeyRow("Ctrl+S", "Save notebook"),
                    KeyRow("Cmd+Left/Right", "Home/End (macOS)"),
                    KeyRow("Option+Left/Right", "Word jump (macOS)"),
                ),
            ),

            # Architecture
            Div(
                SectionH2("Architecture"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-6",
                    "Sessions.jl is built in three layers, each with clear responsibilities:"
                ),
                Div(:class => "grid md:grid-cols-3 gap-4",
                    _ArchBox("Layer 1: Engine",
                        "Pure Julia, no UI. Handles notebook format parsing, reactive analysis, cell execution, and the @bind protocol.",
                        "types.jl, format.jl, analysis.jl, kernel.jl, run.jl, bind.jl, session.jl"),
                    _ArchBox("Layer 2: TUI",
                        "Terminal UI built on Tachikoma.jl. Notebook view, cell widgets, output rendering, file browser, REPL panel, diagnostics.",
                        "app.jl, notebook_view.jl, cell_widget.jl, output_widget.jl, file_panel.jl, repl_panel.jl"),
                    _ArchBox("Layer 3: CLI",
                        "Entry points and static analysis integration. ARGS parsing, JETLS LSP client, JET.jl batch analysis.",
                        "cli.jl, lsp_client.jl, jet_analysis.jl"),
                ),
            ),

            # @bind Widgets
            Div(
                SectionH2("@bind Widgets"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "Sessions.jl implements the AbstractPlutoDingetjes ", Kbd("@bind"),
                    " protocol. Use widgets to create interactive controls in your notebooks:"
                ),
                Div(:class => "bg-warm-900 dark:bg-warm-950 rounded-lg p-5 mb-6 overflow-x-auto",
                    CodeBlock(language="julia", """@bind x Slider(1:100)
@bind name TextField()
@bind flag CheckBox()
@bind choice Select(["A", "B", "C"])
@bind n NumberField(1:10)""")
                ),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "Widgets render as interactive TUI elements during development and will compile to WebAssembly for exported notebook viewing."
                ),
            ),

            # Dependencies
            Div(
                SectionH2("Dependencies"),
                P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed mb-4",
                    "Sessions.jl builds on the Julia and Pluto ecosystems:"
                ),
                Ul(:class => "list-disc list-inside space-y-2 text-warm-600 dark:text-warm-400",
                    Li(A(:href => "https://github.com/GroupTherapyOrg/Tachikoma.jl", :class => "text-accent-600 dark:text-accent-400 hover:underline", :target => "_blank", "Tachikoma.jl"), " — Terminal UI framework"),
                    Li(A(:href => "https://github.com/JuliaPluto/ExpressionExplorer.jl", :class => "text-accent-600 dark:text-accent-400 hover:underline", :target => "_blank", "ExpressionExplorer.jl"), " — Reactive analysis (Pluto ecosystem)"),
                    Li(A(:href => "https://github.com/JuliaPluto/PlutoDependencyExplorer.jl", :class => "text-accent-600 dark:text-accent-400 hover:underline", :target => "_blank", "PlutoDependencyExplorer.jl"), " — Topological sort (Pluto ecosystem)"),
                ),
            ),
        )
    )
end

# --- Helpers ---

function _ArchBox(title, description, files)
    Card(class="bg-warm-100/50 dark:bg-warm-900/50",
        CardHeader(
            CardTitle(class="text-base", title)),
        CardContent(
            P(:class => "text-sm text-warm-600 dark:text-warm-400 mb-3", description),
            P(:class => "text-xs font-mono text-warm-500 dark:text-warm-500", files)))
end

GettingStartedIndex
