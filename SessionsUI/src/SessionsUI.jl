module SessionsUI

# SessionsUI — Lightweight notebook API for @bind + interactive widgets.
#
# ZERO heavy deps. Only stdlib (UUIDs). This is what notebook users import:
#   using SessionsUI: @bind, BoundSlider
#
# Sessions.jl (the app) depends on SessionsUI and knows how to render
# these widgets. This package just defines the types and bond pipeline.

using UUIDs

# Widget types + bond registry + @bind macro
include("widgets.jl")

export AbstractWidget, initial_value, possible_values, validate_value
export Slider, NumberField, Button, CounterButton, CheckBox, TextField, Select
export Bond, set_bond_value!, get_bond_names
export @bind

# User-friendly aliases (Bound* prefix to avoid name clashes with Makie etc.)
const BoundSlider = Slider
const BoundNumberField = NumberField
const BoundButton = Button
const BoundCheckBox = CheckBox
const BoundTextField = TextField
const BoundSelect = Select
export BoundSlider, BoundNumberField, BoundButton, BoundCheckBox, BoundTextField, BoundSelect

end # module
