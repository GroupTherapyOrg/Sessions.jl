# Sessions.jl Vision Document

## Executive Summary

Sessions.jl is a **Therapy.jl application** that provides a VSCode + Pluto hybrid experience. It is NOT a Pluto fork - it's a web application built with Therapy.jl components that selectively leverages standalone Pluto packages where they make sense.

**Core Identity**: Sessions.jl is a Therapy.jl app that happens to be a notebook/IDE.

---

## Pluto Compatibility Goal

**Users should be able to copy-paste cells from Pluto notebooks into Sessions and have them work correctly.**

This means:
1. Sessions parses Pluto notebook format (`# ╔═╡` cell markers)
2. Pluto cell code runs without modification in Sessions
3. Eventually: import entire `.jl` Pluto notebooks directly
4. Leverage Pluto packages (ExpressionExplorer.jl, Malt.jl) where they help

The goal is NOT to be a Pluto clone, but to be compatible enough that users can migrate their work easily.

---

## High-Level Goals

### 1. Therapy.jl Application
- Sessions follows the Therapy.jl app structure (`src/app.jl`, `src/components/`, `src/routes/`)
- All UI is built with Therapy.jl components (`Div`, `Button`, `Input`, etc.)
- Server-side rendering with `render_page()` and `render_to_string()`
- Can be extended with additional routes and components

### 2. VSCode + Pluto Hybrid UI
- **File Explorer**: Navigate local filesystem (connected via WebSocket)
- **Integrated Terminal**: Browser-based terminal connected to Julia REPL
- **Notebook Cells**: Code cells with execution and output display
- **Top Bar**: Controls for Run All, Restart, Add Cell

### 3. Hybrid SSR + WebSocket Architecture
Sessions uses a **hybrid approach** combining the best of both worlds:
- **SSR (Server-Side)**: Static UI structure rendered with Therapy.jl components
- **WebSocket (Server→Client)**: JSON data for compute results, NOT HTML
- **Client-side JS**: Renders dynamic content (cells, file tree) from JSON
- **Future**: Wasm islands will replace JS for UI state management

This architecture separates concerns cleanly:
- Server handles COMPUTE (execution, filesystem, terminal)
- Client handles UI (rendering, interaction, state display)

### 4. Selective Pluto Package Leverage (Planned)
We don't fork Pluto. We use its **standalone packages** where they provide value:
- `ExpressionExplorer.jl` - Static analysis of Julia expressions
- `Malt.jl` - Distributed execution in worker processes

### 5. Pure Julia + Tailwind
- All UI logic is Julia code using Therapy.jl primitives
- Tailwind CSS for styling (loaded via CDN)
- Minimal JavaScript - just WebSocket transport (~60 lines)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Browser                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │           Sessions UI (Hybrid SSR + JS)                   │  │
│  │                                                            │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │  │
│  │  │   Sidebar   │  │   Cells     │  │    Terminal     │   │  │
│  │  │  (SSR+JS)   │  │ (JS render) │  │   (SSR+WS)      │   │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────┘   │  │
│  │                                                            │  │
│  │  JS Bridge: Receives JSON, renders cells, handles events  │  │
│  │  Future: Wasm islands for UI state (NotebookIsland.jl)    │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │ WebSocket (JSON)                  │
└──────────────────────────────│──────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Sessions Server (Julia)                       │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  HTTP Server                                               │  │
│  │  - Serves pages rendered with Therapy.jl render_page()    │  │
│  │  - SSR: Layout, Sidebar, Terminal (with hydration keys)   │  │
│  │  - Injects JS bridge for client-side cell rendering       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  WebSocket Handler (COMPUTE ONLY)                          │  │
│  │  - Cell execution → returns JSON {cell_update: {...}}      │  │
│  │  - File operations → returns JSON {files: [...]}           │  │
│  │  - Terminal I/O → returns text                             │  │
│  │  - NO HTML rendering, just data                            │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Core Components                                           │  │
│  │  - Cell.jl: Cell data structure with status, output        │  │
│  │  - Executor.jl: Code execution in isolated module          │  │
│  │  - cell_to_dict(): Converts Cell → JSON for WebSocket      │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Therapy.jl                                │
│  - VNode primitives (Div, Button, Input, Span, etc.)            │
│  - render_page() for full HTML documents                         │
│  - render_to_string() for component rendering                    │
│  - SSR with hydration keys (data-hk)                             │
│  - island() for Wasm-compiled interactive components             │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                       WasmTarget.jl                              │
│  - Julia → WebAssembly compiler                                  │
│  - Foundation for Therapy.jl islands                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component Structure

### src/components/Layout.jl
Main page layout with TopBar:
```julia
function Layout(children...)
    Div(:id => "app", :class => "h-screen flex flex-col bg-gray-900 text-gray-200",
        TopBar(),
        children...
    )
end

function TopBar()
    Div(:class => "h-10 bg-gray-800 ...",
        Span("Sessions.jl"),
        Button(:id => "btn-run-all", "Run All"),
        Button(:id => "btn-restart", "Restart"),
        Button(:id => "btn-add-cell", "+ Cell")
    )
end
```

### src/components/Sidebar.jl
File explorer (populated via WebSocket):
```julia
function Sidebar()
    Div(:id => "sidebar", :class => "w-64 bg-gray-800 ...",
        Span("Explorer"),
        Div(:id => "file-tree")  # Populated by WebSocket
    )
end
```

### src/components/Terminal.jl
Julia REPL terminal:
```julia
function Terminal()
    Div(:id => "terminal-panel", :class => "h-48 bg-gray-800 ...",
        Div(:id => "terminal-output"),
        Input(:id => "terminal-input")
    )
end
```

### Cell Rendering (in WebSocketServer.jl)
Cells are rendered server-side:
```julia
function render_cell_vnode(cell::Cell)
    Div(:class => "cell ...",
        # Header with status icon, run button, delete button
        Div(:class => "...",
            status_icon,
            Button(:class => "cell-run", "Run"),
            Button(:class => "cell-delete", "×")
        ),
        # Code textarea
        Textarea(:class => "cell-code", cell.code),
        # Output (if any)
        if cell.output !== nothing
            Div(:class => "...", repr(cell.output))
        end
    )
end
```

---

## WebSocket Protocol

All communication uses JSON messages. **Server returns DATA, not HTML.**

### Client → Server
```javascript
// Cell operations
{action: 'execute', cell_id: '...', code: '...'}
{action: 'add_cell'}
{action: 'delete_cell', cell_id: '...'}
{action: 'update_code', cell_id: '...', code: '...'}
{action: 'run_all'}
{action: 'restart'}
{action: 'get_cells'}

// File operations
{action: 'files', path: '.'}
{action: 'open_file', path: 'src/foo.jl'}

// Terminal
{action: 'terminal', input: 'x = 1 + 1'}
```

### Server → Client
```javascript
// Cell data (JSON, client renders)
{type: 'cells_state', cells: [{id, code, status, output, ...}, ...], count: N}
{type: 'cell_update', cell: {id, code, status, output, stdout, stderr, error_msg, execution_count}}

// File list (JSON, client renders)
{type: 'files', path: '...', entries: [{name, path, is_directory}, ...]}

// Terminal output
{type: 'terminal', output: '2'}

// File content
{type: 'file', path: '...', content: '...'}
```

---

## Development Phases

### Phase 1: Foundation ✓
- [x] Basic project structure following Therapy.jl patterns
- [x] Layout, Sidebar, Terminal components
- [x] WebSocket server with cell execution
- [x] Server-side rendering with Therapy.jl

### Phase 2: Hybrid Architecture ✓ (Current)
- [x] **Hybrid SSR + WebSocket architecture**
- [x] Server returns JSON data (not HTML)
- [x] Client-side JS bridge for cell rendering
- [x] Cell management (add, delete, run)
- [x] Code execution with output capture
- [x] Status indicators (idle, running, completed, errored)
- [x] NotebookIsland.jl skeleton for future Wasm integration

### Phase 3: Wasm Islands ← Next
- [ ] Integrate NotebookIsland as Wasm-compiled component
- [ ] Replace JS bridge with Wasm signal updates
- [ ] Full Therapy.jl island architecture

### Phase 4: Pluto Integration
- [ ] Dependency tracking with ExpressionExplorer.jl
- [ ] Reactive execution (when cell changes, re-run dependents)
- [ ] Leverage other Pluto patterns/packages

### Phase 5: Rich Editor Features
- [ ] **CodeMirror integration** (like Pluto) for syntax highlighting, line numbers
- [ ] Autocomplete
- [ ] Keyboard shortcuts (Shift+Enter to run)

### Phase 6: File System Enhancement
- [x] File listing via WebSocket
- [x] Directory navigation
- [ ] File editing and saving
- [ ] Project detection (Project.toml)

### Phase 7: Terminal Enhancement
- [x] Basic terminal input/output
- [ ] Full PTY support with ANSI codes
- [ ] Multiple terminal sessions

### Phase 8: Rich Output
- [ ] Plot rendering
- [ ] Table rendering
- [ ] HTML output
- [ ] Better error display

### Phase 9: Polish
- [ ] Themes (light/dark)
- [ ] Settings persistence

### Phase 10: Static Export
- [ ] Build notebooks to static HTML
- [ ] GitHub Pages deployment
- [ ] Baked-in outputs

---

## Why Hybrid Architecture?

Sessions uses a **hybrid architecture** (SSR + WebSocket + client-side rendering) because:

1. **Notebook execution must be server-side** - Julia code needs to run with full capabilities
2. **UI should be responsive** - Client-side rendering provides immediate feedback
3. **Clean separation** - Server handles compute, client handles UI
4. **Future-proof** - Easy to upgrade JS rendering to Wasm islands

This is similar to how Pluto works: server executes code, client renders UI.
The difference is that Sessions will eventually use Therapy.jl's Wasm islands for the UI layer.

---

## Success Metrics

1. **Can build a simple notebook** that executes Julia code ✓
2. **Can navigate files** in a project ✓
3. **Can use terminal** to run Julia commands ✓
4. **All UI is Therapy.jl components** ✓
5. **Feels like VSCode + Pluto** - familiar, intuitive

---

## Non-Goals (For Now)

- Full VSCode extension compatibility
- Multi-user collaboration
- Cloud execution
- Non-Julia languages
- Mobile support

---

## Conclusion

Sessions.jl demonstrates that Therapy.jl can power more than just Wasm islands - it's a full UI framework. By using Therapy.jl components for server-side rendering with WebSocket updates, we get:

1. **Consistency**: Same component model as pure Therapy.jl apps
2. **Simplicity**: All UI logic in Julia, minimal JavaScript
3. **Power**: Full server-side Julia for notebook execution
4. **Maintainability**: Changes to components apply everywhere

The key insight is that Therapy.jl's `Div`, `Button`, `Input` etc. are useful even without Wasm compilation - they provide a clean, composable way to build HTML in Julia.
