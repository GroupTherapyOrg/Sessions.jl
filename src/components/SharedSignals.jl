# SharedSignals.jl — Cross-island shared signals + shared constants
#
# Module-level `create_signal(...)` tuples captured by multiple @island
# components. Naming convention: `<name>_signal` (tuple); destructure as
# `name, set_name = <name>_signal` inside the @island body.
#
# Therapy's compiler detects shared bindings and (after the Stage-1
# compiler patch in Therapy.jl/src/Compiler/Compile.jl) wires them to
# `window.__therapy.reg / set / get` — the nanostores-style pub/sub
# runtime from SignalRuntime.jl. That makes cross-island reactivity
# actually work: any code can call `window.__therapy.set('<name>', v)`
# and every island subscribed to that signal re-renders. No manual
# on_mount listeners, no direct DOM mutation.
#
# The JS side (Sessions WS bridge) just needs to call
# `window.__therapy.set('<name>', value)` where `<name>` is the
# DESTRUCTURED variable name inside the @island — the closure field
# name is what the compiler tags as `shared_name`.

using Therapy: create_signal

# ═══════════════════════════════════════════════════════════
# localStorage keys — single source of truth
# Used by: Layout.jl, StatusBar.jl, ActivityBar.jl, SessionsApp.jl, ReplPanel.jl
# ═══════════════════════════════════════════════════════════
const LS_THEME    = "sessions-theme"
const LS_SIDEBAR  = "sessions-sidebar"
const LS_TERMINAL = "sessions-repl"

# ═══════════════════════════════════════════════════════════
# Shared signals — read by @island bodies, written by the WS bridge.
# ═══════════════════════════════════════════════════════════
#
# Panel visibility (sidebar/terminal) is handled by direct DOM +
# localStorage in SessionsApp.jl's IIFE, not by shared signals — see
# ActivityBar.jl for why.

# ── Notebook ─────────────────────────────────────────────────

# Whether the worker is currently executing any cell. 0/1 (Bool
# encoded as i32 — Therapy's WASM signals are scalar scoped).
# Read by: NotebookToolbar (pill-exec mode flip).
const is_executing_signal = create_signal(0)

# Whether the CodeMirror buffer has unsaved edits.
# Read by: NotebookToolbar (save indicator text + dot color).
const is_unsaved_signal = create_signal(0)

# Run-progress pill. Split into two scalars rather than a tuple because
# Therapy WASM signals hold single values. Read by: NotebookToolbar
# (progress bar fill + "N / M" label + visibility gate).
const run_progress_current_signal = create_signal(0)
const run_progress_total_signal   = create_signal(0)

# Number of stale cells (cells whose source changed since last run OR
# that have never been run but have non-empty code). Drives the
# "Run stale (N)" toolbar badge + the button's enabled state.
const stale_count_signal = create_signal(0)

# Total cell count in the active notebook.
# Read by: StatusBar (footer "N cells" label).
const cellcount_signal = create_signal(0)

# Connection status (WS open / closed / reconnecting).
# Read by: StatusBar (connected/disconnected dot + label).
const connection_signal = create_signal(1)

# Format-in-progress flag (Format button text + disabled state).
# Read by: NotebookToolbar.
const is_formatting_signal = create_signal(0)

# Whether the active tab is a file (1) or a notebook (0). Drives the
# notebook-controls visibility in NotebookToolbar (file tabs hide the
# Run all / Run stale / Stop pill; only Save + Format apply).
const active_is_file_signal = create_signal(0)

# Whether the active tab can be formatted (1 = yes, 0 = disabled).
# Notebooks: always 1. File tabs: only when JuliaFormatter recognises
# the extension. NotebookToolbar reflects this on the Format button.
const active_can_format_signal = create_signal(1)
