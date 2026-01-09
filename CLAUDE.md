# Sessions.jl Developer Guide

## Quick Reference

Sessions.jl is a **Therapy.jl component** providing a VSCode + Pluto hybrid IDE/notebook experience. It is NOT a Pluto fork.

**Sister Repos**:
- `../Therapy.jl` - Reactive web framework (provides components, signals, SSR, Wasm compilation)
- `../WasmTarget.jl` - Julia → WebAssembly compiler (foundation for Therapy.jl)

**Key Principle**: Sessions is a Therapy.jl component first. All UI is built with Therapy.jl primitives (`island()`, `component()`, `create_signal()`, etc.).

---

## Project Structure

```
Sessions.jl/
├── src/
│   ├── Sessions.jl              # Main module
│   ├── Components/
│   │   ├── SessionsApp.jl       # Top-level IDE component
│   │   ├── FileExplorer.jl      # File tree sidebar
│   │   ├── EditorPane.jl        # Code editing area
│   │   ├── Terminal.jl          # Browser terminal
│   │   ├── Notebook/
│   │   │   ├── NotebookSession.jl  # Notebook container
│   │   │   ├── Cell.jl            # Individual cell
│   │   │   ├── CodeEditor.jl      # Code input
│   │   │   └── OutputRenderer.jl  # Output display
│   │   └── UI/
│   │       ├── TopBar.jl          # Menu bar, tabs
│   │       ├── Sidebar.jl         # Activity bar + side panel
│   │       ├── BottomPanel.jl     # Terminal, problems, output
│   │       └── CommandPalette.jl  # Quick actions
│   ├── Server/
│   │   ├── SessionsServer.jl    # Main server
│   │   ├── Filesystem.jl        # FS operations via WebSocket
│   │   ├── Terminal.jl          # PTY handling
│   │   └── Execution.jl         # Cell execution via Malt.jl
│   ├── Notebook/
│   │   ├── Cell.jl              # Cell data structure
│   │   ├── DependencyGraph.jl   # ExpressionExplorer integration
│   │   └── Executor.jl          # Malt.jl wrapper
│   └── Export/
│       └── StaticNotebook.jl    # GitHub Pages export
├── test/
│   └── runtests.jl
├── examples/
│   └── demo_notebook.jl
├── VISION.md                    # Architecture and goals
├── CLAUDE.md                    # This file
└── Project.toml
```

---

## Development Workflow

### Running in Development
```bash
cd /Users/daleblack/Documents/dev/TherapeuticJulia/Sessions.jl
julia --project=.

julia> using Sessions
julia> Sessions.dev()  # Starts dev server at localhost:8080
```

### Testing
```bash
julia --project=. test/runtests.jl
```

### Working Across Repos

When Sessions needs something from Therapy.jl or WasmTarget.jl:

1. **Identify the need** in Sessions.jl
2. **Switch to sister repo** and implement
3. **Test the enhancement** in isolation
4. **Return to Sessions** and use the new feature

```julia
# In Sessions Project.toml, use local path during dev:
[deps]
Therapy = "12345678-1234-1234-1234-123456789abc"

[sources]
Therapy = {path = "../Therapy.jl"}
```

---

## Key Dependencies

### From Pluto Ecosystem (Standalone Packages)
- **ExpressionExplorer.jl**: Static analysis of Julia expressions
- **Malt.jl**: Isolated worker process execution

### From TherapeuticJulia
- **Therapy.jl**: All UI components, reactivity, Wasm compilation

### Standard Library
- **HTTP.jl**: WebSocket server
- **Sockets.jl**: Network communication
- **JSON3.jl**: Data serialization

---

## Architecture Patterns

### 1. Components are Islands
All interactive components use `island()` for Wasm compilation:

```julia
MyComponent = island(:MyComponent) do
    state, set_state = create_signal(initial)
    Div(:on_click => () -> set_state(new_value), ...)
end
```

### 2. Server Communication via WebSocket
Browser components communicate with SessionsServer:

```julia
# Client side (in component)
on_mount() do
    ws_send("fs/list", "/path")
end

# Server side
@ws_handler "fs/list" function(path)
    readdir(path)
end
```

### 3. Cell Execution Model
1. User edits cell code
2. ExpressionExplorer analyzes for dependencies
3. DependencyGraph updated
4. Affected cells marked for re-execution
5. Malt.jl worker executes cells in topological order
6. Outputs streamed back via WebSocket
7. Signal updates trigger UI re-render

### 4. Static Export
For GitHub Pages:
1. Execute all cells, capture outputs
2. Serialize notebook state (code + outputs)
3. Generate static HTML with embedded Wasm
4. Outputs are "baked in" - no server needed

---

## Current Status

### Implemented
- [ ] Basic project structure
- [ ] VISION.md documentation

### In Progress
- [ ] Core component skeletons

### Blocked On
- **Nested conditionals in WasmTarget.jl** - Complex handlers fail
- **For component in Therapy.jl** - Needed for cell lists

---

## Common Tasks

### Adding a New Component
1. Create file in `src/Components/`
2. Use `island()` if interactive, `component()` if static
3. Export from `Sessions.jl` main module
4. Add tests

### Adding a Server Endpoint
1. Add handler in `src/Server/`
2. Register WebSocket route
3. Add client-side call in component

### Debugging Wasm Compilation
If a handler fails to compile:
1. Check for unsupported patterns (closures, complex control flow)
2. Simplify handler logic
3. May need to enhance WasmTarget.jl

---

## Testing Strategy

### Unit Tests
- Test data structures (Cell, DependencyGraph)
- Test ExpressionExplorer integration
- Test Malt.jl execution wrapper

### Integration Tests
- Test component rendering
- Test WebSocket communication
- Test full notebook execution flow

### Manual Testing
```julia
# Start dev server
Sessions.dev()

# Open browser to localhost:8080
# Interact with UI
```

---

## Performance Considerations

1. **Virtualized cell rendering** - Only render visible cells
2. **Lazy signal creation** - Cells not in view don't need signals
3. **Debounced analysis** - Don't re-analyze on every keystroke
4. **Incremental execution** - Only re-run affected cells

---

## Future Enhancements

See VISION.md for full roadmap. Key items:
1. Rich output rendering (plots, tables)
2. Git integration
3. Package management UI
4. Multi-session support
5. Collaboration features

---

## Contact

This is part of the TherapeuticJulia project. All three repos (Sessions.jl, Therapy.jl, WasmTarget.jl) are developed in concert.
