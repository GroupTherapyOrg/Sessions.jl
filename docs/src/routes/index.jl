# Sessions.jl docs landing page
#
# Web-native notebook IDE. Green accent, warm neutrals.
# Uses local components from PageComponents.jl (no Suite.jl).

function Index()
    Fragment(
        # Hero Section
        Div(:class => "py-20 sm:py-32",
            Div(:class => "text-center max-w-4xl mx-auto",
                Div(:class => "inline-flex items-center gap-2 border border-warm-200 dark:border-warm-700 bg-warm-100 dark:bg-warm-900 rounded-full px-4 py-1.5 mb-8",
                    Span(:class => "text-xs font-medium text-warm-600 dark:text-warm-400", "Open Source"),
                    Span(:class => "text-warm-300 dark:text-warm-600", "/"),
                    Span(:class => "text-xs font-medium text-accent-600 dark:text-accent-400", "Web IDE")
                ),
                H1(:class => "text-4xl sm:text-6xl lg:text-7xl font-serif font-semibold text-warm-800 dark:text-warm-300 tracking-tight leading-[1.1]",
                    "A reactive Julia notebook",
                    Br(),
                    "IDE with ",
                    Span(:class => "text-accent-600 dark:text-accent-400", "Sessions"),
                    Span(:class => "text-4xl sm:text-5xl lg:text-6xl font-light",
                        Span(:style => "color:#b08fd8;", "."),
                        Span(:class => "text-accent-600 dark:text-accent-400", "j"),
                        Span(:class => "text-accent-secondary-600 dark:text-accent-secondary-400", "l")
                    )
                ),
                P(:class => "mt-8 text-lg sm:text-xl text-warm-600 dark:text-warm-400 max-w-2xl mx-auto leading-relaxed",
                    "A Julia notebook IDE with Pluto-compatible reactivity, integrated terminal, and code formatting. Edit from the browser or any tool — changes sync in real time."
                ),
                Div(:class => "mt-10 flex flex-col sm:flex-row justify-center gap-4",
                    A(:href => "./getting-started/",
                      :class => "inline-flex items-center justify-center h-12 px-8 text-base font-medium rounded-md bg-accent-600 text-white hover:bg-accent-700 transition-colors no-underline",
                      "Get Started"),
                    A(:href => "https://github.com/GroupTherapyOrg/Sessions.jl",
                      :class => "inline-flex items-center justify-center h-12 px-8 text-base font-medium rounded-md border border-warm-300 dark:border-warm-600 text-warm-800 dark:text-warm-300 hover:bg-warm-100 dark:hover:bg-warm-800 transition-colors no-underline",
                      :target => "_blank", "View on GitHub")
                )
            )
        ),

        # Install Showcase
        Div(:class => "py-16",
            H2(:class => "text-3xl font-serif font-semibold text-center text-warm-800 dark:text-warm-300 mb-4",
                "One command to start"
            ),
            P(:class => "text-center text-warm-600 dark:text-warm-400 mb-10 max-w-lg mx-auto",
                "Install as a Julia app. Open any notebook in the browser. Run headlessly for CI."
            ),
            Div(:class => "bg-warm-900 dark:bg-warm-950 rounded-xl border border-warm-800 dark:border-warm-800 p-8 max-w-3xl mx-auto overflow-x-auto shadow-xl",
                Div(:class => "flex items-center gap-2 mb-5",
                    Span(:class => "w-3 h-3 rounded-full bg-red-500/60"),
                    Span(:class => "w-3 h-3 rounded-full bg-yellow-500/60"),
                    Span(:class => "w-3 h-3 rounded-full bg-accent-500/60")
                ),
                CodeBlock(language="bash", """# Install as a Julia app
julia -e 'using Pkg; Pkg.Apps.add(url="https://github.com/GroupTherapyOrg/Sessions.jl")'

# Open a notebook in the web IDE
sessions my_notebook.jl

# Start in your project directory
cd my_project/ && sessions

# Run headlessly (CI, scripts, automation)
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
                    "Web IDE",
                    "CodeMirror editor, Shoelace file explorer, xterm.js terminal. A full IDE in the browser served from a local Julia process.",
                    "M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
                ),
                _FeatureCard(
                    "Code Formatting",
                    "Format individual cells or the entire notebook with Runic.jl. One-click formatting in the toolbar and cell menu.",
                    "M4 6h16M4 10h16M4 14h10M4 18h12"
                ),
                _FeatureCard(
                    "@bind Widgets",
                    "Slider, TextField, CheckBox, Select, NumberField. PlutoUI-compatible @bind protocol for interactive notebooks.",
                    "M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4"
                ),
                _FeatureCard(
                    "Collaborative Editing",
                    "Code/state separation lets you edit from the browser, terminal, or any tool. File watcher syncs changes in real time.",
                    "M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                )
            )
        ),

        # Stats bar
        Div(:class => "py-12 border-y border-warm-200 dark:border-warm-700",
            Div(:class => "grid grid-cols-2 md:grid-cols-4 gap-8 max-w-4xl mx-auto text-center",
                _StatItem("2000+", "Tests"),
                _StatItem("6+", "Widgets"),
                _StatItem("Pure", "Julia"),
                _StatItem("2", "Packages")
            )
        ),

        # Code/State Separation Section
        Div(:class => "py-16",
            H2(:class => "text-3xl font-serif font-semibold text-center text-warm-800 dark:text-warm-300 mb-4",
                "Built for collaboration"
            ),
            P(:class => "text-center text-warm-600 dark:text-warm-400 mb-12 max-w-2xl mx-auto",
                "Sessions.jl separates code from execution state. Your notebook is two files, not one."
            ),

            # Two-file diagram
            Div(:class => "grid md:grid-cols-2 gap-8 max-w-4xl mx-auto px-4 mb-12",
                Card(class="border-accent-200 dark:border-accent-800",
                    CardHeader(
                        Div(:class => "flex items-center gap-4",
                            Div(:class => "w-11 h-11 bg-accent-100 dark:bg-accent-900/30 rounded-lg flex items-center justify-center shrink-0",
                                Span(:class => "text-accent-600 dark:text-accent-400 font-mono text-sm font-bold", ".jl")
                            ),
                            Div(
                                CardTitle("notebook.jl"),
                                CardDescription("Source of truth"),
                            ),
                        ),
                    ),
                    CardContent(
                        Div(:class => "space-y-2 text-sm text-warm-600 dark:text-warm-400",
                            P("Cell code, cell order, fold/disabled metadata"),
                            P(:class => "font-medium text-warm-800 dark:text-warm-300",
                                "Safe to modify from any editor, terminal, or tool."
                            ),
                            P("Pluto-compatible format. Version-controlled."),
                        ),
                    ),
                ),
                Card(class="border-warm-300 dark:border-warm-700",
                    CardHeader(
                        Div(:class => "flex items-center gap-4",
                            Div(:class => "w-11 h-11 bg-warm-200 dark:bg-warm-800 rounded-lg flex items-center justify-center shrink-0",
                                Span(:class => "text-warm-600 dark:text-warm-400 font-mono text-sm font-bold", ".toml")
                            ),
                            Div(
                                CardTitle("notebook.sessions.toml"),
                                CardDescription("Execution cache"),
                            ),
                        ),
                    ),
                    CardContent(
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

            # Workflow
            Div(:class => "max-w-3xl mx-auto",
                Card(class="bg-warm-100/50 dark:bg-warm-900/50",
                    CardHeader(
                        CardTitle("How collaborative editing works"),
                    ),
                    CardContent(
                        Div(:class => "space-y-4 text-sm text-warm-600 dark:text-warm-400",
                            Div(:class => "flex gap-3",
                                Span(:class => "text-accent-600 dark:text-accent-400 font-mono font-bold shrink-0", "1."),
                                P("Edit in the browser IDE, or modify the .jl file from any editor or tool. Both at the same time."),
                            ),
                            Div(:class => "flex gap-3",
                                Span(:class => "text-accent-600 dark:text-accent-400 font-mono font-bold shrink-0", "2."),
                                P("The built-in file watcher detects all changes within ~0.5 seconds."),
                            ),
                            Div(:class => "flex gap-3",
                                Span(:class => "text-accent-600 dark:text-accent-400 font-mono font-bold shrink-0", "3."),
                                P("Changed cells are marked stale. Old outputs remain visible for reference."),
                            ),
                            Div(:class => "flex gap-3",
                                Span(:class => "text-accent-600 dark:text-accent-400 font-mono font-bold shrink-0", "4."),
                                P("Click Run Stale, or run ", Code("sessions run notebook.jl"), " from the integrated terminal."),
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
                Table(:class => "w-full text-sm",
                    Thead(Tr(
                        Th(:class => _TH_CLS, ""),
                        Th(:class => _TH_CLS, "Sessions.jl"),
                        Th(:class => _TH_CLS, "Pluto"),
                    )),
                    Tbody(
                        Tr(:class => _TR_CLS,
                            Td(:class => _TD_LABEL_CLS, "Code storage"),
                            Td(:class => _TD_CLS, ".jl (cell code + order)"),
                            Td(:class => _TD_CLS, ".jl (code + order + embedded pkg state)"),
                        ),
                        Tr(:class => _TR_CLS,
                            Td(:class => _TD_LABEL_CLS, "Output storage"),
                            Td(:class => _TD_CLS, ".sessions.toml (separate file)"),
                            Td(:class => _TD_CLS, "In-memory only (recomputed on open)"),
                        ),
                        Tr(:class => _TR_CLS,
                            Td(:class => _TD_LABEL_CLS, "External edits"),
                            Td(:class => _TD_CLS, "Safe: file watcher auto-detects changes"),
                            Td(:class => _TD_CLS, "Risky: may break embedded metadata"),
                        ),
                        Tr(:class => _TR_CLS,
                            Td(:class => _TD_LABEL_CLS, "Startup"),
                            Td(:class => _TD_CLS, "Instant: outputs restored from cache"),
                            Td(:class => _TD_CLS, "Full re-execution on every open"),
                        ),
                        Tr(:class => _TR_CLS,
                            Td(:class => _TD_LABEL_CLS, "Reactivity"),
                            Td(:class => _TD_CLS, "Same model (ExpressionExplorer.jl)"),
                            Td(:class => _TD_CLS, "Same model"),
                        ),
                        Tr(:class => _TR_CLS,
                            Td(:class => _TD_LABEL_CLS, "File format"),
                            Td(:class => _TD_CLS, "Pluto-compatible .jl files"),
                            Td(:class => _TD_CLS, "Pluto .jl files"),
                        ),
                        Tr(:class => _TR_CLS,
                            Td(:class => _TD_LABEL_CLS, "Interface"),
                            Td(:class => _TD_CLS, "Browser (web IDE with integrated terminal)"),
                            Td(:class => _TD_CLS, "Browser (HTTP server)"),
                        ),
                        Tr(:class => _TR_CLS,
                            Td(:class => _TD_LABEL_CLS, "Formatting"),
                            Td(:class => _TD_CLS, "Runic.jl (per-cell and notebook-wide)"),
                            Td(:class => _TD_CLS, "None built-in"),
                        ),
                    ),
                ),
            ),
        ),

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

function _StatItem(number, label)
    Div(
        P(:class => "text-3xl sm:text-4xl font-serif font-bold text-accent-600 dark:text-accent-400", number),
        P(:class => "text-sm text-warm-600 dark:text-warm-400 mt-1", label)
    )
end

# Export the page component
Index
