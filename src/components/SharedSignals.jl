# SharedSignals.jl — Cross-island shared signals + shared constants
#
# Module-level signal TUPLES captured by multiple @island components.
# Each @island destructures: `getter, setter = signal_tuple`
# The WasmTarget compiler detects shared bindings and emits WASM globals
# keyed by the const name, so all islands sharing a signal stay in sync.

using Therapy: create_signal

# ═══════════════════════════════════════════════════════════
# localStorage keys — single source of truth
# Used by: Layout.jl, StatusBar.jl, ActivityBar.jl, SessionsApp.jl, ReplPanel.jl
# ═══════════════════════════════════════════════════════════
const LS_THEME    = "sessions-theme"
const LS_SIDEBAR  = "sessions-sidebar"
const LS_TERMINAL = "sessions-repl"

# ═══════════════════════════════════════════════════════════
# Shared signals
# ═══════════════════════════════════════════════════════════

# Panel visibility (ActivityBar ↔ FileExplorer, ActivityBar ↔ Terminal)
const sidebar_signal = create_signal(Int32(0))
const terminal_signal = create_signal(Int32(0))

# Notebook state (Notebook ↔ StatusBar)
const cellcount_signal = create_signal(Int32(0))

# Connection status (StatusBar polls WS state)
const connection_signal = create_signal(Int32(1))
