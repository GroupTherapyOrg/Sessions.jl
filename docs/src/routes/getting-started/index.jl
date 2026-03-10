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

GettingStartedIndex
