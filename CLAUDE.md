# Sessions.jl Developer Guide

A Pluto-style reactive notebook IDE built with pure Julia using Therapy.jl for the UI and JuliaPluto packages for execution.

## Quick Start

```bash
cd /Users/daleblack/Documents/dev/TherapeuticJulia/Sessions.jl
julia --project=. -e 'using Sessions; Sessions.dev()'
# Open http://localhost:8080
```

## Architecture

Sessions.jl combines:
- **Therapy.jl** - All UI rendering (SSR + WASM islands)
- **JuliaPluto packages** - Notebook execution engine
- **WebSocket** - Real-time communication

```
┌─────────────────────────────────────────────────────────┐
│                    Browser (Client)                      │
├─────────────────────────────────────────────────────────┤
│  Therapy.jl UI (SSR + WASM)                             │
│  - Layout, CellView components                          │
│  - WebSocket client (TherapyWS)                         │
│  - Cell editing and display                             │
└─────────────────────────────────────────────────────────┘
                         │ WebSocket
┌────────────────────────┼────────────────────────────────┐
│                    Server (Julia)                        │
├────────────────────────┴────────────────────────────────┤
│  Therapy.jl Server                                       │
│  - HTTP + WebSocket handling                            │
│  - Channels: execute, add_cell, save, load              │
│  - Server signals: cell_states, notebook_info           │
├─────────────────────────────────────────────────────────┤
│  Notebook Engine (JuliaPluto packages)                   │
│  - ExpressionExplorer.jl: Code analysis                 │
│  - PlutoDependencyExplorer.jl: Reactive ordering        │
│  - Malt.jl: Sandboxed worker processes                  │
└─────────────────────────────────────────────────────────┘
```

## Project Structure

```
Sessions.jl/
├── src/
│   ├── Sessions.jl           # Main module
│   ├── Engine/
│   │   ├── Cell.jl           # Cell struct, states
│   │   ├── Notebook.jl       # Notebook container
│   │   ├── Reactivity.jl     # Dependency tracking (ExpressionExplorer + PDE)
│   │   ├── Worker.jl         # Malt.jl execution
│   │   └── Output.jl         # MIME handling, rendering
│   ├── Server/
│   │   ├── App.jl            # Therapy.jl app setup
│   │   ├── Channels.jl       # WebSocket channel handlers
│   │   └── Signals.jl        # Server signal definitions
│   ├── UI/
│   │   ├── Layout.jl         # Main layout component
│   │   └── CellView.jl       # Cell rendering
│   ├── FileFormat/
│   │   ├── Parse.jl          # Load Pluto .jl files
│   │   └── Write.jl          # Save Pluto .jl files
│   └── routes/
│       └── index.jl          # Main notebook page
├── ARCHITECTURE.md           # Detailed architecture doc
├── CLAUDE.md                 # This file
└── Project.toml
```

## Dependencies

### JuliaPluto Packages (Execution Engine)
- **ExpressionExplorer.jl** - Analyze code to find variable references/definitions
- **PlutoDependencyExplorer.jl** - Build dependency graph, compute execution order
- **Malt.jl** - Sandboxed worker processes for isolated execution
- **HypertextLiteral.jl** - Safe HTML generation

### Therapy.jl (UI Framework)
- SSR components rendered to HTML
- WebSocket channels for real-time communication
- Server signals for state synchronization
- Client-side routing for SPA navigation

## Core Concepts

### Cell

```julia
mutable struct Cell
    id::UUID
    code::String
    output::Union{Nothing, CellOutput}
    references::Set{Symbol}      # Variables this cell reads
    definitions::Set{Symbol}     # Variables this cell defines
    state::CellState             # IDLE, QUEUED, RUNNING, ERROR
    runtime_ms::Union{Nothing, Float64}
end
```

### Notebook

```julia
mutable struct Notebook
    id::UUID
    path::Union{Nothing, String}
    cells::OrderedDict{UUID, Cell}
    cell_order::Vector{UUID}
    worker::Union{Nothing, Malt.Worker}
end
```

### Reactive Execution

When a cell is executed:
1. `analyze_cell!()` - ExpressionExplorer finds references/definitions
2. `get_execution_order()` - Compute cells that need to re-run
3. `execute_cell!()` - Malt.jl runs code in worker process
4. Broadcast results via WebSocket channels

## WebSocket Protocol

### Client → Server (Channels)

```javascript
// Execute cell
TherapyWS.sendMessage('execute', {notebook_id, cell_id, code})

// Cell operations
TherapyWS.sendMessage('add_cell', {notebook_id, after_cell_id})
TherapyWS.sendMessage('delete_cell', {notebook_id, cell_id})
TherapyWS.sendMessage('move_cell', {notebook_id, cell_id, new_index})

// Notebook operations
TherapyWS.sendMessage('run_all', {notebook_id})
TherapyWS.sendMessage('interrupt', {notebook_id})
TherapyWS.sendMessage('restart', {notebook_id})
TherapyWS.sendMessage('save', {notebook_id, path})
TherapyWS.sendMessage('load', {path})
```

### Server → Client (Channels)

```javascript
// Cell updates
{type: 'cell_state', notebook_id, cell_id, state, runtime_ms}
{type: 'cell_output', notebook_id, cell_id, output: {mime, html, logs}}
{type: 'cell_added', notebook_id, cell, after_cell_id}
{type: 'cell_deleted', notebook_id, cell_id}

// Notebook events
{type: 'saved', notebook_id, path}
{type: 'loaded', notebook}
{type: 'interrupted', notebook_id}
{type: 'restarted', notebook_id}
```

## File Format

Sessions uses Pluto's `.jl` format for notebook files:

```julia
### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ a1b2c3d4-...
x = 1

# ╔═╡ e5f6g7h8-...
y = x + 1

# ╔═╡ Cell order:
# ╠═a1b2c3d4-...
# ╠═e5f6g7h8-...
```

This ensures:
- Notebooks can be run as regular Julia scripts
- Full compatibility with Pluto.jl
- Package environment embedded for reproducibility

## Development

### Running Tests

```bash
julia --project=. test/runtests.jl
```

### Adding Features

1. **New WebSocket channel**: Add handler in `Server/Channels.jl`
2. **New UI component**: Add in `UI/` and include in `Sessions.jl`
3. **New route**: Add in `routes/` directory

### Debugging

```julia
# Check cell analysis
cell = Cell(code="x = 1 + y")
analyze_cell!(cell)
println(cell.references)  # Set([:y])
println(cell.definitions) # Set([:x])

# Check execution order
notebook = Notebook()
add_cell!(notebook; code="x = 1")
add_cell!(notebook; code="y = x + 1")
order = get_all_execution_order(notebook)
```

## Roadmap

### Phase 1: Core Engine ✅
- [x] Cell and Notebook structs
- [x] ExpressionExplorer integration
- [x] PlutoDependencyExplorer integration
- [x] Malt.jl worker execution
- [x] Pluto file format parsing/writing

### Phase 2: WebSocket Communication ✅
- [x] Therapy.jl channel handlers
- [x] Cell execution protocol
- [x] Notebook operations (save, load, restart)

### Phase 3: Basic UI ✅
- [x] Layout component
- [x] CellView component
- [x] Basic styling

### Phase 4: Code Editor ✅
- [x] CodeMirror 6 integration (ESM imports)
- [x] Julia-like syntax highlighting (Pluto theme)
- [x] Keyboard shortcuts (Shift+Enter, Cmd+Enter)
- [x] Therapy.jl + Pluto.jl combined theme
- [x] Server rendering via render_page() with head_extra
- [x] WebSocket integration for cell state updates
- [ ] Julia-specific language mode (using JS as fallback)
- [ ] Auto-completion (future)

### Phase 5: Full IDE (Next)
- [ ] File browser sidebar
- [ ] Multiple notebooks (tabs)
- [ ] Package management UI
- [ ] Keyboard shortcuts
- [ ] Collaboration support

## Sister Projects

- **Therapy.jl** - Reactive web framework (../Therapy.jl)
- **WasmTarget.jl** - Julia → WebAssembly compiler (../WasmTarget.jl)
