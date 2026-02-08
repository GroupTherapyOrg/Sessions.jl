# Sessions.jl

<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="logo/sessions_dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="logo/sessions_light.svg">
    <img alt="Sessions.jl" src="logo/sessions_light.svg" height="60">
  </picture>
</div>

A reactive notebook IDE built with [Therapy.jl](https://github.com/TherapeuticJulia/Therapy.jl) and [Suite.jl](https://github.com/TherapeuticJulia/Suite.jl). Full Pluto.jl compatibility with a VSCode-inspired interface.

## Features

- **Reactive Notebooks** -- Cells auto-re-run when dependencies change (Pluto-style reactivity)
- **Pluto Compatibility** -- Load, edit, and save Pluto `.jl` notebooks. @bind widgets work out of the box
- **Suite.jl Components** -- 60+ UI components (Card, Badge, Alert, Tabs, Dialog, etc.)
- **IDE Shell** -- File browser, integrated terminal, package panel, workspace inspector
- **Portable Runtime** -- Embed `NotebookApp` in any Therapy.jl application
- **5 Built-in Widgets** -- Slider, TextField, CheckBox, Select, NumberField (PlutoUI protocol)
- **Export** -- HTML (self-contained, dark mode) and Julia script export
- **Theme System** -- CSS custom properties, warm neutrals, Julia-branded accent colors

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/TherapeuticJulia/Sessions.jl")
```

## Quick Start

```julia
using Sessions

# Start the IDE server
Sessions.serve()
# Open http://localhost:9284
```

### Embed in a Therapy.jl App

```julia
using Therapy, Sessions

function MyApp()
    Div(:class => "my-research-platform",
        H1("Research Dashboard"),
        # Embed a notebook with options
        Sessions.NotebookApp(
            options=NotebookOptions(
                show_toolbar=true,
                editable=true,
                max_height="600px",
                theme="ocean"
            )
        )
    )
end
```

### NotebookOptions

| Option | Default | Description |
|--------|---------|-------------|
| `show_header` | `true` | Show notebook header bar |
| `show_toolbar` | `true` | Show cell toolbar (run, move, fold, delete) |
| `show_add_cell` | `true` | Show add-cell buttons between cells |
| `show_output` | `true` | Show cell output |
| `editable` | `true` | Allow code editing |
| `runnable` | `true` | Allow cell execution |
| `max_height` | `nothing` | CSS max-height for scrollable container |
| `theme` | `"default"` | Theme name (default, ocean, minimal, nature) |

## Architecture

Sessions.jl has a 5-layer architecture:

```
+---------------------------------------------------------+
|  IDE Shell (standalone application)                      |
|  Layout, Sidebar, NotebookTabs, StatusBar, Terminal      |
+---------------------------------------------------------+
|  IDE Components (Suite.jl rewrite)                       |
|  CellCard, CellToolbar, MarkdownCell, OutputRenderer     |
|  FileBrowser, SearchReplace, CommandPalette               |
|  PackagePanel, WorkspaceInspector, KeyboardShortcuts     |
+---------------------------------------------------------+
|  Server (Therapy.jl WebSocket signals + channels)        |
|  App.jl, Channels.jl, Signals.jl, server.jl             |
+---------------------------------------------------------+
|  Bonds (@bind protocol, widget rendering)                |
|  Slider, TextField, CheckBox, Select, NumberField        |
+---------------------------------------------------------+
|  Engine (kept from original, no UI)                      |
|  Cell, Notebook, Reactivity, Workspace, Worker           |
|  FileFormat (Parse.jl, Write.jl)                         |
+---------------------------------------------------------+
```

## Cell Layout

Matches the SVG design -- output above code:

```
  Output rendered in base layer (plain text, serif for markdown)
  - - - - - - - - - - - - - - - (dotted separator)
  | Code card with left accent bar
  | - warm-50 / dark:#111110 background
  | - Left accent: green (output), purple (markdown), neutral (idle), red (error)
  | - Hover: run button, move, fold, delete
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Shift+Enter` | Run cell |
| `Ctrl+Enter` | Run cell, stay in cell |
| `Ctrl+Shift+Enter` | Run all cells |
| `Ctrl+S` | Save notebook |
| `Ctrl+P` | Command palette |
| `Ctrl+F` | Search/replace |
| `Ctrl+Shift+N` | New cell |
| `Ctrl+Shift+D` | Delete cell |
| `Alt+Up/Down` | Move cell up/down |

## @bind Widgets

Sessions.jl implements the full AbstractPlutoDingetjes `@bind` protocol:

```julia
@bind x Slider(1:100)
@bind name TextField()
@bind flag CheckBox()
@bind choice Select(["A", "B", "C"])
@bind n NumberField(1:10)
```

Each widget supports `initial_value`, `transform_value`, `validate_value`, and `possible_values`.

## WebSocket Protocol

The server uses Therapy.jl's signal/channel system:

**Signals** (server to client, per-cell):
- `cell_state_{id}` -- Cell state (IDLE, RUNNING, ERROR, etc.)
- `cell_output_{id}` -- Rendered HTML output
- `cell_runtime_{id}` -- Execution time in ms

**Channels** (client to server):
- `execute` -- Run a cell
- `add_cell` / `delete_cell` / `move_cell` -- Cell management
- `toggle_markdown` -- Toggle markdown cell mode
- `save_notebook` -- Save to disk
- `set_bond` -- Update @bind value

## Testing

```bash
# Run all tests (1097 tests)
julia +1.12 --project=. test/runtests.jl

# Run benchmarks (16 benchmarks)
julia +1.12 --project=. test/benchmarks.jl

# Run Pluto compatibility smoke test (651 tests)
julia +1.12 --project=. test/pluto_smoke_test.jl
```

## Project Structure

```
Sessions.jl/
  src/
    Sessions.jl              # Main module (154 exports)
    app.jl                   # Entry point
    Engine/                  # Core notebook engine
      Cell.jl                # Cell struct, CellState, CellOutput
      Notebook.jl            # Notebook container, metadata
      Reactivity.jl          # Dependency analysis, execution order
      Workspace.jl           # Isolated module execution
      Worker.jl              # Rich MIME output
      Output.jl              # HTML rendering utilities
      FileFormat/            # Pluto .jl file format
        Parse.jl             # Load notebooks
        Write.jl             # Save/export notebooks
    Server/                  # HTTP + WebSocket
      App.jl                 # Server setup, routes
      server.jl              # Global state, file browser
      Channels.jl            # WebSocket channel handlers
      Signals.jl             # Per-cell signal management
    IDE/                     # Suite.jl UI components
      Layout.jl              # Main IDE layout
      CellCard.jl            # Cell card (output + code)
      CellToolbar.jl         # Cell action toolbar
      CellState.jl           # State badges, indicators
      CellEditor.jl          # CodeMirror integration
      MarkdownCell.jl        # Markdown rendering
      OutputRenderer.jl      # Output display + styles
      NotebookTabs.jl        # Multi-notebook tabs
      StatusBar.jl           # Kernel status, git, connection
      Sidebar.jl             # File tree, panels
      FileBrowser.jl         # File explorer
      TerminalPanel.jl       # Terminal UI
      PackagePanel.jl        # Package management
      WorkspaceInspector.jl  # Variable browser
      SearchReplace.jl       # Find/replace
      CommandPalette.jl      # Command palette
      KeyboardShortcuts.jl   # Keyboard shortcuts
      RunControls.jl         # Run all / interrupt
    components/              # Legacy + island components
      islands/               # Wasm islands
        widgets/             # @bind widgets
      server/                # SSR components
  test/
    runtests.jl              # Main test suite (1097 tests)
    benchmarks.jl            # Performance benchmarks
    pluto_smoke_test.jl      # Pluto compatibility tests
    fixtures/                # Test notebooks
  Project.toml
```

## Design System

- **Accent**: Julia green `#389826` (primary), blue `#4063d8` (secondary)
- **Neutrals**: warm-50 through warm-950 (no stone/neutral/gray)
- **Typography**: EB Garamond serif (markdown), JetBrains Mono (code)
- **Cell accent bars**: green (output), purple `#9558b2` (markdown), red `#cb3c33` (error), warm (idle)

## Related Projects

- [Therapy.jl](https://github.com/TherapeuticJulia/Therapy.jl) -- Reactive web framework for Julia
- [Suite.jl](https://github.com/TherapeuticJulia/Suite.jl) -- UI component library (60+ components)
- [WasmTarget.jl](https://github.com/TherapeuticJulia/WasmTarget.jl) -- Julia to WebAssembly compiler

## License

MIT
