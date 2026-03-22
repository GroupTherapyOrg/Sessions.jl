# BoundSlider.jl — User-facing slider widget for @bind
#
# This is the notebook API. Users write:
#   @bind w BoundSlider(2:20, default=8)
#
# Internally creates a Sessions.Slider. The web UI coordinator renders
# this as a BoundSlider @island (WASM signal for instant value display).
# The @island component lives in web/src/components/BoundSlider.jl.

"""
    BoundSlider(range; default=first(range), show_value=true)

Interactive slider for use with `@bind` in notebooks.

## Examples
```julia
using SessionsUI: @bind, BoundSlider
@bind x BoundSlider(1:10)
@bind x BoundSlider(0.0:0.1:1.0, default=0.5)
@bind n BoundSlider(1:100, default=25)
```
"""
BoundSlider(range; default=first(range), show_value::Bool=true) =
    Sessions.Slider(range; default, show_value)

export BoundSlider
