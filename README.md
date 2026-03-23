# Sessions.jl

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/sessions_dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/sessions_light.svg">
    <img alt="Sessions.jl" src="assets/sessions_light.svg" height="60">
  </picture>

  **A web-native reactive Julia notebook IDE. Pure Julia, agent-friendly, WASM-ready.**

  [![Docs](https://img.shields.io/badge/docs-stable-blue)](https://grouptherapyorg.github.io/Sessions.jl/)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE.md)
</div>

---

> **Warning: Experimental, alpha-quality software.** Largely built by AI agents (Claude Code). Untested outside its own test suite. Rough edges everywhere. Everything is subject to breaking changes. If you need a reliable reactive notebook today, use [Pluto.jl](https://github.com/fonsp/Pluto.jl). This exists to explore ideas at the intersection of reactive notebooks, agent-driven development, and WebAssembly compilation.

## What is Sessions.jl?

Sessions.jl is a reactive Julia notebook that runs in your browser as a local web IDE. It's designed for a workflow where **you and AI agents edit the same notebook files** -- the agent modifies `.jl` files directly, a file watcher picks up changes, and the UI updates live.

**Key ideas:**
- **Code/state separation** -- pure code in `.jl`, cached outputs in `.sessions.toml`. Agents never corrupt your execution state.
- **Web IDE** -- CodeMirror editor, Shoelace file explorer, xterm.js terminal, all served from a local Julia process.
- **Pluto-compatible** -- same `.jl` file format, same reactivity engine (ExpressionExplorer + PlutoDependencyExplorer). Open the same file in Pluto or Sessions.
- **Integrated terminal** -- real PTY-backed shell via xterm.js. Type `julia` to get a REPL. Run build commands. Everything in one window.
- **WASM experiments** -- compiling notebook interactivity to WebAssembly via [WasmTarget.jl](https://github.com/GroupTherapyOrg/WasmTarget.jl), so exported notebooks can run without a Julia server. Very early, barely works for sliders.

## Installation

Requires Julia 1.12+.

```julia
using Pkg
Pkg.Apps.add(url="https://github.com/GroupTherapyOrg/Sessions.jl")
```

This installs the `sessions` command to `~/.julia/bin/`.

## Quick Start

```bash
# Open a notebook in the web IDE
sessions my_notebook.jl

# Create a new notebook
sessions

# Run headlessly (CI, scripts, agents)
sessions run my_notebook.jl
```

The web IDE opens at `http://127.0.0.1:8080`.

Or from a Julia session:

```julia
using Sessions
Sessions.main(["my_notebook.jl"])
```

## Architecture

```
Sessions.jl/
├── src/
│   ├── Sessions.jl          # Core module
│   ├── types.jl             # Cell, Notebook, CellOutput
│   ├── format.jl            # .jl notebook parser/serializer (Pluto-compatible)
│   ├── analysis.jl          # Reactive dependency analysis
│   ├── kernel.jl            # Cell execution engine
│   ├── session.jl           # .sessions.toml cache read/write
│   ├── pty.jl               # PTY management (terminal subprocess)
│   ├── terminal_server.jl   # xterm.js <-> PTY WebSocket bridge
│   ├── web_server.jl        # WebSocket channel handlers
│   ├── web/                 # Web UI (Therapy.jl app)
│   │   ├── app.jl           # Web app entry point
│   │   └── src/components/  # Layout, NotebookPanel, FileExplorer, ReplPanel, etc.
│   └── worker/              # Malt.jl notebook workers (isolated execution)
├── SessionsUI/              # Lightweight notebook API (zero heavy deps)
│   └── src/
│       ├── SessionsUI.jl
│       └── widgets.jl       # @bind, Slider, Bond, etc.
└── test/
```

### Two Packages, One Repo

| Package | Purpose | Deps | How to use |
|---------|---------|------|-----------|
| **Sessions.jl** | The IDE app | Therapy.jl, Malt.jl, WasmTarget.jl, HTTP... | `Pkg.Apps.add(url=...)` |
| **SessionsUI** | Notebook API for `@bind` | UUIDs only (stdlib) | `using SessionsUI: @bind, BoundSlider` |

SessionsUI is what notebook code imports. It has zero heavy dependencies -- compiles in ~300ms. Sessions.jl (the app) depends on SessionsUI, not the other way around.

## Code/State Separation

Sessions.jl splits your notebook into two files:

| File | Contains | Role |
|------|----------|------|
| `notebook.jl` | Cell code, cell order, fold/disabled metadata | **Source of truth** -- safe for agents/editors to modify |
| `notebook.sessions.toml` | Cached outputs, stdout, runtime, errors | **Execution cache** -- optional, deletable, auto-regenerated |

An agent or script can freely edit the `.jl` file. The file watcher detects changes within a second, marks modified cells as stale, and the UI shows what needs re-execution.

## @bind Widgets

```julia
using SessionsUI: @bind, BoundSlider, BoundCheckBox, BoundTextField, BoundSelect

@bind x BoundSlider(1:100)
@bind name BoundTextField(default="world")
@bind flag BoundCheckBox()
@bind choice BoundSelect(["A", "B", "C"])
```

## Agent-Driven Development

Sessions.jl is built for the workflow where an AI agent (Claude Code, Cursor, etc.) edits your notebook files while you watch:

1. Agent edits `notebook.jl` (adds cells, modifies code)
2. File watcher detects changes in <1 second
3. UI marks modified cells as stale (orange indicator)
4. You click "Run Stale" or the agent runs `sessions run notebook.jl`
5. Outputs update, agent sees results

The `.sessions.toml` file caches execution state so reopening a notebook shows previous outputs without re-running everything.

## Built On

- [Pluto.jl](https://github.com/fonsp/Pluto.jl) file format + reactive engine ([ExpressionExplorer.jl](https://github.com/JuliaPluto/ExpressionExplorer.jl), [PlutoDependencyExplorer.jl](https://github.com/JuliaPluto/PlutoDependencyExplorer.jl))
- [Therapy.jl](https://github.com/GroupTherapyOrg/Therapy.jl) web framework (SSR, WebSocket channels, @island hydration)
- [WasmTarget.jl](https://github.com/GroupTherapyOrg/WasmTarget.jl) Julia-to-WebAssembly compiler
- [Malt.jl](https://github.com/JuliaPluto/Malt.jl) isolated worker processes
- [CodeMirror](https://codemirror.net/) code editor
- [Shoelace](https://shoelace.style/) web components (file explorer)
- [xterm.js](https://xtermjs.org/) terminal emulator

## Experiments

Things being explored -- none production-ready, all likely to change or be removed:

- **JETLS integration** -- real-time [JET.jl](https://github.com/aviatesk/JET.jl) diagnostics via LSP
- **Runic.jl formatting** -- auto-format cells on save
- **WASM export** -- compiling @bind interactivity to WebAssembly so exported notebooks don't need a running Julia server
- **Malt.jl workers** -- each notebook tab runs in its own process for isolation

## License

MIT
