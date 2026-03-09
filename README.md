# Sessions.jl

A terminal-native reactive Julia notebook. Pluto-compatible file format with a full TUI IDE built on [Tachikoma.jl](https://github.com/GroupTherapyOrg/Tachikoma.jl).

## Features

- **Reactive Notebooks** -- Cells auto-re-run when dependencies change (Pluto-style reactivity)
- **Pluto Compatibility** -- Load, edit, and save Pluto `.jl` notebooks natively
- **Terminal IDE** -- File browser, REPL panel, diagnostics panel, tab bar, activity bar, status bar
- **Real-time Diagnostics** -- JETLS (JET.jl LSP) integration catches type errors and undefined variables as you type
- **@bind Widgets** -- Slider, TextField, CheckBox, Select, NumberField (PlutoUI protocol)
- **Agent-first Notebook** -- Code/state separation lets LLMs, IDEs, and scripts safely modify notebooks while the TUI watches and reacts
- **Session Persistence** -- Cell outputs cached in `.session.toml`, restored across restarts with stale detection
- **Agent-Friendly Architecture** -- Code/state separation lets external tools (LLMs, IDEs, scripts) safely modify notebooks while the TUI watches and reacts
- **Full Keyboard Control** -- Kitty protocol support, macOS Cmd/Option handling, legacy terminal fallbacks

## Installation

Requires Julia 1.12+.

```julia
using Pkg
Pkg.Apps.add(url="https://github.com/GroupTherapyOrg/Sessions.jl")
```

This installs the `sessions` command to `~/.julia/bin/`. On first launch, JETLS (real-time diagnostics) is auto-installed.

## Quick Start

```bash
# Open a notebook
sessions my_notebook.jl

# Create a new notebook
sessions

# Run headlessly (CI, scripts)
sessions run my_notebook.jl
```

Or from the Julia REPL:

```julia
using Sessions
Sessions.main("my_notebook.jl")
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

## Code/State Separation: `.jl` + `.session.toml`

Sessions.jl splits your notebook into two files:

| File | Contains | Role |
|------|----------|------|
| `notebook.jl` | Cell code, cell order, fold/disabled metadata | **Source of truth** -- safe for agents and tools to modify |
| `notebook.session.toml` | Cached outputs, stdout, runtime, error messages | **Execution cache** -- optional, can be deleted and regenerated |

This is the key architectural difference from Pluto. In Pluto, the `.jl` file contains code, package state, and notebook metadata interleaved with Pluto-specific formatting. External tools modifying a Pluto file risk corrupting that interleaved state.

In Sessions.jl, the `.jl` file is pure code. An LLM agent, an IDE, or a shell script can modify cell code freely -- the cached outputs live separately in `.session.toml` and are never corrupted by code edits.

### How It Works

```
Agent/IDE modifies notebook.jl
          |
File Watcher (0.5s debounce)
          |
merge_external_changes!()
  - Diffs disk vs in-memory notebook
  - Applies only disk changes
  - Preserves unsaved local edits
          |
Stale detection: source_hash(cell) != produced_by_hash
  - Changed cells get visual indicator
  - Old outputs remain visible until re-execution
          |
User runs stale cells (Ctrl+R / Ctrl+Shift+Enter)
          |
save_session!() -- outputs cached to .session.toml
```

### Agent-Driven Workflow Example

```bash
# Terminal 1: User has notebook open in Sessions TUI
sessions analysis.jl

# Terminal 2: LLM agent modifies a cell
# (or any tool -- sed, python script, another editor)
#
# Sessions TUI detects the change in <1 second:
#   - Modified cells marked as stale (visual indicator)
#   - Old outputs still visible for reference
#   - User presses Ctrl+Shift+Enter to re-run
#   - New outputs saved to .session.toml
```

The `.session.toml` file is:
- **Atomic** -- written via temp file + rename, never half-written
- **Bounded** -- text output truncated to 50KB, stdout to 20KB
- **Optional** -- delete it and all cells revert to "never run" state
- **Gitignored** -- cached outputs are local, not version-controlled

### Comparison with Pluto

| | Sessions.jl | Pluto |
|-|-------------|-------|
| **Code storage** | `.jl` (cell code + order) | `.jl` (code + order + embedded pkg state) |
| **Output storage** | `.session.toml` (separate) | In-memory only (recomputed on open) |
| **External tool safety** | Safe -- agents modify `.jl`, outputs are separate | Risky -- agents may break embedded metadata |
| **Startup with cached state** | Instant -- outputs restored from cache | Full re-execution on every open |
| **Stale detection** | Hash-based -- shows which cells changed since last run | Hash-based (same mechanism) |
| **File watcher** | Built-in -- auto-detects external edits | Not built-in |

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
