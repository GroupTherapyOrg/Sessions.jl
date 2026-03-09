# Sessions.jl docs landing page
#
# Terminal-native notebook IDE. Green accent, warm neutrals.

function Index()
    Fragment(
        # Hero Section
        Div(:class => "py-20 sm:py-32",
            Div(:class => "text-center max-w-4xl mx-auto",
                Div(:class => "inline-flex items-center gap-2 border border-warm-200 dark:border-warm-700 bg-warm-100 dark:bg-warm-900 rounded-full px-4 py-1.5 mb-8",
                    Span(:class => "text-xs font-medium text-warm-600 dark:text-warm-400", "Open Source"),
                    Span(:class => "text-warm-300 dark:text-warm-600", "/"),
                    Span(:class => "text-xs font-medium text-accent-600 dark:text-accent-400", "Terminal IDE")
                ),
                H1(:class => "text-4xl sm:text-6xl lg:text-7xl font-serif font-semibold text-warm-800 dark:text-warm-300 tracking-tight leading-[1.1]",
                    "Terminal-native",
                    Br(),
                    "Julia notebooks with ",
                    Span(:class => "text-accent-600 dark:text-accent-400", "Sessions"),
                    Span(:class => "text-warm-400 dark:text-warm-600 text-4xl sm:text-5xl lg:text-6xl font-light",
                        Span(:style => "color: var(--jl-dot)", "."),
                        Span(:style => "color: var(--jl-j)", "j"),
                        Span(:style => "color: var(--jl-l)", "l")
                    )
                ),
                P(:class => "mt-8 text-lg sm:text-xl text-warm-600 dark:text-warm-400 max-w-2xl mx-auto leading-relaxed",
                    "Reactive notebooks in your terminal. Pluto-compatible format, full IDE experience, real-time diagnostics."
                ),
                Div(:class => "mt-10 flex flex-col sm:flex-row justify-center gap-4",
                    Main.Button(variant="default", class="h-12 px-8 text-base",
                        A(:href => "./getting-started/", :class => "text-white no-underline", "Get Started")
                    ),
                    Main.Button(variant="outline", class="h-12 px-8 text-base",
                        A(:href => "https://github.com/GroupTherapyOrg/Sessions.jl", :class => "no-underline text-warm-800 dark:text-warm-300", :target => "_blank", "View on GitHub")
                    )
                )
            )
        ),

        # Terminal Code Showcase
        Div(:class => "py-16",
            H2(:class => "text-3xl font-serif font-semibold text-center text-warm-800 dark:text-warm-300 mb-4",
                "Your notebook, in the terminal"
            ),
            P(:class => "text-center text-warm-600 dark:text-warm-400 mb-10 max-w-lg mx-auto",
                "One command to open, edit, and run reactive Julia notebooks. No browser required."
            ),
            Div(:class => "bg-warm-900 dark:bg-warm-950 rounded-xl border border-warm-800 dark:border-warm-800 p-8 max-w-3xl mx-auto overflow-x-auto shadow-xl",
                Div(:class => "flex items-center gap-2 mb-5",
                    Span(:class => "w-3 h-3 rounded-full bg-red-500/60"),
                    Span(:class => "w-3 h-3 rounded-full bg-yellow-500/60"),
                    Span(:class => "w-3 h-3 rounded-full bg-green-500/60")
                ),
                Main.CodeBlock(language="bash", """# Install as a Julia app
julia -e 'using Pkg; Pkg.Apps.add(url=\"https://github.com/GroupTherapyOrg/Sessions.jl\")'

# Open a notebook
sessions my_notebook.jl

# Create a new notebook
sessions

# Run headlessly (CI, scripts)
sessions run my_notebook.jl""")
            )
        ),

        # Feature Grid
        Div(:class => "py-16",
            H2(:class => "text-3xl font-serif font-semibold text-center text-warm-800 dark:text-warm-300 mb-12",
                "Everything you need"
            ),
            Div(:class => "grid md:grid-cols-3 gap-8 max-w-5xl mx-auto px-4",
                _FeatureCard(
                    "Reactive Notebooks",
                    "Cells auto-re-run when dependencies change. Pluto-style reactivity powered by ExpressionExplorer.jl.",
                    "M13 10V3L4 14h7v7l9-11h-7z"
                ),
                _FeatureCard(
                    "Pluto Compatibility",
                    "Load, edit, and save Pluto .jl notebooks natively. Same file format, same reactivity model.",
                    "M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                ),
                _FeatureCard(
                    "Terminal IDE",
                    "File browser, REPL panel, diagnostics panel, tab bar, activity bar, status bar. A full IDE in your terminal.",
                    "M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
                ),
                _FeatureCard(
                    "Real-time Diagnostics",
                    "JETLS (JET.jl LSP) integration catches type errors and undefined variables as you type.",
                    "M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"
                ),
                _FeatureCard(
                    "@bind Widgets",
                    "Slider, TextField, CheckBox, Select, NumberField. PlutoUI-compatible @bind protocol for interactive notebooks.",
                    "M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4"
                ),
                _FeatureCard(
                    "Agent-first Notebook",
                    "Code/state separation lets LLMs, IDEs, and scripts safely modify notebooks while the TUI watches and reacts.",
                    "M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                )
            )
        ),

        # Stats bar
        Div(:class => "py-12 border-y border-warm-200 dark:border-warm-700",
            Div(:class => "grid grid-cols-2 md:grid-cols-4 gap-8 max-w-4xl mx-auto text-center",
                _StatItem("3600+", "Tests"),
                _StatItem("5+", "Widgets"),
                _StatItem("20+", "TUI Components"),
                _StatItem("3", "Layers")
            )
        ),

        # Code/State Separation Section
        Div(:class => "py-16",
            H2(:class => "text-3xl font-serif font-semibold text-center text-warm-800 dark:text-warm-300 mb-4",
                "Agent-ready architecture"
            ),
            P(:class => "text-center text-warm-600 dark:text-warm-400 mb-12 max-w-2xl mx-auto",
                "Sessions.jl separates code from execution state. Your notebook is two files, not one."
            ),

            # Two-file diagram
            Div(:class => "grid md:grid-cols-2 gap-8 max-w-4xl mx-auto px-4 mb-12",
                Main.Card(class="border-accent-200 dark:border-accent-800",
                    Main.CardHeader(
                        Div(:class => "flex items-center gap-3",
                            Div(:class => "w-8 h-8 bg-accent-100 dark:bg-accent-900/30 rounded-md flex items-center justify-center",
                                Span(:class => "text-accent-600 dark:text-accent-400 font-mono text-xs font-bold", ".jl")
                            ),
                            Div(
                                Main.CardTitle("notebook.jl"),
                                Main.CardDescription("Source of truth"),
                            ),
                        ),
                    ),
                    Main.CardContent(
                        Div(:class => "space-y-2 text-sm text-warm-600 dark:text-warm-400",
                            P("Cell code, cell order, fold/disabled metadata"),
                            P(:class => "font-medium text-warm-800 dark:text-warm-300",
                                "Safe for agents, LLMs, IDEs, and scripts to modify directly."
                            ),
                            P("Pluto-compatible format. Version-controlled."),
                        ),
                    ),
                ),
                Main.Card(class="border-warm-300 dark:border-warm-700",
                    Main.CardHeader(
                        Div(:class => "flex items-center gap-3",
                            Div(:class => "w-8 h-8 bg-warm-200 dark:bg-warm-800 rounded-md flex items-center justify-center",
                                Span(:class => "text-warm-600 dark:text-warm-400 font-mono text-xs font-bold", ".toml")
                            ),
                            Div(
                                Main.CardTitle("notebook.session.toml"),
                                Main.CardDescription("Execution cache"),
                            ),
                        ),
                    ),
                    Main.CardContent(
                        Div(:class => "space-y-2 text-sm text-warm-600 dark:text-warm-400",
                            P("Cached outputs, stdout, runtimes, error messages"),
                            P(:class => "font-medium text-warm-800 dark:text-warm-300",
                                "Optional, gitignored, auto-generated. Delete it anytime."
                            ),
                            P("Outputs restored instantly on restart. No re-execution needed."),
                        ),
                    ),
                ),
            ),

            # Agent workflow
            Div(:class => "max-w-3xl mx-auto",
                Main.Card(class="bg-warm-100/50 dark:bg-warm-900/50",
                    Main.CardHeader(
                        Main.CardTitle("How agent-driven development works"),
                    ),
                    Main.CardContent(
                        Div(:class => "space-y-4 text-sm text-warm-600 dark:text-warm-400",
                            Div(:class => "flex gap-3",
                                Span(:class => "text-accent-600 dark:text-accent-400 font-mono font-bold shrink-0", "1."),
                                P("An external tool (LLM agent, IDE, script) modifies cell code in the .jl file."),
                            ),
                            Div(:class => "flex gap-3",
                                Span(:class => "text-accent-600 dark:text-accent-400 font-mono font-bold shrink-0", "2."),
                                P("The built-in file watcher detects the change within ~0.5 seconds."),
                            ),
                            Div(:class => "flex gap-3",
                                Span(:class => "text-accent-600 dark:text-accent-400 font-mono font-bold shrink-0", "3."),
                                P("Changed cells are marked stale — old outputs remain visible for reference."),
                            ),
                            Div(:class => "flex gap-3",
                                Span(:class => "text-accent-600 dark:text-accent-400 font-mono font-bold shrink-0", "4."),
                                P("You re-run stale cells. New outputs are cached to .session.toml."),
                            ),
                        ),
                    ),
                ),
            ),
        ),

        # Coming from Pluto section
        Div(:class => "py-16 border-t border-warm-200 dark:border-warm-700",
            H2(:class => "text-3xl font-serif font-semibold text-center text-warm-800 dark:text-warm-300 mb-12",
                "Coming from Pluto?"
            ),
            Div(:class => "max-w-4xl mx-auto overflow-x-auto",
                Main.Table(
                    Main.TableHeader(Main.TableRow(
                        Main.TableHead(""),
                        Main.TableHead("Sessions.jl"),
                        Main.TableHead("Pluto"),
                    )),
                    Main.TableBody(
                        Main.TableRow(
                            Main.TableCell(:class => "font-medium text-warm-800 dark:text-warm-300", "Code storage"),
                            Main.TableCell(".jl (cell code + order)"),
                            Main.TableCell(".jl (code + order + embedded pkg state)"),
                        ),
                        Main.TableRow(
                            Main.TableCell(:class => "font-medium text-warm-800 dark:text-warm-300", "Output storage"),
                            Main.TableCell(".session.toml (separate file)"),
                            Main.TableCell("In-memory only (recomputed on open)"),
                        ),
                        Main.TableRow(
                            Main.TableCell(:class => "font-medium text-warm-800 dark:text-warm-300", "External edits"),
                            Main.TableCell("Safe — file watcher auto-detects changes"),
                            Main.TableCell("Risky — may break embedded metadata"),
                        ),
                        Main.TableRow(
                            Main.TableCell(:class => "font-medium text-warm-800 dark:text-warm-300", "Startup"),
                            Main.TableCell("Instant — outputs restored from cache"),
                            Main.TableCell("Full re-execution on every open"),
                        ),
                        Main.TableRow(
                            Main.TableCell(:class => "font-medium text-warm-800 dark:text-warm-300", "Reactivity"),
                            Main.TableCell("Same model (ExpressionExplorer.jl)"),
                            Main.TableCell("Same model"),
                        ),
                        Main.TableRow(
                            Main.TableCell(:class => "font-medium text-warm-800 dark:text-warm-300", "File format"),
                            Main.TableCell("Pluto-compatible .jl files"),
                            Main.TableCell("Pluto .jl files"),
                        ),
                        Main.TableRow(
                            Main.TableCell(:class => "font-medium text-warm-800 dark:text-warm-300", "Interface"),
                            Main.TableCell("Terminal TUI (Tachikoma.jl)"),
                            Main.TableCell("Browser (HTTP server)"),
                        ),
                    ),
                ),
            ),
        ),

        # Architecture Section
        Div(:class => "py-16",
            H2(:class => "text-3xl font-serif font-semibold text-center text-warm-800 dark:text-warm-300 mb-12",
                "Three-layer architecture"
            ),
            Div(:class => "grid md:grid-cols-3 gap-8 max-w-5xl mx-auto px-4",
                _ArchCard("Layer 1: Engine", "Pure Julia, no UI",
                    "types.jl, format.jl, analysis.jl, kernel.jl, run.jl, bind.jl, session.jl, watcher.jl"),
                _ArchCard("Layer 2: TUI", "Tachikoma.jl terminal interface",
                    "app.jl, notebook_view.jl, cell_widget.jl, output_widget.jl, file_panel.jl, repl_panel.jl, diagnostics_panel.jl"),
                _ArchCard("Layer 3: CLI", "Entry points & integration",
                    "cli.jl (ARGS parsing), JETLS LSP client, JET.jl batch analysis")
            )
        )
    )
end

# --- Helper components ---

function _FeatureCard(title, description, icon_path)
    Div(:class => "text-center p-6",
        Div(:class => "w-12 h-12 bg-warm-100 dark:bg-warm-800 rounded-lg border border-warm-200 dark:border-warm-700 flex items-center justify-center mx-auto mb-5",
            Svg(:class => "w-6 h-6 text-accent-600 dark:text-accent-400", :fill => "none", :viewBox => "0 0 24 24", :stroke => "currentColor", :stroke_width => "1.5",
                Path(:stroke_linecap => "round", :stroke_linejoin => "round", :d => icon_path)
            )
        ),
        H3(:class => "text-lg font-serif font-semibold text-warm-800 dark:text-warm-300 mb-3", title),
        P(:class => "text-warm-600 dark:text-warm-400 leading-relaxed text-sm", description)
    )
end

function _ArchCard(title, subtitle, components)
    Main.Card(class="bg-warm-100/50 dark:bg-warm-900/50",
        Main.CardHeader(
            Main.CardTitle(title),
            Main.CardDescription(
                Span(:class => "text-sm font-medium text-accent-600 dark:text-accent-400", subtitle)
            )
        ),
        Main.CardContent(
            P(:class => "text-sm text-warm-600 dark:text-warm-400", components)
        )
    )
end

function _StatItem(number, label)
    Div(
        P(:class => "text-3xl sm:text-4xl font-serif font-bold text-accent-600 dark:text-accent-400", number),
        P(:class => "text-sm text-warm-600 dark:text-warm-400 mt-1", label)
    )
end

# Export the page component
Index
