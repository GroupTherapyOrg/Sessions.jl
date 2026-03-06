# Interactive bindings — @bind macro + widget types
# Mirrors PlutoUI's Builtins.jl widget API, adapted for TUI rendering.
# Widget structs/constructors are 1:1 with PlutoUI; HTML show methods are replaced
# by TUI rendering in output_widget.jl.

# ── Bonds interface (mirrors AbstractPlutoDingetjes.Bonds) ──────────

"""Abstract type for all interactive widgets (like PlutoUI's widget protocol)."""
abstract type AbstractWidget end

"""Get the initial/default value for a widget (AbstractPlutoDingetjes.Bonds.initial_value)."""
initial_value(::AbstractWidget) = missing

"""Get possible values for a widget (AbstractPlutoDingetjes.Bonds.possible_values)."""
possible_values(::AbstractWidget) = nothing

"""Validate a value for a widget (AbstractPlutoDingetjes.Bonds.validate_value)."""
validate_value(::AbstractWidget, ::Any) = false

# ── Helper functions (from PlutoUI Builtins.jl) ─────────────────────

"""Return the element of `range` closest to `x` (PlutoUI.closest)."""
function closest(range::AbstractRange, x::Real)
    rmin = minimum(range)
    rmax = maximum(range)
    if x <= rmin
        rmin
    elseif x >= rmax
        rmax
    else
        rstep = step(range)
        int_val = (x - rmin) / rstep
        range[round(Int, int_val) + 1]
    end
end

function closest(values::AbstractVector{<:Real}, x::Real)
    mapfoldl(y -> (abs(y - x), y), ((a1,a2),(b1,b2)) -> a1 > b1 ? (b1,b2) : (a1,a2), values)[2]
end

closest(values::AbstractVector, x) = first(values)

"""Downsample a vector to at most `max_steps` elements (PlutoUI.downsample)."""
function downsample(x::AbstractVector{T}, max_steps::Integer) where T
    if max_steps >= length(x)
        x
    else
        T[x[round(Int, i)] for i in range(firstindex(x), stop=lastindex(x), length=max_steps)]
    end
end

# ── Slider (from PlutoUI.Slider) ────────────────────────────────────

"""A slider over the given values.

## Examples
`@bind x Slider(1:10)`

`@bind x Slider(0.00 : 0.01 : 0.30)`

`@bind x Slider(1:10; default=8, show_value=true)`

`@bind x Slider(["hello", "world!"])`
"""
struct Slider{T <: Any} <: AbstractWidget
    values::AbstractVector{T}
    default::T
    show_value::Bool
end

function Slider(values::AbstractVector{T}; default=missing, show_value::Bool=true, max_steps::Integer=1_000) where T
    new_values = downsample(values, max_steps)
    Slider(new_values, (default === missing) ? first(new_values) : let
        d = default
        d ∈ new_values ? convert(T, d) : closest(new_values, d)
    end, show_value)
end

# Convenience: Slider(1:10) — range gets collected
Slider(range::AbstractRange; kwargs...) = Slider(collect(range); kwargs...)

initial_value(s::Slider) = s.default
possible_values(s::Slider) = s.values
validate_value(s::Slider{T}, val) where T = val isa T && val ∈ s.values

"""Index of `val` in slider's values (1-based)."""
function _slider_index(s::Slider, val)
    idx = findfirst(==(val), s.values)
    idx === nothing ? 1 : idx
end

# ── NumberField (from PlutoUI.NumberField) ───────────────────────────

"""A number input with min/max bounds.

## Examples
`@bind x NumberField(1:10)`

`@bind x NumberField(0.00 : 0.01 : 0.30)`

`@bind x NumberField(1:10; default=8)`
"""
struct NumberField <: AbstractWidget
    range::AbstractRange
    default::Number
end

function NumberField(range::AbstractRange{T}; default=missing) where T
    NumberField(range, (default === missing) ? first(range) : let
        d = default
        d ∈ range ? convert(T, d) : closest(range, d)
    end)
end

initial_value(nf::NumberField) = nf.default
possible_values(nf::NumberField) = nf.range
function validate_value(nf::NumberField, val)
    val isa Real && (minimum(nf.range) - 0.0001 <= val <= maximum(nf.range) + 0.0001)
end

# ── Button (from PlutoUI.LabelButton) ───────────────────────────────

"""A button that sends back the same value every time it is pressed.

## Examples
`@bind go Button("Go!")`
"""
struct Button <: AbstractWidget
    label::AbstractString
end

Button() = Button("Click")

initial_value(b::Button) = b.label
possible_values(b::Button) = [b.label]
validate_value(b::Button, val) = val == b.label

# ── CounterButton (from PlutoUI.CounterButton) ──────────────────────

"""A button that counts how many times it has been pressed.

## Examples
`@bind clicks CounterButton("Go!")`
"""
struct CounterButton <: AbstractWidget
    label::AbstractString
end

CounterButton() = CounterButton("Click")

initial_value(::CounterButton) = 0
possible_values(::CounterButton) = nothing  # infinite
validate_value(::CounterButton, val) = val isa Integer && val >= 0

# ── CheckBox (from PlutoUI.CheckBox) ────────────────────────────────

"""A checkbox to choose a Boolean value true/false.

## Examples
`@bind programming_is_fun CheckBox()`

`@bind julia_is_fun CheckBox(default=true)`
"""
struct CheckBox <: AbstractWidget
    default::Bool
end

CheckBox(; default::Bool=false) = CheckBox(default)

initial_value(b::CheckBox) = b.default
possible_values(::CheckBox) = [false, true]
validate_value(::CheckBox, val) = val isa Bool

# ── TextField (from PlutoUI.TextField) ──────────────────────────────

"""A text input — the user can type text, returned as String via @bind.

## Examples
`@bind author TextField()`

`@bind poem TextField(; default="Hello")`
"""
struct TextField <: AbstractWidget
    default::AbstractString
end

TextField(; default::AbstractString="") = TextField(default)

initial_value(t::TextField) = t.default
possible_values(::TextField) = nothing  # infinite
validate_value(::TextField, val) = val isa AbstractString

# ── Select (from PlutoUI.Select) ────────────────────────────────────

"""A dropdown select menu.

## Examples
`@bind veg Select(["potato", "carrot"])`

`@bind f Select([sin => "sine", cos => "cosine"])`
"""
struct Select <: AbstractWidget
    options::AbstractVector{Pair}
    default::Union{Missing, Any}
end

Select(options::AbstractVector; default=missing) = Select([o => o for o in options], default)
Select(options::AbstractVector{<:Pair}; default=missing) = Select(convert(Vector{Pair}, collect(options)), default)

function initial_value(s::Select)
    ismissing(s.default) ? first(s.options).first : s.default
end
possible_values(s::Select) = [o.first for o in s.options]
validate_value(s::Select, val) = any(o -> o.first == val, s.options)

# ── Bond (mirrors PlutoRunner.Bond) ─────────────────────────────────

"""A bond connecting an interactive widget to a Julia variable.
Created by the @bind macro. When the widget's value changes in the TUI,
the bound variable is updated and dependent cells re-execute.

Mirrors Pluto's Bond struct — element is the widget, defines is the variable name.
"""
struct Bond
    element::Any  # Any widget (AbstractWidget or custom types)
    defines::Symbol
end

function Base.show(io::IO, ::MIME"text/plain", b::Bond)
    print(io, "Bond(:$(b.defines) ↔ $(typeof(b.element)))")
end

function Base.show(io::IO, b::Bond)
    print(io, "Bond(:$(b.defines) ↔ $(typeof(b.element)))")
end

# ── Bond Registry (mirrors PlutoRunner.registered_bond_elements) ────

"""Registry of active bonds: variable_name => (widget, current_value, cell_id).
Equivalent to Pluto's `registered_bond_elements` + value tracking."""
const _BOND_REGISTRY = Dict{Symbol, Tuple{Any, Any, UUID}}()

"""Per-cell bond names — tracks which cell defined which bonds.
Equivalent to Pluto's `cell_registered_bond_names`."""
const _CELL_BOND_NAMES = Dict{UUID, Set{Symbol}}()

"""Cell ID currently being executed (set before each cell eval)."""
const _EXECUTING_CELL_ID = Ref(UUID(0))

"""Register or update a bond in the registry (mirrors PlutoRunner.create_bond)."""
function _register_bond!(name::Symbol, widget, value, cell_id::UUID)
    _BOND_REGISTRY[name] = (widget, value, cell_id)
    # Track which cell owns this bond
    if !haskey(_CELL_BOND_NAMES, cell_id)
        _CELL_BOND_NAMES[cell_id] = Set{Symbol}()
    end
    push!(_CELL_BOND_NAMES[cell_id], name)
end

"""Update a bond's value (called when user interacts with widget in TUI).
Equivalent to Pluto's set_bond_values_reactive (the value assignment part)."""
function set_bond_value!(name::Symbol, new_value)
    haskey(_BOND_REGISTRY, name) || return
    widget, _, cell_id = _BOND_REGISTRY[name]
    _BOND_REGISTRY[name] = (widget, new_value, cell_id)
end

"""Get the cell that defined a bond."""
function _bond_cell_id(name::Symbol)::Union{UUID, Nothing}
    haskey(_BOND_REGISTRY, name) || return nothing
    _BOND_REGISTRY[name][3]
end

"""Get bond names for a cell."""
function get_bond_names(cell_id::UUID)
    get(_CELL_BOND_NAMES, cell_id, Set{Symbol}())
end

"""Clear all bonds (when notebook changes)."""
function _clear_bonds!()
    empty!(_BOND_REGISTRY)
    empty!(_CELL_BOND_NAMES)
end

# ── @bind Macro (mirrors PlutoRunner.@bind) ─────────────────────────

"""
    @bind var widget

Bind a Julia variable to an interactive TUI widget.
The variable gets the widget's initial value and updates reactively
when the user interacts with the widget.

Mirrors Pluto's @bind — but instead of rendering HTML and relying on
JavaScript events, the TUI handles interaction directly.

## Examples
    @bind x Slider(1:10)
    @bind name TextField(default="world")
    @bind flag CheckBox()
"""
macro bind(var, expr)
    if var isa Symbol
        quote
            local el = $(esc(expr))
            local cell_id = Sessions._EXECUTING_CELL_ID[]
            # Preserve existing bond value across re-execution (slider position etc.)
            # This is equivalent to Pluto's eq_tester in RunBonds.jl — skip re-setting
            # if the variable already has the right value.
            local val = if haskey(Sessions._BOND_REGISTRY, $(QuoteNode(var)))
                Sessions._BOND_REGISTRY[$(QuoteNode(var))][2]
            else
                Sessions.initial_value(el)
            end
            Sessions._register_bond!($(QuoteNode(var)), el, val, cell_id)
            $(esc(var)) = val
            Sessions.Bond(el, $(QuoteNode(var)))
        end
    else
        :(throw(ArgumentError("""\nMacro example usage: \n\n\t@bind my_number Slider(1:10)\n\n""")))
    end
end
