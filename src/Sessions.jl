module Sessions

# Sessions.jl — Web-Native Reactive Julia Notebook
# Web UI via Therapy.jl + xterm.js + Shoelace + CodeMirror
# Execution via Malt.jl workers, PTY terminals, Therapy.jl @islands

using UUIDs

# Debug logging (enable with SESSIONS_DEBUG=1)
include("debug_log.jl")

# Layer 1: Engine
include("color.jl")
export ColorRGB

include("types.jl")
include("format.jl")

export CellState, cell_idle, cell_queued, cell_running, cell_done, cell_errored
export LogRecord, CellOutput, Cell, Notebook
export add_cell!, insert_cell!, remove_cell!, get_cell, ordered_cells, swap_cell_up!, swap_cell_down!, reorder_cell!
export source_hash, is_stale, is_never_run, stale_cells, never_run_cells, mark_executed!
export load_notebook, save_notebook, parse_notebook, serialize_notebook, is_notebook_file

include("analysis.jl")
export analyze_cell, cell_definitions, cell_references, update_topology!, execution_order, downstream_dependents

include("bind.jl")
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

# CLI entry point (sessions command — uses @main for Pkg.Apps)
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

function __init__()
    # Re-register @islands into Therapy's ISLAND_REGISTRY at runtime
    # (precompilation doesn't persist cross-module Dict mutations)
    for name in (:CellToggle, :WebSlider, :BoundValue)
        if isdefined(@__MODULE__, name)
            island = getfield(@__MODULE__, name)
            if island isa Therapy.IslandDef
                Therapy.ISLAND_REGISTRY[island.name] = island
            end
        end
    end
end

end # module
