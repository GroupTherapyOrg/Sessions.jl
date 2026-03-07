# TUI: Cell editor widget — Pluto-style cell with hover controls

# ── Selection state ──────────────────────────────────────────────────

"""Tracks text selection within a cell's code editor."""
mutable struct SelectionState
    active::Bool
    anchor_row::Int   # row where selection started (1-based)
    anchor_col::Int   # col where selection started (0-based, like cursor_col)
end
SelectionState() = SelectionState(false, 1, 0)

# ── Clipboard ────────────────────────────────────────────────────────

const _CLIPBOARD = Ref("")
const _CLIPBOARD_DIRTY = Ref(false)  # true after internal copy (pbcopy may have failed)

function _clipboard_copy!(text::String)
    _CLIPBOARD[] = text
    _CLIPBOARD_DIRTY[] = true
    # Try pbcopy (may fail silently inside TUI — that's OK, we have _CLIPBOARD)
    try
        if Sys.isapple()
            open(`pbcopy`, "w") do io
                write(io, text)
            end
        end
    catch; end
end

function _clipboard_paste()::String
    if _CLIPBOARD_DIRTY[]
        # Last copy was internal — use our buffer (pbcopy may have failed)
        _CLIPBOARD_DIRTY[] = false
        return _CLIPBOARD[]
    end
    # No pending internal copy — try system clipboard (for external copies)
    try
        if Sys.isapple()
            sys = read(`pbpaste`, String)
            !isempty(sys) && return sys
        end
    catch; end
    return _CLIPBOARD[]
end

# ── Word boundary (matching Julia REPL.LineEdit is_non_word_char) ────

const _NON_WORD_CHARS = Set(collect(" \t\n\"\\'\`@\$><=:;|&{}()[].,+-*/?%^~"))
_is_non_word_char(c::Char) = c in _NON_WORD_CHARS

# ── Auto-close brackets ──────────────────────────────────────────────

const _BRACKET_PAIRS = Dict('(' => ')', '[' => ']', '{' => '}', '"' => '"')
const _CLOSE_BRACKETS = Set(values(_BRACKET_PAIRS))

"""
Handle auto-close bracket logic for a CodeEditor.
Returns true if the event was consumed, false if it should be passed through.
Only active in insert mode.
"""
function _handle_auto_close!(editor::Tachikoma.CodeEditor, evt)
    editor.mode == :insert || return false
    line = editor.lines[editor.cursor_row]

    # ── Opening bracket: insert pair, cursor between ──
    if evt.key == :char && haskey(_BRACKET_PAIRS, evt.char)
        close = _BRACKET_PAIRS[evt.char]
        # For quotes: skip-over if next char is the same quote
        if evt.char == '"' && editor.cursor_col < length(line) &&
                line[editor.cursor_col + 1] == '"'
            editor.cursor_col += 1
            return true
        end
        Tachikoma._push_undo!(editor; force=true)
        insert!(line, editor.cursor_col + 1, evt.char)
        insert!(line, editor.cursor_col + 2, close)
        editor.cursor_col += 1
        Tachikoma._mark_dirty!(editor, editor.cursor_row)
        Tachikoma._ensure_tokens!(editor)
        return true
    end

    # ── Closing bracket: skip-over if next char matches ──
    if evt.key == :char && evt.char in _CLOSE_BRACKETS && evt.char != '"'
        if editor.cursor_col < length(line) && line[editor.cursor_col + 1] == evt.char
            editor.cursor_col += 1
            return true
        end
    end

    # ── Backspace: delete both if cursor between matching pair ──
    if evt.key == :backspace && editor.cursor_col > 0 && editor.cursor_col < length(line)
        open_char = line[editor.cursor_col]
        close_char = line[editor.cursor_col + 1]
        if haskey(_BRACKET_PAIRS, open_char) && _BRACKET_PAIRS[open_char] == close_char
            Tachikoma._push_undo!(editor; force=true)
            deleteat!(line, editor.cursor_col + 1)  # delete close
            deleteat!(line, editor.cursor_col)       # delete open
            editor.cursor_col -= 1
            Tachikoma._mark_dirty!(editor, editor.cursor_row)
            Tachikoma._ensure_tokens!(editor)
            return true
        end
    end

    false
end

# ── CellWidget ───────────────────────────────────────────────────────

"""A cell widget combining a CodeEditor with state/output display."""
mutable struct CellWidget
    cell::Cell
    editor::Tachikoma.CodeEditor
    focused::Bool
    hovered::Bool    # Mouse is hovering over this cell (shows controls)
    collapsed::Bool  # Whether output is collapsed
    selected::Bool   # Whether this cell is part of multi-cell selection
    ellipsis_hovered::Bool  # Mouse hovering over ⋯ button
    selection::SelectionState
    diagnostics::Vector{Diagnostic}  # inline diagnostics (populated from LSP/JET)
end

function CellWidget(cell::Cell; focused::Bool=false)
    editor = Tachikoma.CodeEditor()
    Tachikoma.set_text!(editor, cell.code)
    editor.focused = false  # cursor hidden by default; app sets true only in insert mode
    CellWidget(cell, editor, focused, false, false, false, false, SelectionState(), Diagnostic[])
end

"""Sync editor text back to cell."""
function sync_to_cell!(cw::CellWidget)
    cw.cell.code = Tachikoma.text(cw.editor)
end

"""Sync cell code to editor (after external change)."""
function sync_from_cell!(cw::CellWidget)
    Tachikoma.set_text!(cw.editor, cw.cell.code)
end

"""Check if editor text differs from cell code (unsaved edits)."""
is_dirty(cw::CellWidget) = Tachikoma.text(cw.editor) != cw.cell.code

"""State indicator character and style for a cell."""
function state_indicator(cell::Cell)
    if cell.disabled
        return "⊘", Theme.S_DISABLED
    end
    tick = Theme.tick()
    if cell.state == cell_running
        b = Tachikoma.breathe(tick; period=45)
        fg = Tachikoma.color_lerp(Theme.ACCENT_DIM, Theme.ACCENT_GLOW, b)
        return "●", Tachikoma.Style(; fg)
    elseif cell.state == cell_queued
        return "◌", Theme.S_QUEUED
    elseif cell.state == cell_errored
        return "✗", Theme.S_ERRORED
    elseif is_stale(cell)
        return "○", Theme.S_STALE
    elseif is_never_run(cell)
        return "◌", Theme.S_NEVER_RUN
    elseif cell.state == cell_done
        return "●", Theme.S_DONE
    else
        return "○", Theme.S_NEVER_RUN
    end
end

"""Format runtime_ns to a human-readable string."""
function format_runtime(ns::UInt64)
    ns == 0 && return ""
    if ns < 1_000
        return "$(ns)ns"
    elseif ns < 1_000_000
        return "$(round(ns / 1_000; digits=1))µs"
    elseif ns < 1_000_000_000
        return "$(round(ns / 1_000_000; digits=1))ms"
    else
        return "$(round(ns / 1_000_000_000; digits=2))s"
    end
end

"""Height needed to render this cell widget.
When `has_output` is true and the cell is folded, the cell collapses to 0
so only the output is visible."""
function cell_height(cw::CellWidget; has_output::Bool=false)
    if cw.cell.folded
        return has_output ? 0 : 1
    end
    vi = Theme.CELL_V_INSET
    if cw.cell.disabled
        return 3 + 2 * vi
    end
    n_lines = count(==('\n'), cw.cell.code) + 1
    diag_lines = (cw.focused && !isempty(cw.diagnostics)) ? length(cw.diagnostics) : 0
    n_lines + diag_lines + 2 + 2 * vi  # +2 for border, +2*vi for vertical padding
end

Tachikoma.focusable(::CellWidget) = true

# ── Selection helpers ────────────────────────────────────────────────

"""Return normalized (start_row, start_col, end_row, end_col) for the selection."""
function _selection_range(sel::SelectionState, cursor_row::Int, cursor_col::Int)
    ar, ac = sel.anchor_row, sel.anchor_col
    cr, cc = cursor_row, cursor_col
    if ar < cr || (ar == cr && ac <= cc)
        return (ar, ac, cr, cc)
    else
        return (cr, cc, ar, ac)
    end
end

"""Extract the selected text as a String."""
function _selected_text(lines, sel::SelectionState, cursor_row::Int, cursor_col::Int)
    !sel.active && return ""
    sr, sc, er, ec = _selection_range(sel, cursor_row, cursor_col)
    if sr == er
        line = lines[sr]
        from = sc + 1  # 1-based
        to = min(ec, length(line))
        from > to && return ""
        return String(line[from:to])
    else
        parts = String[]
        push!(parts, String(lines[sr][sc+1:end]))
        for r in sr+1:er-1
            push!(parts, String(lines[r]))
        end
        push!(parts, String(lines[er][1:min(ec, length(lines[er]))]))
        return join(parts, '\n')
    end
end

"""Copy current selection to system clipboard if active."""
function _auto_copy_selection!(cw::CellWidget)
    sel = cw.selection
    !sel.active && return
    text = _selected_text(cw.editor.lines, sel, cw.editor.cursor_row, cw.editor.cursor_col)
    !isempty(text) && _clipboard_copy!(text)
end

"""Delete the selected text and position cursor at selection start."""
function _delete_selection!(cw::CellWidget)
    sel = cw.selection
    !sel.active && return
    editor = cw.editor
    Tachikoma._push_undo!(editor; force=true)
    sr, sc, er, ec = _selection_range(sel, editor.cursor_row, editor.cursor_col)

    if sr == er
        line = editor.lines[sr]
        to_del = min(ec, length(line))
        from_del = sc + 1
        if from_del <= to_del
            deleteat!(line, from_del:to_del)
        end
    else
        first_part = editor.lines[sr][1:sc]
        last_line = editor.lines[er]
        last_part = ec < length(last_line) ? last_line[ec+1:end] : Char[]
        editor.lines[sr] = vcat(first_part, last_part)
        if er > sr
            deleteat!(editor.lines, sr+1:er)
        end
    end

    editor.cursor_row = sr
    editor.cursor_col = sc
    sel.active = false
    editor.token_cache = [Tachikoma.tokenize_line(l) for l in editor.lines]
    empty!(editor.dirty_lines)
end

# ── Word motion (matching REPL.LineEdit char_move_word_left/right) ───

"""Move cursor left to previous word boundary (REPL two-phase algorithm)."""
function _word_left!(editor)
    row = editor.cursor_row
    col = editor.cursor_col
    lines = editor.lines

    # Phase 1: Skip non-word chars backward
    while true
        if col > 0
            c = lines[row][col]  # char to the left of cursor
            if !_is_non_word_char(c)
                break
            end
            col -= 1
        elseif row > 1
            row -= 1
            col = length(lines[row])
        else
            break
        end
    end

    # Phase 2: Skip word chars backward
    while col > 0
        c = lines[row][col]
        if _is_non_word_char(c)
            break
        end
        col -= 1
    end

    editor.cursor_row = row
    editor.cursor_col = col
end

"""Move cursor right to next word boundary (REPL two-phase algorithm)."""
function _word_right!(editor)
    row = editor.cursor_row
    col = editor.cursor_col
    lines = editor.lines
    n = length(lines[row])

    # Phase 1: Skip non-word chars forward
    while true
        if col < n
            c = lines[row][col + 1]  # char to the right of cursor
            if !_is_non_word_char(c)
                break
            end
            col += 1
        elseif row < length(lines)
            row += 1
            col = 0
            n = length(lines[row])
        else
            break
        end
    end

    # Phase 2: Skip word chars forward
    n = length(lines[row])
    while col < n
        c = lines[row][col + 1]
        if _is_non_word_char(c)
            break
        end
        col += 1
    end

    editor.cursor_row = row
    editor.cursor_col = col
end

"""Delete previous word (REPL edit_delete_prev_word / Meta+Backspace)."""
function _delete_prev_word!(cw::CellWidget)
    editor = cw.editor
    Tachikoma._push_undo!(editor; force=true)
    start_row = editor.cursor_row
    start_col = editor.cursor_col
    _word_left!(editor)
    end_row = editor.cursor_row
    end_col = editor.cursor_col
    # Temporarily set up selection to delete the range
    cw.selection.active = true
    cw.selection.anchor_row = start_row
    cw.selection.anchor_col = start_col
    # cursor is already at the word boundary (start of deleted range)
    _delete_selection_no_undo!(cw)  # we already pushed undo
end

"""Delete next word (REPL edit_delete_next_word / Meta+D)."""
function _delete_next_word!(cw::CellWidget)
    editor = cw.editor
    Tachikoma._push_undo!(editor; force=true)
    start_row = editor.cursor_row
    start_col = editor.cursor_col
    _word_right!(editor)
    end_row = editor.cursor_row
    end_col = editor.cursor_col
    # Set up selection to delete
    cw.selection.active = true
    cw.selection.anchor_row = start_row
    cw.selection.anchor_col = start_col
    _delete_selection_no_undo!(cw)
end

"""Delete selection without pushing undo (caller already did)."""
function _delete_selection_no_undo!(cw::CellWidget)
    sel = cw.selection
    !sel.active && return
    editor = cw.editor
    sr, sc, er, ec = _selection_range(sel, editor.cursor_row, editor.cursor_col)
    if sr == er
        line = editor.lines[sr]
        to_del = min(ec, length(line))
        from_del = sc + 1
        if from_del <= to_del
            deleteat!(line, from_del:to_del)
        end
    else
        first_part = editor.lines[sr][1:sc]
        last_line = editor.lines[er]
        last_part = ec < length(last_line) ? last_line[ec+1:end] : Char[]
        editor.lines[sr] = vcat(first_part, last_part)
        if er > sr
            deleteat!(editor.lines, sr+1:er)
        end
    end
    editor.cursor_row = sr
    editor.cursor_col = sc
    sel.active = false
    editor.token_cache = [Tachikoma.tokenize_line(l) for l in editor.lines]
    empty!(editor.dirty_lines)
end

# ── Cursor movement for Shift+Arrow ──────────────────────────────────

function _move_cursor_for_shift!(editor, key::Symbol)
    if key == :shift_left
        if editor.cursor_col > 0
            editor.cursor_col -= 1
        elseif editor.cursor_row > 1
            editor.cursor_row -= 1
            editor.cursor_col = length(editor.lines[editor.cursor_row])
        end
    elseif key == :shift_right
        line = editor.lines[editor.cursor_row]
        if editor.cursor_col < length(line)
            editor.cursor_col += 1
        elseif editor.cursor_row < length(editor.lines)
            editor.cursor_row += 1
            editor.cursor_col = 0
        end
    elseif key == :shift_up
        if editor.cursor_row > 1
            editor.cursor_row -= 1
            editor.cursor_col = min(editor.cursor_col, length(editor.lines[editor.cursor_row]))
        end
    elseif key == :shift_down
        if editor.cursor_row < length(editor.lines)
            editor.cursor_row += 1
            editor.cursor_col = min(editor.cursor_col, length(editor.lines[editor.cursor_row]))
        end
    elseif key == :shift_home
        editor.cursor_col = 0
    elseif key == :shift_end
        editor.cursor_col = length(editor.lines[editor.cursor_row])
    end
end

# ── Text insertion helper ────────────────────────────────────────────

"""Insert a multi-line text string at the current cursor position."""
function _insert_text!(editor, text::String)
    Tachikoma._push_undo!(editor; force=true)
    parts = split(text, '\n'; keepempty=true)
    if length(parts) == 1
        chars = collect(parts[1])
        line = editor.lines[editor.cursor_row]
        for (i, c) in enumerate(chars)
            insert!(line, editor.cursor_col + i, c)
        end
        editor.cursor_col += length(chars)
    else
        line = editor.lines[editor.cursor_row]
        left = line[1:editor.cursor_col]
        right = line[editor.cursor_col+1:end]

        editor.lines[editor.cursor_row] = vcat(left, collect(parts[1]))
        for i in 2:length(parts)-1
            insert!(editor.lines, editor.cursor_row + i - 1, collect(parts[i]))
        end
        last_line = vcat(collect(parts[end]), right)
        insert!(editor.lines, editor.cursor_row + length(parts) - 1, last_line)

        editor.cursor_row += length(parts) - 1
        editor.cursor_col = length(collect(parts[end]))
    end
    editor.token_cache = [Tachikoma.tokenize_line(l) for l in editor.lines]
    empty!(editor.dirty_lines)
end

# ── Click-to-position helper ─────────────────────────────────────────

"""Map screen coordinates to editor (row, col) given the code area rect."""
function click_to_editor_pos(editor::Tachikoma.CodeEditor, area::Tachikoma.Rect,
                              click_x::Int, click_y::Int)
    line_count = length(editor.lines)
    gw = editor.show_line_numbers ? ndigits(max(line_count, 1)) + 1 : 0
    code_x = area.x + gw

    row = (click_y - area.y) + 1 + editor.scroll_offset
    row = clamp(row, 1, max(1, line_count))

    col = (click_x - code_x) + editor.h_scroll
    col = clamp(col, 0, length(editor.lines[row]))

    return (row, col)
end

# ── Key handling (selection-aware, REPL-matching keybindings) ────────

function Tachikoma.handle_key!(cw::CellWidget, evt)
    sel = cw.selection
    editor = cw.editor

    # ── Ctrl+A: move to line start (REPL ^A) ──
    if evt.key == :ctrl && evt.char == 'a'
        sel.active = false
        editor.cursor_col = 0
        return true
    end

    # ── Ctrl+E: move to line end (REPL ^E) ──
    if evt.key == :ctrl && evt.char == 'e'
        sel.active = false
        editor.cursor_col = length(editor.lines[editor.cursor_row])
        return true
    end

    # ── Ctrl+K: kill line forward (REPL ^K) ──
    if evt.key == :ctrl && evt.char == 'k'
        Tachikoma._push_undo!(editor; force=true)
        line = editor.lines[editor.cursor_row]
        if editor.cursor_col < length(line)
            killed = String(line[editor.cursor_col+1:end])
            deleteat!(line, editor.cursor_col+1:length(line))
            _clipboard_copy!(killed)
            Tachikoma._mark_dirty!(editor, editor.cursor_row)
        elseif editor.cursor_row < length(editor.lines)
            append!(editor.lines[editor.cursor_row], editor.lines[editor.cursor_row + 1])
            deleteat!(editor.lines, editor.cursor_row + 1)
            Tachikoma._mark_dirty!(editor, editor.cursor_row)
        end
        Tachikoma._ensure_tokens!(editor)
        sync_to_cell!(cw)
        return true
    end

    # ── Ctrl+U: kill line backward (REPL ^U) ──
    if evt.key == :ctrl && evt.char == 'u'
        Tachikoma._push_undo!(editor; force=true)
        line = editor.lines[editor.cursor_row]
        if editor.cursor_col > 0
            killed = String(line[1:editor.cursor_col])
            deleteat!(line, 1:editor.cursor_col)
            editor.cursor_col = 0
            _clipboard_copy!(killed)
            Tachikoma._mark_dirty!(editor, editor.cursor_row)
        end
        Tachikoma._ensure_tokens!(editor)
        sync_to_cell!(cw)
        return true
    end

    # ── Ctrl+W: delete word backward (whitespace-delimited, REPL ^W) ──
    if evt.key == :ctrl && evt.char == 'w'
        _delete_prev_word!(cw)
        sync_to_cell!(cw)
        return true
    end

    # ── Ctrl+Y: yank/paste (REPL ^Y) ──
    if evt.key == :ctrl && evt.char == 'y'
        clip = _clipboard_paste()
        isempty(clip) && return true
        if sel.active
            _delete_selection!(cw)
        end
        _insert_text!(editor, clip)
        sync_to_cell!(cw)
        return true
    end

    # ── Ctrl+C / Cmd+C: copy selection ──
    # On Kitty-protocol terminals: Cmd+C produces :ctrl + 'c' (bypasses Tachikoma quit)
    # On legacy terminals: Ctrl+C produces :ctrl_c (intercepted by Tachikoma for quit)
    # So this handler works on Kitty terminals with Cmd+C; legacy terminals use auto-copy
    if evt.key == :ctrl && evt.char == 'c' && sel.active
        text = _selected_text(editor.lines, sel, editor.cursor_row, editor.cursor_col)
        _clipboard_copy!(text)
        return true
    end

    # ── Ctrl+X / Cmd+X: cut selection ──
    if evt.key == :ctrl && evt.char == 'x' && sel.active
        text = _selected_text(editor.lines, sel, editor.cursor_row, editor.cursor_col)
        _clipboard_copy!(text)
        _delete_selection!(cw)
        sync_to_cell!(cw)
        return true
    end

    # ── Ctrl+V / Cmd+V: paste ──
    if evt.key == :ctrl && evt.char == 'v'
        clip = _clipboard_paste()
        isempty(clip) && return true
        if sel.active
            _delete_selection!(cw)
        end
        _insert_text!(editor, clip)
        sync_to_cell!(cw)
        return true
    end

    # ── Shift+Arrow: extend selection ──
    if evt.key in (:shift_left, :shift_right, :shift_up, :shift_down, :shift_home, :shift_end)
        if !sel.active
            sel.active = true
            sel.anchor_row = editor.cursor_row
            sel.anchor_col = editor.cursor_col
        end
        _move_cursor_for_shift!(editor, evt.key)
        _auto_copy_selection!(cw)
        return true
    end

    # ── Ctrl+Shift+Arrow: word selection ──
    if evt.key in (:ctrl_shift_left, :ctrl_shift_right)
        if !sel.active
            sel.active = true
            sel.anchor_row = editor.cursor_row
            sel.anchor_col = editor.cursor_col
        end
        if evt.key == :ctrl_shift_left
            _word_left!(editor)
        else
            _word_right!(editor)
        end
        _auto_copy_selection!(cw)
        return true
    end

    # ── Alt+Shift+Arrow (Option+Shift+Arrow): word selection (macOS standard) ──
    if evt.key in (:alt_shift_left, :alt_shift_right)
        if !sel.active
            sel.active = true
            sel.anchor_row = editor.cursor_row
            sel.anchor_col = editor.cursor_col
        end
        if evt.key == :alt_shift_left
            _word_left!(editor)
        else
            _word_right!(editor)
        end
        _auto_copy_selection!(cw)
        return true
    end

    # ── Ctrl+Arrow: word jump (clear selection) ──
    if evt.key == :ctrl_left
        sel.active = false
        _word_left!(editor)
        return true
    end
    if evt.key == :ctrl_right
        sel.active = false
        _word_right!(editor)
        return true
    end

    # ── Alt+Arrow (Option+Arrow): word jump (macOS standard) ──
    if evt.key == :alt_left
        sel.active = false
        _word_left!(editor)
        return true
    end
    if evt.key == :alt_right
        sel.active = false
        _word_right!(editor)
        return true
    end

    # ── Alt+Backspace (Option+Backspace): delete word backward (macOS standard) ──
    if evt.key == :alt_backspace
        if sel.active
            _delete_selection!(cw)
        else
            _delete_prev_word!(cw)
        end
        sync_to_cell!(cw)
        return true
    end

    # ── Alt+Delete (Option+D): delete word forward (macOS standard) ──
    if evt.key == :alt_delete
        if sel.active
            _delete_selection!(cw)
        else
            _delete_next_word!(cw)
        end
        sync_to_cell!(cw)
        return true
    end

    # ── Arrow keys with active selection: collapse to edge ──
    if sel.active && evt.key in (:left, :right, :up, :down, :home, :end_key)
        sr, sc, er, ec = _selection_range(sel, editor.cursor_row, editor.cursor_col)
        sel.active = false
        if evt.key in (:left, :up, :home)
            editor.cursor_row = sr
            editor.cursor_col = sc
        else
            editor.cursor_row = er
            editor.cursor_col = ec
        end
        return true
    end

    # ── Backspace/Delete with active selection: delete selection ──
    if sel.active && (evt.key == :backspace || evt.key == :delete)
        _delete_selection!(cw)
        sync_to_cell!(cw)
        return true
    end

    # ── Typing with active selection: replace selection ──
    if sel.active && (evt.key == :char || evt.key == :enter || evt.key == :tab)
        _delete_selection!(cw)
        sync_to_cell!(cw)
        # Fall through to editor for the actual character insertion
    end

    # ── Plain movement clears selection ──
    if !sel.active
        # nothing to clear
    elseif evt.key == :escape
        sel.active = false
        # let escape propagate
    end

    # Auto-close brackets (before passing to editor)
    if _handle_auto_close!(editor, evt)
        sync_to_cell!(cw)
        return true
    end

    # Pass to editor
    handled = Tachikoma.handle_key!(cw.editor, evt)
    if handled
        sync_to_cell!(cw)
    end
    handled
end

# ── Border rendering ─────────────────────────────────────────────────

"""Draw a dashed rounded border — rounded corners with dashed horizontal/vertical lines."""
function _draw_dashed_border!(buf::Tachikoma.Buffer, rect::Tachikoma.Rect,
                               border_fg, surface_bg)
    (rect.width < 2 || rect.height < 2) && return
    box = Theme.BOX
    s = Tachikoma.Style(; fg=border_fg, bg=surface_bg)

    rx = rect.x; ry = rect.y
    rx2 = Tachikoma.right(rect); ry2 = Tachikoma.bottom(rect)

    Tachikoma.set_char!(buf, rx, ry, box.tl, s)
    Tachikoma.set_char!(buf, rx2, ry, box.tr, s)
    Tachikoma.set_char!(buf, rx, ry2, box.bl, s)
    Tachikoma.set_char!(buf, rx2, ry2, box.br, s)

    for x in (rx + 1):(rx2 - 1)
        Tachikoma.set_char!(buf, x, ry, '┄', s)
        Tachikoma.set_char!(buf, x, ry2, '┄', s)
    end

    for y in (ry + 1):(ry2 - 1)
        Tachikoma.set_char!(buf, rx, y, '┆', s)
        Tachikoma.set_char!(buf, rx2, y, '┆', s)
    end
end

"""Draw a rounded border. All border chars use surface_bg so they match the cell fill exactly."""
function _draw_rounded_border!(buf::Tachikoma.Buffer, rect::Tachikoma.Rect,
                                border_fg, surface_bg)
    (rect.width < 2 || rect.height < 2) && return
    box = Theme.BOX
    s = Tachikoma.Style(; fg=border_fg, bg=surface_bg)

    rx = rect.x; ry = rect.y
    rx2 = Tachikoma.right(rect); ry2 = Tachikoma.bottom(rect)

    Tachikoma.set_char!(buf, rx, ry, box.tl, s)
    Tachikoma.set_char!(buf, rx2, ry, box.tr, s)
    Tachikoma.set_char!(buf, rx, ry2, box.bl, s)
    Tachikoma.set_char!(buf, rx2, ry2, box.br, s)

    for x in (rx + 1):(rx2 - 1)
        Tachikoma.set_char!(buf, x, ry, box.h, s)
        Tachikoma.set_char!(buf, x, ry2, box.h, s)
    end

    for y in (ry + 1):(ry2 - 1)
        Tachikoma.set_char!(buf, rx, y, box.v, s)
        Tachikoma.set_char!(buf, rx2, y, box.v, s)
    end
end

"""Draw a shimmer border. All border chars use surface_bg so they match the cell fill exactly."""
function _shimmer_border_with_bg!(buf::Tachikoma.Buffer, rect::Tachikoma.Rect,
                                   base_color, surface_bg, tick::Int;
                                   box=Theme.BOX, intensity::Float64=0.2)
    (rect.width < 2 || rect.height < 2) && return
    base_rgb = Tachikoma.to_rgb(base_color)

    function _style(x::Int, y::Int)
        if Tachikoma.animations_enabled()
            n = Tachikoma.fbm(x * 0.3 + tick * 0.04, y * 0.5 + tick * 0.02)
            adj = (n - 0.5) * 2.0 * intensity
            c = if adj > 0
                Tachikoma.brighten(base_rgb, adj)
            else
                Tachikoma.dim_color(base_rgb, -adj)
            end
            Tachikoma.Style(; fg=c, bg=surface_bg)
        else
            Tachikoma.Style(; fg=base_rgb, bg=surface_bg)
        end
    end

    rx = rect.x; ry = rect.y
    rx2 = Tachikoma.right(rect); ry2 = Tachikoma.bottom(rect)

    Tachikoma.set_char!(buf, rx, ry, box.tl, _style(rx, ry))
    Tachikoma.set_char!(buf, rx2, ry, box.tr, _style(rx2, ry))
    Tachikoma.set_char!(buf, rx, ry2, box.bl, _style(rx, ry2))
    Tachikoma.set_char!(buf, rx2, ry2, box.br, _style(rx2, ry2))

    for x in (rx + 1):(rx2 - 1)
        Tachikoma.set_char!(buf, x, ry, box.h, _style(x, ry))
        Tachikoma.set_char!(buf, x, ry2, box.h, _style(x, ry2))
    end

    for y in (ry + 1):(ry2 - 1)
        Tachikoma.set_char!(buf, rx, y, box.v, _style(rx, y))
        Tachikoma.set_char!(buf, rx2, y, box.v, _style(rx2, y))
    end
end

# ── Inline diagnostics rendering ─────────────────────────────────────

"""Render inline diagnostic messages below code lines inside the cell border."""
function _render_diagnostics!(cw::CellWidget, inner::Tachikoma.Rect, buf::Tachikoma.Buffer,
                               surface_bg, n_code_lines::Int)
    isempty(cw.diagnostics) && return
    for (i, d) in enumerate(cw.diagnostics)
        dy = inner.y + n_code_lines + i - 1
        dy > inner.y + inner.height - 1 && break
        fg = d.severity == :error ? Theme.RED :
             d.severity == :warning ? Theme.ORANGE : Theme.CYAN
        style = Tachikoma.Style(; fg, bg=surface_bg, italic=true)
        prefix = "↳ "
        msg = prefix * d.message
        # Truncate to fit inner width
        if length(msg) > inner.width
            msg = msg[1:max(1, inner.width - 1)] * "…"
        end
        Tachikoma.set_string!(buf, inner.x, dy, msg, style)
    end
end

# ── Main render ──────────────────────────────────────────────────────

function Tachikoma.render(cw::CellWidget, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    tick = Theme.tick()

    # Folded cell: hidden code — just a thin canvas-bg row (or nothing if output visible)
    if cw.cell.folded
        rect.height < 1 && return  # height 0 means output is showing instead
        Tachikoma.set_string!(buf, rect.x, rect.y, " " ^ rect.width, Theme.S_CANVAS)
        if cw.focused || cw.hovered
            bar_style = Tachikoma.Style(; fg=Theme.FOLD_BAR_FG, bg=Theme.CANVAS_BG)
            Tachikoma.set_char!(buf, rect.x, rect.y, '│', bar_style)
        end
        return
    end

    surface_bg = Theme.cell_surface(cw.focused)

    # Fill the entire rect with surface_bg (gray cell island).
    fill_style = Tachikoma.Style(; bg=surface_bg)
    for fy in rect.y:(rect.y + rect.height - 1)
        Tachikoma.set_string!(buf, rect.x, fy, " " ^ rect.width, fill_style)
    end

    # Border is drawn INSET from the fill — horizontal padding visible on sides.
    hi = Theme.CELL_H_INSET
    vi = Theme.CELL_V_INSET
    border_w = rect.width - 2 * hi
    border_h = rect.height - 2 * vi
    (border_w < 2 || border_h < 2) && return
    border_rect = Tachikoma.Rect(rect.x + hi, rect.y + vi, border_w, border_h)

    hp = Theme.CELL_H_PAD
    inner_w = border_w - 2 - 2 * hp
    inner_h = border_h - 2
    (inner_w < 1 || inner_h < 1) && return
    inner = Tachikoma.Rect(border_rect.x + 1 + hp, border_rect.y + 1, inner_w, inner_h)

    dirty = is_dirty(cw)

    if cw.focused && !cw.cell.disabled
        if cw.editor.focused
            # Insert mode: bright shimmer border (actively editing)
            border_color = dirty ? Theme.ORANGE : Theme.ACCENT
            _shimmer_border_with_bg!(buf, border_rect, border_color, surface_bg, tick;
                box=Theme.BOX, intensity=Theme.SHIMMER_INTENSITY)
        else
            # Normal mode: gray border + solid accent left bar (focused but not editing)
            border_color = dirty ? Theme.DIRTY_BORDER_FG : Theme.BORDER_BRIGHT
            _draw_rounded_border!(buf, border_rect, border_color, surface_bg)
            # Accent left bar — clear "this cell is selected" indicator
            bar_color = dirty ? Theme.ORANGE : Theme.ACCENT_DIM
            bar_style = Tachikoma.Style(; fg=bar_color, bg=surface_bg)
            for by in (border_rect.y):(Tachikoma.bottom(border_rect))
                Tachikoma.set_char!(buf, border_rect.x, by, '▎', bar_style)
            end
        end
        _render_code!(cw, inner, buf, surface_bg)
        _render_ellipsis_button!(border_rect, buf; hovered=cw.ellipsis_hovered)
        # Inline diagnostics below code (only for focused cell)
        if !isempty(cw.diagnostics)
            n_code = count(==('\n'), cw.cell.code) + 1
            _render_diagnostics!(cw, inner, buf, surface_bg, n_code)
        end

    elseif cw.hovered && !cw.cell.disabled
        border_color = dirty ? Theme.DIRTY_BORDER_FG : Theme.BORDER_BRIGHT
        _draw_rounded_border!(buf, border_rect, border_color, surface_bg)
        # Preserve selection left bar when hovering over a selected cell
        if cw.selected
            bar_color = dirty ? Theme.ORANGE : Theme.ACCENT_DIM
            bar_style = Tachikoma.Style(; fg=bar_color, bg=surface_bg)
            for by in (border_rect.y):(Tachikoma.bottom(border_rect))
                Tachikoma.set_char!(buf, border_rect.x, by, '▎', bar_style)
            end
        end
        _render_code!(cw, inner, buf, surface_bg)
        _render_ellipsis_button!(border_rect, buf; hovered=cw.ellipsis_hovered)

    elseif cw.cell.disabled
        _draw_rounded_border!(buf, border_rect, Theme.FG_MUTED, surface_bg)
        _render_folded_preview(cw, inner, buf, surface_bg)

    elseif cw.selected
        # Selected cells look like normal-mode focused: gray border + accent left bar
        border_color = dirty ? Theme.DIRTY_BORDER_FG : Theme.BORDER_BRIGHT
        _draw_rounded_border!(buf, border_rect, border_color, surface_bg)
        bar_color = dirty ? Theme.ORANGE : Theme.ACCENT_DIM
        bar_style = Tachikoma.Style(; fg=bar_color, bg=surface_bg)
        for by in (border_rect.y):(Tachikoma.bottom(border_rect))
            Tachikoma.set_char!(buf, border_rect.x, by, '▎', bar_style)
        end
        _render_code!(cw, inner, buf, surface_bg)

    elseif dirty
        _draw_rounded_border!(buf, border_rect, Theme.DIRTY_BORDER_FG, surface_bg)
        _render_code!(cw, inner, buf, surface_bg)

    else
        _draw_rounded_border!(buf, border_rect, Theme.BORDER_DIM, surface_bg)
        _render_code!(cw, inner, buf, surface_bg)
    end

    # Running/queued left border indicator (Pluto-style colored left edge)
    _render_run_indicator!(cw.cell, border_rect, buf, surface_bg, tick)

    # Selection highlight + cursor — only when cell is being edited
    if cw.editor.focused && !cw.cell.disabled
        _render_selection!(cw, inner, buf)
        _render_cursor!(cw.editor, inner, buf, tick)
    end
end

"""Overlay the left border with a colored bar when cell is running or queued."""
function _render_run_indicator!(cell::Cell, border_rect::Tachikoma.Rect,
                                 buf::Tachikoma.Buffer, surface_bg, tick::Int)
    (cell.state != cell_running && cell.state != cell_queued) && return
    border_rect.height < 2 && return

    rx = border_rect.x
    ry = border_rect.y
    ry2 = Tachikoma.bottom(border_rect)

    if cell.state == cell_running
        for y in ry:ry2
            b = Tachikoma.breathe(tick + (y - ry) * 3; period=45)
            fg = Tachikoma.color_lerp(Theme.ACCENT_DIM, Theme.ACCENT_GLOW, b)
            Tachikoma.set_char!(buf, rx, y, '▎', Tachikoma.Style(; fg, bg=surface_bg))
        end
    else  # cell_queued
        style = Tachikoma.Style(; fg=Theme.ORANGE, bg=surface_bg)
        for y in ry:ry2
            Tachikoma.set_char!(buf, rx, y, '▎', style)
        end
    end
end

"""Render code editor (folded cells are handled before this is called)."""
function _render_code!(cw::CellWidget, inner::Tachikoma.Rect,
                        buf::Tachikoma.Buffer, surface_bg)
    cw.editor.scroll_offset = 0

    if cw.focused
        # Suppress built-in block cursor; we draw our own cursor after
        was_focused = cw.editor.focused
        cw.editor.focused = false
        Tachikoma.render(cw.editor, inner, buf)
        cw.editor.focused = was_focused
    else
        Tachikoma.render(cw.editor, inner, buf)
    end
end

"""Render ⋯ pill button inside cell, top-right corner."""
function _render_ellipsis_button!(rect::Tachikoma.Rect, buf::Tachikoma.Buffer; hovered::Bool=false)
    rect.height < 3 && return
    ey = rect.y + 1
    ex = rect.x + rect.width - 4  # 3 chars + border
    ex < rect.x + 2 && return
    if hovered
        bracket = Tachikoma.Style(; fg=Theme.ACCENT, bg=Theme.BTN_BG)
        center  = Tachikoma.Style(; fg=Theme.ACCENT_GLOW, bg=Theme.BTN_BG)
    else
        bracket = Tachikoma.Style(; fg=Theme.BTN_BRACKET, bg=Theme.BTN_BG)
        center  = Tachikoma.Style(; fg=Theme.BTN_FG, bg=Theme.BTN_BG)
    end
    Tachikoma.set_char!(buf, ex, ey, '(', bracket)
    Tachikoma.set_char!(buf, ex + 1, ey, Theme.BTN_CHAR, center)
    Tachikoma.set_char!(buf, ex + 2, ey, ')', bracket)
end

"""Compute run button style for a cell (used by notebook_view for gap rendering)."""
function run_button_style(cell::Cell, tick::Int)
    bg = Theme.RUN_BG
    if cell.state == cell_running
        p = Tachikoma.pulse(tick; period=30, lo=0.4, hi=1.0)
        fg = Tachikoma.color_lerp(Theme.ACCENT_DIM, Theme.ACCENT_GLOW, p)
        Tachikoma.Style(; fg, bg, bold=true)
    elseif cell.state == cell_errored
        Tachikoma.Style(; fg=Theme.RUN_ERROR_FG, bg)
    elseif cell.state == cell_done
        Tachikoma.Style(; fg=Theme.RUN_DONE_FG, bg)
    else
        Tachikoma.Style(; fg=Theme.RUN_DEFAULT_FG, bg)
    end
end

"""Compute run button text for a cell."""
function run_button_text(cell::Cell)
    rt = format_runtime(cell.output.runtime_ns)
    rt_display = isempty(rt) ? "" : " $rt "
    cell.state == cell_running ? "▶ ..." : "▶" * rt_display
end

# ── Selection highlight rendering ────────────────────────────────────

"""Overlay selection highlighting on the code area."""
function _render_selection!(cw::CellWidget, area::Tachikoma.Rect, buf::Tachikoma.Buffer)
    sel = cw.selection
    !sel.active && return

    editor = cw.editor
    sr, sc, er, ec = _selection_range(sel, editor.cursor_row, editor.cursor_col)

    line_count = length(editor.lines)
    gw = editor.show_line_numbers ? ndigits(max(line_count, 1)) + 1 : 0
    code_x = area.x + gw
    code_width = area.width - gw
    code_width < 1 && return

    Tachikoma._ensure_tokens!(editor)

    for vi in 1:area.height
        li = editor.scroll_offset + vi
        li > line_count && break
        (li < sr || li > er) && continue

        y = area.y + vi - 1
        line = editor.lines[li]
        tokens = li <= length(editor.token_cache) ? editor.token_cache[li] : Tachikoma.Token[]

        # Selection range on this line (1-based char indices)
        line_sel_start = li == sr ? sc + 1 : 1
        line_sel_end = li == er ? ec : length(line)

        for ci in 1:code_width
            char_idx = editor.h_scroll + ci
            x = code_x + ci - 1
            x > Tachikoma.right(area) && break

            (char_idx < line_sel_start || char_idx > line_sel_end) && continue

            if char_idx >= 1 && char_idx <= length(line)
                ch = line[char_idx]
                # Get syntax fg for this character
                tok = nothing
                for t in tokens
                    if char_idx >= t.start && char_idx <= t.stop
                        tok = t
                        break
                    end
                end
                fg = tok !== nothing ? Tachikoma._token_style(tok.kind).fg : editor.style.fg
                Tachikoma.set_char!(buf, x, y, ch, Tachikoma.Style(; fg=fg, bg=Theme.SELECTION_BG))
            else
                Tachikoma.set_char!(buf, x, y, ' ', Tachikoma.Style(; bg=Theme.SELECTION_BG))
            end
        end
    end
end

# ── Cursor rendering (character-preserving) ──────────────────────────

"""Draw cursor by highlighting the character at cursor position with accent background.
The character remains visible (unlike the old bar cursor that replaced it with ▏)."""
function _render_cursor!(editor::Tachikoma.CodeEditor, area::Tachikoma.Rect,
                          buf::Tachikoma.Buffer, tick::Int)
    line_count = length(editor.lines)
    gw = editor.show_line_numbers ? ndigits(max(line_count, 1)) + 1 : 0

    vis_row = editor.cursor_row - editor.scroll_offset
    vis_row < 1 && return
    vis_row > area.height && return

    cy = area.y + vis_row - 1
    cx = area.x + gw + (editor.cursor_col - editor.h_scroll)

    cx < area.x + gw && return
    cx > area.x + area.width - 1 && return

    # Get the character at cursor position (to the right of the insert point)
    line = editor.lines[editor.cursor_row]
    char_idx = editor.cursor_col + 1  # 1-based
    ch = char_idx >= 1 && char_idx <= length(line) ? line[char_idx] : ' '

    # Breathing accent background — character stays fully visible
    b = Tachikoma.breathe(tick; period=60)
    bg = Tachikoma.color_lerp(Theme.CURSOR_BG, Theme.CURSOR_BG_GLOW, b)
    cursor_style = Tachikoma.Style(; fg=Theme.FG, bg=bg)

    Tachikoma.set_char!(buf, cx, cy, ch, cursor_style)
end

"""Render folded/disabled preview text."""
function _render_folded_preview(cw::CellWidget, inner::Tachikoma.Rect,
                                 buf::Tachikoma.Buffer, surface_bg)
    first_line = first(split(cw.cell.code, '\n'; limit=2))
    preview = isempty(first_line) ? "..." : first_line * " ..."
    para = Tachikoma.Paragraph([Tachikoma.Span(preview,
        Tachikoma.Style(; fg=Theme.FG_DIM, bg=surface_bg))])
    Tachikoma.render(para, inner, buf)
end
