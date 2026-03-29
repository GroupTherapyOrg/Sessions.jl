# SharedSignals.jl — Cross-island shared signals
#
# Module-level signal TUPLES captured by multiple @island components.
# Each @island destructures: `getter, setter = signal_tuple`
# The compiler emits __t.shared("getter_name", initial) so all islands
# reading the same signal stay in sync automatically.
#
# This follows the exact pattern from Therapy.jl's DarkModeToggle example:
#   const dark_mode = create_signal(0)   ← module level tuple
#   @island function Toggle()
#       is_dark, set_dark = dark_mode    ← destructure inside @island
#   end

using Therapy: create_signal

# Panel visibility (ActivityBar ↔ FileExplorer, ActivityBar ↔ Terminal)
const sidebar_signal = create_signal(0)
const terminal_signal = create_signal(0)

# Notebook state (Notebook ↔ StatusBar)
const cellcount_signal = create_signal(0)

# Connection status (StatusBar polls WS state)
const connection_signal = create_signal(1)  # 1=connected, 0=disconnected
