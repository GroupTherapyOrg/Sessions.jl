module SessionsUI

using Sessions: Sessions, AbstractWidget, Bond, Slider, TextField, CheckBox,
    Select, NumberField, Button, CounterButton,
    initial_value, possible_values, validate_value, set_bond_value!

# Re-export widget types so users can do `using SessionsUI: @bind, Slider`
export @bind, Bond
export AbstractWidget, Slider, TextField, CheckBox, Select, NumberField, Button, CounterButton
export initial_value, possible_values, validate_value

# @bind macro — creates a Bond that connects a widget to a variable
include("Bind.jl")

# Widget components
include("widgets/BoundSlider.jl")

end # module
