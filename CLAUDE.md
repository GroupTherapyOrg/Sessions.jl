# Sessions.jl Developer Guide

A reactive notebook IDE built with Therapy.jl + Suite.jl, with full Pluto.jl compatibility.

## Architecture

Sessions.jl has 5 layers. Code changes should respect layer boundaries:

1. **Engine** (`src/Engine/`) -- Core notebook logic, no UI. Cell, Notebook, Reactivity, Workspace, Worker, FileFormat.
2. **Bonds** (`src/components/islands/widgets/`) -- @bind protocol. Slider, TextField, CheckBox, Select, NumberField.
3. **Server** (`src/Server/`) -- HTTP + WebSocket. App.jl, Channels.jl, Signals.jl, server.jl.
4. **IDE Components** (`src/IDE/`) -- Suite.jl UI components. All use `import Suite` and qualified calls.
5. **IDE Shell** (`src/IDE/Layout.jl`, `src/app.jl`) -- Standalone application that assembles components.

## Critical Rules

### Rule 1: Suite.jl for ALL UI

All UI must use Suite.jl components via qualified calls:

```julia
import Suite

Suite.Card(:class => "...",
    Suite.CardContent(
        Suite.Badge(:variant => "success", "Running")
    )
)
```

Never use raw HTML divs for UI structure. See the component mapping in `sessions-guardrails.md`.

### Rule 2: Therapy.jl Patterns

| Feature | Pattern |
|---------|---------|
| Reactive text | `Span(Symbol("data-server-signal") => "cell_runtime_id")` |
| Reactive HTML | `Div(Symbol("data-signal-html") => "cell_output_id")` |
| Reactive CSS | `Div(Symbol("data-signal-match") => "state:VALUE:class")` |
| Click handlers | `:on_click => "handler()"` (NOT `:onclick`) |
| Channels | `TherapyWS.sendMessage(type, payload)` |

### Rule 3: Design System Tokens

- **Accent**: `accent-*` classes (Julia green `#389826`)
- **Secondary**: `accent-secondary` (blue `#4063d8`)
- **Neutrals**: `warm-*` classes only (never stone/neutral/gray/bg-white)
- **Cell accents**: green=output, purple=#9558b2=markdown, red=#cb3c33=error, warm=idle
- **Fonts**: EB Garamond (markdown), JetBrains Mono (code)

### Rule 4: Component Names

Suite.jl components have NO prefix:

```julia
Suite.Card()       # NOT Suite.SuiteCard()
Suite.Badge()      # NOT Suite.SuiteBadge()
Suite.Alert()      # NOT Suite.SuiteAlert()
```

Verify with: `grep "^function" Suite.jl/src/components/{ComponentName}.jl`

## Key Data Structures

### Cell

```julia
mutable struct Cell
    id::UUID
    code::String
    output::Union{Nothing, CellOutput}
    state::CellState           # CELL_IDLE, CELL_RUNNING, CELL_ERROR, CELL_QUEUED, CELL_STALE
    cell_type::Symbol          # :code or :markdown
    folded::Bool
    runtime_ms::Union{Nothing, Float64}
    last_run_at::Union{Nothing, Float64}
    definitions::Set{Symbol}   # Variables defined by this cell
    references::Set{Symbol}    # Variables referenced by this cell
end
```

### CellOutput

Positional constructor only:
```julia
CellOutput(value, mime, html, logs, error_logs)
CellOutput()  # = CellOutput(nothing, "text/plain", "", String[], String[])
```

### FileEntry

Positional constructor only:
```julia
FileEntry(name, is_directory, size, modified, path)
```

### NotebookOptions

```julia
NotebookOptions(;
    show_header=true, show_toolbar=true, show_add_cell=true,
    editable=true, runnable=true, show_output=true,
    max_height=nothing, theme="default"
)
```

### IDENotebookTabs

Expects `Vector{Dict}` with string keys:
```julia
notebooks = [Dict("id" => uuid, "title" => "file.jl", "modified" => false)]
IDENotebookTabs(notebooks; active_id=uuid)
```

## Testing

```bash
# Main test suite (1097 tests)
julia +1.12 --project=. test/runtests.jl

# Benchmarks (16 benchmarks)
julia +1.12 --project=. test/benchmarks.jl

# Pluto compatibility (651 tests, 5 real notebooks)
julia +1.12 --project=. test/pluto_smoke_test.jl
```

Always run `test/runtests.jl` after code changes. Engine tests must never break.

## WebSocket Protocol

**Signals** (server -> client, per-cell):
- `cell_state_{id}` -- CellState enum value
- `cell_output_{id}` -- Rendered HTML string
- `cell_runtime_{id}` -- Execution time text

**Channels** (client -> server):
- `execute` -- `{notebook_id, cell_id, code}`
- `add_cell` / `delete_cell` -- `{notebook_id, cell_id}`
- `move_cell` -- `{notebook_id, cell_id, direction}`
- `save_notebook` -- `{notebook_id}`
- `set_bond` -- `{notebook_id, name, value}`
- `toggle_markdown` -- `{notebook_id, cell_id, mode}`

## Commit Convention

```
SESSIONS-XXXX: Description
```

Code commits go in the Sessions.jl repo. PRD/progress updates go in the parent GroupTherapyOrg repo.

## Known Gotchas

- `render_markdown_html` strips trailing whitespace before `Markdown.parse()` -- single-line markdown headings don't parse as headings
- Script functions (e.g., `cell_toolbar_script()`) return raw JS strings, NOT wrapped in `<script>` tags
- `IDEFileBrowser` returns a `Fragment`, not a `VNode`
- `Notebook()` constructor sets `created_at = time()`, not `nothing`
- `export_to_html` uses `basename(notebook.path)` for the title, not `notebook.title`
- String indexing in Julia is byte-based, not character-based -- use `nextind`/`prevind` for Unicode
