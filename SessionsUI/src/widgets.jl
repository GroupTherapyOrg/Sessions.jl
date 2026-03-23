# widgets.jl — Interactive widget types + bond pipeline
#
# Mirrors PlutoUI's widget API. Self-contained — no external deps.
# Sessions.jl imports these types via `using SessionsUI`.

# ── Widget protocol ──────────────────────────────────────────────

"""Abstract type for all interactive widgets."""
abstract type AbstractWidget end

"""Get the initial/default value for a widget."""
initial_value(::AbstractWidget) = missing

"""Get possible values for a widget."""
possible_values(::AbstractWidget) = nothing

"""Validate a value for a widget."""
validate_value(::AbstractWidget, ::Any) = false

# ── Helpers ──────────────────────────────────────────────────────

"""Return the element of `range` closest to `x`."""
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

"""Downsample a vector to at most `max_steps` elements."""
function downsample(x::AbstractVector{T}, max_steps::Integer) where T
    if max_steps >= length(x)
        x
    else
        T[x[round(Int, i)] for i in range(firstindex(x), stop=lastindex(x), length=max_steps)]
    end
end

# ── Slider ───────────────────────────────────────────────────────

"""A slider over the given values.

## Examples
```julia
@bind x Slider(1:10)
@bind x Slider(0.00:0.01:0.30)
@bind x Slider(1:10; default=8, show_value=true)
```
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

Slider(range::AbstractRange; kwargs...) = Slider(collect(range); kwargs...)

initial_value(s::Slider) = s.default
possible_values(s::Slider) = s.values
validate_value(s::Slider{T}, val) where T = val isa T && val ∈ s.values

"""Index of `val` in slider's values (1-based)."""
function _slider_index(s::Slider, val)
    idx = findfirst(==(val), s.values)
    idx === nothing ? 1 : idx
end

# ── NumberField ──────────────────────────────────────────────────

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
validate_value(nf::NumberField, val) = val isa Real && (minimum(nf.range) - 0.0001 <= val <= maximum(nf.range) + 0.0001)

# ── Button ───────────────────────────────────────────────────────

struct Button <: AbstractWidget
    label::AbstractString
end

Button() = Button("Click")

initial_value(b::Button) = b.label
possible_values(b::Button) = [b.label]
validate_value(b::Button, val) = val == b.label

# ── CounterButton ────────────────────────────────────────────────

struct CounterButton <: AbstractWidget
    label::AbstractString
end

CounterButton() = CounterButton("Click")

initial_value(::CounterButton) = 0
possible_values(::CounterButton) = nothing
validate_value(::CounterButton, val) = val isa Integer && val >= 0

# ── CheckBox ─────────────────────────────────────────────────────

struct CheckBox <: AbstractWidget
    default::Bool
end

CheckBox(; default::Bool=false) = CheckBox(default)

initial_value(b::CheckBox) = b.default
possible_values(::CheckBox) = [false, true]
validate_value(::CheckBox, val) = val isa Bool

# ── TextField ────────────────────────────────────────────────────

struct TextField <: AbstractWidget
    default::AbstractString
end

TextField(; default::AbstractString="") = TextField(default)

initial_value(t::TextField) = t.default
possible_values(::TextField) = nothing
validate_value(::TextField, val) = val isa AbstractString

# ── Select ───────────────────────────────────────────────────────

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

# ── Bond ─────────────────────────────────────────────────────────

"""A bond connecting an interactive widget to a Julia variable.
Created by the @bind macro."""
struct Bond
    element::Any
    defines::Symbol
end

function Base.show(io::IO, ::MIME"text/plain", b::Bond)
    print(io, "Bond(:$(b.defines) ↔ $(typeof(b.element)))")
end

function Base.show(io::IO, b::Bond)
    print(io, "Bond(:$(b.defines) ↔ $(typeof(b.element)))")
end

# ── Bond Registry ────────────────────────────────────────────────

"""Registry of active bonds: variable_name => (widget, current_value, cell_id)."""
const _BOND_REGISTRY = Dict{Symbol, Tuple{Any, Any, UUID}}()

"""Per-cell bond names — tracks which cell defined which bonds."""
const _CELL_BOND_NAMES = Dict{UUID, Set{Symbol}}()

"""Cell ID currently being executed (set by the execution engine before eval)."""
const _EXECUTING_CELL_ID = Ref(UUID(0))

"""Register or update a bond in the registry."""
function _register_bond!(name::Symbol, widget, value, cell_id::UUID)
    _BOND_REGISTRY[name] = (widget, value, cell_id)
    if !haskey(_CELL_BOND_NAMES, cell_id)
        _CELL_BOND_NAMES[cell_id] = Set{Symbol}()
    end
    push!(_CELL_BOND_NAMES[cell_id], name)
end

"""Update a bond's value (called when user interacts with widget)."""
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

"""Clear all bonds."""
function _clear_bonds!()
    empty!(_BOND_REGISTRY)
    empty!(_CELL_BOND_NAMES)
end

# ── @bind Macro ──────────────────────────────────────────────────

"""
    @bind var widget

Bind a Julia variable to an interactive widget.

## Examples
```julia
using SessionsUI: @bind, BoundSlider
@bind x BoundSlider(1:10)
@bind w BoundSlider(2:20, default=8)
```
"""
macro bind(var, expr)
    mod = __module__  # the module where @bind is called (notebook workspace)
    if var isa Symbol
        quote
            local el = $(esc(expr))
            local cell_id = $SessionsUI._EXECUTING_CELL_ID[]
            local val = if haskey($SessionsUI._BOND_REGISTRY, $(QuoteNode(var)))
                $SessionsUI._BOND_REGISTRY[$(QuoteNode(var))][2]
            else
                $SessionsUI.initial_value(el)
            end
            $SessionsUI._register_bond!($(QuoteNode(var)), el, val, cell_id)
            $(esc(var)) = val
            $SessionsUI.Bond(el, $(QuoteNode(var)))
        end
    else
        :(throw(ArgumentError("""\nMacro example usage: \n\n\t@bind my_number BoundSlider(1:10)\n\n""")))
    end
end
