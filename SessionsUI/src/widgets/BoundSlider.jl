# BoundSlider.jl — Interactive slider widget for @bind

"""
    BoundSlider(range; default=first(range))

An interactive slider for use with `@bind`. Wraps Sessions.Slider.

## Examples
```julia
@bind x BoundSlider(1:10)
@bind x BoundSlider(0.0:0.1:1.0, default=0.5)
@bind n BoundSlider(1:100, default=25)
```
"""
function BoundSlider(range; default=first(range), show_value::Bool=true)
    Slider(range; default, show_value)
end

export BoundSlider
