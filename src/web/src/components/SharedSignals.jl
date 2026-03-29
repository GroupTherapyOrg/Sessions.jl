# SharedSignals.jl — Cross-island shared signals
#
# Module-level signals captured by multiple @island components.
# When an @island captures these, the compiler emits __t.shared("name", initial)
# so all islands reading the same signal stay in sync automatically.
#
# This is the Therapy.jl equivalent of SolidJS nanostores or Astro shared state.

using Therapy: create_signal

# Panel visibility (ActivityBar ↔ FileExplorer, ActivityBar ↔ Terminal)
const sidebar_open, set_sidebar_open = create_signal(0)
const terminal_open, set_terminal_open = create_signal(0)

# Notebook state (Notebook ↔ StatusBar)
const cell_count, set_cell_count = create_signal(0)

# Connection status (StatusBar polls WS state)
const connection_status, set_connection_status = create_signal(1)  # 1=connected, 0=disconnected
