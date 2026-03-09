# TUI: Tab bar — VS Code–style editor tabs with close buttons

"""A deleted cell with its original position for undo."""
struct DeletedCell
    cell::Cell
    position::Int
end

"""Create a safe notebook snapshot for diffing (avoids deepcopy of Module references in error stacktraces)."""
function _snapshot_notebook(nb::Notebook)
    snap = Notebook(; path=nb.path)
    for id in nb.cell_order
        cell = nb.cells[id]
        push!(snap.cell_order, id)
        snap.cells[id] = Cell(; id, code=cell.code, folded=cell.folded, disabled=cell.disabled)
    end
    snap
end

"""A single editor tab holding either a notebook or a file editor."""
mutable struct EditorTab
    id::UUID
    label::String                               # display name (filename)
    path::String                                # file path
    tab_type::Symbol                            # :notebook or :file
    # Notebook state
    nb::Notebook
    workspace::Workspace
    notebook_view::NotebookView
    last_disk_nb::Union{Notebook, Nothing}
    watcher::Union{DebouncedWatcher, Nothing}
    last_save_time::Float64
    # File editor state
    file_editor_view::Union{Nothing, FileEditorView}
    # Per-tab state
    undo_buffer::Vector{DeletedCell}
    progress_recently::Set{UUID}
    progress_done_tick::Int
    mode::Symbol                                # :panel, :normal, :insert
end

"""Create a notebook tab."""
function EditorTab(nb::Notebook)
    nv = NotebookView(nb)
    ws = Workspace(; notebook_path=nb.path)
    snap = _snapshot_notebook(nb)
    EditorTab(uuid4(), basename(nb.path), nb.path, :notebook,
        nb, ws, nv, snap, nothing, 0.0,
        nothing,
        DeletedCell[], Set{UUID}(), 0, :normal)
end

"""Create a file editor tab."""
function EditorTab(fev::FileEditorView)
    # Dummy notebook for compatibility
    nb = Notebook(; path=fev.path)
    nv = NotebookView(nb)
    ws = Workspace(; notebook_path=fev.path)
    EditorTab(uuid4(), basename(fev.path), fev.path, :file,
        nb, ws, nv, nothing, nothing, 0.0,
        fev,
        DeletedCell[], Set{UUID}(), 0, :insert)
end

"""Check if this tab has unsaved changes."""
function is_tab_dirty(tab::EditorTab)
    if tab.tab_type == :file
        fev = tab.file_editor_view
        return fev !== nothing && fev.dirty
    else
        tab.last_disk_nb === nothing && return false
        snap = tab.last_disk_nb
        nb = tab.nb
        nb.cell_order != snap.cell_order && return true
        for id in nb.cell_order
            haskey(snap.cells, id) || return true
            nb.cells[id].code != snap.cells[id].code && return true
            nb.cells[id].folded != snap.cells[id].folded && return true
            nb.cells[id].disabled != snap.cells[id].disabled && return true
        end
        false
    end
end

"""Tab icon based on type."""
function tab_icon(tab::EditorTab)
    if tab.tab_type == :notebook
        "◆"
    else
        ext = lowercase(splitext(tab.path)[2])
        ext == ".jl" ? "◇" : ext == ".md" ? "≡" : ext == ".toml" ? "⟐" : "·"
    end
end

const TAB_BAR_HEIGHT = 1  # single row

"""Render the tab bar. Returns Vector of (tab_rect, close_rect) for mouse hit testing."""
function render_tab_bar!(tabs::Vector{EditorTab}, active_idx::Int,
                         rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    tab_rects = Tachikoma.Rect[]
    close_rects = Tachikoma.Rect[]

    # Fill with background
    bg_style = Tachikoma.Style(; fg=Theme.FG_MUTED, bg=Theme.BG)
    Tachikoma.set_string!(buf, rect.x, rect.y, " " ^ rect.width, bg_style)

    x = rect.x
    max_x = rect.x + rect.width - 1

    for (i, tab) in enumerate(tabs)
        is_active = (i == active_idx)
        dirty = is_tab_dirty(tab)

        icon = tab_icon(tab)
        name = tab.label
        # Truncate long names
        if length(name) > 18
            name = name[1:15] * "..."
        end
        dirty_mark = dirty ? " ●" : ""
        # Tab content: " icon name ● × "
        label = " $(icon) $(name)$(dirty_mark) × "
        tab_len = length(label)

        # Don't overflow
        x + tab_len > max_x + 1 && break

        # Styles
        tab_bg = is_active ? Theme.CANVAS_BG : Theme.BG
        tab_fg = is_active ? Theme.FG : Theme.FG_DIM
        dirty_fg = dirty ? Theme.DIRTY_BORDER_FG : tab_fg
        tab_style = Tachikoma.Style(; fg=tab_fg, bg=tab_bg)

        # Render tab background
        Tachikoma.set_string!(buf, x, rect.y, " " ^ tab_len, Tachikoma.Style(; bg=tab_bg))

        # Render icon
        icon_fg = if tab.tab_type == :notebook
            is_active ? Theme.GREEN : Theme.GREEN_DIM
        else
            is_active ? Theme.FG_DIM : Theme.FG_MUTED
        end
        Tachikoma.set_string!(buf, x + 1, rect.y, icon,
            Tachikoma.Style(; fg=icon_fg, bg=tab_bg))

        # Render name
        name_with_dirty = "$(name)$(dirty_mark)"
        name_style = Tachikoma.Style(; fg=(dirty ? dirty_fg : tab_fg), bg=tab_bg,
            bold=is_active)
        Tachikoma.set_string!(buf, x + 3, rect.y, name_with_dirty, name_style)

        # Render × close button
        close_x = x + tab_len - 2  # position of ×
        close_fg = is_active ? Theme.FG_MUTED : Theme.FG_FAINT
        Tachikoma.set_string!(buf, close_x, rect.y, "×",
            Tachikoma.Style(; fg=close_fg, bg=tab_bg))

        # Store rects
        push!(tab_rects, Tachikoma.Rect(x, rect.y, tab_len, 1))
        push!(close_rects, Tachikoma.Rect(close_x, rect.y, 1, 1))

        x += tab_len

        # Separator between tabs
        if i < length(tabs) && x <= max_x
            sep_fg = Theme.BORDER_DIM
            Tachikoma.set_string!(buf, x, rect.y, "│",
                Tachikoma.Style(; fg=sep_fg, bg=Theme.BG))
            x += 1
        end
    end

    # Bottom edge line for inactive area (after all tabs)
    if x <= max_x
        Tachikoma.set_string!(buf, x, rect.y, " " ^ (max_x - x + 1), bg_style)
    end

    (tab_rects, close_rects)
end
