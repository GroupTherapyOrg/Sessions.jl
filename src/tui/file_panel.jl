# TUI: File explorer panel — superfile-inspired sidebar
# Rounded borders, file type icons, cursor indicator, click navigation
# Navigate directories inline: click folders to enter, .. to go up

struct FileEntry
    name::String
    path::String
    is_dir::Bool
    is_hidden::Bool
    is_notebook::Bool  # cached: is this a Pluto/Sessions notebook?
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
    hovered_idx::Int       # which entry the mouse is hovering (0 = none)
    last_refresh_tick::Int  # tick when entries were last refreshed
end

function FilePanel(dir::String=".")
    dir = abspath(dir)
    fp = FilePanel(dir, dir, FileEntry[], 1, 0, Tachikoma.Rect(), false, 0, 0)
    refresh_entries!(fp)
    fp
end

"""Scan current_dir and populate entries."""
function refresh_entries!(fp::FilePanel)
    fp.entries = FileEntry[]
    isdir(fp.current_dir) || return

    # Add parent directory entry (..) if not at filesystem root
    parent = dirname(fp.current_dir)
    if parent != fp.current_dir
        push!(fp.entries, FileEntry("..", parent, true, false, false, 0))
    end

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
            push!(dirs, FileEntry(name, full, true, is_hidden, false, 0))
        else
            sz = try; filesize(full); catch; Int64(0); end
            is_nb = endswith(name, ".jl") ? is_notebook_file(full) : false
            push!(files, FileEntry(name, full, false, is_hidden, is_nb, sz))
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
    parent == fp.current_dir && return  # already at root
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
    if entry.name == ".." && entry.is_dir
        go_up!(fp)
        return nothing
    elseif entry.is_dir
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

# ── Icons & colors per file type ──────────────────────────────────────

# Using simple Unicode that works without nerd fonts
const ICON_FOLDER     = "▸"
const ICON_FOLDER_OPEN = "▾"
const ICON_FILE       = "·"
const ICON_JULIA_NB   = "◆"   # filled diamond — Pluto/Sessions notebook
const ICON_JULIA      = "◇"   # hollow diamond — plain .jl file
const ICON_PYTHON     = "⊙"
const ICON_MARKDOWN   = "≡"
const ICON_JSON       = "⟐"
const ICON_YAML       = "⟐"
const ICON_TOML       = "⟐"
const ICON_GIT        = "●"
const ICON_SHELL      = "⊞"
const ICON_IMAGE      = "◻"
const ICON_ARCHIVE    = "⊠"
const ICON_SESSION    = "◈"   # session cache file
const ICON_PARENT     = "⊖"

function file_icon(entry::FileEntry)
    entry.name == ".." && return ICON_PARENT
    entry.is_dir && return ICON_FOLDER
    ext = lowercase(splitext(entry.name)[2])
    if ext == ".jl"
        return entry.is_notebook ? ICON_JULIA_NB : ICON_JULIA
    end
    endswith(entry.name, ".session") && return ICON_SESSION
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
    entry.name == ".." && return Theme.FG_DIM
    entry.is_dir && return Theme.ACCENT
    ext = lowercase(splitext(entry.name)[2])
    if ext == ".jl"
        return entry.is_notebook ? Theme.GREEN : Theme.GREEN_DIM
    end
    endswith(entry.name, ".session") && return Theme.FG_MUTED
    ext == ".py"    && return Theme.CYAN
    ext == ".md"    && return Theme.FG_DIM
    ext == ".json"  && return Theme.ORANGE
    ext == ".yaml"  && return Theme.ORANGE
    ext == ".yml"   && return Theme.ORANGE
    ext == ".toml"  && return Theme.ORANGE
    ext == ".sh"    && return Theme.GREEN_DIM
    ext == ".bash"  && return Theme.GREEN_DIM
    ext == ".zsh"   && return Theme.GREEN_DIM
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


const FILE_PANEL_REFRESH_INTERVAL = 60  # ticks between auto-refreshes (~2s at 30fps)

function Tachikoma.render(fp::FilePanel, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    fp.viewport = rect
    rect.width < 4 && return
    rect.height < 4 && return

    # Auto-refresh entries periodically to pick up filesystem changes
    tick = Theme.tick()
    if tick - fp.last_refresh_tick >= FILE_PANEL_REFRESH_INTERVAL
        fp.last_refresh_tick = tick
        refresh_entries!(fp)
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

    max_name_w = inner_w - 7  # cursor(1) + space(1) + icon(1) + space(1) + padding(1) + trash(1) + pad(1)

    for vi_idx in 0:(entries_height - 1)
        ei = fp.scroll_offset + vi_idx + 1
        ei > length(fp.entries) && break
        entry = fp.entries[ei]
        row = entries_start_y + vi_idx
        is_cursor = (ei == fp.cursor_idx)
        is_hovered = (ei == fp.hovered_idx)
        is_jl = endswith(entry.name, ".jl")

        # Cursor indicator
        cursor_char = is_cursor ? "›" : (is_hovered ? "›" : " ")
        cursor_fg = is_cursor ? Theme.ACCENT_GLOW : (is_hovered ? Theme.ACCENT_DIM : Theme.FG_MUTED)
        Tachikoma.set_string!(buf, inner_x, row, cursor_char,
            Tachikoma.Style(; fg=cursor_fg, bg=Theme.SIDEBAR_BG))

        # Icon — brighten on hover
        icon = file_icon(entry)
        ic = icon_color(entry)
        if is_hovered && !is_cursor
            ic = Theme.ACCENT_GLOW
        end
        Tachikoma.set_string!(buf, inner_x + 2, row, icon,
            Tachikoma.Style(; fg=ic, bg=Theme.SIDEBAR_BG))

        # Filename — color varies by state and file type
        name = first(entry.name, max_name_w)
        name_fg = if is_cursor
            Theme.FG
        elseif is_hovered
            Theme.FG  # bright on hover
        elseif entry.name == ".."
            Theme.FG_DIM
        elseif entry.is_dir
            Theme.FG_DIM
        elseif is_jl
            Theme.FG_DIM
        elseif entry.is_hidden
            Theme.FG_MUTED
        else
            Theme.FG_MUTED  # non-.jl files are dimmer
        end
        Tachikoma.set_string!(buf, inner_x + 4, row, name,
            Tachikoma.Style(; fg=name_fg, bg=Theme.SIDEBAR_BG))

        # Trash icon on far right (skip ".." parent entry)
        if entry.name != ".."
            trash_x = inner_x + inner_w - 2
            trash_fg = (is_hovered || is_cursor) ? Theme.RED : Theme.FG_MUTED
            Tachikoma.set_string!(buf, trash_x, row, "✕",
                Tachikoma.Style(; fg=trash_fg, bg=Theme.SIDEBAR_BG))
        end
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

"""Check if a click x-coordinate hits the trash icon for an entry row."""
function is_trash_click(fp::FilePanel, screen_x::Int, screen_y::Int)
    vp = fp.viewport
    vp.width == 0 && return false
    hi = Theme.CELL_H_INSET
    bx = vp.x + hi
    bw = max(vp.width - 2 * hi, 3)
    inner_x = bx + 1
    inner_w = bw - 2
    trash_x = inner_x + inner_w - 2
    return screen_x == trash_x
end

"""Truncate a path from the beginning with ... prefix."""
function _truncate_path(path::String, max_width::Int)
    max_width < 4 && return "..."
    length(path) <= max_width && return path
    # Show as much of the end as possible
    return "…" * path[end-max_width+2:end]
end
