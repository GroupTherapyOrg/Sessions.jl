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

# Layer 1: Engine
include("types.jl")
include("format.jl")

export CellState, cell_idle, cell_queued, cell_running, cell_done, cell_errored
export CellOutput, Cell, Notebook
export add_cell!, insert_cell!, remove_cell!, get_cell, ordered_cells, swap_cell_up!, swap_cell_down!
export source_hash, is_stale, is_never_run, stale_cells, never_run_cells, mark_executed!
export load_notebook, save_notebook, parse_notebook, serialize_notebook

include("analysis.jl")
export analyze_cell, cell_definitions, cell_references, build_topology, execution_order, downstream_dependents

include("kernel.jl")
export Workspace, execute_cell!, execute_notebook!, execute_changed!
export classify_output, text_representation
export format_error, format_cell_error

include("run.jl")

include("session.jl")
export session_path, save_session!, load_session, apply_session!

# Layer 2: TUI
include("tui/theme.jl")
include("tui/cell_widget.jl")
include("tui/output_widget.jl")
include("tui/status_bar.jl")
include("tui/notebook_view.jl")
include("tui/file_panel.jl")
include("tui/activity_bar.jl")
include("tui/app.jl")

# Layer 3: CLI
include("cli.jl")
include("watcher.jl")

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
        build_topology(_pc_nb)
        execution_order(_pc_nb)
        source_hash(_pc_nb.cells[_pc_nb.cell_order[1]])
        is_stale(_pc_nb.cells[_pc_nb.cell_order[1]])
        classify_output(2)
        text_representation(2)
        # Note: Workspace/execute_cell! cannot be precompiled (uses eval in dynamic Module)
    end
end

# ── Monkey-patch: add :shift_enter / :ctrl_enter to Kitty protocol ───
# Tachikoma v1.0.3 discards shift/ctrl modifiers for Enter (keycode 13).
# Must live in __init__ because Julia 1.12 forbids method overwriting
# during precompilation.
function __init__()
    @eval function Tachikoma._kitty_keycode_to_event(
            keycode::Int, shift::Bool, alt::Bool, ctrl::Bool,
            action::Tachikoma.KeyAction)
        if ctrl && !alt && keycode == 13
            return Tachikoma.KeyEvent(shift ? :shift_ctrl_enter : :ctrl_enter, action)
        end
        if ctrl && !alt
            if keycode == Int('c') && !shift
                return Tachikoma.KeyEvent(:ctrl_c, action)
            elseif keycode == Int(' ') && !shift
                return Tachikoma.KeyEvent(:ctrl_space, action)
            elseif !shift && keycode >= Int('a') && keycode <= Int('z')
                return Tachikoma.KeyEvent(:ctrl, Char(keycode), action)
            elseif !shift
                ctrl_byte = get(Tachikoma._CTRL_KEYCODE_TO_BYTE, keycode, nothing)
                if ctrl_byte !== nothing
                    mapped = ctrl_byte == 0x00 ? '\0' : Char(ctrl_byte + 0x60)
                    return Tachikoma.KeyEvent(:ctrl, mapped, action)
                end
            end
        end
        if shift && !alt && !ctrl && keycode == 9
            return Tachikoma.KeyEvent(:backtab, action)
        end
        if shift && !ctrl && !alt && keycode == 13
            return Tachikoma.KeyEvent(:shift_enter, action)
        end
        sym = get(Tachikoma.KITTY_FUNCTIONAL_KEYS, keycode, nothing)
        sym !== nothing && return Tachikoma.KeyEvent(sym, action)
        keycode == 27  && return Tachikoma.KeyEvent(:escape, action)
        keycode == 13  && return Tachikoma.KeyEvent(:enter, action)
        keycode == 9   && return Tachikoma.KeyEvent(:tab, action)
        keycode == 127 && return Tachikoma.KeyEvent(:backspace, action)
        if keycode >= 32 && keycode <= 0x10FFFF
            c = Char(keycode)
            if shift && !ctrl && !alt
                c = c >= 'a' && c <= 'z' ? uppercase(c) : get(Tachikoma._SHIFT_SYMBOL_MAP, c, c)
            end
            isvalid(c) && return Tachikoma.KeyEvent(:char, c, action)
        end
        return Tachikoma.KeyEvent(:unknown, action)
    end
end

end # module
