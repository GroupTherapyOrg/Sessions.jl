<div align="center">
  <img alt="Sessions.jl" src="assets/sessions_dark.svg" height="60">

  **A reactive Julia notebook IDE.**

  [![Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://grouptherapyorg.github.io/Sessions.jl/)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE.md)
</div>

---

![Sessions.jl demo](https://raw.githubusercontent.com/GroupTherapyOrg/Sessions.jl/main/assets/2026-03-23%2020.58.23.gif)  

---

> **Warning: Experimental, alpha-quality software.** Untested outside its own test suite. Rough edges everywhere. Everything is subject to breaking changes. If you need a reliable reactive notebook today, use [Pluto.jl](https://github.com/fonsp/Pluto.jl). This exists to explore ideas at the intersection of reactive notebooks, file-based collaboration, and WebAssembly compilation.

## What is Sessions.jl?

Sessions.jl is a reactive Julia notebook that runs in your browser as a local web IDE. It is designed around **plain `.jl` files that anyone can edit** — you in the browser, an AI assistant from the terminal, or a script in CI. A file watcher picks up all changes and the UI updates live.

**Key ideas:**

- **File-based collaboration.** The notebook is a plain `.jl` file. Edit in the browser, from the terminal, or programmatically. Changes from any source appear in real time via file watching.
- **Code/state separation.** Pure code lives in `.jl`, cached outputs in `.sessions.toml`. External edits never corrupt your execution state. Delete the cache anytime; re-run to regenerate.
- **Full IDE in the browser.** CodeMirror editor with Julia syntax highlighting, Shoelace file explorer with lazy loading, xterm.js terminal with real PTY shell. Everything in one window.
- **Pluto-compatible.** Same `.jl` file format, same reactivity engine (ExpressionExplorer + PlutoDependencyExplorer). Open the same file in Pluto or Sessions.
- **Integrated terminal.** Real PTY-backed shell via xterm.js. Type `julia` to get a REPL. Run build commands. Multiple tabs. All without leaving the notebook.
- **Runic.jl formatting.** Format individual cells or the entire notebook with one click via an isolated Runic.jl subprocess.
- **WASM experiments.** Compiling notebook interactivity to WebAssembly via [WasmTarget.jl](https://github.com/GroupTherapyOrg/WasmTarget.jl), so exported notebooks can run without a Julia server. Very early, barely works for sliders.

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

# Start in a project directory (file explorer shows that directory)
cd my_project/ && sessions

# Run headlessly (CI, scripts, automation)
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
│   ├── formatting.jl        # Runic.jl formatter (isolated subprocess)
│   ├── pty.jl               # PTY management (terminal subprocess)
│   ├── terminal_server.jl   # xterm.js to PTY WebSocket bridge
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

SessionsUI is what notebook code imports. It has zero heavy dependencies and compiles in ~300ms. Sessions.jl (the app) depends on SessionsUI, not the other way around.

## Code/State Separation

Sessions.jl splits your notebook into two files:

| File | Contains | Role |
|------|----------|------|
| `notebook.jl` | Cell code, cell order, fold/disabled metadata | **Source of truth** — editable from anywhere |
| `notebook.sessions.toml` | Cached outputs, stdout, runtime, errors | **Execution cache**, optional, deletable, auto-regenerated |

Anyone can freely edit the `.jl` file — the browser IDE, an external editor, or a script. The file watcher detects changes within a second, marks modified cells as stale, and the UI shows what needs re-execution.

## @bind Widgets

```julia
using SessionsUI: @bind, BoundSlider, BoundCheckBox, BoundTextField, BoundSelect

@bind x BoundSlider(1:100)
@bind name BoundTextField(default="world")
@bind flag BoundCheckBox()
@bind choice BoundSelect(["A", "B", "C"])
```

## Collaborative Editing

Since notebooks are plain `.jl` files, they work naturally with any external tool — AI assistants, other editors, scripts, CI pipelines:

1. **Edit in the browser** — write and run code in the web IDE
2. **Edit externally** — modify `notebook.jl` from any editor or tool
3. **File watcher** detects changes in under a second
4. **UI** marks modified cells as stale (orange indicator)
5. **Run Stale** re-executes only what changed

The `.sessions.toml` file caches execution state so reopening a notebook shows previous outputs without re-running everything. The integrated terminal lets you run commands, install packages, or start a Julia REPL without leaving the IDE.

## Built On

- [Pluto.jl](https://github.com/fonsp/Pluto.jl) file format and reactive engine ([ExpressionExplorer.jl](https://github.com/JuliaPluto/ExpressionExplorer.jl), [PlutoDependencyExplorer.jl](https://github.com/JuliaPluto/PlutoDependencyExplorer.jl))
- [Therapy.jl](https://github.com/GroupTherapyOrg/Therapy.jl) web framework (SSR, WebSocket channels, @island hydration)
- [WasmTarget.jl](https://github.com/GroupTherapyOrg/WasmTarget.jl) Julia-to-WebAssembly compiler
- [Malt.jl](https://github.com/JuliaPluto/Malt.jl) isolated worker processes
- [Runic.jl](https://github.com/fredrikekre/Runic.jl) code formatter
- [CodeMirror](https://codemirror.net/) code editor
- [Shoelace](https://shoelace.style/) web components (file explorer)
- [xterm.js](https://xtermjs.org/) terminal emulator

## Experiments

Things being explored, none production-ready, all likely to change or be removed:

- **JETLS integration:** real-time [JET.jl](https://github.com/aviatesk/JET.jl) diagnostics via LSP
- **WASM export:** compiling @bind interactivity to WebAssembly so exported notebooks run without a Julia server
- **Malt.jl workers:** each notebook tab runs in its own process for isolation

## License

MIT
