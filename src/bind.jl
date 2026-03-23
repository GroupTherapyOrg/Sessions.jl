# bind.jl — Re-exports from SessionsUI
#
# All widget types, bond registry, and @bind macro live in SessionsUI
# (zero-dep package for notebook users). Sessions.jl re-exports them
# so internal code can reference Sessions.Bond, Sessions._BOND_REGISTRY, etc.

using SessionsUI

# Re-export everything Sessions internals need
using SessionsUI: AbstractWidget, initial_value, possible_values, validate_value
using SessionsUI: Slider, NumberField, Button, CounterButton, CheckBox, TextField, Select
using SessionsUI: Bond, set_bond_value!, get_bond_names
using SessionsUI: _BOND_REGISTRY, _CELL_BOND_NAMES, _EXECUTING_CELL_ID
using SessionsUI: _register_bond!, _bond_cell_id, _clear_bonds!, _slider_index
using SessionsUI: closest, downsample
