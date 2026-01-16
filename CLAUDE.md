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
│  ├─ Wasm Islands (DarkModeToggle, future: CellEditor)       │
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
│  └─ Per-Cell Signals: cell_state_{id}, cell_output_{id}     │
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
│   │   └── Signals.jl        # Per-cell signals (cell_state_{id}, etc.)
│   ├── UI/
│   │   ├── Layout.jl         # Main layout, CodeMirror setup
│   │   ├── CellView.jl       # Cell rendering component
│   │   ├── DarkModeToggle.jl # Wasm island for theme toggle
│   │   └── CellEditor.jl     # (future) Wasm island for cells
│   └── FileFormat/
│       ├── Parse.jl          # Load Pluto .jl files
│       └── Write.jl          # Save Pluto .jl files
├── CLAUDE.md                 # This file (canonical docs)
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

### ✅ Phase 2 Complete

| Feature | Pluto.jl | Sessions.jl | Status |
|---------|----------|-------------|--------|
| Reactive execution | Auto re-run deps | ✅ | Full dependency tracking |
| Rich output | HTML/SVG/Images | ✅ | MIME priority detection |
| Multi-line cells | Requires begin/end | ✅ | Auto-wrapped transparently |
| Pluto paste | N/A | ✅ | Parse and create cells |

### ⚠️ Partial / In Progress

| Feature | Pluto.jl | Sessions.jl | Status |
|---------|----------|-------------|--------|
| stdout/stderr | Captured & displayed | ⚠️ | Disabled (Pipe issues) |
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

**Sessions.jl uses Per-Cell Server Signals:**

Instead of a single Dict signal for all cells, Sessions.jl creates individual signals per cell for fine-grained updates:

```julia
# Signal naming convention
cell_state_{uuid}   # "CELL_IDLE" | "CELL_QUEUED" | "CELL_RUNNING" | "CELL_ERROR"
cell_output_{uuid}  # HTML output string
cell_runtime_{uuid} # Execution time in ms
cells_list          # JSON array of all cell IDs (for dynamic cell management)

# Server: Register signals when cell is created
function register_cell_signals!(cell::Cell)
    cell_id = string(cell.id)
    create_server_signal("cell_state_$(cell_id)", "CELL_IDLE")
    create_server_signal("cell_output_$(cell_id)", "")
    create_server_signal("cell_runtime_$(cell_id)", "")
end

# Server: Update signal → auto-broadcasts to all subscribers
function set_cell_state!(cell_id::UUID, state::CellState)
    sig = get_server_signal_by_name("cell_state_$(cell_id)")
    sig !== nothing && set_server_signal!(sig, string(state))
end

# Client JS: Subscribe to per-cell signals
TherapyWS.subscribe("cell_state_abc123...");
TherapyWS.subscribe("cell_output_abc123...");

# Client JS: Listen for updates via DOM event
window.addEventListener('therapy:signal:cell_state_abc123...', (e) => {
    const state = e.detail.value;  // "CELL_RUNNING"
    // Update cell CSS class
});

# HTML: CellView uses data attributes for signal binding
<div class="cell"
     data-cell-id="abc123..."
     data-cell-state-signal="cell_state_abc123..."
     data-cell-output-signal="cell_output_abc123...">
```

**Benefits of per-cell signals:**
- Fine-grained updates (only affected cell re-renders)
- Simpler client-side logic (no Dict parsing)
- Better performance with many cells
- Cleaner `data-server-signal` binding

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
    setup_signals!()    # Creates cells_list signal
    setup_lifecycle!()  # Registers connect/disconnect callbacks

    # Register per-cell signals for all existing cells
    register_all_cell_signals!(notebook)

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

### Per-Cell Signal Management

```julia
# When adding a cell (in Channels.jl)
on_channel_message("add_cell") do conn, data
    # ... create cell ...
    register_cell_signals!(new_cell)    # Register signals for new cell
    update_cells_list_signal!(notebook) # Update cells_list JSON array
end

# When deleting a cell
on_channel_message("delete_cell") do conn, data
    # ... delete cell ...
    unregister_cell_signals!(cell)      # Clean up cell signals
    update_cells_list_signal!(notebook)
end
```

### Client Setup (in Layout.jl)

```javascript
// Subscribe to per-cell signals on page load
document.querySelectorAll('[data-cell-state-signal]').forEach(cell => {
    const stateSignal = cell.dataset.cellStateSignal;
    const outputSignal = cell.dataset.cellOutputSignal;
    TherapyWS.subscribe(stateSignal);
    TherapyWS.subscribe(outputSignal);
});

// Listen for per-cell state updates
document.querySelectorAll('[data-cell-id]').forEach(cell => {
    const stateSignal = cell.dataset.cellStateSignal;
    window.addEventListener(`therapy:signal:${stateSignal}`, (e) => {
        const state = e.detail.value;
        // Update cell CSS classes based on state
        cell.classList.toggle('cell-running', state === 'CELL_RUNNING');
        cell.classList.toggle('cell-error', state === 'CELL_ERROR');
    });
});
```

---

### Wasm Islands

Therapy.jl compiles Julia closures to WebAssembly for interactive UI without JavaScript.

**DarkModeToggle (implemented):**

```julia
# src/UI/DarkModeToggle.jl - Pure Julia compiled to Wasm
DarkModeToggle = island(:DarkModeToggle) do
    # Reactive state: 0 = light, 1 = dark (Int32 for Wasm compatibility)
    dark, set_dark = create_signal(Int32(0))

    # :dark_mode prop tells compiler to call set_dark_mode(value) when signal changes
    Div(:dark_mode => dark,
        Button(
            :class => "p-2 rounded ...",
            :on_click => () -> begin
                if dark() == Int32(0)
                    set_dark(Int32(1))
                else
                    set_dark(Int32(0))
                end
            end,
            :title => "Toggle dark mode",
            Svg(:class => "w-5 h-5", ...)  # Moon/sun icon
        )
    )
end
```

**Key patterns:**
- `island(:Name) do ... end` - Creates interactive Wasm component
- `create_signal(Int32(x))` - Use Int32 for Wasm number compatibility
- `:dark_mode => signal` - Special prop binding to document theme
- `:on_click => () -> ...` - Julia closure compiled to Wasm

**Future: CellEditor island**

```julia
# Interactive cell editor with dirty state tracking
CellEditor = island(:CellEditor) do props
    cell_id = get_prop(props, :cell_id)
    code, set_code = create_signal("")
    is_dirty, set_dirty = create_signal(Int32(0))

    Div(:class => "cell-editor",
        # Dirty indicator controlled by Wasm
        Span(:class => is_dirty() == Int32(1) ? "bg-yellow-500" : ""),
        # CodeMirror container (initialized via hydration script)
        Div(Symbol("data-codemirror") => "true"),
        Button(:on_click => () -> execute(cell_id), "▶ Run")
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

## 🚨 CRITICAL DESIGN PRINCIPLE: Therapy.jl Native UI

**NEVER write raw JavaScript strings in Julia code.**

Sessions.jl must use Therapy.jl's native components for ALL UI:

| ❌ WRONG | ✅ CORRECT |
|----------|-----------|
| `Script("document.getElementById...")` | Therapy.jl server signals |
| `:onclick => "jsFunction()"` | `:on_click => () -> julia_fn()` (Wasm island) |
| Raw `<script>` tags in strings | `websocket_client_script()`, `client_router_script()` |
| Manual innerHTML updates | `RawHtml(content)` + server signal broadcast |
| Custom WebSocket code | Therapy.jl channels and signals |

**The only exception:** CodeMirror initialization (external JS library) - but even this should be minimized.

---

## Development Roadmap

### Phase 1: Core Polish ✅
- [x] Cell execution via WebSocket channels
- [x] Server signals for state broadcasting
- [x] CodeMirror with Julia syntax (codemirror-pluto-setup)
- [x] Basic cell operations (add, delete, run)
- [x] SPA-style cell insertion (no page reload)
- [x] Elegant parchment-inspired UI design

### Phase 2: Rich Output & Reactivity ✅
- [x] Rich MIME output (HTML, SVG, PNG, JPEG) - Worker.jl `render_rich_output()`
- [x] Full reactivity with downstream re-execution - Reactivity.jl
- [x] Smart multi-line cells (auto begin...end) - Cell.jl `parse_cell_code()`
- [x] Paste Pluto notebook content - Parse.jl `parse_pluto_content()`
- [x] Paste channel handler - Channels.jl `setup_paste_content_channel!()`
- [x] Client-side paste detection - Layout.jl `setupPasteHandler()`

### Phase 3: Interactive Widgets
- [ ] @bind macro support
- [ ] PlutoUI-compatible widgets (Slider, Button, etc.)
- [ ] Custom widget API via Therapy.jl islands

### Phase 4: IDE Features
- [ ] Keyboard shortcuts (Ctrl+S, Ctrl+Enter, etc.)
- [ ] Cell drag-and-drop reordering
- [ ] Multiple notebooks (tabs)
- [ ] File browser sidebar
- [ ] Export to HTML/PDF

### Phase 5: Advanced
- [ ] Package management (auto Pkg.add)
- [ ] Autocomplete (LSP integration)
- [ ] Multi-user collaboration via bidirectional signals

---

## ✅ PHASE 2 IMPLEMENTATION (COMPLETE)

### Overview

Phase 2 implemented four major features:

1. **Rich Output** ✅ - Display HTML, SVG, images, DataFrames, plots
2. **Full Reactivity** ✅ - Auto re-run downstream cells when dependencies change
3. **Smart Multi-line Cells** ✅ - Auto-wrap in `begin...end` transparently
4. **Paste Pluto Notebooks** ✅ - Parse pasted Pluto content into cells

All implementations use **Therapy.jl native components** - no raw JavaScript.

---

### 2.1 Rich Output Display

#### How Pluto Does It

Pluto uses a MIME-type priority system:
1. `text/html` - HTML rendering (highest priority)
2. `image/svg+xml` - SVG graphics
3. `image/png` - PNG images (base64)
4. `text/plain` - Fallback text

#### Sessions.jl Implementation (Therapy.jl Native)

**File: `src/Engine/Output.jl`**

```julia
# MIME type priority (highest first)
const MIME_PRIORITY = [
    MIME"text/html",
    MIME"image/svg+xml",
    MIME"image/png",
    MIME"image/jpeg",
    MIME"text/plain"
]

"""
Get the richest available representation of a value.
Returns (mime_type, content) tuple.
"""
function get_rich_output(value)
    for mime in MIME_PRIORITY
        if showable(mime, value)
            io = IOBuffer()
            show(io, mime, value)
            return (string(mime), String(take!(io)))
        end
    end
    # Fallback to repr
    return ("text/plain", repr(value))
end

"""
Render output as Therapy.jl component (NOT raw HTML string).
"""
function render_output(mime_type::String, content::String)
    if mime_type == "text/html"
        # Use Therapy.jl RawHtml for trusted HTML
        RawHtml(content)
    elseif mime_type == "image/svg+xml"
        # SVG can be rendered directly via RawHtml
        RawHtml(content)
    elseif startswith(mime_type, "image/")
        # Images as base64 data URI using Therapy.jl Img element
        Img(:src => "data:$mime_type;base64,$content",
            :class => "max-w-full h-auto")
    else
        # Plain text in Pre/Code elements
        Pre(:class => "font-mono text-sm whitespace-pre-wrap",
            Code(content))
    end
end
```

**File: `src/UI/CellOutput.jl`** (NEW - Therapy.jl component)

```julia
"""
Cell output component - renders rich output via Therapy.jl elements.
NEVER uses raw HTML strings - always Therapy.jl components.
"""
function CellOutput(cell::Cell)
    if cell.output === nothing
        return nothing
    end

    mime_type = cell.output.mime_type
    content = cell.output.content

    Div(:class => "cell-output-content",
        render_output(mime_type, content)
    )
end
```

**Signal Updates (Server → Client)**

```julia
# In Channels.jl - after execution
function broadcast_cell_output(cell::Cell)
    # Get rich output
    mime_type, content = get_rich_output(cell.result)

    # Render to HTML via Therapy.jl (NOT string concatenation)
    output_component = render_output(mime_type, content)
    output_html = render_to_string(output_component)

    # Broadcast via server signal
    set_cell_output!(cell.id, output_html)
end
```

#### Key Insight: RawHtml for Rich Content

Therapy.jl's `RawHtml` is the correct way to inject HTML:
- It explicitly marks content as trusted HTML
- It integrates with SSR rendering
- It's type-safe (not a string in a string)

```julia
# ✅ CORRECT - Therapy.jl native
RawHtml("<table><tr><td>Data</td></tr></table>")

# ❌ WRONG - raw string manipulation
"<div>" * html_content * "</div>"
```

---

### 2.2 Full Reactivity (Auto Re-run)

#### How Pluto Does It

1. **ExpressionExplorer.jl** - Analyzes each cell's code to find:
   - `references` - Variables the cell reads
   - `definitions` - Variables the cell defines

2. **PlutoDependencyExplorer.jl** - Builds dependency graph:
   - Cell A defines `x` → Cell B references `x` → B depends on A
   - When A changes, B must re-run

#### Sessions.jl Implementation

**File: `src/Engine/Reactivity.jl`** (enhance existing)

```julia
using ExpressionExplorer
import PlutoDependencyExplorer as PDE

"""
Analyze cell code and extract references/definitions.
Handles multi-expression cells by wrapping in begin...end.
"""
function analyze_cell!(cell::Cell)
    # Parse code (may be wrapped - see section 2.3)
    expr = parse_cell_code(cell.code)

    # Use ExpressionExplorer to find refs/defs
    node = ExpressionExplorer.compute_reactive_node(expr)

    cell.references = node.references
    cell.definitions = node.definitions
    cell.funcdefs = node.funcdefs_without_signatures
end

"""
Get cells that need to re-run when `changed_cell` executes.
Uses PlutoDependencyExplorer for correct topological ordering.
"""
function get_downstream_cells(notebook::Notebook, changed_cell::Cell)
    # Build topology using PDE
    cells = collect(values(notebook.cells))

    topology = PDE.NotebookTopology{Cell}()
    topology = PDE.updated_topology(
        topology, cells, cells;
        get_code_str = c -> c.code,
        get_code_expr = c -> parse_cell_code(c.code)
    )

    # Get execution order starting from changed cell
    order = PDE.topological_order(topology)

    # Filter to cells downstream of changed_cell
    changed_defs = changed_cell.definitions
    downstream = Cell[]

    for cell in order.runnable
        if cell.id != changed_cell.id
            # Cell depends on changed_cell if it references any of its definitions
            if !isempty(intersect(cell.references, changed_defs))
                push!(downstream, cell)
            end
        end
    end

    return downstream
end

"""
Execute cell and all downstream dependencies reactively.
"""
function execute_reactive!(notebook::Notebook, cell_id::UUID)
    cell = get_cell(notebook, cell_id)
    cell === nothing && return

    # Re-analyze in case code changed
    analyze_cell!(cell)

    # Get execution order: this cell + all downstream
    to_execute = [cell]
    append!(to_execute, get_downstream_cells(notebook, cell))

    # Execute in order, broadcasting state updates
    for c in to_execute
        set_cell_state!(c.id, CELL_RUNNING)

        result = execute_cell!(notebook, c)

        # Broadcast output via Therapy.jl signal
        broadcast_cell_output(c)

        set_cell_state!(c.id, result.success ? CELL_IDLE : CELL_ERROR)
    end
end
```

**Channel Handler Update**

```julia
# In Channels.jl
on_channel_message("execute") do conn, data
    cell_id = UUID(data["cell_id"])
    code = get(data, "code", nothing)

    # Update code if provided
    if code !== nothing
        cell.code = code
    end

    # Execute reactively (cell + downstream)
    execute_reactive!(notebook, cell_id)

    # All state/output updates happen via server signals automatically
end
```

---

### 2.3 Smart Multi-line Cells (Auto begin...end)

#### How Pluto Does It

Pluto requires users to explicitly wrap multi-line code in `begin...end`.
**Sessions.jl will be smarter** - auto-wrap transparently.

#### Sessions.jl Implementation

**File: `src/Engine/Cell.jl`** (enhance)

```julia
"""
Parse cell code, auto-wrapping multi-expression code in begin...end.
This is transparent to the user - they write multiple lines, we handle it.
"""
function parse_cell_code(code::String)
    # Try parsing as single expression
    expr = Meta.parse(code)

    if expr isa Expr && expr.head == :incomplete
        # Try wrapping in begin...end
        wrapped = "begin\n$code\nend"
        expr = Meta.parse(wrapped)
        if !(expr isa Expr && expr.head == :incomplete)
            return expr
        end
    end

    # Check if it's multiple top-level expressions
    # Meta.parse with `raise=false` returns :toplevel for multiple exprs
    full_parse = Meta.parseall(code)

    if full_parse isa Expr && full_parse.head == :toplevel && length(full_parse.args) > 1
        # Multiple expressions - wrap in begin...end
        return Expr(:block, full_parse.args...)
    end

    return expr
end

"""
Get the display value of a cell (last expression in multi-line).
"""
function get_display_value(result)
    # If result is from a begin...end block, it's the last expression
    # This matches Pluto's behavior
    return result
end
```

**Key Insight: Transparent Wrapping**

```julia
# User writes (no begin/end needed):
x = 1
y = 2
z = x + y

# Sessions.jl internally parses as:
begin
    x = 1
    y = 2
    z = x + y  # ← This value is displayed
end

# Variables x, y, z are all defined at module scope (not local)
```

---

### 2.4 Paste Pluto Notebook Content

#### Pluto File Format

```julia
### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 844da824-dcb6-11ea-1b3d-95c52106a0d2
x = 1

# ╔═╡ 844da856-dcb6-11ea-2061-a59a23dd029f
y = x + 2

# ╔═╡ Cell order:
# ╠═844da824-dcb6-11ea-1b3d-95c52106a0d2
# ╠═844da856-dcb6-11ea-2061-a59a23dd029f
```

#### Sessions.jl Implementation

**File: `src/FileFormat/Parse.jl`** (enhance)

```julia
const PLUTO_HEADER = r"^### A Pluto\.jl notebook ###"
const CELL_HEADER = r"^# ╔═╡ ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$"m
const CELL_ORDER = r"^# ╔═╡ Cell order:$"m

"""
Parse pasted Pluto notebook content into cells.
Returns Vector of (uuid, code) tuples in display order.
"""
function parse_pluto_content(content::String)
    cells = Dict{String, String}()
    order = String[]

    # Check if it's a Pluto notebook
    if !occursin(PLUTO_HEADER, content)
        # Not a Pluto notebook - treat as single cell
        return [(string(uuid4()), content)]
    end

    # Extract cells
    lines = split(content, '\n')
    current_uuid = nothing
    current_code = String[]

    for line in lines
        m = match(CELL_HEADER, line)
        if m !== nothing
            # Save previous cell
            if current_uuid !== nothing
                cells[current_uuid] = join(current_code, '\n')
            end
            current_uuid = m.captures[1]
            current_code = String[]
        elseif occursin(CELL_ORDER, line)
            # Save last cell and start reading order
            if current_uuid !== nothing
                cells[current_uuid] = join(current_code, '\n')
            end
            current_uuid = nothing
        elseif startswith(line, "# ╠═") || startswith(line, "# ╟─")
            # Cell order entry
            uuid = replace(line, r"^# [╠╟][═─]" => "")
            push!(order, strip(uuid))
        elseif current_uuid !== nothing
            push!(current_code, line)
        end
    end

    # Return cells in display order
    return [(uuid, strip(get(cells, uuid, ""))) for uuid in order if haskey(cells, uuid)]
end
```

**Channel Handler for Paste**

```julia
# In Channels.jl - new channel
create_channel("paste_content")

on_channel_message("paste_content") do conn, data
    content = data["content"]
    notebook_id = UUID(data["notebook_id"])

    notebook = get(NOTEBOOKS, notebook_id, nothing)
    notebook === nothing && return

    # Parse pasted content (handles Pluto format or raw code)
    parsed_cells = parse_pluto_content(content)

    # Create cells and broadcast
    for (uuid_str, code) in parsed_cells
        cell = add_cell!(notebook; code=code)
        register_cell_signals!(cell)

        # Broadcast rendered HTML for SPA insertion
        cell_html = render_to_string(CellView(cell))
        broadcast_channel!("cell_added", Dict(
            "cell_id" => string(cell.id),
            "cell_html" => cell_html,
            "after_cell_id" => nothing
        ))
    end

    update_cells_list_signal!(notebook)
end
```

**UI Component for Paste Detection** (Therapy.jl native)

```julia
# In Layout.jl - add paste handler via Therapy.jl
# This uses :onpaste HTML attribute (SSR) until we have full Wasm paste handling
Div(:class => "cells-container",
    :onpaste => "handleNotebookPaste(event)",  # Minimal JS bridge
    # ... cells
)
```

Note: The paste handler is one of the few places where a small JS bridge is needed
because clipboard API requires direct browser interaction. But the actual parsing
and cell creation happens server-side via Therapy.jl channels.

---

### 2.5 stdout/stderr Capture

**File: `src/Engine/Worker.jl`** (enhance)

```julia
using IOCapture  # Add to Project.toml

"""
Execute code with stdout/stderr capture.
"""
function execute_with_capture(worker, code::String)
    # IOCapture handles all the complexity
    captured = IOCapture.capture() do
        remote_eval(worker, code)
    end

    return (
        value = captured.value,
        output = captured.output,  # Combined stdout/stderr
        success = !captured.error
    )
end
```

**Render stdout/stderr via Therapy.jl**

```julia
function render_captured_output(stdout_content::String, result_html::String)
    Div(:class => "cell-output",
        # stdout/stderr in muted style
        !isempty(stdout_content) ?
            Pre(:class => "text-xs text-stone-500 dark:text-stone-400 mb-2 font-mono",
                stdout_content
            ) : nothing,
        # Main result
        RawHtml(result_html)
    )
end
```

---

### 2.6 File Structure After Phase 2

```
src/
├── Engine/
│   ├── Cell.jl           # + parse_cell_code() auto-wrapping
│   ├── Notebook.jl       # unchanged
│   ├── Output.jl         # + MIME handling, render_output()
│   ├── Reactivity.jl     # + full PDE integration, execute_reactive!
│   └── Worker.jl         # + IOCapture for stdout/stderr
├── Server/
│   ├── App.jl            # unchanged
│   ├── Channels.jl       # + paste_content channel
│   └── Signals.jl        # unchanged
├── UI/
│   ├── Layout.jl         # + paste handler attribute
│   ├── CellView.jl       # unchanged (already uses Therapy.jl)
│   ├── CellOutput.jl     # NEW - Therapy.jl output component
│   └── DarkModeToggle.jl # unchanged
└── FileFormat/
    ├── Parse.jl          # + parse_pluto_content()
    └── Write.jl          # unchanged
```

---

### 2.7 Testing Checklist

```julia
# Test rich output
notebook = Notebook()
add_cell!(notebook; code="using DataFrames; DataFrame(a=1:3, b=4:6)")
# Should render as HTML table

# Test reactivity
add_cell!(notebook; code="x = 10")
add_cell!(notebook; code="y = x * 2")  # y = 20
# Change first cell to x = 5
# y should auto-update to 10

# Test multi-line
add_cell!(notebook; code="""
a = 1
b = 2
a + b
""")
# Should work without explicit begin/end, display 3

# Test paste
content = """
### A Pluto.jl notebook ###
# ╔═╡ abc123...
x = 1
# ╔═╡ def456...
y = x + 1
"""
# Pasting should create 2 cells
```

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

### Server → Client (via Per-Cell Signals)

```javascript
// Subscribe to per-cell signals on page load
cells.forEach(cell => {
    TherapyWS.subscribe(`cell_state_${cell.id}`);
    TherapyWS.subscribe(`cell_output_${cell.id}`);
    TherapyWS.subscribe(`cell_runtime_${cell.id}`);
});

// Listen for individual cell state updates
window.addEventListener('therapy:signal:cell_state_abc123...', (e) => {
    // e.detail.value = "CELL_RUNNING" | "CELL_IDLE" | "CELL_ERROR"
});

window.addEventListener('therapy:signal:cell_output_abc123...', (e) => {
    // e.detail.value = "<pre>4</pre>" (HTML string)
});

// Listen for cells list changes (add/delete)
TherapyWS.subscribe('cells_list');
window.addEventListener('therapy:signal:cells_list', (e) => {
    // e.detail.value = ["uuid1", "uuid2", ...] (ordered array)
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
