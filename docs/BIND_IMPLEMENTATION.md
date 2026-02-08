# @bind Implementation Research

This document analyzes Pluto.jl's `@bind` mechanism and outlines the implementation plan for Sessions.jl.

## Overview

Pluto's `@bind` macro creates a bidirectional binding between browser widgets and Julia variables. When combined with Pluto's reactivity system, user interactions with widgets automatically trigger downstream cell re-execution.

```julia
@bind x Slider(1:10)  # Creates bound variable x
y = x * 2             # Automatically re-runs when x changes
```

---

## Pluto.jl Architecture

### 1. The @bind Macro (PlutoRunner)

**Location:** `src/runner/PlutoRunner/src/bonds.jl`

The macro transforms `@bind x widget` into:

```julia
begin
    local el = widget
    global x = initial_value(el)  # Set default (usually `missing`)
    PlutoRunner.create_bond(el, :x, cell_id)
end
```

**Key data structures:**
```julia
struct Bond
    element::Any      # The HTML-showable widget
    defines::Symbol   # Variable name being bound (:x)
    unique_id::String # Forces re-render on re-execution
end

# Registry tracking
cell_registered_bond_names::Dict{UUID, Set{Symbol}}  # Bonds per cell
registered_bond_elements::Dict{Symbol, Any}          # Symbol → widget
```

### 2. HTML Rendering

When `Bond` is displayed as HTML, it wraps the widget in a `<bond>` tag:

```html
<bond def="x">
    <input type="range" min="1" max="10" value="5">
</bond>
```

The `def` attribute tells the frontend which Julia variable to update.

### 3. Frontend Bond Detection (JavaScript)

**Location:** `frontend/common/Bond.js`

The frontend:
1. Queries for all `<bond>` elements in cell output
2. Finds the input element inside each bond
3. Attaches appropriate event listeners (`input`, `change`, `click`)
4. Extracts values using type-specific logic

```javascript
// Event detection
function eventof(input_el) {
    if (input_el.tagName === "BUTTON") return "click"
    if (input_el.type === "file") return "change"
    return "input"
}

// Value extraction
function get_input_value(input) {
    if (input.type === "range" || input.type === "number")
        return input.valueAsNumber
    if (input.type === "checkbox")
        return input.checked
    // ... etc
    return input.value
}
```

### 4. Server Communication

When a bond value changes:

```javascript
// Frontend sends update
pluto_actions.set_bond(name, value)

// This triggers notebook patch
notebook.bonds[name] = { value: value }
```

The server receives the patch and processes it in `RunBonds.jl`.

### 5. Reactive Execution (RunBonds.jl)

**Location:** `src/evaluation/RunBonds.jl`

When bond values change:

1. **Filter bonds**: Only process bonds for assigned variables
2. **Transform values**: Apply `transform_value()` for type conversion (e.g., JS number → Julia Int)
3. **Skip unchanged**: If value matches current workspace, skip re-execution
4. **Find dependents**: Use `PlutoDependencyExplorer.where_referenced()` to find cells using the bound variable
5. **Execute**: Run dependent cells in topological order

**Key function:**
```julia
function set_bond_values_reactive(session, notebook, bound_sym_names)
    # 1. Get new values from notebook.bonds
    # 2. Compare with workspace values via transform_bond_value
    # 3. Find cells that reference these symbols
    # 4. Execute affected cells in order
end
```

### 6. AbstractPlutoDingetjes Interface

**Package:** `AbstractPlutoDingetjes.jl`

Widgets implement these methods to customize bond behavior:

```julia
# Default value before any interaction
Bonds.initial_value(widget) → Any  # Default: missing

# Transform JS value to Julia type
Bonds.transform_value(widget, js_value) → Any  # Default: identity

# Enumerate possible values (for PlutoSliderServer)
Bonds.possible_values(widget) → Iterable  # Default: NotGiven()

# Validate value from browser (security)
Bonds.validate_value(widget, value) → Bool  # Default: false
```

**Example: Slider implementation:**
```julia
struct Slider
    values::Vector
    default::Any
end

Bonds.initial_value(s::Slider) = s.default
Bonds.possible_values(s::Slider) = 1:length(s.values)
Bonds.transform_value(s::Slider, idx) = s.values[idx]
Bonds.validate_value(s::Slider, idx) = 1 ≤ idx ≤ length(s.values)
```

### 7. Notebook State

**Location:** `src/notebook/Notebook.jl`

```julia
mutable struct BondValue
    value::Any
end

struct Notebook
    # ... other fields
    bonds::Dict{Symbol, BondValue}  # Current bond values
end
```

---

## Sessions.jl Implementation Plan

### Phase 1: Core Infrastructure

#### 1.1 Bond Type and @bind Macro

Create `src/server/bonds.jl`:

```julia
# Bond struct for Sessions.jl
struct SessionsBond
    element::Any      # HTML-showable widget
    defines::Symbol   # Variable name
    cell_id::UUID     # Owning cell
end

# Registry
const CELL_BOND_NAMES = Dict{UUID, Set{Symbol}}()
const BOND_ELEMENTS = Dict{Symbol, Any}()

# Macro implementation
macro bind(def, element)
    @assert def isa Symbol "@bind requires a symbol"
    quote
        local el = $(esc(element))
        global $(esc(def)) = Sessions.initial_value(el)
        Sessions.create_bond(el, $(Meta.quot(def)), current_cell_id())
    end
end

function create_bond(element, defines::Symbol, cell_id::UUID)
    # Register bond
    if !haskey(CELL_BOND_NAMES, cell_id)
        CELL_BOND_NAMES[cell_id] = Set{Symbol}()
    end
    push!(CELL_BOND_NAMES[cell_id], defines)
    BOND_ELEMENTS[defines] = element

    # Return bond for display
    SessionsBond(element, defines, cell_id)
end
```

#### 1.2 HTML Rendering

```julia
function Base.show(io::IO, ::MIME"text/html", bond::SessionsBond)
    print(io, """<bond def="$(bond.defines)">""")
    show(io, MIME"text/html"(), bond.element)
    print(io, "</bond>")
end
```

#### 1.3 Bond Interface Protocol

```julia
# Default implementations (override in widgets)
initial_value(x) = missing
transform_value(x, val) = val
possible_values(x) = nothing
validate_value(x, val) = true
```

### Phase 2: Frontend Integration

#### 2.1 JavaScript Bond Handler

Add to `sessions_script()` (minimal bridge allowed by CLAUDE.md):

```javascript
// Bond detection and event handling
function setupBonds(container, onBondChange) {
    const bonds = container.querySelectorAll('bond')

    bonds.forEach(bond => {
        const name = bond.getAttribute('def')
        const input = bond.querySelector('input, select, button')
        if (!input) return

        const eventType = getEventType(input)
        input.addEventListener(eventType, () => {
            const value = extractValue(input)
            onBondChange(name, value)
        })
    })
}

function getEventType(el) {
    if (el.tagName === 'BUTTON') return 'click'
    if (el.type === 'file') return 'change'
    return 'input'
}

function extractValue(el) {
    if (el.type === 'range' || el.type === 'number') return el.valueAsNumber
    if (el.type === 'checkbox') return el.checked
    return el.value
}
```

#### 2.2 WebSocket Channel

Add channel for bond updates using Therapy.jl pattern:

```julia
# In Channels.jl
add_channel!("set_bond") do msg
    notebook = get_notebook(msg["notebook_id"])
    name = Symbol(msg["name"])
    value = msg["value"]

    # Store bond value
    notebook.bonds[name] = BondValue(value)

    # Transform value
    widget = get(BOND_ELEMENTS, name, nothing)
    julia_value = transform_value(widget, value)

    # Update workspace and run dependents
    set_bond_and_run!(notebook, name, julia_value)
end
```

### Phase 3: Reactive Integration

#### 3.1 Modify Notebook Struct

Update `src/Engine/Notebook.jl`:

```julia
mutable struct Notebook
    # Existing fields...
    bonds::Dict{Symbol, BondValue}  # Add this
end
```

#### 3.2 Bond-Aware Execution

Update `src/Engine/Reactivity.jl`:

```julia
function set_bond_and_run!(notebook::Notebook, name::Symbol, value)
    # 1. Set variable in workspace
    set_workspace_variable!(notebook.worker, name, value)

    # 2. Find cells that reference this variable
    affected_cells = find_referencing_cells(notebook, name)

    # 3. Execute in topological order
    for cell in topological_sort(affected_cells)
        execute_cell!(notebook, cell)
    end
end
```

### Phase 4: Widget Implementation (SESSIONS-012)

Create `src/components/islands/widgets/`:

```julia
# Slider.jl
struct Slider{T}
    range::AbstractRange{T}
    default::T
end

Slider(range::AbstractRange) = Slider(range, first(range))

function Base.show(io::IO, ::MIME"text/html", s::Slider)
    print(io, """
    <input type="range"
           min="$(first(s.range))"
           max="$(last(s.range))"
           step="$(step(s.range))"
           value="$(s.default)">
    """)
end

Sessions.initial_value(s::Slider) = s.default
Sessions.transform_value(s::Slider{<:Integer}, v) = round(Int, v)
```

---

## Key Differences from Pluto.jl

| Aspect | Pluto.jl | Sessions.jl |
|--------|----------|-------------|
| Frontend | Custom React app | Therapy.jl SSR + Islands |
| Event transport | Custom WebSocket protocol | Therapy.jl channels |
| HTML rendering | Custom bond tag | Same `<bond>` tag pattern |
| JavaScript | Full custom implementation | Minimal bridge in sessions_script() |
| Reactivity | PlutoDependencyExplorer | Same (already integrated) |

## File Structure

```
Sessions.jl/
├── src/
│   ├── server/
│   │   ├── server.jl        # Add @bind macro
│   │   └── bonds.jl         # NEW: Bond infrastructure
│   ├── components/
│   │   └── islands/
│   │       └── widgets/     # NEW: Widget components
│   │           ├── Slider.jl
│   │           ├── TextField.jl
│   │           └── CheckBox.jl
│   └── Engine/
│       ├── Notebook.jl      # Add bonds field
│       └── Reactivity.jl    # Add set_bond_and_run!
```

---

## Implementation Order

1. **SESSIONS-011: @bind macro** (depends on this research)
   - Add `Bond` struct and `@bind` macro to `src/server/server.jl`
   - Add HTML rendering with `<bond>` tags
   - Add WebSocket channel for `set_bond`
   - Add JavaScript bond handler to `sessions_script()`
   - Integrate with reactivity system

2. **SESSIONS-012: Basic widgets** (depends on SESSIONS-011)
   - Implement `Slider`, `TextField`, `CheckBox`
   - Ensure they work with `@bind`

---

## References

- [Pluto.jl Repository](https://github.com/fonsp/Pluto.jl)
- [PlutoUI.jl Repository](https://github.com/JuliaPluto/PlutoUI.jl)
- [AbstractPlutoDingetjes.jl](https://github.com/JuliaPluto/AbstractPlutoDingetjes.jl)
- [Pluto Wiki: Writing and Running Code](https://github.com/fonsp/Pluto.jl/wiki/%E2%9A%A1-Writing-and-running-code)
