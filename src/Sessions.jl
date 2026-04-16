module Sessions

# Sessions.jl — Web-Native Reactive Julia Notebook
# Web UI via Therapy.jl + xterm.js + Shoelace + CodeMirror
# Execution via Malt.jl workers, PTY terminals, Therapy.jl @islands

using UUIDs

# Debug logging (enable with SESSIONS_DEBUG=1)
include("debug_log.jl")

# Layer 1: Engine
include("engine/color.jl")
export ColorRGB

include("engine/types.jl")
include("engine/format.jl")

export CellState, cell_idle, cell_queued, cell_running, cell_done, cell_errored
export LogRecord, CellOutput, Cell, Notebook
export add_cell!, insert_cell!, remove_cell!, get_cell, ordered_cells, swap_cell_up!, swap_cell_down!, reorder_cell!
export source_hash, is_stale, is_never_run, stale_cells, never_run_cells, mark_executed!
export load_notebook, save_notebook, parse_notebook, serialize_notebook, is_notebook_file

include("engine/analysis.jl")
export analyze_cell, cell_definitions, cell_references, update_topology!, execution_order, downstream_dependents

include("engine/bind.jl")
export Bond, set_bond_value!, initial_value, possible_values, validate_value

include("engine/kernel.jl")
export Workspace, execute_cell!, execute_notebook!, execute_changed!
export classify_output, text_representation
export format_error, format_cell_error, build_structured_error
export StructuredFrame, StructuredError

include("engine/output.jl")
export decode_png, decode_jpeg

include("engine/run.jl")

include("engine/session.jl")

# Layer 1.5: Web Islands (WASM-compiled @island components)
include("engine/islands.jl")

# Layer 1.5: Web Rendering (notebook → VNodes, static export pipeline)
include("engine/web_rendering.jl")
export notebook_title
export session_path, save_session!, load_session, apply_session!, load_notebook_with_session

# Services: PTY, Watcher
include("services/pty.jl")
export PTY, pty_spawn, pty_write, pty_resize!, pty_close!, pty_alive

include("services/watcher.jl")

# Layer 1.5: Notebook Worker (Malt.jl per-notebook process)
include("engine/worker/manager.jl")
export NotebookWorker, remote_execute_cell!, stop_worker!, restart_worker!, is_worker_alive

# Channels: WebSocket handlers (replaces web_server.jl)
include("channels/notebook.jl")
export WebTab, WebNotebookState, active_tab, active_nb, active_worker
export setup_notebook_channel!, send_full_state!, create_cell_signals!, start_web_watchers!

include("channels/files.jl")
export FileNode, _build_file_tree, setup_files_channel!

include("channels/terminal.jl")
export TerminalTab, TerminalState, setup_terminal_channel!, stop_all_terminals!

# Services: Static Analysis (JET.jl + JETLS LSP)
include("services/jet.jl")
export Diagnostic, CellDiagnostics, analyze_cell_jet, analyze_notebook_jet, total_diagnostics, cell_diagnostics

include("services/lsp.jl")
export LspClient, LspDiagnostic, LspStatus, lsp_off, lsp_starting, lsp_ready, lsp_error
export start_lsp!, stop_lsp!, lsp_sync_notebook!, lsp_did_save!, lsp_cell_diagnostics
export LspCompletionItem, parse_completions, lsp_completion!, lsp_complete_with_timeout!
export LspHoverResult, parse_hover, lsp_hover!, lsp_hover_with_timeout!
export LspLocation, parse_definition, lsp_definition!, lsp_definition_with_timeout!
export LspSignatureHelp, parse_signature_help, lsp_signature_help!, lsp_signature_help_with_timeout!
export LspTextEdit, parse_workspace_edit, lsp_rename!, lsp_rename_with_timeout!

# Services: Code Formatting (Runic.jl runtime-loaded)
include("services/formatter.jl")
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
    isdefined(Main, :Therapy) || return
    _Therapy = getfield(Main, :Therapy)
    isdefined(_Therapy, :IslandDef) || return
    _IslandDef = getfield(_Therapy, :IslandDef)
    _Registry = getfield(_Therapy, :ISLAND_REGISTRY)
    for name in (:CellToggle,)
        if isdefined(@__MODULE__, name)
            island = getfield(@__MODULE__, name)
            if island isa _IslandDef
                _Registry[island.name] = island
            end
        end
    end
end

end # module
