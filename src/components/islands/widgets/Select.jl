# Select.jl - Dropdown select widget for @bind macro
#
# PlutoUI-compatible Select widget. Works with Sessions.jl's @bind macro
# to create bidirectional bindings between a dropdown and a Julia variable.
#
# Usage:
#   @bind choice Select(["a", "b", "c"])                  # Simple options
#   @bind choice Select(["a" => "A", "b" => "B"])         # Label/value pairs
#   @bind choice Select(options, default="b")             # With default
#
# Gold Standard: PlutoUI.jl Select

using Therapy

"""
    Select(options; default=nothing)

A dropdown select widget for use with `@bind`.

# Arguments
- `options`: Vector of options. Can be:
  - Simple values: `["a", "b", "c"]` - shown as both label and value
  - Pairs: `["a" => "Label A", "b" => "Label B"]` - value => label
  - Dict: `Dict("a" => "Label A")` - value => label
- `default`: Initial selected value (defaults to first option)

# Example
```julia
@bind animal Select(["dog", "cat", "bird"])
println("You chose: \$animal")

# With labels
@bind lang Select([
    "en" => "English",
    "es" => "Spanish",
    "fr" => "French"
], default="en")
```
"""
struct Select{T}
    options::Vector{Pair{T, String}}  # value => label
    default::Union{T, Nothing}
end

function Select(options::Vector{<:Pair}; default=nothing)
    # options is already value => label pairs
    typed_options = [Pair{Any, String}(k, string(v)) for (k, v) in options]
    Select(typed_options, default)
end

function Select(options::Vector; default=nothing)
    # Simple values - use as both value and label
    typed_options = [Pair{Any, String}(v, string(v)) for v in options]
    Select(typed_options, default)
end

function Select(options::Dict; default=nothing)
    # Dict - value => label
    typed_options = [Pair{Any, String}(k, string(v)) for (k, v) in options]
    Select(typed_options, default)
end

# Bond interface implementation

"""
Return the initial value for the select.
"""
function Sessions.initial_value(s::Select)
    if s.default !== nothing
        return s.default
    elseif !isempty(s.options)
        return first(s.options).first
    else
        return nothing
    end
end

"""
Transform JavaScript string value back to the original type.
This handles the case where values are stringified for HTML.
"""
function Sessions.transform_value(s::Select, val)
    # Find matching option by string comparison
    val_str = string(val)
    for (value, _) in s.options
        if string(value) == val_str
            return value
        end
    end
    # If no match, return as-is (might be a new value somehow)
    return val
end

"""
Return all possible values.
"""
function Sessions.possible_values(s::Select)
    return [opt.first for opt in s.options]
end

"""
Validate that the value is one of the options.
"""
function Sessions.validate_value(s::Select, val)
    val_str = string(val)
    for (value, _) in s.options
        if string(value) == val_str
            return true
        end
    end
    return false
end

# HTML rendering
function Base.show(io::IO, ::MIME"text/html", s::Select)
    default_val = s.default !== nothing ? s.default : (isempty(s.options) ? nothing : first(s.options).first)

    print(io, """<select style="padding: 0.25rem 0.5rem; border: 1px solid #ccc; border-radius: 4px; background: white;">""")

    for (value, label) in s.options
        val_str = string(value)
        # Escape HTML in label
        escaped_label = replace(label, "<" => "&lt;", ">" => "&gt;", "&" => "&amp;")
        # Escape value for HTML attribute
        escaped_val = replace(val_str, "\"" => "&quot;", "<" => "&lt;", ">" => "&gt;", "&" => "&amp;")

        selected = default_val !== nothing && string(default_val) == val_str ? " selected" : ""
        print(io, """<option value="$(escaped_val)"$(selected)>$(escaped_label)</option>""")
    end

    print(io, """</select>""")
end
