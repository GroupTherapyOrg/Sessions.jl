# NotebookSignals.jl — page-level reactive state, shared across @islands
#
# Each `const` here defines a (getter, setter) tuple from `create_signal`.
# Any @island that destructures one of these consts gets a "shared signal"
# (Therapy compiler tags `shared_name = <field name in closure>`). At
# runtime the WASM compiler emits `window.__therapy.reg/set` wiring per
# Therapy's nanostores-style cross-island pub/sub (battle-tested pattern,
# same as Astro Islands).
#
# WS bridge (Notebook.jl) calls `window.__therapy.set('<name>', value)`
# on every server event. All islands subscribed to that name re-render
# automatically — no per-island on_mount listeners, no manual flush.
#
# CONVENTION: const is named `sig_<name>`. @islands MUST destructure
# with the bare name so the closure field name (= shared_name) matches
# what the WS bridge sets:
#
#     # NotebookSignals.jl
#     const sig_is_executing = create_signal(0)
#
#     # Some @island
#     is_executing, _ = sig_is_executing      # shared_name = "is_executing"
#     create_effect(() -> ...is_executing()...)
#
#     # Notebook.jl WS bridge JS
#     window.__therapy.set("is_executing", 1)
#
# Per-cell state (cell_state, runtime, stale-class) does NOT live here —
# each CellView @island owns its own private signals. The WS bridge
# locates the right island by `[data-cell-id]` selector and pokes the
# island's _wasmExports directly (the same pattern Therapy's HMR uses).

using Therapy

# ── Toolbar / global state ─────────────────────────────────────────

# Whether the worker is currently executing any cell. 0/1 (Bool encoded
# as i32 — Therapy's WASM signals are scalar; we keep type simple).
const sig_is_executing = create_signal(0)

# Whether the buffer has unsaved edits.
const sig_is_unsaved = create_signal(0)

# Run-progress pill. (current / total) — split into two scalar signals
# rather than a tuple because Therapy WASM signals are single-value.
const sig_run_progress_current = create_signal(0)
const sig_run_progress_total = create_signal(0)

# Number of stale cells (cells whose source has changed since last run
# OR which have never been run with non-empty code). Drives the
# "Run stale (N)" toolbar badge.
const sig_stale_count = create_signal(0)

# Total cell count in the active notebook — drives the footer pill.
const sig_total_cells = create_signal(0)

# Cell currently executing (UUID string), 0 = none. Used by the
# "Jump to running cell" affordance.
# Encoded as the cell index (1-based) for now since externref signals
# require an extra hop and we mostly just need "is anything running".
const sig_running_cell_index = create_signal(0)
