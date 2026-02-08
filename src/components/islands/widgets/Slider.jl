# Slider.jl - Range slider widget for @bind macro
#
# PlutoUI-compatible Slider widget. Works with Sessions.jl's @bind macro
# to create bidirectional bindings between a slider and a Julia variable.
#
# Usage:
#   @bind x Slider(1:10)              # Range from 1 to 10
#   @bind y Slider(1:0.1:10)          # Range with step 0.1
#   @bind z Slider(1:100, default=50) # With default value
#
# Gold Standard: PlutoUI.jl Slider

using Therapy

"""
    Slider(range; default=nothing, show_value=false)

A range slider widget for use with `@bind`.

# Arguments
- `range`: The range of values (e.g., `1:10`, `0.0:0.1:1.0`)
- `default`: Initial value (defaults to first value in range)
- `show_value`: Whether to display the current value next to the slider

# Example
```julia
@bind x Slider(1:100, default=50)
y = x^2  # Updates automatically when slider moves
```
"""
struct Slider{T<:AbstractRange}
    range::T
    default::Any
    show_value::Bool
end

function Slider(range::AbstractRange; default=nothing, show_value::Bool=false)
    Slider(range, default, show_value)
end

# Bond interface implementation

"""
Return the initial value for the slider.
"""
function Sessions.initial_value(s::Slider)
    if s.default !== nothing
        return s.default
    else
        return first(s.range)
    end
end

"""
Transform JavaScript string value to appropriate Julia numeric type.
"""
function Sessions.transform_value(s::Slider, val)
    T = eltype(s.range)
    if val isa String
        return parse(T, val)
    elseif val isa Number
        return T(val)
    else
        return val
    end
end

"""
Return all possible values for validation.
"""
function Sessions.possible_values(s::Slider)
    return collect(s.range)
end

"""
Validate that the value is within the slider's range.
"""
function Sessions.validate_value(s::Slider, val)
    return val in s.range
end

# HTML rendering (Suite.jl-styled with warm/accent Tailwind classes)
function Base.show(io::IO, ::MIME"text/html", s::Slider)
    min_val = first(s.range)
    max_val = last(s.range)
    step_val = step(s.range)
    default_val = s.default !== nothing ? s.default : min_val

    slider_class = "w-40 h-1.5 rounded-full appearance-none cursor-pointer bg-warm-200 dark:bg-warm-700 accent-accent-600"

    if s.show_value
        print(io, """<span class="inline-flex items-center gap-2">""")
        print(io, """<input type="range" class="$(slider_class)" """)
        print(io, """min="$(min_val)" max="$(max_val)" step="$(step_val)" value="$(default_val)" """)
        print(io, """oninput="this.nextElementSibling.textContent = this.value" />""")
        print(io, """<span class="min-w-[3em] text-right text-xs font-mono text-warm-600 dark:text-warm-400">$(default_val)</span>""")
        print(io, """</span>""")
    else
        print(io, """<input type="range" class="$(slider_class)" """)
        print(io, """min="$(min_val)" max="$(max_val)" step="$(step_val)" value="$(default_val)" />""")
    end
end
