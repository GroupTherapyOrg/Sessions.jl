module Sessions

# Sessions.jl v2 — Terminal-Native Reactive Julia Notebook
# Built on Tachikoma.jl (TUI framework)
# NO browser dependencies (Therapy.jl, Suite.jl, HTTP.jl)

# Dependencies will be added as stories are implemented:
# - Tachikoma.jl (TUI)
# - ExpressionExplorer.jl (reactive analysis)
# - PlutoDependencyExplorer.jl (topological sort)
# - UUIDs (cell identifiers)
# - FileWatching (agent integration)
# - OrderedCollections (ordered cell storage)

using UUIDs
import Tachikoma

# Debug logging (enable with SESSIONS_DEBUG=1)
include("debug_log.jl")

# Layer 1: Engine
include("types.jl")
include("format.jl")

export CellState, cell_idle, cell_queued, cell_running, cell_done, cell_errored
export CellOutput, Cell, Notebook
export add_cell!, insert_cell!, remove_cell!, get_cell, ordered_cells, swap_cell_up!, swap_cell_down!
export source_hash, is_stale, is_never_run, stale_cells, never_run_cells, mark_executed!
export load_notebook, save_notebook, parse_notebook, serialize_notebook, is_notebook_file

include("analysis.jl")
export analyze_cell, cell_definitions, cell_references, update_topology!, execution_order, downstream_dependents

include("bind.jl")
# Widget types (Slider, Button, etc.) are engine internals — NOT exported.
# Users interact via SessionsUI's Bound* wrappers (BoundSlider, etc.).
# The TUI kernel injects widget types directly into workspace modules.
export Bond, set_bond_value!, initial_value, possible_values, validate_value

include("kernel.jl")
export Workspace, execute_cell!, execute_notebook!, execute_changed!
export classify_output, text_representation
export format_error, format_cell_error, build_structured_error
export StructuredFrame, StructuredError

include("png_decoder.jl")
export decode_png

include("jpeg_decoder.jl")
export decode_jpeg

include("run.jl")

include("session.jl")

# Layer 1.5: Web Export (types, execution pipeline, stubs for rendering)
# Rendering to VNodes is provided by ext/SessionsTherapyExt when Therapy.jl is loaded.
include("web.jl")
export PrerenderedGallery, execute_notebook_for_web, NotebookPage, notebook_title
export session_path, save_session!, load_session, apply_session!, load_notebook_with_session

# Layer 1.5: PTY (standalone pseudo-terminal for web terminal)
include("pty.jl")
export PTY, pty_spawn, pty_write, pty_resize!, pty_close!, pty_alive

# Layer 1.5: File Watcher (needed by web_server.jl for DebouncedWatcher)
include("watcher.jl")

# Layer 1.5: Notebook Worker (Malt.jl per-notebook process)
include("worker/notebook_worker.jl")
export NotebookWorker, remote_execute_cell!, stop_worker!, restart_worker!, is_worker_alive

# Layer 1.5: Web Server (channel handlers for web UI)
include("web_server.jl")
export WebTab, WebNotebookState, active_tab, active_nb, active_worker
export setup_web_notebook!, send_full_state!, create_cell_signals!, start_web_watchers!
export setup_file_explorer!
export FileNode, _build_file_tree

# Layer 1.5: Terminal Server (xterm.js ↔ PTY bridge)
include("terminal_server.jl")
export TerminalTab, TerminalState, setup_terminal!, stop_all_terminals!

# Layer 1.5: Static Analysis (JET.jl + JETLS LSP)
include("jet_analysis.jl")
export Diagnostic, CellDiagnostics, analyze_cell_jet, analyze_notebook_jet, total_diagnostics, cell_diagnostics

include("lsp_client.jl")
export LspClient, LspDiagnostic, LspStatus, lsp_off, lsp_starting, lsp_ready, lsp_error
export start_lsp!, stop_lsp!, lsp_sync_notebook!, lsp_did_save!, lsp_cell_diagnostics
export LspCompletionItem, parse_completions, lsp_completion!, lsp_complete_with_timeout!
export LspHoverResult, parse_hover, lsp_hover!, lsp_hover_with_timeout!
export LspLocation, parse_definition, lsp_definition!, lsp_definition_with_timeout!
export LspSignatureHelp, parse_signature_help, lsp_signature_help!, lsp_signature_help_with_timeout!
export LspTextEdit, parse_workspace_edit, lsp_rename!, lsp_rename_with_timeout!

# Layer 1.5: Code Formatting (Runic.jl runtime-loaded)
include("formatting.jl")
export format_code, format_code_available

# Layer 2: Watcher already included above (before web_server.jl)

# Layer 2: TUI
include("tui/theme.jl")
include("tui/cell_widget.jl")
include("tui/output_widget.jl")
include("tui/notebook_view.jl")
include("tui/file_editor_view.jl")
include("tui/status_bar.jl")
include("tui/file_panel.jl")
include("tui/activity_bar.jl")
include("tui/tab_bar.jl")
include("tui/repl_panel.jl")
include("tui/diagnostics_panel.jl")
include("tui/app.jl")

# Layer 3: CLI
include("cli.jl")

# Precompilation workload
using PrecompileTools

@setup_workload begin
    _pc_source = """### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 00000001-0000-0000-0000-000000000001
x = 1 + 1

# ╔═╡ 00000002-0000-0000-0000-000000000002
y = x * 2

# ╔═╡ Cell order:
# ╠═00000001-0000-0000-0000-000000000001
# ╠═00000002-0000-0000-0000-000000000002
"""
    @compile_workload begin
        _pc_nb = parse_notebook(_pc_source; path="precompile.jl")
        serialize_notebook(_pc_nb)
        analyze_cell(_pc_nb.cells[_pc_nb.cell_order[1]])
        update_topology!(_pc_nb)
        execution_order(_pc_nb)
        source_hash(_pc_nb.cells[_pc_nb.cell_order[1]])
        is_stale(_pc_nb.cells[_pc_nb.cell_order[1]])
        classify_output(2)
        text_representation(2)
        # Note: Workspace/execute_cell! cannot be precompiled (uses eval in dynamic Module)
    end
end

# ── Monkey-patch: Kitty protocol extensions ───
# 1. Add :shift_enter / :ctrl_enter
# 2. Separate super (Cmd) from ctrl: Cmd+Arrow → Home/End, Cmd+letter → :ctrl+letter
# 3. Alt/Option+Arrow → :alt_left/:alt_right (word jump on macOS)
# 4. ESC b / ESC f (Meta sequences from Option+Arrow on legacy terminals)
# 5. Modified arrow/nav keys: :shift_left, :ctrl_right, :ctrl_shift_left, etc.
# 6. CSI arrow sequences with modifiers (ESC[1;2A = Shift+Up, etc.)
# Must live in __init__ because Julia 1.12 forbids method overwriting
# during precompilation.
function __init__()
    # Re-register islands into Therapy's ISLAND_REGISTRY at runtime
    # (precompilation doesn't persist cross-module Dict mutations)
    for name in (:CellToggle, :WebSlider, :BoundValue)
        if isdefined(@__MODULE__, name)
            island = getfield(@__MODULE__, name)
            if island isa Therapy.IslandDef
                Therapy.ISLAND_REGISTRY[island.name] = island
            end
        end
    end

    # TUI keyboard patches removed — they live in the TUI app layer, not the core module.
    # The web UI fork doesn't need Tachikoma monkey-patching.
end

end # module
