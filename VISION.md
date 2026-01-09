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

### 3. Server-Side Rendering with WebSocket Updates
Unlike pure Therapy.jl islands (which compile to Wasm), Sessions uses:
- Server renders all HTML using Therapy.jl components
- WebSocket sends **pre-rendered HTML fragments** to the client
- Minimal client JavaScript handles only transport (no rendering logic)
- This is necessary because notebook execution must happen server-side

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
│  │           Sessions UI (Therapy.jl Components)             │  │
│  │                                                            │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │  │
│  │  │   Sidebar   │  │   Cells     │  │    Terminal     │   │  │
│  │  │  (files)    │  │ (notebook)  │  │   (REPL)        │   │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────┘   │  │
│  │                                                            │  │
│  │  Minimal JS: WebSocket transport only (~60 lines)         │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │ WebSocket                         │
└──────────────────────────────│──────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Sessions Server (Julia)                       │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  HTTP Server                                               │  │
│  │  - Serves pages rendered with Therapy.jl render_page()    │  │
│  │  - Uses Layout, Sidebar, Terminal components              │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  WebSocket Handler                                         │  │
│  │  - Cell execution → returns pre-rendered HTML              │  │
│  │  - File operations → returns pre-rendered HTML             │  │
│  │  - Terminal I/O → returns output text                      │  │
│  │  - All UI rendering happens HERE, not in browser           │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Core Components                                           │  │
│  │  - Cell.jl: Cell data structure with status, output        │  │
│  │  - Executor.jl: Code execution in isolated module          │  │
│  │  - render_cell_vnode(): Converts Cell → Therapy.jl VNode   │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Therapy.jl                                │
│  - VNode primitives (Div, Button, Input, Span, etc.)            │
│  - render_page() for full HTML documents                         │
│  - render_to_string() for HTML fragments                         │
│  - SSR with hydration keys (data-hk)                             │
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

All communication uses JSON messages:

### Client → Server
```javascript
// Execute cell
{action: 'execute', cell_id: '...', code: '...'}

// Add/delete cell
{action: 'add_cell'}
{action: 'delete_cell', cell_id: '...'}

// File operations
{action: 'files', path: '.'}
{action: 'open_file', path: 'src/foo.jl'}

// Terminal
{action: 'terminal', input: 'x = 1 + 1'}
```

### Server → Client
```javascript
// Pre-rendered cells HTML
{type: 'cells', html: '<div id="cells-content">...</div>'}

// Pre-rendered file tree HTML
{type: 'files', html: '<div id="file-tree-content">...</div>'}

// Terminal output
{type: 'terminal', output: '2'}
```

---

## Development Phases

### Phase 1: Foundation ✓
- [x] Basic project structure following Therapy.jl patterns
- [x] Layout, Sidebar, Terminal components
- [x] WebSocket server with cell execution
- [x] Server-side rendering with Therapy.jl

### Phase 2: Core Notebook ← Current
- [x] Cell management (add, delete, run)
- [x] Code execution with output capture
- [x] Status indicators (idle, running, completed, errored)
- [ ] Dependency tracking with ExpressionExplorer.jl
- [ ] Reactive execution (when cell changes, re-run dependents)

### Phase 3: File System
- [x] File listing via WebSocket
- [x] Directory navigation
- [ ] File editing and saving
- [ ] Project detection (Project.toml)

### Phase 4: Terminal
- [x] Basic terminal input/output
- [ ] Full PTY support with ANSI codes
- [ ] Multiple terminal sessions

### Phase 5: Rich Features
- [ ] Syntax highlighting (server-side or Prism.js)
- [ ] Autocomplete
- [ ] Plot rendering
- [ ] Table rendering
- [ ] HTML output

### Phase 6: Polish
- [ ] Keyboard shortcuts (Shift+Enter to run)
- [ ] Themes (light/dark)
- [ ] Settings persistence
- [ ] Better error display

### Phase 7: Static Export
- [ ] Build notebooks to static HTML
- [ ] GitHub Pages deployment
- [ ] Baked-in outputs

---

## Why Not Client-Side Wasm?

Sessions differs from typical Therapy.jl islands because:

1. **Notebook execution must be server-side** - Julia code needs to run with full capabilities
2. **State lives on server** - Cells, outputs, execution results
3. **WebSocket is natural** - Real-time updates for long-running computations

For pure Therapy.jl apps (like the docs site), islands compile to Wasm for client-side reactivity. But Sessions needs server-side execution, so we use:
- Server-side Therapy.jl rendering (still using all the same components!)
- WebSocket for communication
- Pre-rendered HTML fragments for updates

This is the same pattern used by HTMX, LiveView, and similar frameworks.

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
