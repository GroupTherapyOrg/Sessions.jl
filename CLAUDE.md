# Sessions.jl Developer Guide

## Quick Reference

Sessions.jl is a **Therapy.jl application** providing a VSCode + Pluto hybrid IDE/notebook experience. It is NOT a Pluto fork.

**Sister Repos**:
- `../Therapy.jl` - Reactive web framework (provides components, SSR, Wasm compilation)
- `../WasmTarget.jl` - Julia → WebAssembly compiler (foundation for Therapy.jl)

**Key Principle**: All UI is built with Therapy.jl primitives (`Div`, `Button`, `Input`, etc.) rendered server-side.

---

## Project Structure

```
Sessions.jl/
├── src/
│   ├── app.jl              # Entry point (like Therapy.jl apps)
│   ├── Sessions.jl         # Main module
│   ├── components/         # Therapy.jl UI components
│   │   ├── Layout.jl       # Main page layout + TopBar
│   │   ├── Sidebar.jl      # File explorer
│   │   └── Terminal.jl     # REPL terminal
│   ├── routes/             # Page routes (file-based routing ready)
│   │   └── index.jl        # Main notebook page
│   ├── Notebook/           # Core notebook logic
│   │   ├── Cell.jl         # Cell data structure
│   │   └── Executor.jl     # Code execution
│   └── Server/             # HTTP + WebSocket server
│       └── WebSocketServer.jl
├── test/
│   └── runtests.jl
├── VISION.md               # Architecture and goals
├── CLAUDE.md               # This file
└── Project.toml
```

---

## Development Workflow

### Running in Development
```bash
cd /Users/daleblack/Documents/dev/TherapeuticJulia/Sessions.jl

# Option 1: Direct
julia --project=. -e 'using Sessions; Sessions.dev()'

# Option 2: App entry point
julia --project=. src/app.jl dev

# Open http://localhost:8080 in your browser
```

### Testing
```bash
julia --project=. test/runtests.jl
```

### Working Across Repos

When Sessions needs something from Therapy.jl:

1. **Identify the need** in Sessions.jl
2. **Switch to Therapy.jl** and implement
3. **Test the enhancement** in isolation
4. **Return to Sessions** and use the new feature

```julia
# In Sessions Project.toml, local path is already configured:
[sources]
Therapy = {path = "../Therapy.jl"}
```

---

## Key Dependencies

### From TherapeuticJulia
- **Therapy.jl**: VNode components, render_page(), render_to_string()

### Standard Library
- **HTTP.jl**: HTTP server + WebSocket
- **JSON3.jl**: Message serialization
- **UUIDs**: Cell identification

### Planned (from Pluto Ecosystem)
- **ExpressionExplorer.jl**: Static analysis for dependency tracking
- **Malt.jl**: Isolated worker process execution

---

## Architecture

### Server-Side Rendering (NOT Client-Side Wasm)

Sessions uses **server-side Therapy.jl rendering** with WebSocket updates:

```
Browser                          Server
   │                                │
   │  GET /                         │
   │ ─────────────────────────────► │
   │                                │  render_page(Layout(...))
   │  HTML (Therapy.jl rendered)    │
   │ ◄───────────────────────────── │
   │                                │
   │  WebSocket /ws                 │
   │ ◄─────────────────────────────►│
   │                                │
   │  {action: 'execute', ...}      │
   │ ─────────────────────────────► │
   │                                │  execute code
   │                                │  render_cells_html()
   │  {type: 'cells', html: '...'}  │
   │ ◄───────────────────────────── │
   │                                │
   │  innerHTML = html              │
   │  (no client-side rendering)    │
```

### Why Server-Side?

1. **Notebook execution must be server-side** - Julia code runs on the server
2. **State lives on server** - Cells, outputs, execution context
3. **Simpler architecture** - No need to sync state between Wasm and server

### Code Flow

1. **HTTP Request** → `generate_page()` → `render_page(Layout(Sidebar(), Terminal()))`
2. **WebSocket** → `handle_ws_message()` → action handlers
3. **Cell Execution** → `execute_cell!()` → `broadcast_cells_html()` → `render_cells_html()`
4. **Client** receives pre-rendered HTML, swaps into DOM

---

## Key Files

### src/Sessions.jl
Main module - loads components and server:
```julia
module Sessions
using Therapy, HTTP, JSON3, UUIDs

include("Notebook/Cell.jl")
include("Notebook/Executor.jl")
include("components/Layout.jl")
include("components/Sidebar.jl")
include("components/Terminal.jl")
include("Server/WebSocketServer.jl")

function dev(; port=8080, host="127.0.0.1")
    start_server(host, port)
end
end
```

### src/Server/WebSocketServer.jl
Main server logic:
- `start_server()` - HTTP listener with WebSocket upgrade
- `handle_websocket()` - WebSocket connection handler
- `handle_ws_message()` - Message router (execute, add_cell, files, terminal, etc.)
- `generate_page()` - Renders main page with Therapy.jl
- `render_cells_html()` - Renders all cells to HTML
- `render_cell_vnode()` - Converts Cell → Therapy.jl VNode

### src/Notebook/Cell.jl
Cell data structure:
```julia
@enum CellStatus IDLE QUEUED RUNNING COMPLETED ERRORED

mutable struct Cell
    id::UUID
    code::String
    status::CellStatus
    output::Any
    stdout::String
    stderr::String
    error_msg::String
    execution_count::Int
end
```

### src/Notebook/Executor.jl
Code execution:
```julia
struct Executor
    mod::Module  # Isolated execution module
end

function execute(exec::Executor, code::String) -> ExecutionResult
    # Evaluate in isolated module, capture stdout/stderr
end

function execute_cell!(exec::Executor, cell::Cell)
    # Update cell status, execute, store output
end
```

---

## WebSocket Protocol

### Client → Server Actions
```javascript
{action: 'execute', cell_id: '...', code: '...'}  // Run cell
{action: 'add_cell'}                               // Add new cell
{action: 'delete_cell', cell_id: '...'}           // Delete cell
{action: 'update_code', cell_id: '...', code: '...'} // Update without running
{action: 'run_all'}                                // Run all cells
{action: 'restart'}                                // Restart executor
{action: 'files', path: '.'}                       // List directory
{action: 'open_file', path: '...'}                // Read file
{action: 'terminal', input: '...'}                // Terminal input
```

### Server → Client Messages
```javascript
{type: 'cells', html: '...'}     // Pre-rendered cells HTML
{type: 'files', html: '...'}     // Pre-rendered file tree HTML
{type: 'terminal', output: '...'} // Terminal output text
{type: 'file', path: '...', content: '...'} // File content
{type: 'error', message: '...'}  // Error message
```

---

## Adding Features

### Adding a New Component
1. Create file in `src/components/`
2. Define function returning VNodes: `function MyComponent() Div(...) end`
3. Include in `src/Sessions.jl`
4. Use in `generate_page()` or other components

### Adding a WebSocket Action
1. Add handler in `handle_ws_message()`:
```julia
elseif action == "my_action"
    # Handle action
    result = do_something(data["param"])
    # Send response
    send(ws, JSON3.write(Dict("type" => "my_response", ...)))
```
2. Add client-side binding in `ws_client_script()`

### Adding a Route (Future)
When file-based routing is enabled:
1. Create `src/routes/my-page.jl`
2. Define page function returning VNodes
3. Export the function

---

## Testing Strategy

### Unit Tests
```julia
@testset "Cell" begin
    cell = Cell()
    @test cell.status == IDLE
end

@testset "Executor" begin
    exec = Executor()
    result = execute(exec, "1 + 1")
    @test result.value == 2
end
```

### Manual Testing
1. Start dev server: `Sessions.dev()`
2. Open browser to localhost:8080
3. Test: add cells, run code, navigate files, use terminal

---

## Current Status

### Implemented
- [x] Project structure following Therapy.jl patterns
- [x] Layout, Sidebar, Terminal components
- [x] Cell data structure with status tracking
- [x] Code execution in isolated module
- [x] WebSocket server with pre-rendered HTML updates
- [x] File explorer (list, navigate directories)
- [x] Terminal (basic input/output)

### In Progress
- [ ] Dependency tracking (ExpressionExplorer.jl)
- [ ] Reactive execution (re-run dependent cells)
- [ ] Syntax highlighting

### Planned
- [ ] File editing/saving
- [ ] Plot rendering
- [ ] Keyboard shortcuts
- [ ] Static export to GitHub Pages

---

## Debugging Tips

### Server won't start
- Check if port is in use: `lsof -i:8080`
- Kill existing process: `lsof -ti:8080 | xargs kill -9`

### WebSocket not connecting
- Check browser console for errors
- Verify server is running and listening
- Check for CORS issues (shouldn't be any with same-origin)

### Code execution fails
- Check cell.error_msg for Julia errors
- Verify Executor module is initialized
- Check stdout/stderr capture

### UI not updating
- Check WebSocket connection in browser dev tools
- Verify `broadcast_cells_html()` is called after state changes
- Check `render_cells_html()` output

---

## Performance Notes

1. **Server renders everything** - No client-side computation
2. **HTML over WebSocket** - Pre-rendered, just swap innerHTML
3. **Minimal JS** - ~60 lines, just transport
4. **Single module execution** - All cells share one executor module

---

## Contact

This is part of the TherapeuticJulia project. All three repos (Sessions.jl, Therapy.jl, WasmTarget.jl) are developed in concert.
