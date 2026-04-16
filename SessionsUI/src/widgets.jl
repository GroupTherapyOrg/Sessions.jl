# widgets.jl — Interactive widget types + bond pipeline
#
# Design goals:
# - One unified @bind macro that works in three modes:
#     1. Plain script (just import SessionsUI) — assigns initial value, no live updates
#     2. Sessions.jl IDE — registers bond, dispatches reactive re-runs
#     3. WASM-SSR exported notebook — the same HTML drives a Therapy.jl island signal
# - No "fake_bind" macro injected at file save time. Our @bind is always @bind.
# - Each widget self-renders to PlutoUI-compatible HTML via Base.show(io, MIME"text/html", w),
#   so the wire/storage format is just standard HTML — no parsing on either end.
# - Bond.show wraps the widget in <bond def="x"> (PlutoUI/PlutoSliderServer compatible).
# - Cell ID for the executing cell is read from task_local_storage so the same
#   process can host multiple workers without contention.
#
# Widget structs use Bound* prefix to avoid clashing with Therapy.jl VNode constructors
# (Button, Input, Select, etc.) that are also exported in notebook scope.

using UUIDs

# ── Widget protocol (mirrors AbstractPlutoDingetjes.Bonds) ────────

"""Abstract type for all interactive widgets."""
abstract type AbstractWidget end

"""Initial value the widget produces before the user has interacted.
Returned to Julia even in script mode."""
initial_value(::AbstractWidget) = missing

"""Server-side transform from what JS sends to what Julia sees.
By default, identity; widgets that send indices (Slider, Select, …) override this."""
transform_value(::AbstractWidget, value_from_js) = value_from_js

"""Iterable of possible widget values, or `nothing` (= unknown / infinite).
Used by SSR pre-rendering to bake every output cell for every value combo."""
possible_values(::AbstractWidget) = nothing

"""Security gate: must explicitly return `true` for a value sent by JS to be accepted.
Default is `false` — widgets that accept input must override."""
validate_value(::AbstractWidget, ::Any) = false

# ── HTML helpers ─────────────────────────────────────────────────

"""Escape a string for safe inclusion in an HTML attribute or text node."""
function _h(s)::String
    s = string(s)
    s = replace(s, "&" => "&amp;")
    s = replace(s, "<" => "&lt;")
    s = replace(s, ">" => "&gt;")
    s = replace(s, "\"" => "&quot;")
    s
end

"""Return the element of `range` closest to `x`."""
function closest(range::AbstractRange, x::Real)
    rmin = minimum(range); rmax = maximum(range)
    if x <= rmin
        rmin
    elseif x >= rmax
        rmax
    else
        rstep = step(range)
        int_val = (x - rmin) / rstep
        range[round(Int, int_val) + 1]
    end
end

function closest(values::AbstractVector{<:Real}, x::Real)
    mapfoldl(y -> (abs(y - x), y), ((a1,a2),(b1,b2)) -> a1 > b1 ? (b1,b2) : (a1,a2), values)[2]
end

closest(values::AbstractVector, x) = first(values)

"""Downsample a vector to at most `max_steps` elements."""
function downsample(x::AbstractVector{T}, max_steps::Integer) where T
    if max_steps >= length(x)
        x
    else
        T[x[round(Int, i)] for i in range(firstindex(x), stop=lastindex(x), length=max_steps)]
    end
end

# ─────────────────────────────────────────────────────────────────
#                          BoundSlider
# ─────────────────────────────────────────────────────────────────

"""A slider over the given values.

```julia
@bind x BoundSlider(1:10)
@bind x BoundSlider(0.00:0.01:0.30)
@bind x BoundSlider(1:10; default=8, show_value=true)
```
"""
struct BoundSlider{T} <: AbstractWidget
    values::AbstractVector{T}
    default::T
    show_value::Bool
end

function BoundSlider(values::AbstractVector{T}; default=missing, show_value::Bool=true, max_steps::Integer=1_000) where T
    new_values = downsample(values, max_steps)
    BoundSlider(new_values, (default === missing) ? first(new_values) : let
        d = default
        d ∈ new_values ? convert(T, d) : closest(new_values, d)
    end, show_value)
end

BoundSlider(range::AbstractRange; kwargs...) = BoundSlider(collect(range); kwargs...)

initial_value(s::BoundSlider) = s.default
possible_values(s::BoundSlider) = 1:length(s.values)              # JS sends integer index
transform_value(s::BoundSlider, idx_from_js) = s.values[Int(idx_from_js)]
validate_value(s::BoundSlider, val) = val isa Integer && 1 <= val <= length(s.values)

"""Index of `val` in slider's values (1-based)."""
function _slider_index(s::BoundSlider, val)
    idx = findfirst(==(val), s.values)
    idx === nothing ? 1 : idx
end

function Base.show(io::IO, ::MIME"text/html", s::BoundSlider)
    n = length(s.values)
    start_idx = _slider_index(s, s.default)
    show_val = s.show_value
    print(io, """<input type="range" min="1" max="$n" value="$start_idx" step="1" class="su-slider">""")
    if show_val
        # The neighbour <output> mirrors the slider value (rendered Julia-side).
        print(io, """<output class="su-slider-out">$(_h(s.default))</output>""")
        print(io, """<script>(function(){var s=document.currentScript.previousElementSibling.previousElementSibling;var o=s.nextElementSibling;var V=""")
        # Inline the values vector so the <output> can decode index→display.
        # Keep this small; downsample already capped to max_steps.
        first_show = sprint(show, s.values[1])
        print(io, "[")
        for (i, v) in enumerate(s.values)
            i > 1 && print(io, ",")
            print(io, "\"", _h(sprint(show, v)), "\"")
        end
        print(io, "];s.addEventListener('input',function(){o.textContent=V[+s.value-1]});})();</script>")
    end
end

# ─────────────────────────────────────────────────────────────────
#                          BoundNumberField
# ─────────────────────────────────────────────────────────────────

struct BoundNumberField <: AbstractWidget
    range::AbstractRange
    default::Number
end

function BoundNumberField(range::AbstractRange{T}; default=missing) where T
    BoundNumberField(range, (default === missing) ? first(range) : let
        d = default
        d ∈ range ? convert(T, d) : closest(range, d)
    end)
end

initial_value(nf::BoundNumberField) = nf.default
possible_values(nf::BoundNumberField) = nf.range
transform_value(nf::BoundNumberField, val) = val isa Integer ? convert(eltype(nf.range), val) : val
validate_value(nf::BoundNumberField, val) = val isa Real &&
    (minimum(nf.range) - 0.0001 <= val <= maximum(nf.range) + 0.0001)

function Base.show(io::IO, ::MIME"text/html", nf::BoundNumberField)
    print(io, """<input type="number" min="$(minimum(nf.range))" max="$(maximum(nf.range))" step="$(step(nf.range))" value="$(_h(nf.default))" class="su-number">""")
end

# ─────────────────────────────────────────────────────────────────
#                          BoundButton
# ─────────────────────────────────────────────────────────────────

struct BoundButton <: AbstractWidget
    label::AbstractString
end
BoundButton() = BoundButton("Click")

initial_value(b::BoundButton) = b.label
possible_values(b::BoundButton) = [b.label]
validate_value(b::BoundButton, val) = val == b.label

function Base.show(io::IO, ::MIME"text/html", b::BoundButton)
    print(io, """<input type="button" value="$(_h(b.label))" class="su-button">""")
end

# ─────────────────────────────────────────────────────────────────
#                          BoundCounterButton
# ─────────────────────────────────────────────────────────────────

struct BoundCounterButton <: AbstractWidget
    label::AbstractString
end
BoundCounterButton() = BoundCounterButton("Click")

initial_value(::BoundCounterButton) = 0
possible_values(::BoundCounterButton) = nothing                   # InfinitePossibilities
validate_value(::BoundCounterButton, val) = val isa Integer && val >= 0

function Base.show(io::IO, ::MIME"text/html", b::BoundCounterButton)
    # Container's .value holds the count; click increments and dispatches input.
    print(io, """<span class="su-counter"><input type="button" value="$(_h(b.label))"><script>(function(){var s=document.currentScript.parentElement;s.value=0;s.firstElementChild.addEventListener('click',function(){s.value=(+s.value||0)+1;s.dispatchEvent(new CustomEvent('input'))});})();</script></span>""")
end

# ─────────────────────────────────────────────────────────────────
#                          BoundCheckBox
# ─────────────────────────────────────────────────────────────────

struct BoundCheckBox <: AbstractWidget
    default::Bool
end
BoundCheckBox(; default::Bool=false) = BoundCheckBox(default)

initial_value(b::BoundCheckBox) = b.default
possible_values(::BoundCheckBox) = [false, true]
validate_value(::BoundCheckBox, val) = val isa Bool

function Base.show(io::IO, ::MIME"text/html", b::BoundCheckBox)
    checked = b.default ? " checked" : ""
    print(io, """<input type="checkbox"$(checked) class="su-check">""")
end

# ─────────────────────────────────────────────────────────────────
#                          BoundTextField
# ─────────────────────────────────────────────────────────────────

struct BoundTextField <: AbstractWidget
    dims::Union{Int, Tuple{Int,Int}}                              # `n` or `(cols, rows)`
    default::AbstractString
    placeholder::AbstractString
end

BoundTextField(; default::AbstractString="", placeholder::AbstractString="") =
    BoundTextField(1, default, placeholder)
BoundTextField(dims::Int; default::AbstractString="", placeholder::AbstractString="") =
    BoundTextField(dims, default, placeholder)
BoundTextField(dims::Tuple{Int,Int}; default::AbstractString="", placeholder::AbstractString="") =
    BoundTextField(dims, default, placeholder)

initial_value(t::BoundTextField) = t.default
possible_values(::BoundTextField) = nothing
validate_value(::BoundTextField, val) = val isa AbstractString

function Base.show(io::IO, ::MIME"text/html", t::BoundTextField)
    if t.dims isa Tuple
        cols, rows = t.dims
        print(io, """<textarea cols="$(cols)" rows="$(rows)" placeholder="$(_h(t.placeholder))" class="su-text">$(_h(t.default))</textarea>""")
    else
        size = t.dims === 1 ? "" : """ size="$(t.dims)\""""
        print(io, """<input type="text" value="$(_h(t.default))" placeholder="$(_h(t.placeholder))"$size class="su-text">""")
    end
end

# ─────────────────────────────────────────────────────────────────
#                          BoundPasswordField
# ─────────────────────────────────────────────────────────────────

struct BoundPasswordField <: AbstractWidget
    default::AbstractString
end
BoundPasswordField(; default::AbstractString="") = BoundPasswordField(default)

initial_value(p::BoundPasswordField) = p.default
possible_values(::BoundPasswordField) = nothing
validate_value(::BoundPasswordField, val) = val isa AbstractString

function Base.show(io::IO, ::MIME"text/html", p::BoundPasswordField)
    print(io, """<input type="password" value="$(_h(p.default))" class="su-text">""")
end

# ─────────────────────────────────────────────────────────────────
#                          BoundSelect
# ─────────────────────────────────────────────────────────────────

struct BoundSelect <: AbstractWidget
    options::AbstractVector{Pair}
    default::Union{Missing, Any}
end

BoundSelect(options::AbstractVector; default=missing) = BoundSelect([o => o for o in options], default)
BoundSelect(options::AbstractVector{<:Pair}; default=missing) =
    BoundSelect(convert(Vector{Pair}, collect(options)), default)

function initial_value(s::BoundSelect)
    ismissing(s.default) ? first(s.options).first : s.default
end
possible_values(s::BoundSelect) = ["su-sel-$i" for i in 1:length(s.options)]
function transform_value(s::BoundSelect, str_from_js)
    m = match(r"^su-sel-(\d+)$", string(str_from_js))
    m === nothing && return s.options[1].first
    s.options[parse(Int, m.captures[1])].first
end
function validate_value(s::BoundSelect, val)
    val isa AbstractString || return false
    m = match(r"^su-sel-(\d+)$", val)
    m === nothing && return false
    1 <= parse(Int, m.captures[1]) <= length(s.options)
end

function Base.show(io::IO, ::MIME"text/html", s::BoundSelect)
    print(io, """<select class="su-select">""")
    default_first = ismissing(s.default) ? s.options[1].first : s.default
    for (i, p) in enumerate(s.options)
        sel = (p.first == default_first) ? " selected" : ""
        print(io, """<option value="su-sel-$i"$sel>""", _h(p.second), "</option>")
    end
    print(io, "</select>")
end

# ─────────────────────────────────────────────────────────────────
#                          BoundMultiSelect
# ─────────────────────────────────────────────────────────────────

struct BoundMultiSelect <: AbstractWidget
    options::AbstractVector{Pair}
    default::AbstractVector
    size::Int
end

BoundMultiSelect(options::AbstractVector; default=Any[], size::Int=6) =
    BoundMultiSelect([o => o for o in options], default, size)
BoundMultiSelect(options::AbstractVector{<:Pair}; default=Any[], size::Int=6) =
    BoundMultiSelect(convert(Vector{Pair}, collect(options)), default, size)

initial_value(m::BoundMultiSelect) = m.default
possible_values(m::BoundMultiSelect) = ["su-sel-$i" for i in 1:length(m.options)]
function transform_value(m::BoundMultiSelect, vals_from_js)
    vals = vals_from_js isa AbstractVector ? vals_from_js : [vals_from_js]
    out = Any[]
    for v in vals
        mm = match(r"^su-sel-(\d+)$", string(v))
        mm === nothing && continue
        push!(out, m.options[parse(Int, mm.captures[1])].first)
    end
    out
end
validate_value(m::BoundMultiSelect, vals) = vals isa AbstractVector && all(v -> v isa AbstractString && occursin(r"^su-sel-\d+$", v), vals)

function Base.show(io::IO, ::MIME"text/html", m::BoundMultiSelect)
    print(io, """<select multiple size="$(m.size)" class="su-select">""")
    for (i, p) in enumerate(m.options)
        sel = (p.first ∈ m.default) ? " selected" : ""
        print(io, """<option value="su-sel-$i"$sel>""", _h(p.second), "</option>")
    end
    print(io, "</select>")
end

# ─────────────────────────────────────────────────────────────────
#                          BoundRadio
# ─────────────────────────────────────────────────────────────────

struct BoundRadio <: AbstractWidget
    options::AbstractVector{Pair}
    default::Union{Missing, Any}
end

BoundRadio(options::AbstractVector; default=missing) = BoundRadio([o => o for o in options], default)
BoundRadio(options::AbstractVector{<:Pair}; default=missing) =
    BoundRadio(convert(Vector{Pair}, collect(options)), default)

function initial_value(r::BoundRadio)
    ismissing(r.default) ? r.options[1].first : r.default
end
possible_values(r::BoundRadio) = ["su-rad-$i" for i in 1:length(r.options)]
function transform_value(r::BoundRadio, str_from_js)
    m = match(r"^su-rad-(\d+)$", string(str_from_js))
    m === nothing && return r.options[1].first
    r.options[parse(Int, m.captures[1])].first
end
function validate_value(r::BoundRadio, val)
    val isa AbstractString || return false
    m = match(r"^su-rad-(\d+)$", val)
    m === nothing && return false
    1 <= parse(Int, m.captures[1]) <= length(r.options)
end

function Base.show(io::IO, ::MIME"text/html", r::BoundRadio)
    name = "su-rad-" * string(objectid(r), base=16)
    default_first = ismissing(r.default) ? r.options[1].first : r.default
    print(io, """<form class="su-radio"><script>(function(){var f=document.currentScript.parentElement;Object.defineProperty(f,'value',{get:function(){var c=f.querySelector('input:checked');return c?c.value:null}});f.addEventListener('change',function(){f.dispatchEvent(new CustomEvent('input'))});})();</script>""")
    for (i, p) in enumerate(r.options)
        chk = (p.first == default_first) ? " checked" : ""
        print(io, """<label><input type="radio" name="$(_h(name))" value="su-rad-$i"$chk> """, _h(p.second), "</label>")
    end
    print(io, "</form>")
end

# ─────────────────────────────────────────────────────────────────
#                          BoundRangeSlider
# ─────────────────────────────────────────────────────────────────

struct BoundRangeSlider{T} <: AbstractWidget
    values::AbstractVector{T}
    default::Tuple{T,T}
    show_value::Bool
end

function BoundRangeSlider(values::AbstractVector{T}; default=missing, show_value::Bool=true, max_steps::Integer=1_000) where T
    new_values = downsample(values, max_steps)
    d = (default === missing) ? (first(new_values), last(new_values)) : default
    BoundRangeSlider(new_values, (convert(T, d[1]), convert(T, d[2])), show_value)
end

BoundRangeSlider(range::AbstractRange; kwargs...) = BoundRangeSlider(collect(range); kwargs...)

initial_value(r::BoundRangeSlider) = r.default
possible_values(::BoundRangeSlider) = nothing                     # 2D, too many to enumerate
function transform_value(r::BoundRangeSlider, pair_from_js)
    p = pair_from_js
    (r.values[Int(p[1])], r.values[Int(p[2])])
end
validate_value(r::BoundRangeSlider, val) = val isa AbstractVector && length(val) == 2 &&
    all(v -> v isa Integer && 1 <= v <= length(r.values), val)

function Base.show(io::IO, ::MIME"text/html", r::BoundRangeSlider)
    n = length(r.values)
    lo_idx = findfirst(==(r.default[1]), r.values); lo_idx === nothing && (lo_idx = 1)
    hi_idx = findfirst(==(r.default[2]), r.values); hi_idx === nothing && (hi_idx = n)
    # Two synced range inputs; container exposes .value = [lo, hi] for the bond reader.
    print(io, """<span class="su-range"><input type="range" min="1" max="$n" value="$lo_idx" step="1"><input type="range" min="1" max="$n" value="$hi_idx" step="1">""")
    if r.show_value
        print(io, """<output>$(_h(r.default[1])) – $(_h(r.default[2]))</output>""")
    end
    # Inline values vector for output decode + container.value sync.
    print(io, "<script>(function(){var c=document.currentScript.parentElement;var inps=c.querySelectorAll('input[type=range]');var lo=inps[0],hi=inps[1];var o=c.querySelector('output');var V=[")
    for (i, v) in enumerate(r.values)
        i > 1 && print(io, ",")
        print(io, "\"", _h(sprint(show, v)), "\"")
    end
    print(io, "];function sync(){var a=+lo.value,b=+hi.value;if(a>b){if(this===lo)hi.value=a;else lo.value=b;a=+lo.value;b=+hi.value;}c.value=[a,b];if(o)o.textContent=V[a-1]+' – '+V[b-1];c.dispatchEvent(new CustomEvent('input'))}lo.addEventListener('input',sync);hi.addEventListener('input',sync);c.value=[+lo.value,+hi.value];})();</script></span>")
end

# ─────────────────────────────────────────────────────────────────
#                          BoundColorPicker (string hex)
# ─────────────────────────────────────────────────────────────────

struct BoundColorPicker <: AbstractWidget
    default::String
end
BoundColorPicker(; default::String="#000000") = BoundColorPicker(default)

initial_value(c::BoundColorPicker) = c.default
possible_values(::BoundColorPicker) = nothing
validate_value(::BoundColorPicker, val) = val isa AbstractString && occursin(r"^#[0-9A-Fa-f]{6}$", val)

function Base.show(io::IO, ::MIME"text/html", c::BoundColorPicker)
    print(io, """<input type="color" value="$(_h(c.default))" class="su-color">""")
end

# ─────────────────────────────────────────────────────────────────
#                          BoundDatePicker
# ─────────────────────────────────────────────────────────────────
# Returns an ISO-8601 date string ("YYYY-MM-DD"). Users who want a
# `Dates.Date` object can wrap with `Date(my_var)` themselves —
# keeping SessionsUI free of the Dates stdlib dependency.

struct BoundDatePicker <: AbstractWidget
    default::String                                               # "" = blank, otherwise YYYY-MM-DD
end
BoundDatePicker(; default::AbstractString="") = BoundDatePicker(String(default))

initial_value(d::BoundDatePicker) = d.default
possible_values(::BoundDatePicker) = nothing
validate_value(::BoundDatePicker, val) = val isa AbstractString &&
    (isempty(val) || occursin(r"^\d{4}-\d{2}-\d{2}$", val))

function Base.show(io::IO, ::MIME"text/html", d::BoundDatePicker)
    val_attr = isempty(d.default) ? "" : """ value="$(_h(d.default))\""""
    print(io, """<input type="date"$val_attr class="su-date">""")
end

# ─────────────────────────────────────────────────────────────────
#                          BoundTimePicker
# ─────────────────────────────────────────────────────────────────
# Returns a "HH:MM" or "HH:MM:SS" string.

struct BoundTimePicker <: AbstractWidget
    default::String                                               # "" = blank
    show_seconds::Bool
end
BoundTimePicker(; default::AbstractString="", show_seconds::Bool=false) =
    BoundTimePicker(String(default), show_seconds)

initial_value(t::BoundTimePicker) = t.default
possible_values(::BoundTimePicker) = nothing
validate_value(::BoundTimePicker, val) = val isa AbstractString &&
    (isempty(val) || occursin(r"^\d{2}:\d{2}", val))

function Base.show(io::IO, ::MIME"text/html", t::BoundTimePicker)
    val_attr = isempty(t.default) ? "" : """ value="$(_h(t.default))\""""
    step_attr = t.show_seconds ? """ step="1\"""" : ""
    print(io, """<input type="time"$val_attr$step_attr class="su-time">""")
end

# ─────────────────────────────────────────────────────────────────
#                          BoundFilePicker
# ─────────────────────────────────────────────────────────────────

struct BoundFilePicker <: AbstractWidget
    accept::Vector{String}
end
BoundFilePicker(; accept::Vector{String}=String[]) = BoundFilePicker(accept)

initial_value(::BoundFilePicker) = nothing
possible_values(::BoundFilePicker) = nothing
validate_value(::BoundFilePicker, val) = val === nothing ||
    (val isa AbstractDict && haskey(val, "name") && haskey(val, "data"))

function Base.show(io::IO, ::MIME"text/html", f::BoundFilePicker)
    accept = isempty(f.accept) ? "" : """ accept="$(_h(join(f.accept, ",")))\""""
    print(io, """<input type="file"$accept class="su-file">""")
end

# ─────────────────────────────────────────────────────────────────
#                          BoundClock (interval ticker)
# ─────────────────────────────────────────────────────────────────

struct BoundClock <: AbstractWidget
    interval_ms::Int
    max_ticks::Int                                                # 0 = unbounded
    start_running::Bool
end
BoundClock(; interval_ms::Int=1000, max_ticks::Int=0, start_running::Bool=true) =
    BoundClock(interval_ms, max_ticks, start_running)

initial_value(::BoundClock) = 0
possible_values(c::BoundClock) = c.max_ticks == 0 ? nothing : 0:c.max_ticks
validate_value(::BoundClock, val) = val isa Integer && val >= 0

function Base.show(io::IO, ::MIME"text/html", c::BoundClock)
    print(io, """<span class="su-clock"><script>(function(){var s=document.currentScript.parentElement;s.value=0;var max=$(c.max_ticks);var iv=null;function tick(){s.value=(+s.value)+1;s.dispatchEvent(new CustomEvent('input'));if(max>0&&s.value>=max){clearInterval(iv);iv=null}}if($(c.start_running ? "true" : "false"))iv=setInterval(tick,$(c.interval_ms));})();</script></span>""")
end

# ─────────────────────────────────────────────────────────────────
#                          Bond
# ─────────────────────────────────────────────────────────────────

"""A bond connecting an interactive widget to a Julia variable.
Created by the `@bind` macro. Renders as `<bond def="x">...widget HTML...</bond>`,
which is the PlutoUI/PlutoSliderServer-compatible wire format."""
struct Bond
    element::Any
    defines::Symbol
end

function Base.show(io::IO, ::MIME"text/plain", b::Bond)
    print(io, "Bond(:$(b.defines) ↔ $(typeof(b.element)))")
end

Base.show(io::IO, b::Bond) = print(io, "Bond(:$(b.defines) ↔ $(typeof(b.element)))")

function Base.show(io::IO, m::MIME"text/html", b::Bond)
    # PlutoUI-compatible <bond def> wrapper. The client-side bridge attaches an
    # `input` listener to the first child and reports value changes via either
    # the Sessions WS channel (IDE mode) or a Therapy signal (WASM-SSR mode).
    print(io, """<bond def="$(b.defines)">""")
    show(io, m, b.element)
    print(io, "</bond>")
end

# ── Bond Registry ────────────────────────────────────────────────

"""Registry of active bonds: variable_name => (widget, current_value, cell_id)."""
const _BOND_REGISTRY = Dict{Symbol, Tuple{Any, Any, UUID}}()

"""Per-cell bond names — tracks which cell defined which bonds."""
const _CELL_BOND_NAMES = Dict{UUID, Set{Symbol}}()

"""Global Ref that Sessions.jl's kernel writes to before evaluating each cell:
`SessionsUI._EXECUTING_CELL_ID[] = cell.id`. The `@bind` macro reads it via
`_current_cell_id()` to associate each bond with its defining cell. UUID(0)
is the sentinel for "no cell context" (plain script / REPL mode)."""
const _EXECUTING_CELL_ID = Ref(UUID(0))

_current_cell_id()::UUID = _EXECUTING_CELL_ID[]

function _register_bond!(name::Symbol, widget, value, cell_id::UUID)
    _BOND_REGISTRY[name] = (widget, value, cell_id)
    if !haskey(_CELL_BOND_NAMES, cell_id)
        _CELL_BOND_NAMES[cell_id] = Set{Symbol}()
    end
    push!(_CELL_BOND_NAMES[cell_id], name)
    return value
end

"""Update a bond's stored value (called by the channel handler when JS reports
a new value, after `transform_value` and `validate_value` have run)."""
function set_bond_value!(name::Symbol, new_value)
    haskey(_BOND_REGISTRY, name) || return
    widget, _, cell_id = _BOND_REGISTRY[name]
    _BOND_REGISTRY[name] = (widget, new_value, cell_id)
end

"""Get the cell that defined a bond."""
function _bond_cell_id(name::Symbol)::Union{UUID, Nothing}
    haskey(_BOND_REGISTRY, name) || return nothing
    _BOND_REGISTRY[name][3]
end

"""Get bond names defined by a given cell."""
function get_bond_names(cell_id::UUID)
    get(_CELL_BOND_NAMES, cell_id, Set{Symbol}())
end

function _clear_bonds!()
    empty!(_BOND_REGISTRY)
    empty!(_CELL_BOND_NAMES)
end

# ── @bind Macro ──────────────────────────────────────────────────

"""
    @bind var widget

Bind a Julia variable to an interactive widget.

Works in three modes with the **same** macro — no file-injection trick,
no Pluto-style `fake_bind` duality:

  1. **Plain Julia script** (`using SessionsUI` then `julia my_notebook.jl`)
     — `var` is assigned the widget's `initial_value`. No live updates.
     The script runs end-to-end as a normal program.
  2. **Sessions.jl IDE** — the bond is registered against the executing cell;
     downstream cells re-run when the user moves the widget.
  3. **WASM-SSR exported notebook** — the same `<bond>` HTML is wired to a
     Therapy.jl signal at hydration time; downstream WASM islands recompute
     from the signal without any server round-trip.

```julia
using SessionsUI: @bind, BoundSlider
@bind x BoundSlider(1:10)
@bind w BoundSlider(2:20; default=8)
```
"""
macro bind(var, expr)
    if !(var isa Symbol)
        return :(throw(ArgumentError("""\nMacro example usage: \n\n\t@bind my_number BoundSlider(1:10)\n\n""")))
    end
    quote
        local el = $(esc(expr))
        local cell_id = $(SessionsUI)._current_cell_id()
        # Honour an existing bond's user-set value across re-runs (so the
        # cell can re-execute without snapping the slider back to default).
        # Fall back to Base.get if the widget defines it (Pluto convention),
        # then to initial_value as the universal contract.
        local val = if haskey($(SessionsUI)._BOND_REGISTRY, $(QuoteNode(var)))
            $(SessionsUI)._BOND_REGISTRY[$(QuoteNode(var))][2]
        elseif Core.applicable(Base.get, el)
            Base.get(el)
        else
            $(SessionsUI).initial_value(el)
        end
        $(SessionsUI)._register_bond!($(QuoteNode(var)), el, val, cell_id)
        $(esc(var)) = val
        $(SessionsUI).Bond(el, $(QuoteNode(var)))
    end
end
