# TUI: File explorer panel — superfile-inspired sidebar
# Rounded borders, file type icons, cursor indicator, click navigation

struct FileEntry
    name::String
    path::String
    is_dir::Bool
    is_hidden::Bool
    size::Int64
end

mutable struct FilePanel
    root_dir::String
    current_dir::String
    entries::Vector{FileEntry}
    cursor_idx::Int
    scroll_offset::Int
    viewport::Tachikoma.Rect
    show_hidden::Bool
    # Folder picker mode (for "Open Folder" workflow)
    picker_mode::Bool
    picker_dir::String
    picker_entries::Vector{FileEntry}
    picker_cursor::Int
    picker_scroll::Int
end

function FilePanel(dir::String=".")
    dir = abspath(dir)
    fp = FilePanel(dir, dir, FileEntry[], 1, 0, Tachikoma.Rect(), false,
                   false, homedir(), FileEntry[], 1, 0)
    refresh_entries!(fp)
    fp
end

"""Scan current_dir and populate entries."""
function refresh_entries!(fp::FilePanel)
    fp.entries = FileEntry[]
    isdir(fp.current_dir) || return

    names = try
        readdir(fp.current_dir)
    catch
        String[]
    end

    dirs = FileEntry[]
    files = FileEntry[]
    for name in sort(names)
        is_hidden = startswith(name, '.')
        (!fp.show_hidden && is_hidden) && continue
        full = joinpath(fp.current_dir, name)
        if isdir(full)
            push!(dirs, FileEntry(name, full, true, is_hidden, 0))
        else
            sz = try; filesize(full); catch; Int64(0); end
            push!(files, FileEntry(name, full, false, is_hidden, sz))
        end
    end

    # Directories first, then files (like superfile)
    append!(fp.entries, dirs)
    append!(fp.entries, files)

    fp.cursor_idx = clamp(fp.cursor_idx, 1, max(length(fp.entries), 1))
    fp.scroll_offset = 0
end

"""Navigate into a directory."""
function enter_dir!(fp::FilePanel, path::String)
    isdir(path) || return
    fp.current_dir = abspath(path)
    fp.cursor_idx = 1
    refresh_entries!(fp)
end

"""Navigate to parent directory."""
function go_up!(fp::FilePanel)
    parent = dirname(fp.current_dir)
    old_name = basename(fp.current_dir)
    fp.current_dir = parent
    fp.cursor_idx = 1
    refresh_entries!(fp)
    # Try to re-select the dir we came from
    for (i, e) in enumerate(fp.entries)
        if e.name == old_name
            fp.cursor_idx = i
            break
        end
    end
end

"""Move cursor up."""
function cursor_up!(fp::FilePanel)
    fp.cursor_idx = max(1, fp.cursor_idx - 1)
end

"""Move cursor down."""
function cursor_down!(fp::FilePanel)
    fp.cursor_idx = min(length(fp.entries), fp.cursor_idx + 1)
end

"""Activate the entry under cursor (enter dir or return file path)."""
function activate!(fp::FilePanel)
    isempty(fp.entries) && return nothing
    entry = fp.entries[fp.cursor_idx]
    if entry.is_dir
        enter_dir!(fp, entry.path)
        return nothing
    else
        return entry.path
    end
end

"""Toggle hidden files."""
function toggle_hidden!(fp::FilePanel)
    fp.show_hidden = !fp.show_hidden
    refresh_entries!(fp)
end

# ── Folder picker mode ───────────────────────────────────────────────

"""Enter picker mode — browse directories starting from home."""
function enter_picker_mode!(fp::FilePanel)
    fp.picker_mode = true
    fp.picker_dir = homedir()
    fp.picker_cursor = 1
    fp.picker_scroll = 0
    refresh_picker!(fp)
end

"""Exit picker mode."""
function exit_picker_mode!(fp::FilePanel)
    fp.picker_mode = false
end

"""Refresh picker directory listing (dirs only + parent)."""
function refresh_picker!(fp::FilePanel)
    fp.picker_entries = FileEntry[]
    isdir(fp.picker_dir) || return

    names = try readdir(fp.picker_dir) catch; String[] end
    for name in sort(names)
        startswith(name, '.') && continue
        full = joinpath(fp.picker_dir, name)
        isdir(full) || continue
        push!(fp.picker_entries, FileEntry(name, full, true, false, 0))
    end
    fp.picker_cursor = clamp(fp.picker_cursor, 1, max(length(fp.picker_entries), 1))
    fp.picker_scroll = 0
end

"""Navigate picker into a subdirectory."""
function picker_enter!(fp::FilePanel, path::String)
    isdir(path) || return
    fp.picker_dir = abspath(path)
    fp.picker_cursor = 1
    refresh_picker!(fp)
end

"""Navigate picker to parent directory."""
function picker_go_up!(fp::FilePanel)
    parent = dirname(fp.picker_dir)
    parent == fp.picker_dir && return  # already at root
    old_name = basename(fp.picker_dir)
    fp.picker_dir = parent
    fp.picker_cursor = 1
    refresh_picker!(fp)
    for (i, e) in enumerate(fp.picker_entries)
        if e.name == old_name
            fp.picker_cursor = i
            break
        end
    end
end

"""Map screen y to a picker entry index, or :parent, or :select, or nothing."""
function picker_hit_at_y(fp::FilePanel, screen_y::Int)
    vp = fp.viewport
    vp.width == 0 && return nothing
    hi = Theme.CELL_H_INSET
    vi = Theme.CELL_V_INSET
    by = vp.y + vi

    # Row layout inside border: header(1) | parent_row(1) | divider(1) | entries...
    parent_y = by + 2
    screen_y == parent_y && return :parent

    # Select button at bottom border
    select_y = by + max(vp.height - 2 * vi, 3) - 1  # bottom border row
    screen_y == select_y && return :select

    entries_start = by + 4
    entry_idx = screen_y - entries_start + fp.picker_scroll
    (entry_idx < 0 || entry_idx >= length(fp.picker_entries)) && return nothing
    return entry_idx + 1
end

# ── Icons & colors per file type ──────────────────────────────────────

# Using simple Unicode that works without nerd fonts
const ICON_FOLDER     = "▸"
const ICON_FOLDER_OPEN = "▾"
const ICON_FILE       = "·"
const ICON_JULIA      = "◆"
const ICON_PYTHON     = "◇"
const ICON_MARKDOWN   = "≡"
const ICON_JSON       = "⟐"
const ICON_YAML       = "⟐"
const ICON_TOML       = "⟐"
const ICON_GIT        = "●"
const ICON_SHELL      = "⊞"
const ICON_IMAGE      = "◻"
const ICON_ARCHIVE    = "⊠"
const ICON_PARENT     = "⊖"

function file_icon(entry::FileEntry)
    entry.is_dir && return ICON_FOLDER
    ext = lowercase(splitext(entry.name)[2])
    ext == ".jl"    && return ICON_JULIA
    ext == ".py"    && return ICON_PYTHON
    ext == ".md"    && return ICON_MARKDOWN
    ext == ".json"  && return ICON_JSON
    ext == ".yaml"  && return ICON_YAML
    ext == ".yml"   && return ICON_YAML
    ext == ".toml"  && return ICON_TOML
    ext == ".sh"    && return ICON_SHELL
    ext == ".bash"  && return ICON_SHELL
    ext == ".zsh"   && return ICON_SHELL
    ext == ".png"   && return ICON_IMAGE
    ext == ".jpg"   && return ICON_IMAGE
    ext == ".svg"   && return ICON_IMAGE
    ext == ".zip"   && return ICON_ARCHIVE
    ext == ".tar"   && return ICON_ARCHIVE
    ext == ".gz"    && return ICON_ARCHIVE
    startswith(entry.name, ".git") && return ICON_GIT
    return ICON_FILE
end

function icon_color(entry::FileEntry)
    entry.is_dir && return Theme.ACCENT
    ext = lowercase(splitext(entry.name)[2])
    ext == ".jl"    && return Theme.GREEN
    ext == ".py"    && return Theme.CYAN
    ext == ".md"    && return Theme.FG_DIM
    ext == ".json"  && return Theme.ORANGE
    ext == ".yaml"  && return Theme.ORANGE
    ext == ".yml"   && return Theme.ORANGE
    ext == ".toml"  && return Theme.ORANGE
    ext == ".sh"    && return Theme.GREEN
    ext == ".bash"  && return Theme.GREEN
    ext == ".zsh"   && return Theme.GREEN
    ext == ".png"   && return Theme.RED
    ext == ".jpg"   && return Theme.RED
    ext == ".zip"   && return Theme.RED
    ext == ".tar"   && return Theme.RED
    ext == ".gz"    && return Theme.RED
    startswith(entry.name, ".git") && return Theme.ORANGE
    return Theme.FG_MUTED
end

"""Format file size for display."""
function format_size(bytes::Int64)
    bytes < 0 && return ""
    bytes < 1024 && return "$(bytes)B"
    bytes < 1024^2 && return "$(round(bytes / 1024; digits=1))K"
    bytes < 1024^3 && return "$(round(bytes / 1024^2; digits=1))M"
    return "$(round(bytes / 1024^3; digits=1))G"
end

# ── Rendering ─────────────────────────────────────────────────────────

"""Height needed for the content area (entries + header + divider)."""
function panel_content_height(fp::FilePanel)
    length(fp.entries) + 3  # header + divider + entries
end

"""Map a screen y-coordinate to a file entry index."""
function entry_at_y(fp::FilePanel, screen_y::Int)
    vp = fp.viewport
    vp.width == 0 && return nothing

    # Content starts after v_inset + border(1) + header(1) + divider(1)
    vi = Theme.CELL_V_INSET
    content_start_y = vp.y + vi + 3
    entry_y = screen_y - content_start_y + fp.scroll_offset

    (entry_y < 0 || entry_y >= length(fp.entries)) && return nothing
    return entry_y + 1
end


function Tachikoma.render(fp::FilePanel, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    fp.viewport = rect
    rect.width < 4 && return
    rect.height < 4 && return

    if fp.picker_mode
        _render_picker!(fp, rect, buf)
        return
    end

    # ── Rounded border (inset to match cell island style) ─────────────
    hi = Theme.CELL_H_INSET
    vi = Theme.CELL_V_INSET
    border_style = Tachikoma.Style(; fg=Theme.SIDEBAR_BORDER_FG, bg=Theme.SIDEBAR_BG)

    # Fill entire rect with sidebar bg (overflow visible around border)
    for fy in rect.y:(rect.y + rect.height - 1)
        Tachikoma.set_string!(buf, rect.x, fy, " " ^ rect.width,
            Tachikoma.Style(; bg=Theme.SIDEBAR_BG))
    end

    # Border drawn inset from fill edges
    bx = rect.x + hi
    by = rect.y + vi
    bw = max(rect.width - 2 * hi, 3)
    bh = max(rect.height - 2 * vi, 3)

    # Corners
    Tachikoma.set_char!(buf, bx, by, '╭', border_style)
    Tachikoma.set_char!(buf, bx + bw - 1, by, '╮', border_style)
    Tachikoma.set_char!(buf, bx, by + bh - 1, '╰', border_style)
    Tachikoma.set_char!(buf, bx + bw - 1, by + bh - 1, '╯', border_style)

    # Top/bottom edges
    for cx in (bx + 1):(bx + bw - 2)
        Tachikoma.set_char!(buf, cx, by, '─', border_style)
        Tachikoma.set_char!(buf, cx, by + bh - 1, '─', border_style)
    end

    # Left/right edges
    for fy in (by + 1):(by + bh - 2)
        Tachikoma.set_char!(buf, bx, fy, '│', border_style)
        Tachikoma.set_char!(buf, bx + bw - 1, fy, '│', border_style)
    end

    inner_x = bx + 1
    inner_w = bw - 2
    inner_w < 2 && return

    # ── Header: folder icon + truncated path ──────────────────────────
    header_y = by + 1
    path_display = _truncate_path(fp.current_dir, inner_w - 4)
    icon_style = Tachikoma.Style(; fg=Theme.GREEN, bg=Theme.SIDEBAR_BG)
    path_style = Tachikoma.Style(; fg=Theme.ACCENT, bg=Theme.SIDEBAR_BG)
    Tachikoma.set_string!(buf, inner_x + 1, header_y, ICON_FOLDER_OPEN, icon_style)
    Tachikoma.set_string!(buf, inner_x + 3, header_y, first(path_display, inner_w - 4), path_style)

    # ── Section divider ───────────────────────────────────────────────
    div_y = by + 2
    Tachikoma.set_char!(buf, bx, div_y, '├', border_style)
    Tachikoma.set_char!(buf, bx + bw - 1, div_y, '┤', border_style)
    for cx in (bx + 1):(bx + bw - 2)
        Tachikoma.set_char!(buf, cx, div_y, '─', border_style)
    end

    # ── File entries ──────────────────────────────────────────────────
    entries_start_y = by + 3
    entries_height = bh - 4  # border(2) + header(1) + divider(1)
    entries_height < 1 && return

    # Ensure cursor is visible (auto-scroll)
    if fp.cursor_idx - 1 < fp.scroll_offset
        fp.scroll_offset = fp.cursor_idx - 1
    end
    if fp.cursor_idx - 1 >= fp.scroll_offset + entries_height
        fp.scroll_offset = fp.cursor_idx - entries_height
    end
    fp.scroll_offset = clamp(fp.scroll_offset, 0, max(0, length(fp.entries) - entries_height))

    max_name_w = inner_w - 5  # cursor(1) + space(1) + icon(1) + space(1) + padding(1)

    for vi in 0:(entries_height - 1)
        ei = fp.scroll_offset + vi + 1
        ei > length(fp.entries) && break
        entry = fp.entries[ei]
        row = entries_start_y + vi
        is_cursor = (ei == fp.cursor_idx)

        # Cursor indicator
        cursor_char = is_cursor ? "›" : " "
        cursor_style = Tachikoma.Style(;
            fg=is_cursor ? Theme.ACCENT_GLOW : Theme.FG_MUTED,
            bg=Theme.SIDEBAR_BG)
        Tachikoma.set_string!(buf, inner_x, row, cursor_char, cursor_style)

        # Icon
        icon = file_icon(entry)
        ic = icon_color(entry)
        Tachikoma.set_string!(buf, inner_x + 2, row, icon,
            Tachikoma.Style(; fg=ic, bg=Theme.SIDEBAR_BG))

        # Filename
        name = first(entry.name, max_name_w)
        name_fg = is_cursor ? Theme.FG : (entry.is_hidden ? Theme.FG_MUTED : Theme.FG_DIM)
        Tachikoma.set_string!(buf, inner_x + 4, row, name,
            Tachikoma.Style(; fg=name_fg, bg=Theme.SIDEBAR_BG))
    end

    # ── Bottom border with cursor position ────────────────────────────
    if !isempty(fp.entries)
        pos_text = "$(fp.cursor_idx)/$(length(fp.entries))"
        pos_x = bx + bw - length(pos_text) - 2
        if pos_x > bx + 1
            Tachikoma.set_char!(buf, pos_x - 1, by + bh - 1, '┤', border_style)
            Tachikoma.set_string!(buf, pos_x, by + bh - 1, pos_text,
                Tachikoma.Style(; fg=Theme.FG_DIM, bg=Theme.SIDEBAR_BG))
            Tachikoma.set_char!(buf, pos_x + length(pos_text), by + bh - 1,
                '├', border_style)
        end
    end
end

"""Render the folder picker overlay (directory-only browser with select button)."""
function _render_picker!(fp::FilePanel, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    hi = Theme.CELL_H_INSET
    vi = Theme.CELL_V_INSET
    border_style = Tachikoma.Style(; fg=Theme.ACCENT_DIM, bg=Theme.SIDEBAR_BG)
    bg = Tachikoma.Style(; bg=Theme.SIDEBAR_BG)

    # Fill
    for fy in rect.y:(rect.y + rect.height - 1)
        Tachikoma.set_string!(buf, rect.x, fy, " " ^ rect.width, bg)
    end

    # Border inset
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

    inner_x = bx + 1
    inner_w = bw - 2
    inner_w < 2 && return

    # Header: "Open Folder"
    header_y = by + 1
    title = "Open Folder"
    title_style = Tachikoma.Style(; fg=Theme.ACCENT_GLOW, bg=Theme.SIDEBAR_BG, bold=true)
    Tachikoma.set_string!(buf, inner_x + 1, header_y, first(title, inner_w - 2), title_style)

    # Parent row: "⊖ .." to go up
    parent_y = by + 2
    parent_style = Tachikoma.Style(; fg=Theme.FG_DIM, bg=Theme.SIDEBAR_BG)
    Tachikoma.set_string!(buf, inner_x + 1, parent_y, "⊖ ..", parent_style)
    # Show current dir on right
    dir_name = basename(fp.picker_dir)
    if isempty(dir_name); dir_name = fp.picker_dir; end
    dir_max = inner_w - 7
    if dir_max > 0
        dir_text = first(dir_name, dir_max)
        Tachikoma.set_string!(buf, inner_x + 6, parent_y, dir_text,
            Tachikoma.Style(; fg=Theme.FG_MUTED, bg=Theme.SIDEBAR_BG))
    end

    # Divider
    div_y = by + 3
    Tachikoma.set_char!(buf, bx, div_y, '├', border_style)
    Tachikoma.set_char!(buf, bx + bw - 1, div_y, '┤', border_style)
    for cx in (bx + 1):(bx + bw - 2)
        Tachikoma.set_char!(buf, cx, div_y, '─', border_style)
    end

    # Directory entries
    entries_start = by + 4
    # Reserve 1 row for select button on bottom border
    entries_height = bh - 5  # border(2) + header(1) + parent(1) + divider(1)
    entries_height < 1 && return

    # Auto-scroll
    if fp.picker_cursor - 1 < fp.picker_scroll
        fp.picker_scroll = fp.picker_cursor - 1
    end
    if fp.picker_cursor - 1 >= fp.picker_scroll + entries_height
        fp.picker_scroll = fp.picker_cursor - entries_height
    end
    fp.picker_scroll = clamp(fp.picker_scroll, 0, max(0, length(fp.picker_entries) - entries_height))

    max_name_w = inner_w - 5

    for vi_idx in 0:(entries_height - 1)
        ei = fp.picker_scroll + vi_idx + 1
        ei > length(fp.picker_entries) && break
        entry = fp.picker_entries[ei]
        row = entries_start + vi_idx
        is_cursor = (ei == fp.picker_cursor)

        cursor_char = is_cursor ? "›" : " "
        cursor_fg = is_cursor ? Theme.ACCENT_GLOW : Theme.FG_MUTED
        Tachikoma.set_string!(buf, inner_x, row, cursor_char,
            Tachikoma.Style(; fg=cursor_fg, bg=Theme.SIDEBAR_BG))
        Tachikoma.set_string!(buf, inner_x + 2, row, ICON_FOLDER,
            Tachikoma.Style(; fg=Theme.ACCENT, bg=Theme.SIDEBAR_BG))
        name = first(entry.name, max_name_w)
        name_fg = is_cursor ? Theme.FG : Theme.FG_DIM
        Tachikoma.set_string!(buf, inner_x + 4, row, name,
            Tachikoma.Style(; fg=name_fg, bg=Theme.SIDEBAR_BG))
    end

    # Select button on bottom border — "┤ Select ├"
    sel_text = " Select "
    sel_x = bx + div(bw - length(sel_text) - 2, 2)
    if sel_x > bx
        Tachikoma.set_char!(buf, sel_x, by + bh - 1, '┤', border_style)
        Tachikoma.set_string!(buf, sel_x + 1, by + bh - 1, sel_text,
            Tachikoma.Style(; fg=Theme.ACCENT_GLOW, bg=Theme.SIDEBAR_BG, bold=true))
        Tachikoma.set_char!(buf, sel_x + 1 + length(sel_text), by + bh - 1, '├', border_style)
    end
end

"""Truncate a path from the beginning with ... prefix."""
function _truncate_path(path::String, max_width::Int)
    max_width < 4 && return "..."
    length(path) <= max_width && return path
    # Show as much of the end as possible
    return "…" * path[end-max_width+2:end]
end
