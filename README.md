# Sessions.jl

A VSCode + Pluto hybrid IDE and notebook environment built entirely on [Therapy.jl](https://github.com/TherapeuticJulia/Therapy.jl).

## Vision

Sessions.jl is a **Therapy.jl application** that provides:

- **VSCode-like IDE**: File explorer, integrated terminal, multiple panes
- **Pluto-like Notebooks**: Reactive cells with code execution
- **Pure Therapy.jl UI**: All components rendered server-side using Therapy.jl
- **WebSocket Communication**: Real-time state sync between browser and server
- **Pluto Compatibility**: Copy-paste cells from Pluto notebooks (planned)

## Key Principle

Sessions follows the Therapy.jl application pattern:
- All UI is built with Therapy.jl components (`Div`, `Button`, `Input`, etc.)
- Server renders HTML using `render_page()` and `render_to_string()`
- WebSocket handles real-time communication (cell execution, file operations)
- Minimal client JavaScript - just transport, no rendering logic

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/TherapeuticJulia/Sessions.jl")
```

## Quick Start

```julia
using Sessions

# Start the development server
Sessions.dev()

# Open http://localhost:8080 in your browser
```

Or use the app entry point:
```bash
julia --project=. src/app.jl dev
```

## Current Features

- **Notebook Cells**: Add, edit, run, and delete cells
- **Code Execution**: Julia code runs in isolated module with stdout capture
- **File Explorer**: Browse project files, click to load into cells
- **Terminal**: Interactive Julia REPL in the browser
- **Real-time Sync**: All state changes broadcast via WebSocket

## Project Structure

```
Sessions.jl/
├── src/
│   ├── app.jl              # Entry point (like Therapy.jl apps)
│   ├── Sessions.jl         # Main module
│   ├── components/         # Therapy.jl UI components
│   │   ├── Layout.jl       # Main page layout + TopBar
│   │   ├── Sidebar.jl      # File explorer
│   │   └── Terminal.jl     # REPL terminal
│   ├── routes/             # Page routes
│   │   └── index.jl        # Main notebook page
│   ├── Notebook/           # Core notebook logic
│   │   ├── Cell.jl         # Cell data structure
│   │   └── Executor.jl     # Code execution
│   └── Server/             # HTTP + WebSocket server
│       └── WebSocketServer.jl
├── test/
│   └── runtests.jl
├── VISION.md               # Architecture and goals
├── CLAUDE.md               # Developer guide
└── Project.toml
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Browser                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    Sessions UI                             │  │
│  │  (HTML rendered by Therapy.jl, updated via WebSocket)     │  │
│  │                                                            │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │  │
│  │  │  Sidebar    │  │   Cells     │  │    Terminal     │   │  │
│  │  │  (files)    │  │  (notebook) │  │   (REPL)        │   │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────┘   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │ WebSocket                         │
└──────────────────────────────│──────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Sessions Server (Julia)                       │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  HTTP Server (serves Therapy.jl rendered pages)           │  │
│  └───────────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  WebSocket Handler                                         │  │
│  │  - Cell execution (execute code, return results)          │  │
│  │  - File operations (list, read, write)                    │  │
│  │  - Terminal I/O                                            │  │
│  │  - State broadcast (sends pre-rendered HTML)              │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Pluto Package Leverage (Planned)

Sessions will use standalone Pluto packages where they provide value:

- **ExpressionExplorer.jl**: Static analysis for dependency tracking
- **Malt.jl**: Isolated worker process execution

We don't fork Pluto - we build on its excellent standalone packages.

## Development Status

Sessions.jl is under active development as part of the TherapeuticJulia project.

**Working:**
- Basic notebook UI with cell management
- Code execution with output display
- File explorer with directory navigation
- Terminal with command execution
- WebSocket real-time sync

**In Progress:**
- Dependency tracking between cells
- Rich output rendering (plots, tables)
- Syntax highlighting

See [VISION.md](./VISION.md) for detailed architecture and roadmap.

## Related Projects

- [Therapy.jl](https://github.com/TherapeuticJulia/Therapy.jl) - Reactive web framework for Julia
- [WasmTarget.jl](https://github.com/TherapeuticJulia/WasmTarget.jl) - Julia to WebAssembly compiler

## License

MIT
