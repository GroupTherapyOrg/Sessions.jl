# Sessions.jl Developer Guide

## Quick Reference

Sessions.jl is a **Therapy.jl application** providing a VSCode + Pluto hybrid IDE/notebook experience. It is NOT a Pluto fork.

**Sister Repos** (in dependency order):
1. `../WasmTarget.jl` - Julia → WebAssembly compiler (most fundamental)
2. `../Therapy.jl` - Reactive web framework (depends on WasmTarget)
3. `Sessions.jl` - This app (depends on Therapy.jl)

**Architecture**: Hybrid SSR + WebSocket
- **SSR (Server-Side Rendering)**: Static UI components rendered with Therapy.jl
- **WebSocket**: Compute operations (code execution, terminal, filesystem)
- **Client-side JS**: UI state management and cell rendering
- **Future**: Wasm islands for UI state (NotebookIsland.jl ready)

**Key Principle**: Server handles COMPUTE, client handles UI. All data exchanged as JSON, not HTML.

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
│   │   ├── Terminal.jl     # REPL terminal
│   │   └── NotebookIsland.jl  # Future Wasm island for UI state
│   ├── routes/             # Page routes (file-based routing ready)
│   │   └── index.jl        # Main notebook page
│   ├── Notebook/           # Core notebook logic
│   │   ├── Cell.jl         # Cell data structure
│   │   ├── Executor.jl     # Code execution
│   │   └── DependencyTracker.jl  # Reactive dependency tracking (uses Pluto packages)
│   └── Server/             # HTTP + WebSocket server
│       ├── WebSocketServer.jl  # HTTP/WebSocket handling
│       └── ClientBridge.jl     # WebSocket JS bridge (CodeMirror, cell rendering)
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

### From Pluto Ecosystem (Integrated)
- **ExpressionExplorer.jl**: Static analysis for variable references
- **PlutoDependencyExplorer.jl**: Topological ordering of cell dependencies
- **Malt.jl**: Worker process management (for future isolated execution)

---

## Architecture

### Hybrid SSR + WebSocket Architecture

Sessions uses a **hybrid architecture**:
- SSR for initial page structure (Therapy.jl components)
- WebSocket for compute (JSON data exchange)
- Client-side JS for UI state and cell rendering

```
Browser                              Server
   │                                    │
   │  GET /                             │
   │ ─────────────────────────────────► │
   │                                    │  render_page(Layout(...))
   │  HTML (Therapy.jl SSR + JS bridge) │  (SSR components + hydration keys)
   │ ◄───────────────────────────────── │
   │                                    │
   │  WebSocket /ws                     │
   │ ◄──────────────────────────────────►
   │                                    │
   │  {action: 'execute', ...}          │
   │ ─────────────────────────────────► │
   │                                    │  execute code
   │  {type: 'cell_update', cell: {...}}│  (JSON data, NOT HTML)
   │ ◄───────────────────────────────── │
   │                                    │
   │  JS bridge renders cell to DOM     │
   │  (or future: Wasm signal update)   │
```

### Separation of Concerns

1. **Server = COMPUTE**
   - Code execution in isolated module
   - Cell state management (code, outputs, errors)
   - File system operations
   - Terminal I/O
   - Returns JSON data, never HTML

2. **Client = UI**
   - Cell rendering (currently JS, future Wasm)
   - Status indicators
   - Event handling
   - File tree display

### Why This Architecture?

1. **Notebook execution must be server-side** - Julia code runs on the server
2. **Clean separation** - Server doesn't care about UI, client doesn't care about execution
3. **Future-proof** - Easy to swap JS rendering for Wasm islands
4. **Follows Pluto patterns** - Similar WebSocket approach, easier to leverage Pluto packages

### Code Flow

1. **HTTP Request** → `generate_page()` → `render_page(Layout(...))`
2. **WebSocket Connect** → `broadcast_cells_state()` (JSON cell data)
3. **Execute Cell** → `execute_cell!()` → `broadcast_cell_update()` (JSON)
4. **Client** receives JSON, JS bridge renders cells to DOM

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
- `generate_page()` - Renders main page with Therapy.jl components
- `broadcast_cells_state()` - Send all cells to connected clients
- `broadcast_cell_update()` - Send single cell update (efficient)

### src/Server/ClientBridge.jl
JavaScript bridge for WebSocket ↔ UI:
- `head_extra()` - CodeMirror imports, CSS styles
- `websocket_bridge_script()` - Cell rendering, event handling, WebSocket connection

### src/Notebook/DependencyTracker.jl
Reactive cell execution using Pluto packages:
- `NotebookReactivity` - Tracks cell topology
- `update_cells!()` - Rebuild dependency graph
- `get_downstream_cells()` - Find cells to re-execute
- `get_execution_order()` - Topological sort for run_all

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

All messages are JSON. Server returns **data**, not HTML.

### Client → Server Actions
```javascript
{action: 'execute', cell_id: '...', code: '...'}  // Run cell
{action: 'add_cell'}                               // Add new cell
{action: 'delete_cell', cell_id: '...'}           // Delete cell
{action: 'update_code', cell_id: '...', code: '...'} // Update without running
{action: 'run_all'}                                // Run all cells
{action: 'restart'}                                // Restart executor
{action: 'get_cells'}                              // Request full cell state
{action: 'files', path: '.'}                       // List directory
{action: 'open_file', path: '...'}                // Read file
{action: 'terminal', input: '...'}                // Terminal input
```

### Server → Client Messages
```javascript
// Cell state (JSON data, client renders)
{type: 'cells_state', cells: [...], count: N}
{type: 'cell_update', cell: {id, code, status, output, ...}}

// File list (JSON data, client renders)
{type: 'files', path: '...', entries: [{name, path, is_directory}, ...]}

// Other
{type: 'terminal', output: '...'} // Terminal output text
{type: 'file', path: '...', content: '...'} // File content
{type: 'error', message: '...'}  // Error message
```

### Cell Data Structure (JSON)
```javascript
{
    id: 'uuid-string',
    code: 'julia code...',
    status: 1,  // 0=hidden, 1=idle, 2=running, 3=completed, 4=error
    status_name: 'IDLE',
    output: 'result repr',
    stdout: 'printed output',
    stderr: 'error output',
    error_msg: 'exception message',
    execution_count: 0
}
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
- [x] Layout, Sidebar, Terminal components (SSR with hydration keys)
- [x] Cell data structure with status tracking
- [x] Code execution in isolated module
- [x] **Hybrid architecture**: SSR + WebSocket (JSON) + client-side rendering
- [x] WebSocket returns JSON data (not HTML)
- [x] File explorer (list, navigate directories)
- [x] Terminal (basic input/output)
- [x] CodeMirror 6 syntax highlighting (Julia-like colors)
- [x] Dependency tracking (PlutoDependencyExplorer integration)
- [x] Reactive execution (re-run downstream cells automatically)
- [x] Clean module separation (WebSocketServer + ClientBridge)

### In Progress
- [ ] Full Wasm island integration (replace JS bridge with Wasm signals)
- [ ] Isolated worker processes (Malt.jl integration)

### Planned
- [ ] File editing/saving
- [ ] Plot rendering (using Therapy.jl Wasm)
- [ ] Keyboard shortcuts
- [ ] Static export to GitHub Pages
- [ ] Multi-session support

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

1. **Server handles compute** - Julia code execution server-side
2. **JSON over WebSocket** - Efficient data transfer, client renders
3. **CodeMirror 6** - Modern editor with ES modules from CDN
4. **Efficient updates** - `broadcast_cell_update()` for single-cell changes
5. **Reactive execution** - Only re-run downstream cells via dependency tracking

---

## Contact

This is part of the TherapeuticJulia project. All three repos (Sessions.jl, Therapy.jl, WasmTarget.jl) are developed in concert.
