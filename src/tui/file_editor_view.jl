# TUI: File editor view — full-screen code editor for plain .jl files
# Reuses Tachikoma.CodeEditor with line numbers, vim modes, undo/redo, search.

"""
Renders a plain .jl file in a full-screen code editor.
Unlike NotebookView (cell-based), this is a single CodeEditor filling the pane.
"""
mutable struct FileEditorView
    path::String
    editor::Tachikoma.CodeEditor
    dirty::Bool            # unsaved changes
    viewport::Tachikoma.Rect
    diagnostics::Vector{Diagnostic}  # inline diagnostics from LSP
    lsp_doc_version::Int             # LSP document version counter
end

function FileEditorView(path::String)
    editor = Tachikoma.CodeEditor(;
        show_line_numbers=true,
        focused=true,
        mode=:normal,
        style=Tachikoma.Style(; fg=Theme.FG, bg=Theme.CANVAS_BG),
        gutter_style=Tachikoma.Style(; fg=Theme.FG_MUTED, bg=Theme.CANVAS_BG),
        cursor_style=Tachikoma.Style(; fg=Theme.BG, bg=Theme.ACCENT),
    )
    if isfile(path)
        content = read(path, String)
        Tachikoma.set_text!(editor, content)
        # Reset cursor to top of file (set_text! leaves cursor at end)
        editor.cursor_row = 1
        editor.cursor_col = 0
        editor.scroll_offset = 0
    end
    FileEditorView(path, editor, false, Tachikoma.Rect(), Diagnostic[], 1)
end

"""Save the editor contents to disk."""
function save_file!(fev::FileEditorView)
    content = Tachikoma.text(fev.editor)
    # Ensure trailing newline (Julia convention)
    if !endswith(content, '\n')
        content *= "\n"
    end
    Base.write(fev.path, content)
    fev.dirty = false
end

"""Reload file from disk (discards unsaved changes)."""
function reload_file!(fev::FileEditorView)
    if isfile(fev.path)
        content = read(fev.path, String)
        Tachikoma.set_text!(fev.editor, content)
        fev.dirty = false
    end
end

"""Get display filename for status bar."""
file_basename(fev::FileEditorView) = basename(fev.path)

"""Get line count."""
line_count(fev::FileEditorView) = length(fev.editor.lines)

"""Get cursor position as (row, col) — 1-based."""
cursor_pos(fev::FileEditorView) = (fev.editor.cursor_row, fev.editor.cursor_col + 1)

"""Get editor mode symbol."""
editor_mode(fev::FileEditorView) = fev.editor.mode

function Tachikoma.render(fev::FileEditorView, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    fev.viewport = rect
    rect.width < 4 && return
    rect.height < 4 && return

    hi = Theme.CELL_H_INSET
    vi = Theme.CELL_V_INSET
    border_style = Tachikoma.Style(; fg=Theme.BORDER_DIM, bg=Theme.CANVAS_BG)

    # Fill rect with canvas bg
    for fy in rect.y:(rect.y + rect.height - 1)
        Tachikoma.set_string!(buf, rect.x, fy, " " ^ rect.width, Theme.S_CANVAS)
    end

    # Rounded border
    bx = rect.x + hi
    by = rect.y + vi
    bw = max(rect.width - 2 * hi, 3)
    bh = max(rect.height - 2 * vi, 3)

    Tachikoma.set_char!(buf, bx, by, '╭', border_style)
    Tachikoma.set_char!(buf, bx + bw - 1, by, '╮', border_style)
    Tachikoma.set_char!(buf, bx, by + bh - 1, '╰', border_style)
    Tachikoma.set_char!(buf, bx + bw - 1, by + bh - 1, '╯', border_style)

    for cx in (bx + 1):(bx + bw - 2)
        Tachikoma.set_char!(buf, cx, by, '─', border_style)
        Tachikoma.set_char!(buf, cx, by + bh - 1, '─', border_style)
    end
    for fy in (by + 1):(by + bh - 2)
        Tachikoma.set_char!(buf, bx, fy, '│', border_style)
        Tachikoma.set_char!(buf, bx + bw - 1, fy, '│', border_style)
    end

    # Title in top border — filename with dirty indicator
    title = " " * file_basename(fev) * (fev.dirty ? " ●" : "") * " "
    title_x = bx + 2
    title_s = Tachikoma.Style(; fg=Theme.ACCENT, bg=Theme.CANVAS_BG, bold=true)
    Tachikoma.set_string!(buf, title_x, by, title, title_s)

    # Cursor position in top-right border
    row, col = cursor_pos(fev)
    pos_str = " Ln $(row), Col $(col) "
    pos_x = bx + bw - 1 - length(pos_str)
    if pos_x > title_x + length(title)
        Tachikoma.set_string!(buf, pos_x, by, pos_str,
            Tachikoma.Style(; fg=Theme.FG_DIM, bg=Theme.CANVAS_BG))
    end

    # Editor fills inner area
    inner_x = bx + 1
    inner_y = by + 1
    inner_w = bw - 2
    inner_h = bh - 2
    inner_w < 2 && return
    inner_h < 2 && return

    editor_rect = Tachikoma.Rect(inner_x, inner_y, inner_w, inner_h)
    Tachikoma.render(fev.editor, editor_rect, buf)

    # Diagnostic gutter markers (colored dots on lines with issues)
    if !isempty(fev.diagnostics)
        scroll = fev.editor.scroll_offset
        for d in fev.diagnostics
            vis_row = d.line - scroll  # 1-based visible row
            dy = inner_y + vis_row - 1
            (dy < inner_y || dy > inner_y + inner_h - 1) && continue
            marker_fg = d.severity == :error ? Theme.RED :
                        d.severity == :warning ? Theme.ORANGE : Theme.CYAN
            # Place dot just outside the left border
            marker_x = bx - 1
            marker_x >= rect.x && Tachikoma.set_string!(buf, marker_x, dy, "●",
                Tachikoma.Style(; fg=marker_fg, bg=Theme.CANVAS_BG))
        end
    end
end
