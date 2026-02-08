# CheckBox.jl - Checkbox widget for @bind macro
#
# PlutoUI-compatible CheckBox widget. Works with Sessions.jl's @bind macro
# to create bidirectional bindings between a checkbox and a Julia Bool variable.
#
# Usage:
#   @bind enabled CheckBox()               # Unchecked by default
#   @bind enabled CheckBox(default=true)   # Checked by default
#   @bind enabled CheckBox(label="Enable") # With label text
#
# Gold Standard: PlutoUI.jl CheckBox

using Therapy

"""
    CheckBox(; default=false, label="")

A checkbox widget for use with `@bind`.

# Arguments
- `default`: Initial checked state (true/false)
- `label`: Optional label text displayed next to the checkbox

# Example
```julia
@bind show_details CheckBox(default=true, label="Show details")
if show_details
    # Display detailed view
end
```
"""
struct CheckBox
    default::Bool
    label::String
end

function CheckBox(; default::Bool=false, label::String="")
    CheckBox(default, label)
end

# Bond interface implementation

"""
Return the initial value for the checkbox.
"""
function Sessions.initial_value(cb::CheckBox)
    return cb.default
end

"""
Transform JavaScript value to Bool.
JavaScript sends "true"/"false" strings or true/false booleans.
"""
function Sessions.transform_value(cb::CheckBox, val)
    if val isa Bool
        return val
    elseif val isa String
        return lowercase(val) == "true"
    elseif val isa Number
        return val != 0
    else
        return false
    end
end

"""
Checkboxes have only two possible values.
"""
function Sessions.possible_values(cb::CheckBox)
    return [false, true]
end

"""
Validate that value is a boolean.
"""
function Sessions.validate_value(cb::CheckBox, val)
    return val isa Bool
end

# HTML rendering (Suite.jl-styled with warm/accent Tailwind classes)
function Base.show(io::IO, ::MIME"text/html", cb::CheckBox)
    cb_class = "h-4 w-4 rounded border border-warm-300 dark:border-warm-600 accent-accent-600 cursor-pointer focus:outline-none focus:ring-2 focus:ring-accent-600/50"
    checked_attr = cb.default ? " checked" : ""

    if isempty(cb.label)
        print(io, """<input type="checkbox" class="$(cb_class)"$(checked_attr) />""")
    else
        id = string(hash(cb), base=16)[1:8]
        escaped_label = replace(cb.label, "<" => "&lt;", ">" => "&gt;", "&" => "&amp;")
        print(io, """<label class="inline-flex items-center gap-2 cursor-pointer text-sm text-warm-700 dark:text-warm-300">""")
        print(io, """<input type="checkbox" id="cb-$(id)" class="$(cb_class)"$(checked_attr) />""")
        print(io, """<span>$(escaped_label)</span>""")
        print(io, """</label>""")
    end
end
