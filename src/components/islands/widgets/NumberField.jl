# NumberField.jl - Numeric input widget for @bind macro
#
# PlutoUI-compatible NumberField widget. Works with Sessions.jl's @bind macro
# to create bidirectional bindings between a numeric input and a Julia variable.
#
# Usage:
#   @bind n NumberField()                        # Any number
#   @bind n NumberField(1:100)                   # Range constraint
#   @bind n NumberField(default=42)              # With default
#   @bind n NumberField(1:100, default=50)       # Range with default
#
# Gold Standard: PlutoUI.jl NumberField

using Therapy

"""
    NumberField(range=nothing; default=nothing)

A numeric input widget for use with `@bind`.

# Arguments
- `range`: Optional range constraining the value (e.g., `1:100`, `0.0:0.1:1.0`)
- `default`: Initial value (defaults to first value in range, or 0)

# Example
```julia
@bind count NumberField(1:100, default=10)
total = count * price  # Updates automatically when count changes

# Float input
@bind temperature NumberField(0.0:0.1:100.0, default=20.0)
```
"""
struct NumberField{T<:Union{Nothing, AbstractRange}}
    range::T
    default::Union{Number, Nothing}
end

function NumberField(range::AbstractRange; default=nothing)
    NumberField(range, default)
end

function NumberField(; default=nothing)
    NumberField(nothing, default)
end

# Bond interface implementation

"""
Return the initial value for the number field.
"""
function Sessions.initial_value(nf::NumberField)
    if nf.default !== nothing
        return nf.default
    elseif nf.range !== nothing
        return first(nf.range)
    else
        return 0
    end
end

"""
Transform JavaScript value to appropriate Julia numeric type.
"""
function Sessions.transform_value(nf::NumberField, val)
    if nf.range !== nothing
        T = eltype(nf.range)
        if val isa String
            return parse(T, val)
        elseif val isa Number
            return T(val)
        else
            return val
        end
    else
        # No range - infer type from value
        if val isa String
            # Try parsing as Int first, then Float64
            if occursin(".", val)
                return parse(Float64, val)
            else
                return parse(Int, val)
            end
        elseif val isa Number
            return val
        else
            return val
        end
    end
end

"""
Return all possible values (only for discrete ranges).
"""
function Sessions.possible_values(nf::NumberField)
    if nf.range !== nothing && length(nf.range) <= 1000
        return collect(nf.range)
    else
        return nothing
    end
end

"""
Validate that the value is within range (if specified).
"""
function Sessions.validate_value(nf::NumberField, val)
    if !(val isa Number)
        return false
    end
    if nf.range !== nothing
        return first(nf.range) <= val <= last(nf.range)
    end
    return true
end

# HTML rendering (Suite.jl-styled with warm/accent Tailwind classes)
function Base.show(io::IO, ::MIME"text/html", nf::NumberField)
    default_val = Sessions.initial_value(nf)

    input_class = "h-9 w-32 rounded-md border border-warm-200 dark:border-warm-700 bg-transparent px-3 py-1 text-sm text-right font-mono text-warm-900 dark:text-warm-100 focus:outline-none focus:border-accent-600 focus:ring-2 focus:ring-accent-600/50 transition-colors"
    print(io, """<input type="number" class="$(input_class)" value="$(default_val)" """)

    if nf.range !== nothing
        min_val = first(nf.range)
        max_val = last(nf.range)
        step_val = step(nf.range)
        print(io, """min="$(min_val)" max="$(max_val)" step="$(step_val)" """)
    end

    print(io, """/>""")
end
