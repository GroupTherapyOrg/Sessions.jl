# Sessions.jl

A terminal-native reactive Julia notebook. Pluto-compatible file format with a full TUI IDE built on [Tachikoma.jl](https://github.com/GroupTherapyOrg/Tachikoma.jl).

## Features

- **Reactive Notebooks** -- Cells auto-re-run when dependencies change (Pluto-style reactivity)
- **Pluto Compatibility** -- Load, edit, and save Pluto `.jl` notebooks natively
- **Terminal IDE** -- File browser, REPL panel, diagnostics panel, tab bar, activity bar, status bar
- **Real-time Diagnostics** -- JETLS (JET.jl LSP) integration catches type errors and undefined variables as you type
- **@bind Widgets** -- Slider, TextField, CheckBox, Select, NumberField (PlutoUI protocol)
- **Vim-style Editing** -- Normal/insert mode, visual selection, word motions, clipboard integration
- **Session Persistence** -- Cell outputs, scroll position, and fold state saved across restarts
- **Full Keyboard Control** -- Kitty protocol support, macOS Cmd/Option handling, legacy terminal fallbacks

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/GroupTherapyOrg/Sessions.jl")
```

### JETLS (Optional -- Real-time Diagnostics)

For real-time type error detection while editing:

```julia
using Pkg
Pkg.Apps.add(; url="https://github.com/aviatesk/JETLS.jl", rev="release")
```

This installs the `jetls` binary to `~/.julia/bin/`. Sessions.jl will detect and use it automatically.

## Quick Start

```julia
using Sessions

# Launch the TUI with a notebook
Sessions.main("my_notebook.jl")

# Or create a new notebook interactively
Sessions.main()
```

## Keyboard Shortcuts

### Normal Mode

| Shortcut | Action |
|----------|--------|
| `j` / `k` | Navigate cells down/up |
| `i` / `Enter` | Enter insert mode (edit cell) |
| `Ctrl+R` | Run current cell |
| `Shift+Enter` | Run cell and move to next |
| `Ctrl+Shift+Enter` | Run all cells |
| `o` / `O` | Add cell below/above |
| `dd` | Delete cell |
| `J` / `K` | Move cell down/up |
| `Ctrl+S` | Save notebook |
| `Ctrl+Q` | Quit |
| `1`-`4` | Toggle sidebar panels (files, REPL, diagnostics, search) |

### Insert Mode

| Shortcut | Action |
|----------|--------|
| `Escape` | Return to normal mode |
| `Ctrl+R` | Run cell |
| `Ctrl+S` | Save notebook |
| `Cmd+Left/Right` | Home/End (macOS) |
| `Option+Left/Right` | Word jump (macOS) |

## Architecture

```
+--------------------------------------------------+
|  Layer 3: CLI                                     |
|  cli.jl (entry points, ARGS parsing)              |
+--------------------------------------------------+
|  Layer 2: TUI (Tachikoma.jl)                      |
|  app.jl, notebook_view.jl, cell_widget.jl,        |
|  output_widget.jl, file_panel.jl, repl_panel.jl,  |
|  diagnostics_panel.jl, status_bar.jl, tab_bar.jl  |
+--------------------------------------------------+
|  Layer 1.5: Static Analysis                       |
|  jet_analysis.jl (JET.jl batch analysis)          |
|  lsp_client.jl (JETLS LSP client)                 |
+--------------------------------------------------+
|  Layer 1: Engine (pure Julia, no UI)              |
|  types.jl, format.jl, analysis.jl, kernel.jl,     |
|  run.jl, bind.jl, session.jl, watcher.jl          |
+--------------------------------------------------+
```

## @bind Widgets

Sessions.jl implements the AbstractPlutoDingetjes `@bind` protocol:

```julia
@bind x Slider(1:100)
@bind name TextField()
@bind flag CheckBox()
@bind choice Select(["A", "B", "C"])
@bind n NumberField(1:10)
```

## Testing

```bash
julia +1.12 --project=. test/runtests.jl
```

## Dependencies

- [Tachikoma.jl](https://github.com/GroupTherapyOrg/Tachikoma.jl) -- Terminal UI framework
- [ExpressionExplorer.jl](https://github.com/JuliaPluto/ExpressionExplorer.jl) -- Reactive analysis (Pluto ecosystem)
- [PlutoDependencyExplorer.jl](https://github.com/JuliaPluto/PlutoDependencyExplorer.jl) -- Topological sort (Pluto ecosystem)

## License

MIT
