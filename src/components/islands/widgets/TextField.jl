# TextField.jl - Text input widget for @bind macro
#
# PlutoUI-compatible TextField widget. Works with Sessions.jl's @bind macro
# to create bidirectional bindings between a text input and a Julia variable.
#
# Usage:
#   @bind name TextField()                    # Empty text field
#   @bind name TextField(default="Alice")     # With default value
#   @bind name TextField(placeholder="Enter") # With placeholder
#
# Gold Standard: PlutoUI.jl TextField

using Therapy

"""
    TextField(; default="", placeholder="")

A text input widget for use with `@bind`.

# Arguments
- `default`: Initial text value
- `placeholder`: Placeholder text shown when empty

# Example
```julia
@bind name TextField(default="World")
greeting = "Hello, \$name!"  # Updates automatically when text changes
```
"""
struct TextField
    default::String
    placeholder::String
end

function TextField(; default::String="", placeholder::String="")
    TextField(default, placeholder)
end

# Bond interface implementation

"""
Return the initial value for the text field.
"""
function Sessions.initial_value(tf::TextField)
    return tf.default
end

"""
Transform JavaScript value (already a string).
"""
function Sessions.transform_value(tf::TextField, val)
    if val isa String
        return val
    else
        return string(val)
    end
end

"""
No fixed set of possible values for text fields.
"""
function Sessions.possible_values(tf::TextField)
    return nothing
end

"""
All string values are valid.
"""
function Sessions.validate_value(tf::TextField, val)
    return val isa String
end

# HTML rendering (Suite.jl-styled with warm/accent Tailwind classes)
function Base.show(io::IO, ::MIME"text/html", tf::TextField)
    input_class = "h-9 rounded-md border border-warm-200 dark:border-warm-700 bg-transparent px-3 py-1 text-sm text-warm-900 dark:text-warm-100 placeholder:text-warm-500 dark:placeholder:text-warm-600 focus:outline-none focus:border-accent-600 focus:ring-2 focus:ring-accent-600/50 transition-colors"
    print(io, """<input type="text" class="$(input_class)" """)
    if !isempty(tf.default)
        escaped = replace(tf.default, "\"" => "&quot;", "<" => "&lt;", ">" => "&gt;", "&" => "&amp;")
        print(io, """value="$(escaped)" """)
    end
    if !isempty(tf.placeholder)
        escaped = replace(tf.placeholder, "\"" => "&quot;", "<" => "&lt;", ">" => "&gt;", "&" => "&amp;")
        print(io, """placeholder="$(escaped)" """)
    end
    print(io, """/>""")
end
