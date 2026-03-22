# BoundSlider.jl — @island: Interactive slider for @bind (web rendering)
#
# This is the web UI rendering component. When a notebook cell creates a
# Bond via @bind w BoundSlider(2:20), the coordinator renders this @island
# for the web UI.
#
# WASM signal drives instant value display (no server round-trip).
# Server bridge (JS oninput → TherapyWS) handles re-execution of
# downstream cells. Later: bridge gets replaced by in-browser Julia WASM
# once channel.send() is implemented.
#
# Architecture:
#   BoundSlider @island
#     └── create_signal(value)     ← WASM, permanent
#     └── on_input → set_signal()  ← WASM, permanent (instant display update)
#     └── Span(signal)             ← WASM, no server round-trip
#     └── Bridge: signal → computation
#          ├── NOW: JS oninput → TherapyWS → server re-executes dependents
#          └── LATER: WASM send() → in-browser Julia WASM runtime
#
# Note: This file is loaded by Therapy's load_app!() into Therapy's module
# scope, so all Therapy functions (@island, create_signal, etc.) are already
# available — no `using Therapy:` needed.

@island function BoundSlider(; min_val=0, max_val=100, value=50, step_val=1, var_name="x")
    current, set_current = create_signal(Int32(value))

    Div(:style => "display:flex;align-items:center;gap:12px;padding:8px 0;",
        # Variable name label (static after SSR — doesn't change at runtime)
        Span(:style => "font-size:13px;font-family:'JetBrains Mono',ui-monospace,monospace;color:#6b7d93;",
            string(var_name), " = "),
        # Range input — WASM on_input handler updates the signal instantly
        Input(:type => "range",
            :min => string(min_val),
            :max => string(max_val),
            :step => string(step_val),
            :value => string(value),
            :style => "flex:1;max-width:300px;accent-color:#56d4a0;cursor:pointer;",
            :on_input => () -> set_current(unsafe_trunc(Int32, get_target_value_f64()))),
        # Value display — driven by WASM signal (instant, no server round-trip)
        Span(:style => "font-size:13px;font-family:'JetBrains Mono',ui-monospace,monospace;color:#56d4a0;min-width:2em;text-align:right;",
            current))
end
