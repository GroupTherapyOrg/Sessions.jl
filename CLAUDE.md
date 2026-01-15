# Sessions.jl Developer Guide

A reactive notebook IDE built with Therapy.jl, targeting full Pluto.jl feature parity while leveraging Therapy's reactive web framework capabilities.

## Quick Start

```bash
cd /Users/daleblack/Documents/dev/TherapeuticJulia/Sessions.jl
julia --project=. -e 'using Sessions; Sessions.serve()'
# Open http://localhost:8080
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Browser (Client)                          │
├─────────────────────────────────────────────────────────────┤
│  Therapy.jl UI                                               │
│  ├─ SSR Components (Layout, CellView)                       │
│  ├─ Pluto CodeMirror (julia_andrey syntax)                  │
│  ├─ TherapyWS (WebSocket client)                            │
│  └─ therapy:signal:* event listeners                        │
└─────────────────────────────────────────────────────────────┘
                         │ WebSocket (real-time)
┌────────────────────────┼────────────────────────────────────┐
│                    Server (Julia)                            │
├────────────────────────┴────────────────────────────────────┤
│  Therapy.jl Server                                           │
│  ├─ HTTP + WebSocket handling                               │
│  ├─ Channels: execute, add_cell, delete_cell, etc.          │
│  └─ Server Signals: cell_states, cell_outputs               │
├─────────────────────────────────────────────────────────────┤
│  Notebook Engine                                             │
│  ├─ ExpressionExplorer.jl (code analysis)                   │
│  ├─ PlutoDependencyExplorer.jl (reactive ordering)          │
│  └─ Malt.jl (sandboxed execution)                           │
└─────────────────────────────────────────────────────────────┘
```

### Therapy.jl Benefits

Sessions.jl leverages Therapy.jl's reactive architecture:

| Feature | Benefit |
|---------|---------|
| **Server Signals** | Cell states broadcast automatically to all clients |
| **Channels** | Bidirectional WebSocket messaging with typed handlers |
| **SSR + Hydration** | Fast initial load, interactive islands |
| **Reactive DOM** | `therapy:signal:*` events for fine-grained updates |
| **Component Model** | Reusable UI components (CellView, Layout) |

---

## Project Structure

```
Sessions.jl/
├── src/
│   ├── Sessions.jl           # Main module, exports
│   ├── Engine/
│   │   ├── Cell.jl           # Cell struct, CellState enum
│   │   ├── Notebook.jl       # Notebook container, worker management
│   │   ├── Reactivity.jl     # ExpressionExplorer + PDE integration
│   │   ├── Worker.jl         # Malt.jl execution
│   │   └── Output.jl         # MIME handling, HTML rendering
│   ├── Server/
│   │   ├── App.jl            # HTTP server, WebSocket routing
│   │   ├── Channels.jl       # execute, add_cell, delete_cell handlers
│   │   └── Signals.jl        # cell_states, cell_outputs signals
│   ├── UI/
│   │   ├── Layout.jl         # Main layout, CodeMirror setup
│   │   ├── CellView.jl       # Cell rendering component
│   │   └── CellIsland.jl     # (future) Wasm island for cells
│   └── FileFormat/
│       ├── Parse.jl          # Load Pluto .jl files
│       └── Write.jl          # Save Pluto .jl files
├── ARCHITECTURE.md
├── CLAUDE.md                 # This file
└── Project.toml
```

---

## Pluto.jl Feature Parity Analysis

### ✅ Complete

| Feature | Pluto.jl | Sessions.jl | Notes |
|---------|----------|-------------|-------|
| Cell struct | ✅ | ✅ | id, code, output, state |
| Notebook struct | ✅ | ✅ | cells, cell_order, worker |
| Code analysis | ExpressionExplorer | ✅ | refs/defs extraction |
| Dependency graph | PlutoDependencyExplorer | ✅ | Execution ordering |
| Sandboxed execution | Malt.jl | ✅ | Isolated workers |
| File format | .jl with markers | ✅ | Full Pluto compatibility |
| WebSocket comms | Custom | ✅ Therapy.jl | Server signals + channels |
| Code editor | CodeMirror 6 | ✅ | codemirror-pluto-setup |
| Julia syntax | julia_andrey | ✅ | Pluto's lezer parser |
| Cell states | IDLE/RUNNING/ERROR | ✅ | Visual indicators |
| Keyboard shortcuts | Shift+Enter | ✅ | Run cell |

### ⚠️ Partial / In Progress

| Feature | Pluto.jl | Sessions.jl | Status |
|---------|----------|-------------|--------|
| Reactive execution | Auto re-run deps | ⚠️ | Basic ordering works |
| stdout/stderr | Captured & displayed | ⚠️ | Disabled (Pipe issues) |
| Rich output | HTML/SVG/Images | ⚠️ | text/plain only |
| Cell folding | Collapse cells | ❌ | Struct field exists |
| Cell disabling | Skip execution | ❌ | Struct field exists |

### ❌ Missing (Roadmap)

| Feature | Pluto.jl | Priority | Description |
|---------|----------|----------|-------------|
| **@bind macro** | Live widgets | P1 | HTML inputs → Julia variables |
| **PlutoUI** | Sliders, buttons | P1 | Widget library |
| **Package management** | Auto-install | P1 | Syntax-analyzed Pkg.add |
| **Autocomplete** | Code completion | P2 | LSP or custom |
| **Multiple notebooks** | Tabs | P2 | Tab-based UI |
| **File browser** | Sidebar | P2 | Browse & open files |
| **Export HTML/PDF** | Static export | P2 | Publishable output |
| **Collaboration** | Multi-user | P3 | Real-time sync |
| **Pkg environment** | Embedded | P3 | Project.toml in notebook |
| **Interrupts** | Stop execution | P2 | Malt.interrupt |

---

## Therapy.jl WebSocket Architecture (Leptos.rs-Inspired)

**CRITICAL: Sessions.jl delegates ALL WebSocket infrastructure to Therapy.jl.**

Sessions.jl should NEVER import `Sockets` directly. All real-time communication is handled by Therapy.jl's Leptos-inspired reactive system.

### Three Types of Real-Time Communication

Therapy.jl provides three distinct patterns (matching Leptos.rs):

| Type | Direction | Use Case | Example |
|------|-----------|----------|---------|
| **Server Signals** | Server → Client | Continuous state | Cell states, outputs |
| **Bidirectional Signals** | Server ↔ Client | Shared state | Collaborative editing |
| **Channels** | Messages | Discrete events | Execute commands, chat |

---

### 1. Server Signals (like Leptos `leptos_server_signal`)

Server-controlled, read-only on client. Updates broadcast as JSON patches (RFC 6902) for efficiency.

```julia
# Server: Create signal
cell_states = create_server_signal("cell_states", Dict{String,String}())

# Server: Update signal → auto-broadcasts patch to all subscribers
set_server_signal!(cell_states, Dict(
    cell_id => "CELL_RUNNING"
))

# Client JS: Subscribe to receive updates
TherapyWS.subscribe("cell_states");

# Client JS: Listen for updates via DOM event
window.addEventListener('therapy:signal:cell_states', function(e) {
    const states = e.detail.value;  // Full current value
    // Update UI...
});

# HTML: Automatic DOM binding (optional)
<span data-server-signal="visitors">0</span>
```

**Sessions.jl uses Server Signals for:**
- `cell_states` - Broadcasting cell execution state (RUNNING/IDLE/ERROR)
- `cell_outputs` - Broadcasting cell outputs when execution completes

---

### 2. Bidirectional Signals (like Leptos `leptos_ws`)

Both server AND client can modify. Client sends patch → Server validates → broadcasts to OTHER clients.

```julia
# Server: Create bidirectional signal
shared_doc = create_bidirectional_signal("shared_doc", "")

# Server: Handle client updates
on_bidirectional_update("shared_doc") do conn, new_value
    # Validate/transform value
    return new_value  # or return false to reject
end

# Client JS: Update signal
TherapyWS.setBidirectional("shared_doc", newValue);

# HTML: Automatic binding
<textarea data-bidirectional-signal="shared_doc"></textarea>
```

**Future Sessions.jl uses:**
- Collaborative notebook editing
- Live code sync between users

---

### 3. Channels (like Leptos channel signals)

Discrete messages (events), NOT continuous state. Perfect for commands/actions.

```julia
# Server: Create channel and handler
create_channel("execute")

on_channel_message("execute") do conn, data
    notebook_id = data["notebook_id"]
    cell_id = data["cell_id"]
    code = data["code"]
    # Execute the cell...
end

# Server: Broadcast to all clients
broadcast_channel!("cell_added", Dict("cell_id" => new_id))

# Client JS: Send message
TherapyWS.sendMessage("execute", {
    notebook_id: notebookId,
    cell_id: cellId,
    code: getCode(cellId)
});

# Client JS: Listen for channel messages
window.addEventListener('therapy:channel:cell_added', function(e) {
    const data = e.detail;
    // Handle message...
});
```

**Sessions.jl uses Channels for:**
- `execute` - Cell execution requests
- `add_cell` / `delete_cell` - Cell management operations
- `run_all` / `save` - Notebook operations
- `cell_added` / `cell_deleted` - Broadcast notifications

---

### 4. Connection Lifecycle

```julia
# Server: Connection callbacks
on_ws_connect() do conn
    println("[Sessions] Client connected: $(conn.id)")
    # Initialize client state...
end

on_ws_disconnect() do conn
    println("[Sessions] Client disconnected: $(conn.id)")
    # Cleanup...
end

# Client: Auto-reconnect with exponential backoff (built-in)
# Static site graceful degradation (GitHub Pages)
```

---

### JavaScript API (TherapyWS)

Therapy.jl provides the `TherapyWS` global object:

```javascript
// Connection management
TherapyWS.isConnected()          // Check connection status

// Server Signals
TherapyWS.subscribe("name")      // Subscribe to signal updates

// Bidirectional Signals
TherapyWS.setBidirectional("name", value)  // Update from client

// Channels
TherapyWS.sendMessage("channel", data)     // Send to server
TherapyWS.onChannelMessage("channel", fn)  // Listen for broadcasts
```

---

### DOM Events

All updates are dispatched as CustomEvents:

```javascript
// Signal updates
window.addEventListener('therapy:signal:cell_states', (e) => {
    e.detail.value;  // Current signal value
});

// Channel messages
window.addEventListener('therapy:channel:cell_added', (e) => {
    e.detail;  // Message data
});
```

---

### HTML Attributes

Automatic DOM binding (optional):

```html
<!-- Server signal: Updates automatically -->
<span data-server-signal="visitors">0</span>

<!-- Bidirectional signal: Two-way sync -->
<textarea data-bidirectional-signal="shared_doc"></textarea>

<!-- WebSocket example marker (for static mode warnings) -->
<div data-ws-example="true">...</div>
```

---

## Sessions.jl Therapy.jl Usage

### Server Setup (in App.jl serve())

```julia
function serve(; port::Int=8080, host::String="127.0.0.1")
    # Set up Therapy.jl WebSocket channels and signals
    setup_channels!()   # Creates execute, add_cell, delete_cell channels
    setup_signals!()    # Creates cell_states, cell_outputs signals
    setup_lifecycle!()  # Registers connect/disconnect callbacks

    # Start HTTP server (Therapy.jl handles WebSocket internally)
    server = HTTP.listen!(handle_stream, host, port)
    # ...
end
```

### WebSocket Route (delegates to Therapy.jl)

```julia
function handle_stream(stream::HTTP.Stream)
    if path == "/ws"
        # Delegate ENTIRELY to Therapy.jl
        handle_websocket(stream)
        return
    end
    # ... handle regular HTTP
end
```

### Client Setup (in Layout.jl)

```javascript
// In sessions_script(), included via sessions_head_extra()
function setupSignalHandlers() {
    // Subscribe to server signals
    TherapyWS.subscribe('cell_states');
    TherapyWS.subscribe('cell_outputs');
}

function setupChannelHandlers() {
    // Listen for broadcasts
    TherapyWS.onChannelMessage('cell_added', () => location.reload());
    TherapyWS.onChannelMessage('cell_deleted', (data) => {
        // Remove cell from DOM...
    });
}
```

---

### Future: Wasm Islands

```julia
# Interactive cell component compiled to Wasm
CellIsland = island(:CellIsland) do props
    cell_id = get_prop(props, :cell_id)
    code, set_code = create_signal("")

    Div(:class => "cell",
        CodeEditor(:value => code, :on_change => set_code),
        Button(:on_click => () -> execute(cell_id), "Run")
    )
end
```

---

## Pluto.jl Color Theme

### Light Mode

```css
/* Primary */
--pluto-blue: #375bbd;
--pluto-blue-light: #5e7ad3;

/* Syntax Highlighting */
--cm-keyword: oklch(45% 80% 30deg);     /* orange-brown */
--cm-string: oklch(35% 100% 180deg);    /* teal */
--cm-function: #cc80ac;                  /* pink */
--cm-builtin: #5e7ad3;                   /* purple-blue */
--cm-html: #48b685;                      /* green */

/* Cell States */
--normal-cell: rgba(0, 0, 0, 0.1);
--selected-cell: rgba(40, 78, 189, 0.4);
--error-cell: rgba(240, 168, 168, 0.7);
--running-cell: #ffcd70;
```

### Dark Mode

```css
/* Primary */
--main-bg: hsl(0deg 0% 12%);
--header-bg: hsl(30deg 3% 16%);

/* Syntax Highlighting */
--cm-function: #f99b15;                  /* orange */
--cm-link: #815ba4;                      /* purple */
--cm-string: oklch(80% 10% 180deg);
--cm-html: #00ab85;
--cm-html-accent: #00e7b4;               /* cyan */
```

---

## Development Roadmap

### Phase 1: Core Polish ✅
- [x] Cell execution via WebSocket
- [x] Server signals for state broadcasting
- [x] CodeMirror with Julia syntax
- [x] Basic cell operations (add, delete, run)

### Phase 2: Rich Output (Current)
- [ ] Fix stdout/stderr capture (use IOCapture.jl?)
- [ ] HTML output rendering
- [ ] SVG/Image display
- [ ] Error formatting with stacktraces
- [ ] Runtime display per cell

### Phase 3: Interactivity
- [ ] @bind macro support
- [ ] PlutoUI slider/button widgets
- [ ] Custom widget API
- [ ] Live reactivity (auto re-run)

### Phase 4: Package Management
- [ ] Syntax-analyzed imports
- [ ] Auto Pkg.add on first use
- [ ] Embedded Project.toml
- [ ] Version pinning

### Phase 5: IDE Features
- [ ] File browser sidebar
- [ ] Multiple notebooks (tabs)
- [ ] Cell folding/collapsing
- [ ] Autocomplete (LSP integration)
- [ ] Export to HTML/PDF

### Phase 6: Collaboration
- [ ] Multi-user editing
- [ ] Cursor presence
- [ ] Real-time sync via Therapy.jl bidirectional signals

---

## WebSocket Protocol

### Client → Server

```javascript
// Cell operations
TherapyWS.sendMessage('execute', {notebook_id, cell_id, code})
TherapyWS.sendMessage('add_cell', {notebook_id, after_cell_id})
TherapyWS.sendMessage('delete_cell', {notebook_id, cell_id})
TherapyWS.sendMessage('move_cell', {notebook_id, cell_id, new_index})
TherapyWS.sendMessage('update_code', {notebook_id, cell_id, code})

// Notebook operations
TherapyWS.sendMessage('run_all', {notebook_id})
TherapyWS.sendMessage('interrupt', {notebook_id})
TherapyWS.sendMessage('restart', {notebook_id})
TherapyWS.sendMessage('save', {notebook_id, path})
TherapyWS.sendMessage('load', {path})
```

### Server → Client (via Signals)

```javascript
// Subscribe on connect
TherapyWS.subscribe('cell_states');
TherapyWS.subscribe('cell_outputs');

// Listen for updates
window.addEventListener('therapy:signal:cell_states', (e) => {
    // e.detail.value = {cell_id: "CELL_RUNNING", ...}
});

window.addEventListener('therapy:signal:cell_outputs', (e) => {
    // e.detail.value = {cell_id: {html: "...", runtime_ms: 42}, ...}
});
```

---

## File Format

Sessions uses Pluto's `.jl` format for full compatibility:

```julia
### A Pluto.jl notebook ###
# v0.19.0

#=╠═╡ a1b2c3d4-e5f6-7890-abcd-ef1234567890
x = 1 + 1
  ╠═╡=#

#=╠═╡ b2c3d4e5-f6a7-8901-bcde-f12345678901
y = x * 2
  ╠═╡=#

# ╔═╡ Cell order:
# ╠═a1b2c3d4-e5f6-7890-abcd-ef1234567890
# ╠═b2c3d4e5-f6a7-8901-bcde-f12345678901
```

---

## Debugging

```julia
# Test cell execution directly
using Sessions
notebook = Notebook()
add_cell!(notebook; code="2 + 2")
cell = first(values(notebook.cells))
result = execute_cell!(notebook, cell)
println("Success: $(result.success), Value: $(result.value)")

# Check reactivity
analyze_cell!(cell)
println("References: $(cell.references)")
println("Definitions: $(cell.definitions)")
```

---

## Sister Projects

- **Therapy.jl** - Reactive web framework (`../Therapy.jl`)
- **WasmTarget.jl** - Julia → WebAssembly compiler (`../WasmTarget.jl`)
