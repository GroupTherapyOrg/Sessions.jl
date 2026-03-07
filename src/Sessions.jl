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
export load_notebook, save_notebook, parse_notebook, serialize_notebook, is_notebook_file

include("analysis.jl")
export analyze_cell, cell_definitions, cell_references, build_topology, execution_order, downstream_dependents

include("bind.jl")
export AbstractWidget, Slider, TextField, CheckBox, Select, NumberField, Button, CounterButton
export Bond, @bind, set_bond_value!, initial_value, possible_values, validate_value

include("kernel.jl")
export Workspace, execute_cell!, execute_notebook!, execute_changed!
export classify_output, text_representation
export format_error, format_cell_error

include("run.jl")

include("session.jl")
export session_path, save_session!, load_session, apply_session!, load_notebook_with_session

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

# Layer 2: Watcher (needed by TUI app for DebouncedWatcher type)
include("watcher.jl")

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
        build_topology(_pc_nb)
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
    # Patch read_event — convert Ctrl+C (byte 0x03) from :ctrl_c to :ctrl+'c'
    # so it reaches our app's update! instead of being intercepted by Tachikoma's
    # hardcoded quit handler. Our app uses Ctrl+Q for quit and Ctrl+C for copy.
    @eval function Tachikoma.read_event()
        io = Tachikoma._input_io()
        bytesavailable(io) == 0 && return Tachikoma.KeyEvent(:unknown)
        byte = read(io, UInt8)
        byte == 0x1b && return Tachikoma.read_escape()
        byte == 0x0d && return Tachikoma.KeyEvent(:enter)
        byte == 0x7f && return Tachikoma.KeyEvent(:backspace)
        byte == 0x08 && return Tachikoma.KeyEvent(:backspace)
        byte == 0x09 && return Tachikoma.KeyEvent(:tab)
        byte == 0x03 && return Tachikoma.KeyEvent(:ctrl, 'c')  # NOT :ctrl_c — we handle quit ourselves
        byte < 0x20  && return Tachikoma.KeyEvent(:ctrl, Char(byte + 0x60))
        return Tachikoma.KeyEvent(Char(byte))
    end

    # Patch read_escape to handle Meta key sequences (ESC+letter)
    # Option+Left sends ESC b, Option+Right sends ESC f on macOS legacy terminals
    @eval function Tachikoma.read_escape()
        b = Tachikoma.read_byte(0.05)
        if b === nothing
            time() - Tachikoma._STARTUP_TIME[] < 1.0 && return Tachikoma.KeyEvent(:unknown)
            return Tachikoma.KeyEvent(:escape)
        end
        b == UInt8('[') && return Tachikoma.read_csi()
        b == UInt8('O') && return Tachikoma.read_ss3()
        if b in (UInt8('_'), UInt8('P'), UInt8(']'), UInt8('^'), UInt8('X'))
            Tachikoma._consume_until_st()
            return Tachikoma.KeyEvent(:unknown)
        end
        b == 0x1b && return Tachikoma.read_escape()
        # Meta key sequences — Option+Arrow on macOS sends ESC b / ESC f
        b == UInt8('b') && return Tachikoma.KeyEvent(:alt_left)
        b == UInt8('f') && return Tachikoma.KeyEvent(:alt_right)
        b == UInt8('d') && return Tachikoma.KeyEvent(:alt_delete)
        b == 0x7f       && return Tachikoma.KeyEvent(:alt_backspace)
        return Tachikoma.KeyEvent(:unknown)
    end

    # Patch parse_kitty_key — keep super (Cmd) separate from ctrl
    @eval function Tachikoma.parse_kitty_key(params::Vector{UInt8})
        str = String(copy(params))
        parts = Base.split(str, ';')
        keycode_parts = Base.split(parts[1], ':')
        keycode = tryparse(Int, keycode_parts[1])
        keycode === nothing && return Tachikoma.KeyEvent(:unknown)
        shifted_keycode = length(keycode_parts) >= 2 ? tryparse(Int, keycode_parts[2]) : nothing
        raw_mod = 1; event_type = 1
        if length(parts) >= 2
            mod_parts = Base.split(parts[2], ':')
            !isempty(mod_parts[1]) && (raw_mod = something(tryparse(Int, mod_parts[1]), 1))
            length(mod_parts) >= 2 && (event_type = something(tryparse(Int, mod_parts[2]), 1))
        end
        mod_bits = raw_mod - 1
        shift = (mod_bits & 1) != 0
        alt   = (mod_bits & 2) != 0
        ctrl  = (mod_bits & 4) != 0
        super = (mod_bits & 8) != 0   # Cmd on macOS — kept separate
        action = event_type == 2 ? Tachikoma.key_repeat : event_type == 3 ? Tachikoma.key_release : Tachikoma.key_press
        effective_keycode = (shift && shifted_keycode !== nothing && shifted_keycode > 0) ?
                            shifted_keycode : keycode
        return Tachikoma._kitty_keycode_to_event(effective_keycode, shift, alt, ctrl, super, action)
    end

    @eval function Tachikoma._kitty_keycode_to_event(
            keycode::Int, shift::Bool, alt::Bool, ctrl::Bool, super::Bool,
            action::Tachikoma.KeyAction)
        # Modified Enter
        if (ctrl || super) && !alt && keycode == 13
            return Tachikoma.KeyEvent(shift ? :shift_ctrl_enter : :ctrl_enter, action)
        end

        # Navigation keys (arrows, home, end)
        _nav_map = Dict(
            57350 => :left, 57351 => :right, 57352 => :up, 57353 => :down,
            57356 => :home, 57357 => :end_key
        )
        nav = get(_nav_map, keycode, nothing)
        if nav !== nothing
            # Super (Cmd) + nav → Home/End (macOS standard: Cmd+Left = line start)
            if super && !ctrl
                if nav in (:left, :up, :home)
                    return Tachikoma.KeyEvent(shift ? :shift_home : :home, action)
                else
                    return Tachikoma.KeyEvent(shift ? :shift_end : :end_key, action)
                end
            end
            # Alt (Option) + nav → word jump (macOS standard: Opt+Left = word left)
            if alt && !ctrl && !super
                sym = if shift
                    nav == :left ? :alt_shift_left : nav == :right ? :alt_shift_right :
                    nav == :up ? :shift_up : :shift_down
                else
                    nav == :left ? :alt_left : nav == :right ? :alt_right :
                    nav == :up ? :up : :down
                end
                return Tachikoma.KeyEvent(sym, action)
            end
            # Ctrl/Shift + nav → existing behavior
            if shift || ctrl
                sym = if shift && ctrl
                    nav == :left ? :ctrl_shift_left : nav == :right ? :ctrl_shift_right :
                    nav == :up ? :ctrl_shift_up : nav == :down ? :ctrl_shift_down :
                    nav == :home ? :ctrl_shift_home : :ctrl_shift_end
                elseif shift
                    nav == :left ? :shift_left : nav == :right ? :shift_right :
                    nav == :up ? :shift_up : nav == :down ? :shift_down :
                    nav == :home ? :shift_home : :shift_end
                else  # ctrl only
                    nav == :left ? :ctrl_left : nav == :right ? :ctrl_right :
                    nav == :up ? :ctrl_up : nav == :down ? :ctrl_down :
                    nav == :home ? :ctrl_home : :ctrl_end
                end
                return Tachikoma.KeyEvent(sym, action)
            end
        end

        # Super (Cmd) + letter → :ctrl + letter (Cmd+S=save, Cmd+C=copy, Cmd+V=paste)
        if super && !ctrl && !alt && !shift && keycode >= Int('a') && keycode <= Int('z')
            return Tachikoma.KeyEvent(:ctrl, Char(keycode), action)
        end

        # Ctrl+letter combinations (including Ctrl+C → :ctrl+'c', NOT :ctrl_c)
        if ctrl && !alt && !super
            if keycode == Int(' ') && !shift
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
        if shift && !alt && !ctrl && !super && keycode == 9
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

    # Patch csi_to_key — extract modifiers, separate super from ctrl for nav keys
    # e.g., ESC[1;2A = Shift+Up, ESC[1;5C = Ctrl+Right, ESC[1;9D = Cmd+Left → Home
    @eval function Tachikoma.csi_to_key(params::Vector{UInt8}, final::Char)
        # Kitty keyboard protocol: CSI ... u
        final == 'u' && return Tachikoma.parse_kitty_key(params)
        # SGR mouse
        if !isempty(params) && params[1] == UInt8('<') && (final == 'M' || final == 'm')
            return Tachikoma.parse_sgr_mouse(params, final)
        end

        # Extract modifiers from CSI params (format: [num;]modifier[:event_type])
        action = Tachikoma.key_press
        shift = false; ctrl = false; alt = false; super = false
        str = String(copy(params))
        parts = Base.split(str, ';')
        if length(parts) >= 2
            mod_str = parts[end]
            mod_parts = Base.split(mod_str, ':')
            raw_mod = something(tryparse(Int, mod_parts[1]), 1)
            mod_bits = raw_mod - 1
            shift = (mod_bits & 1) != 0
            alt   = (mod_bits & 2) != 0
            ctrl  = (mod_bits & 4) != 0
            super = (mod_bits & 8) != 0   # Cmd on macOS — kept separate
            if length(mod_parts) >= 2
                et = something(tryparse(Int, mod_parts[2]), 1)
                action = et == 2 ? Tachikoma.key_repeat : et == 3 ? Tachikoma.key_release : Tachikoma.key_press
            end
        else
            action = Tachikoma._extract_action_from_params(params)
        end

        # Arrow/nav keys with modifier support
        if final in ('A', 'B', 'C', 'D', 'H', 'F')
            base = final == 'A' ? :up : final == 'B' ? :down :
                   final == 'C' ? :right : final == 'D' ? :left :
                   final == 'H' ? :home : :end_key

            # Super (Cmd) + arrow → Home/End (macOS standard)
            if super && !ctrl
                if base in (:left, :up, :home)
                    return Tachikoma.KeyEvent(shift ? :shift_home : :home, action)
                else
                    return Tachikoma.KeyEvent(shift ? :shift_end : :end_key, action)
                end
            end

            # Alt (Option) + arrow → word jump (macOS standard)
            if alt && !ctrl && !super
                sym = if shift
                    base == :left ? :alt_shift_left : base == :right ? :alt_shift_right :
                    base == :up ? :shift_up : :shift_down
                else
                    base == :left ? :alt_left : base == :right ? :alt_right :
                    base == :up ? :up : :down
                end
                return Tachikoma.KeyEvent(sym, action)
            end

            # Ctrl/Shift modifiers (existing behavior)
            if shift || ctrl
                sym = if shift && ctrl
                    base == :left ? :ctrl_shift_left : base == :right ? :ctrl_shift_right :
                    base == :up ? :ctrl_shift_up : base == :down ? :ctrl_shift_down :
                    base == :home ? :ctrl_shift_home : :ctrl_shift_end
                elseif shift
                    base == :left ? :shift_left : base == :right ? :shift_right :
                    base == :up ? :shift_up : base == :down ? :shift_down :
                    base == :home ? :shift_home : :shift_end
                else  # ctrl only
                    base == :left ? :ctrl_left : base == :right ? :ctrl_right :
                    base == :up ? :ctrl_up : base == :down ? :ctrl_down :
                    base == :home ? :ctrl_home : :ctrl_end
                end
                return Tachikoma.KeyEvent(sym, action)
            end
            return Tachikoma.KeyEvent(base, action)
        end

        final == 'Z' && return Tachikoma.KeyEvent(:backtab, action)
        final == 'P' && return Tachikoma.KeyEvent(:f1, action)
        final == 'Q' && return Tachikoma.KeyEvent(:f2, action)
        final == 'R' && return Tachikoma.KeyEvent(:f3, action)
        final == 'S' && return Tachikoma.KeyEvent(:f4, action)
        if final == '~' && !isempty(params)
            n = Tachikoma.parse_csi_num(params)
            n == 2  && return Tachikoma.KeyEvent(:insert, action)
            n == 3  && return Tachikoma.KeyEvent(:delete, action)
            n == 5  && return Tachikoma.KeyEvent(:pageup, action)
            n == 6  && return Tachikoma.KeyEvent(:pagedown, action)
            n == 11 && return Tachikoma.KeyEvent(:f1, action)
            n == 12 && return Tachikoma.KeyEvent(:f2, action)
            n == 13 && return Tachikoma.KeyEvent(:f3, action)
            n == 14 && return Tachikoma.KeyEvent(:f4, action)
            n == 15 && return Tachikoma.KeyEvent(:f5, action)
            n == 17 && return Tachikoma.KeyEvent(:f6, action)
            n == 18 && return Tachikoma.KeyEvent(:f7, action)
            n == 19 && return Tachikoma.KeyEvent(:f8, action)
            n == 20 && return Tachikoma.KeyEvent(:f9, action)
            n == 21 && return Tachikoma.KeyEvent(:f10, action)
            n == 23 && return Tachikoma.KeyEvent(:f11, action)
            n == 24 && return Tachikoma.KeyEvent(:f12, action)
        end
        Tachikoma._log_unknown_csi(params, final)
        return Tachikoma.KeyEvent(:unknown)
    end
end

end # module
