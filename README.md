# Sessions.jl

A VSCode + Pluto hybrid IDE and notebook environment built entirely on [Therapy.jl](https://github.com/TherapeuticJulia/Therapy.jl).

## Vision

Sessions.jl is a **Therapy.jl component** that provides:

- **VSCode-like IDE**: File explorer, integrated terminal, multiple panes
- **Pluto-like Notebooks**: Reactive cells with dependency tracking
- **Full-Stack Integration**: Embed notebooks in any Therapy.jl application
- **Static Export**: Build notebooks to GitHub Pages with pre-computed outputs
- **Pure Julia**: All UI compiles to WebAssembly via WasmTarget.jl

## Key Principle

Sessions is a Therapy.jl component first, notebook second. This means:
- Uses Therapy.jl signals, effects, and components
- Can be embedded in any Therapy.jl application
- Follows the same reactive patterns as the rest of your app

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/TherapeuticJulia/Sessions.jl")
```

## Quick Start

```julia
using Sessions

# Start the full IDE
Sessions.dev()

# Open http://localhost:8080 in your browser
```

## Embedding in Your App

```julia
using Therapy
using Sessions

MyApp = island(:MyApp) do
    Div(
        Header("My Data Science App"),

        # Embed a notebook as just another component
        NotebookSession(:notebook_path => "analysis.jl"),

        Footer("Powered by Sessions.jl")
    )
end
```

## Static Export

Build notebooks to static HTML for GitHub Pages:

```julia
using Sessions

# Single notebook
Sessions.build("notebook.jl", "dist/")

# All notebooks in a directory
Sessions.build_static_site("notebooks/", "dist/")
```

## Architecture

```
Sessions.jl
├── Components/          # Therapy.jl UI components
│   ├── SessionsApp.jl   # Main IDE component
│   ├── FileExplorer.jl  # File tree
│   ├── Terminal.jl      # Browser terminal
│   └── Notebook/        # Notebook components
├── Server/              # WebSocket server
│   ├── Filesystem.jl    # File operations
│   ├── Terminal.jl      # PTY handling
│   └── Execution.jl     # Cell execution
├── Notebook/            # Core notebook logic
│   ├── Cell.jl          # Cell data structure
│   ├── DependencyGraph.jl  # Reactive deps
│   └── Executor.jl      # Malt.jl wrapper
└── Export/              # Static site generation
```

## Pluto Package Leverage

Sessions uses standalone Pluto packages where they provide value:

- **ExpressionExplorer.jl**: Static analysis for dependency tracking
- **Malt.jl**: Isolated worker process execution

We don't fork Pluto - we build on its excellent standalone packages.

## Development Status

Sessions.jl is under active development as part of the TherapeuticJulia project.

See [VISION.md](./VISION.md) for detailed architecture and roadmap.

## Related Projects

- [Therapy.jl](https://github.com/TherapeuticJulia/Therapy.jl) - Reactive web framework for Julia
- [WasmTarget.jl](https://github.com/TherapeuticJulia/WasmTarget.jl) - Julia to WebAssembly compiler

## License

MIT
