# Notebook.jl — Notebook cell rendering
#
# In LIVE IDE mode: cells are rendered server-side via Sessions.render_cell()
# and managed by imperative JS (CM init, WS output injection, state updates).
# This JS lives in Layout.jl as a global script since it manipulates
# existing DOM elements by data-cell-id attributes.
#
# In PUBLISHED mode (future): this becomes a standalone @island with
# all cell signals/memos/effects compiled to JS via JST. The @bind
# widgets drive signal setters, dependent cells recompute via create_memo,
# and outputs render via create_effect. This is the "publishable unit"
# that Sessions.export() will extract.
#
# Architecture decision: the live IDE does NOT use signals for per-cell
# state. The WS handler directly patches DOM (proven fast, simpler than
# maintaining 50+ signals for 50 cells). Signals are used for structural
# UI (panel toggles, toolbar state, theme) via the @island components.
#
# When the export pipeline is built, Notebook.jl will gain:
#   @island function Notebook(; cells_json::String="[]", mode::String="published")
#     ... For(cells) do cell ... end
#     ... on_mount for @bind signal wiring
#   end
#
# For now, cell rendering is handled by NotebookPanel.jl calling
# Sessions.render_cell() and Sessions.CellGap() in a server-side loop.
