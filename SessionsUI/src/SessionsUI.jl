module SessionsUI

# SessionsUI — Lightweight notebook API for @bind + interactive widgets.
#
# User-facing API: @bind and BoundSlider. That's it.
#   using SessionsUI: @bind, BoundSlider
#
# All widget struct names use the Bound* prefix to avoid clashing with
# Therapy.jl VNode constructors (Button, Input, etc.) or other packages.
# Sessions.jl knows how to render these widgets.

using UUIDs

# Widget types + bond registry + @bind macro
include("widgets.jl")

# Table of Contents widget
include("toc.jl")

# User-facing exports — widgets that notebook users construct in cells
export @bind, TableOfContents
export BoundSlider, BoundNumberField, BoundButton, BoundCounterButton,
       BoundCheckBox, BoundTextField, BoundPasswordField, BoundSelect,
       BoundMultiSelect, BoundRadio, BoundRangeSlider, BoundColorPicker,
       BoundDatePicker, BoundTimePicker, BoundFilePicker, BoundClock

# Engine-facing exports — used by Sessions.jl, not by notebook users
export AbstractWidget, initial_value, transform_value, possible_values, validate_value
export Bond, set_bond_value!, get_bond_names

end # module
