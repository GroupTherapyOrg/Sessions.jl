module SessionsUI

# SessionsUI provides the user-facing notebook API for @bind + widget constructors.
#
# Naming convention: "Bound*" prefix for all widgets to avoid clashes with
# HTML elements (Button), Makie (Slider), or other packages.
#   @bind        — macro that connects a widget to a Julia variable
#   BoundSlider  — interactive range slider
#   (future: BoundCheckBox, BoundTextField, BoundSelect, BoundButton, etc.)
#
# The raw Sessions.jl types (Slider, TextField, etc.) are NOT re-exported.
# Users interact with the Bound* wrappers, which internally use Sessions types.
#
# This package is intentionally lightweight (only depends on Sessions.jl)
# so it can be loaded in Malt.jl worker processes. The @island rendering
# components live in the web app (web/src/components/), not here.

import Sessions

# @bind macro — creates a Bond that connects a widget to a variable
export @bind
include("Bind.jl")

# Widget constructors (lightweight wrappers around Sessions types)
export BoundSlider
include("widgets/BoundSlider.jl")

end # module
