# Sessions.jl Vision Document

## Executive Summary

Sessions.jl is a **Therapy.jl component** that provides a VSCode + Pluto hybrid experience entirely in the browser. It is NOT a Pluto fork - it's a pure reactive web component built on Therapy.jl that selectively leverages standalone Pluto packages where they make sense.

**Core Identity**: Sessions.jl is a Therapy.jl component first, notebook second.

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

### 1. Pure Therapy.jl Component
- Sessions is a regular `island()` component that can be embedded in any Therapy.jl app
- Full-stack apps can have notebooks as just another route/component
- The notebook itself is reactive (signals, effects, memos) not a separate architecture

### 2. VSCode + Pluto Hybrid UI
- **File Explorer**: Navigate local filesystem (connected via WebSocket to local server)
- **Integrated Terminal**: Browser-based terminal connected to local hardware
- **Notebook Sessions**: Pluto-like reactive cells with dependency tracking
- **Editor Panes**: Multiple panes, tabs, split views like VSCode
- **Command Palette**: Quick actions, file search, command execution

### 3. Selective Pluto Package Leverage
We don't fork Pluto. We use its **standalone packages** where they provide value:
- `ExpressionExplorer.jl` - Static analysis of Julia expressions
- `Malt.jl` - Distributed execution in worker processes
- `PlutoRunner.jl` concepts - Cell execution model (but reimplemented for our architecture)

### 4. Wasm-Powered Interactivity
- Compile to interactive GitHub Pages via Therapy.jl/WasmTarget pipeline
- No server needed for static notebook viewing
- Full interactivity for computational notebooks when server available

### 5. Pure Julia + Tailwind
- Zero JavaScript framework code
- All UI logic compiles to Wasm via WasmTarget.jl
- Tailwind CSS for styling (consistent with Therapy.jl)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Sessions.jl                               │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   SessionsApp Component                    │  │
│  │  (Top-level Therapy.jl island - the full IDE)             │  │
│  │                                                            │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │  │
│  │  │ FileExplorer│  │  EditorPane │  │    Terminal     │   │  │
│  │  │  Component  │  │  Component  │  │   Component     │   │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────┘   │  │
│  │                                                            │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │              NotebookSession Component               │  │  │
│  │  │  ┌──────────┐ ┌──────────┐ ┌──────────┐            │  │  │
│  │  │  │  Cell 1  │ │  Cell 2  │ │  Cell 3  │  ...       │  │  │
│  │  │  │(reactive)│ │(reactive)│ │(reactive)│            │  │  │
│  │  │  └──────────┘ └──────────┘ └──────────┘            │  │  │
│  │  │                                                     │  │  │
│  │  │  Uses: ExpressionExplorer.jl for dependency graph   │  │  │
│  │  │  Uses: Malt.jl for isolated execution               │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    SessionsServer                          │  │
│  │  - WebSocket server for terminal/filesystem access         │  │
│  │  - Cell execution via Malt.jl workers                      │  │
│  │  - File watching for live reload                           │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Therapy.jl                                │
│  - Reactivity (signals, effects, memos)                          │
│  - Components and islands                                        │
│  - SSR and hydration                                             │
│  - Wasm compilation pipeline                                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       WasmTarget.jl                              │
│  - Julia → WebAssembly compilation                               │
│  - WasmGC structs/arrays                                         │
│  - Signal handler compilation                                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component Breakdown

### 1. SessionsApp (Top-Level Island)

The root component - a full IDE that can be:
- Mounted as a full-page app
- Embedded as a component in a larger Therapy.jl application

```julia
SessionsApp = island(:SessionsApp) do
    # Global state
    active_file, set_active_file = create_signal(nothing)
    open_tabs, set_open_tabs = create_signal(Tab[])
    terminal_visible, set_terminal_visible = create_signal(true)
    sidebar_visible, set_sidebar_visible = create_signal(true)

    Div(:class => "sessions-app h-screen flex flex-col",
        # Top bar (menus, tabs)
        TopBar(open_tabs, active_file),

        Div(:class => "flex-1 flex",
            # Sidebar (file explorer, extensions)
            Show(sidebar_visible,
                Sidebar(active_file, set_active_file)
            ),

            # Main editor area
            EditorArea(active_file, open_tabs),
        ),

        # Bottom panel (terminal, problems, output)
        Show(terminal_visible,
            BottomPanel()
        )
    )
end
```

### 2. FileExplorer Component

VSCode-like file tree with:
- Folder expand/collapse
- File icons by type
- Context menus (new file, rename, delete)
- Drag and drop

**Server Connection**: WebSocket to SessionsServer for filesystem operations.

```julia
FileExplorer = component(:FileExplorer) do props
    root_path = get_prop(props, :root_path, ".")
    files, set_files = create_signal(FileNode[])
    expanded, set_expanded = create_signal(Set{String}())

    # Fetch file tree from server
    on_mount() do
        fetch_files(root_path, set_files)
    end

    Div(:class => "file-explorer",
        FileTree(files, expanded, set_expanded)
    )
end
```

### 3. NotebookSession Component

The Pluto-like notebook experience:
- Reactive cells with dependency tracking
- Live execution with Malt.jl workers
- Rich output rendering (plots, tables, HTML)

```julia
NotebookSession = island(:NotebookSession) do
    cells, set_cells = create_signal(Cell[])
    cell_outputs, set_cell_outputs = create_signal(Dict{UUID, Any}())
    dependency_graph, set_dependency_graph = create_signal(DependencyGraph())

    # When a cell changes, use ExpressionExplorer to update graph
    create_effect() do
        graph = build_dependency_graph(cells())
        set_dependency_graph(graph)
    end

    Div(:class => "notebook-session",
        For(cells()) do cell
            CellComponent(
                cell,
                cell_outputs,
                :on_run => () -> execute_cell(cell, dependency_graph())
            )
        end,
        AddCellButton(set_cells)
    )
end
```

### 4. Terminal Component

Browser-based terminal connected to local machine:
- PTY allocation via server
- xterm.js-like rendering (but in pure Julia/Wasm)
- Full ANSI escape sequence support

```julia
Terminal = island(:Terminal) do
    lines, set_lines = create_signal(TerminalLine[])
    cursor_pos, set_cursor_pos = create_signal((0, 0))

    # WebSocket connection to PTY on server
    on_mount() do
        connect_terminal_ws(set_lines, set_cursor_pos)
    end

    Div(:class => "terminal bg-gray-900 text-green-400 font-mono",
        For(lines()) do line
            TerminalLineComponent(line)
        end,
        TerminalInput(:on_key => send_key_to_server)
    )
end
```

### 5. Cell Component

Individual notebook cell:

```julia
Cell = component(:Cell) do props
    cell_id = get_prop(props, :id)
    code, set_code = create_signal(get_prop(props, :initial_code, ""))
    output = get_prop(props, :output)
    is_running, set_is_running = create_signal(false)

    Div(:class => "cell border rounded-lg mb-2",
        # Cell toolbar
        CellToolbar(cell_id, is_running),

        # Code editor
        CodeEditor(code, set_code),

        # Output area
        Show(() -> output() !== nothing,
            OutputRenderer(output)
        )
    )
end
```

---

## Pluto Packages to Leverage

### ExpressionExplorer.jl
**Purpose**: Static analysis of Julia expressions to determine:
- What symbols an expression references
- What symbols an expression defines
- Function signatures and dependencies

**Use in Sessions**: Build cell dependency graph without executing code.

```julia
using ExpressionExplorer

expr = :(x = y + 1)
result = ExpressionExplorer.compute_symbolreferences(expr)
# result.references = [:y]
# result.definitions = [:x]
```

### Malt.jl
**Purpose**: Run Julia code in isolated worker processes.

**Use in Sessions**: Execute notebook cells safely:
- Isolated from main process
- Can be interrupted/killed
- Memory limits
- Capture stdout/stderr

```julia
using Malt

worker = Malt.Worker()
result = Malt.remote_eval(worker, :(1 + 1))
# result = 2
```

### PlutoDependencyExplorer.jl
**Purpose**: Topological ordering of cells based on dependencies.

**Use in Sessions**: Determine execution order when cell changes.

### Other Potentially Useful Packages
- `FuzzyCompletions.jl` - Autocomplete suggestions
- `PlutoLinks.jl` - Inter-notebook references (maybe)
- `AbstractPlutoDingetjes.jl` - Rich display protocol (study, may reimplement)

---

## Deployment Modes

### 1. Full Interactive Mode (with Server)

```
┌─────────────┐         ┌─────────────────────┐
│   Browser   │ ◄─────► │   SessionsServer    │
│  (Wasm UI)  │   WS    │  (Julia process)    │
└─────────────┘         │                     │
                        │  - Filesystem ops   │
                        │  - PTY for terminal │
                        │  - Cell execution   │
                        │  - File watching    │
                        └─────────────────────┘
```

Features:
- Full file explorer
- Working terminal
- Live cell execution
- File editing and saving

### 2. Static Notebook Mode (GitHub Pages)

```
┌─────────────────────────────────────────┐
│              Static HTML                 │
│  ┌─────────────────────────────────┐    │
│  │        NotebookViewer           │    │
│  │   (Wasm - view only, or with    │    │
│  │    pre-computed outputs)        │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

Features:
- View notebook with rendered outputs
- Navigate cells
- Copy code
- Interactive widgets (if pre-compiled to Wasm)
- No execution (outputs baked in at build time)

### 3. Embedded Component Mode

```julia
# In any Therapy.jl app
MyApp = island(:MyApp) do
    Div(
        Header("My Data Science App"),

        # Embed a notebook as just another component
        NotebookSession(:notebook_path => "analysis.jl"),

        Footer("Powered by Sessions.jl")
    )
end
```

---

## UI/UX Design Principles

### VSCode Inspiration
- **Activity Bar**: Left sidebar with icons (files, search, extensions)
- **Side Bar**: Contextual content (file tree, search results)
- **Editor Groups**: Split panes, tabs
- **Panel**: Bottom area (terminal, problems, output)
- **Status Bar**: Bottom info bar
- **Command Palette**: Ctrl+Shift+P quick actions

### Pluto Inspiration
- **Cell-based editing**: Each cell is independent
- **Reactive execution**: Changes propagate automatically
- **Rich outputs**: Plots, tables, HTML inline
- **Live docs**: Hover for documentation
- **Dependency visualization**: See what depends on what

### Sessions Unique Features
- **Unified environment**: Files + notebooks + terminal in one
- **Project-aware**: Understand Julia project structure
- **Git integration**: See changed files, commit, push
- **Package management**: Add/remove packages visually

---

## Technical Challenges & Solutions

### Challenge 1: Browser Terminal Without Node.js
**Problem**: xterm.js is JavaScript. We want pure Julia.

**Solution**: Build terminal renderer as Therapy.jl component:
- Parse ANSI escape sequences in Julia
- Render to DOM via signals
- Handle input events via Wasm handlers
- WebSocket to server for PTY I/O

### Challenge 2: Code Editor in Pure Julia
**Problem**: Monaco/CodeMirror are JavaScript.

**Solution**: Build minimal editor or strategic JS interop:
- Option A: Simple textarea with syntax highlighting (start here)
- Option B: Build editor component in Julia (complex)
- Option C: Use `JSValue` externref to wrap existing editor (pragmatic)

**Recommended**: Start with Option A, consider Option C for production.

### Challenge 3: Cell Execution Model
**Problem**: Pluto's execution model is tightly coupled.

**Solution**: Reimplement using the principles:
1. Use ExpressionExplorer for static analysis
2. Use Malt.jl for isolated execution
3. Build our own topological sort for execution order
4. Store outputs as signals for reactivity

### Challenge 4: Large Notebook Performance
**Problem**: Many cells = many signals = potential performance issues.

**Solution**:
- Virtualized rendering (only render visible cells)
- Lazy signal creation (cells not in view don't have live signals)
- Efficient diffing for cell outputs

### Challenge 5: Filesystem Access from Browser
**Problem**: Browsers can't access filesystem directly.

**Solution**: WebSocket API to SessionsServer:
```julia
# Server provides filesystem operations
@ws_handler "/fs/list" function(path)
    readdir(path)
end

@ws_handler "/fs/read" function(path)
    read(path, String)
end

@ws_handler "/fs/write" function(path, content)
    write(path, content)
end
```

---

## Development Phases

### Phase 1: Foundation
- [ ] Basic SessionsApp component structure
- [ ] Simple file explorer (hardcoded tree)
- [ ] Basic notebook with static cells
- [ ] WebSocket server skeleton

### Phase 2: Core Notebook
- [ ] Editable cells with CodeEditor
- [ ] Cell execution via Malt.jl
- [ ] ExpressionExplorer integration
- [ ] Dependency graph and reactive execution
- [ ] Basic output rendering (text, numbers)

### Phase 3: File System
- [ ] WebSocket filesystem API
- [ ] Live file explorer
- [ ] File editing and saving
- [ ] Project detection (Project.toml)

### Phase 4: Terminal
- [ ] PTY allocation on server
- [ ] Terminal component with ANSI parsing
- [ ] Input handling
- [ ] Multiple terminal sessions

### Phase 5: Rich Features
- [ ] Syntax highlighting
- [ ] Autocomplete (FuzzyCompletions.jl)
- [ ] Plot rendering
- [ ] Table rendering
- [ ] HTML output

### Phase 6: Polish
- [ ] Command palette
- [ ] Keyboard shortcuts
- [ ] Themes (light/dark)
- [ ] Settings persistence
- [ ] Git integration

### Phase 7: Static Export
- [ ] Build notebooks to static HTML
- [ ] GitHub Pages deployment
- [ ] Baked-in outputs
- [ ] Interactive widgets via Wasm

---

## Integration Points with Therapy.jl/WasmTarget.jl

### Therapy.jl Enhancements Needed
1. **For component** - Efficient list rendering (currently planned)
2. **Context API** - Share state across component tree
3. **Larger islands** - Sessions is complex, may stress compilation

### WasmTarget.jl Enhancements Needed
1. **Nested conditionals fix** - Currently blocked (affects complex handlers)
2. **String operations** - More string manipulation for editor
3. **Larger function support** - Sessions handlers may be complex

### Feedback Loop
Sessions.jl development will reveal what Therapy.jl and WasmTarget.jl need. This is intentional - Sessions is the "customer" driving requirements.

---

## Success Metrics

1. **Can build a simple notebook** that executes Julia code reactively
2. **Can navigate files** in a project
3. **Can use terminal** to run Julia REPL
4. **Can export to GitHub Pages** as static HTML
5. **Can embed in Therapy.jl app** as a component
6. **Feels like VSCode + Pluto** - familiar, intuitive

---

## Non-Goals (For Now)

- Full VSCode extension compatibility
- Multi-user collaboration (future)
- Cloud execution (future)
- Non-Julia languages (future)
- Mobile support (future)

---

## Conclusion

Sessions.jl is an ambitious project that leverages the full TherapeuticJulia stack. By treating the IDE/notebook as "just a component," we gain:

1. **Composability**: Embed notebooks anywhere
2. **Consistency**: Same reactivity model as the rest of the app
3. **Simplicity**: One architecture, not two
4. **Portability**: Compile to Wasm for static hosting

The key insight is that we're not building a Pluto clone - we're building a Therapy.jl component that provides notebook/IDE functionality. Pluto's standalone packages help us avoid reinventing the wheel for complex parts (expression analysis, distributed execution), while we own the UI and integration.
