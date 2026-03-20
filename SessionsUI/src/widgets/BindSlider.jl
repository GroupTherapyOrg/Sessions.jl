# BindSlider.jl — Interactive slider widget for @bind
#
# For now: produces a Slider (from Sessions.jl) that the kernel
# renders as a range input. Later: becomes a Therapy @island component
# with WASM signal for client-side reactivity.
#
# Usage:
#   using SessionsUI: @bind, BindSlider
#   @bind x BindSlider(1:10)
#   @bind x BindSlider(1:100, default=50)

"""
    BindSlider(range; default=first(range))

An interactive slider for use with `@bind`. Wraps Sessions.Slider.

## Examples
```julia
@bind x BindSlider(1:10)
@bind x BindSlider(0.0:0.1:1.0, default=0.5)
@bind n BindSlider(1:100, default=25)
```
"""
function BindSlider(range; default=first(range), show_value::Bool=true)
    Slider(range; default, show_value)
end

export BindSlider
