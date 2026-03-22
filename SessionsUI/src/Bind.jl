# Bind.jl — @bind macro for SessionsUI
#
# Creates a Bond that connects an interactive widget to a Julia variable.
# The variable gets the widget's initial value and updates reactively
# when the user interacts with the widget.
#
# This is the user-facing API. The Bond type and widget types live in
# Sessions.jl (the kernel needs them for output classification).

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
    if var isa Symbol
        quote
            local el = $(esc(expr))
            local cell_id = Sessions._EXECUTING_CELL_ID[]
            # Preserve existing bond value across re-execution
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
        :(throw(ArgumentError("""\nMacro example usage: \n\n\t@bind my_number BoundSlider(1:10)\n\n""")))
    end
end
