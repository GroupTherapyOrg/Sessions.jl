# Therapy Notebook Architecture

Building a Pluto.jl-style reactive notebook IDE using pure Julia with Therapy.jl for the UI and JuliaPluto packages for the execution engine.

## Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Browser (Client)                                 │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Therapy.jl UI (WASM)                          │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │   │
│  │  │ NotebookView │  │  CellEditor  │  │ OutputRender │           │   │
│  │  │   (island)   │  │   (island)   │  │   (island)   │           │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘           │   │
│  │                                                                   │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │   │
│  │  │   Sidebar    │  │  FileTree    │  │   StatusBar  │           │   │
│  │  │   (island)   │  │   (island)   │   │  (component) │           │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘           │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │ WebSocket                                │
└──────────────────────────────┼──────────────────────────────────────────┘
                               │
┌──────────────────────────────┼──────────────────────────────────────────┐
│                         Server (Julia)                                   │
├──────────────────────────────┴──────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                    Therapy.jl Server                             │    │
│  │  - HTTP server (serve UI)                                        │    │
│  │  - WebSocket handler (real-time communication)                   │    │
│  │  - Server signals & channels                                     │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                              │                                           │
│  ┌───────────────────────────┴─────────────────────────────────────┐    │
│  │                    Notebook Engine                               │    │
│  │                                                                   │    │
│  │  ┌─────────────────┐  ┌──────────────────────────────────────┐  │    │
│  │  │ ExpressionExplorer │  │ PlutoDependencyExplorer.jl       │  │    │
│  │  │    .jl           │  │  - NotebookTopology                 │  │    │
│  │  │  - References    │  │  - TopologicalOrder                 │  │    │
│  │  │  - Definitions   │  │  - Dependency graph                 │  │    │
│  │  └─────────────────┘  └──────────────────────────────────────┘  │    │
│  │                                                                   │    │
│  │  ┌─────────────────────────────────────────────────────────────┐ │    │
│  │  │                      Malt.jl                                 │ │    │
│  │  │  - Worker processes (sandboxed Julia execution)              │ │    │
│  │  │  - One worker per notebook                                   │ │    │
│  │  │  - Interrupt support                                         │ │    │
│  │  └─────────────────────────────────────────────────────────────┘ │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                    File System                                    │    │
│  │  - Notebook storage (.jl files, Pluto format)                    │    │
│  │  - Package environments (Project.toml, Manifest.toml)            │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## JuliaPluto Packages to Use

### Core Execution Engine

| Package | Purpose | How We Use It |
|---------|---------|---------------|
| [**ExpressionExplorer.jl**](https://github.com/JuliaPluto/ExpressionExplorer.jl) | Analyze code to find variable references and definitions | Determine cell dependencies |
| [**PlutoDependencyExplorer.jl**](https://github.com/JuliaPluto/PlutoDependencyExplorer.jl) | Build dependency graph, compute execution order | Reactive cell ordering |
| [**Malt.jl**](https://github.com/JuliaPluto/Malt.jl) | Sandboxed worker processes for code execution | Isolate notebook execution |

### Output & Display

| Package | Purpose | How We Use It |
|---------|---------|---------------|
| [**HypertextLiteral.jl**](https://github.com/JuliaPluto/HypertextLiteral.jl) | Safe HTML generation with interpolation | Render rich cell outputs |
| [**AbstractPlutoDingetjes.jl**](https://github.com/JuliaPluto/AbstractPlutoDingetjes.jl) | Abstract interfaces for custom widgets | Enable @bind-style interactivity |

### Optional Enhancements

| Package | Purpose | How We Use It |
|---------|---------|---------------|
| [**PlutoHooks.jl**](https://github.com/JuliaPluto/PlutoHooks.jl) | React-style hooks for state persistence | Advanced cell state management |
| [**PlutoUI.jl**](https://github.com/JuliaPluto/PlutoUI.jl) | Pre-built widgets (sliders, buttons, etc.) | Compatibility with Pluto widgets |
| [**MarkdownLiteral.jl**](https://github.com/JuliaPluto/MarkdownLiteral.jl) | Markdown with interpolation | Rich text in notebooks |

---

## Core Data Structures

### Cell

```julia
mutable struct Cell
    id::UUID
    code::String
    output::Union{Nothing, CellOutput}

    # Reactivity metadata (from ExpressionExplorer)
    references::Set{Symbol}      # Variables this cell reads
    definitions::Set{Symbol}     # Variables this cell defines

    # Execution state
    state::CellState             # :idle, :queued, :running, :error
    runtime_ms::Union{Nothing, Float64}

    # UI state
    folded::Bool
    disabled::Bool
end

@enum CellState idle queued running error

struct CellOutput
    value::Any                   # The actual result
    mime::MIME                   # MIME type for display
    html::String                 # Rendered HTML
    logs::Vector{String}         # Captured stdout/stderr
end
```

### Notebook

```julia
mutable struct Notebook
    id::UUID
    path::Union{Nothing, String}

    cells::OrderedDict{UUID, Cell}
    cell_order::Vector{UUID}     # Display order

    # Reactivity (from PlutoDependencyExplorer)
    topology::NotebookTopology

    # Execution
    worker::Union{Nothing, Malt.Worker}

    # Package environment
    project_toml::String
    manifest_toml::String
end
```

---

## WebSocket Protocol

### Channels (Client → Server)

```julia
# Execute a cell
on_channel_message("execute") do conn, data
    # data = {notebook_id, cell_id, code}
    execute_cell(data["notebook_id"], data["cell_id"], data["code"])
end

# Interrupt execution
on_channel_message("interrupt") do conn, data
    # data = {notebook_id}
    interrupt_notebook(data["notebook_id"])
end

# File operations
on_channel_message("save") do conn, data
    # data = {notebook_id, path?}
    save_notebook(data["notebook_id"], get(data, "path", nothing))
end

on_channel_message("load") do conn, data
    # data = {path}
    load_notebook(data["path"])
end

# Cell operations
on_channel_message("add_cell") do conn, data
    # data = {notebook_id, after_cell_id?, code?}
end

on_channel_message("delete_cell") do conn, data
    # data = {notebook_id, cell_id}
end

on_channel_message("move_cell") do conn, data
    # data = {notebook_id, cell_id, new_index}
end
```

### Server Signals (Server → Client)

```julia
# Cell states for entire notebook
cell_states = create_server_signal("cell_states", Dict{String, String}())
# Example: {"abc-123": "running", "def-456": "idle"}

# Notebook metadata
notebook_info = create_server_signal("notebook", Dict{String, Any}())
# Example: {"id": "...", "path": "untitled.jl", "modified": true}

# Connected users (for collaboration)
users = create_server_signal("users", Vector{Dict}())
```

### Channels (Server → Client)

```julia
# Stream cell output (supports partial updates)
broadcast_channel!("cell_output", Dict(
    "notebook_id" => nb.id,
    "cell_id" => cell.id,
    "output" => Dict(
        "html" => rendered_html,
        "mime" => string(mime),
        "logs" => captured_logs
    )
))

# Cell execution complete
broadcast_channel!("cell_complete", Dict(
    "notebook_id" => nb.id,
    "cell_id" => cell.id,
    "runtime_ms" => elapsed,
    "success" => true
))

# Error notification
broadcast_channel!("error", Dict(
    "notebook_id" => nb.id,
    "cell_id" => cell.id,
    "error" => Dict(
        "type" => "RuntimeError",
        "message" => "...",
        "stacktrace" => "..."
    )
))
```

---

## Execution Flow

### 1. Code Edit → Reactive Execution

```
User edits cell code
        │
        ▼
┌─────────────────────────────────────────┐
│  Client: Send via WebSocket channel     │
│  TherapyWS.sendMessage("execute", {     │
│    notebook_id, cell_id, code           │
│  })                                      │
└─────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────┐
│  Server: Parse and analyze              │
│                                          │
│  1. Parse code to Expr                   │
│  2. ExpressionExplorer.compute_         │
│     reactive_node(expr)                  │
│  3. Update cell.references,             │
│     cell.definitions                     │
└─────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────┐
│  Server: Compute execution order        │
│                                          │
│  1. PlutoDependencyExplorer.            │
│     updated_topology(cells)              │
│  2. topological_order(topology,         │
│     roots=[changed_cell])               │
│  3. Get list of cells to re-run         │
└─────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────┐
│  Server: Queue and execute              │
│                                          │
│  For each cell in order:                 │
│  1. Update state → "running"            │
│  2. Malt.remote_eval(worker, code)      │
│  3. Capture output, render to HTML       │
│  4. Broadcast result via channel         │
│  5. Update state → "idle"               │
└─────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────┐
│  Client: Update UI                       │
│                                          │
│  - Server signal updates cell states    │
│  - Channel delivers output HTML          │
│  - Islands re-render affected cells      │
└─────────────────────────────────────────┘
```

### 2. Cell Analysis with ExpressionExplorer

```julia
using ExpressionExplorer

function analyze_cell(code::String)
    expr = Meta.parse(code)
    node = compute_reactive_node(expr)

    return (
        references = node.references,      # Variables read
        definitions = node.definitions,    # Variables written
        funcdefs = node.funcdefs_with_signatures  # Functions defined
    )
end

# Example:
# code = "y = x + 1"
# → references = Set([:x])
# → definitions = Set([:y])
```

### 3. Dependency Resolution with PlutoDependencyExplorer

```julia
using PlutoDependencyExplorer

function compute_run_order(notebook::Notebook, changed_cells::Vector{UUID})
    # Build topology from all cells
    topology = updated_topology(
        notebook.topology,
        notebook.cells,
        notebook.cells  # all cells
    )

    # Find cells that need to re-run
    roots = [notebook.cells[id] for id in changed_cells]
    order = topological_order(topology, roots)

    return order.runnable  # Cells in execution order
end
```

### 4. Sandboxed Execution with Malt.jl

```julia
using Malt

function create_notebook_worker()
    worker = Malt.Worker()

    # Initialize with common imports
    Malt.remote_eval_wait(worker, quote
        using InteractiveUtils
        # Set up display system, etc.
    end)

    return worker
end

function execute_in_worker(worker::Malt.Worker, code::String)
    expr = Meta.parse(code)

    # Execute and capture result
    result = Malt.remote_eval_fetch(worker, quote
        try
            ans = $(expr)
            (value = ans, success = true, error = nothing)
        catch e
            (value = nothing, success = false, error = (e, catch_backtrace()))
        end
    end)

    return result
end

function interrupt_worker(worker::Malt.Worker)
    Malt.interrupt(worker)
end
```

---

## UI Components (Therapy.jl Islands)

### NotebookView Island

```julia
NotebookView = island(:NotebookView) do
    # Renders the full notebook with all cells
    # Listens to server signals for cell states
    # Handles cell reordering via drag-and-drop
end
```

### CellEditor Island

```julia
CellEditor = island(:CellEditor) do
    # Code editor (integrate CodeMirror via JS interop)
    # Syntax highlighting for Julia
    # Auto-completion hints
    # Keyboard shortcuts (Shift+Enter to run)
end
```

### CellOutput Island

```julia
CellOutput = island(:CellOutput) do
    # Renders cell output based on MIME type
    # Supports: text/plain, text/html, image/png, etc.
    # Shows execution time, logs
    # Error display with stacktrace
end
```

### StatusBar Component

```julia
StatusBar = component(:StatusBar) do props
    # Shows: notebook name, save status, Julia version
    # Cell execution progress
    # Memory usage (optional)
end
```

---

## File Format

Use Pluto's `.jl` format for compatibility:

```julia
### A Pluto.jl notebook ###
# v0.19.x

#> [frontmatter]
#> title = "My Notebook"

# ╔═╡ a1b2c3d4-...
x = 1

# ╔═╡ e5f6g7h8-...
y = x + 1

# ╔═╡ i9j0k1l2-...
z = x * y

# ╔═╡ Cell order:
# ╠═a1b2c3d4-...
# ╠═e5f6g7h8-...
# ╠═i9j0k1l2-...

# ╔═╡ Project.toml
# [deps]
# Plots = "91a5bcdd-..."

# ╔═╡ Manifest.toml
# ...
```

### Parsing/Writing

```julia
function load_notebook(path::String)::Notebook
    content = read(path, String)

    # Verify it's a Pluto notebook
    @assert startswith(content, "### A Pluto.jl notebook ###")

    # Parse cells (between # ╔═╡ markers)
    cells = parse_cells(content)

    # Parse cell order
    order = parse_cell_order(content)

    # Parse package environment
    project, manifest = parse_environment(content)

    return Notebook(cells, order, project, manifest)
end

function save_notebook(notebook::Notebook, path::String)
    # Generate Pluto-compatible .jl file
    content = generate_notebook_content(notebook)
    write(path, content)
end
```

---

## Project Structure

```
TherapyNotebook/
├── src/
│   ├── TherapyNotebook.jl      # Main module
│   │
│   ├── Engine/
│   │   ├── Notebook.jl         # Notebook struct, operations
│   │   ├── Cell.jl             # Cell struct, analysis
│   │   ├── Reactivity.jl       # Dependency tracking (uses PlutoDependencyExplorer)
│   │   ├── Worker.jl           # Malt.jl worker management
│   │   └── Output.jl           # Output rendering, MIME handling
│   │
│   ├── Server/
│   │   ├── App.jl              # Therapy.jl App setup
│   │   ├── Channels.jl         # WebSocket channel handlers
│   │   └── Signals.jl          # Server signal definitions
│   │
│   ├── UI/
│   │   ├── Layout.jl           # Main layout component
│   │   ├── NotebookView.jl     # Notebook island
│   │   ├── CellEditor.jl       # Code editor island
│   │   ├── CellOutput.jl       # Output renderer island
│   │   ├── Sidebar.jl          # File browser, outline
│   │   └── StatusBar.jl        # Status information
│   │
│   └── FileFormat/
│       ├── Parse.jl            # Load .jl notebooks
│       └── Write.jl            # Save .jl notebooks
│
├── assets/
│   ├── codemirror/             # CodeMirror editor files
│   └── styles/                 # CSS
│
├── test/
│   └── runtests.jl
│
└── Project.toml
```

---

## Dependencies

```toml
[deps]
# Therapy.jl ecosystem
Therapy = "..."

# Pluto execution engine
ExpressionExplorer = "..."
PlutoDependencyExplorer = "..."
Malt = "..."

# Output rendering
HypertextLiteral = "..."

# Optional: Pluto widget compatibility
AbstractPlutoDingetjes = "..."
PlutoUI = "..."

# Utilities
UUIDs = "..."
OrderedCollections = "..."
```

---

## Implementation Phases

### Phase 1: Core Notebook Engine
1. Set up project with dependencies
2. Implement `Cell` and `Notebook` structs
3. Integrate ExpressionExplorer for cell analysis
4. Integrate PlutoDependencyExplorer for reactive ordering
5. Integrate Malt.jl for sandboxed execution
6. Basic file loading/saving

### Phase 2: WebSocket Communication
1. Set up Therapy.jl server with WebSocket
2. Define channels: execute, interrupt, save, load
3. Define server signals: cell_states, notebook_info
4. Wire up execution flow end-to-end

### Phase 3: Basic UI
1. Create NotebookView island (cell list)
2. Create CellOutput island (render results)
3. Basic cell editing (textarea, not fancy editor)
4. Status display, basic styling

### Phase 4: Code Editor Integration
1. Integrate CodeMirror or Monaco via JS
2. Julia syntax highlighting
3. Basic auto-completion
4. Keyboard shortcuts

### Phase 5: Full IDE Features
1. File browser sidebar
2. Multiple notebooks (tabs)
3. Package management UI
4. Settings/preferences
5. Collaboration (multiple users)

---

## Key Differences from Pluto.jl

| Aspect | Pluto.jl | TherapyNotebook |
|--------|----------|-----------------|
| **Frontend** | JavaScript + Preact | Therapy.jl (Julia → WASM) |
| **Build system** | webpack/esbuild | Therapy.jl SSR + compile |
| **State management** | Preact signals | Therapy.jl signals |
| **Real-time** | Custom WebSocket | Therapy.jl channels |
| **Widgets** | PlutoUI (@bind) | Therapy.jl islands |
| **Execution** | Pluto internals | Same (Malt.jl) |
| **Reactivity** | Same | Same (PlutoDependencyExplorer) |

**Advantages of Therapy.jl approach:**
- Pure Julia codebase (no JavaScript to maintain)
- Unified reactivity model (same signals client & server)
- Simpler build process
- Easier to extend with Julia packages

---

## References

- [Pluto.jl](https://github.com/fonsp/Pluto.jl) - Original reactive notebook
- [JuliaPluto Organization](https://github.com/JuliaPluto) - Package ecosystem
- [ExpressionExplorer.jl](https://github.com/JuliaPluto/ExpressionExplorer.jl) - Code analysis
- [PlutoDependencyExplorer.jl](https://github.com/JuliaPluto/PlutoDependencyExplorer.jl) - Dependency sorting
- [Malt.jl](https://github.com/JuliaPluto/Malt.jl) - Process sandboxing
- [HypertextLiteral.jl](https://github.com/JuliaPluto/HypertextLiteral.jl) - HTML generation
- [AbstractPlutoDingetjes.jl](https://github.com/JuliaPluto/AbstractPlutoDingetjes.jl) - Widget interfaces
- [Pluto File Format](https://plutojl.org/en/docs/export-julia/) - Notebook format spec
