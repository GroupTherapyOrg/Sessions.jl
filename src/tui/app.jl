# TUI: Main application — SessionsApp Model/update!/view

"""A deleted cell with its original position for undo."""
struct DeletedCell
    cell::Cell
    position::Int
end

"""Dropdown menu anchored to a cell (Pluto-style ⋯ menu)."""
mutable struct CellDropdown
    cell_idx::Int           # which cell this is for
    x::Int                  # screen x of dropdown top-left
    y::Int                  # screen y of dropdown top-left
    items::Vector{Tuple{String, String}}  # (icon, label) pairs
    hovered_idx::Int        # which item mouse is hovering (0 = none)
end

const DROPDOWN_ITEMS = [
    ("⊗", "Delete cell"),
]

"""Centered confirmation dialog (e.g. delete cell confirmation)."""
mutable struct ConfirmDialog
    title::String
    message::String
    on_confirm::Function    # called if user clicks Yes
    selected::Symbol        # :no or :yes — which button has keyboard focus
    yes_hovered::Bool
    no_hovered::Bool
end

"""Sessions notebook TUI application model."""
mutable struct SessionsApp <: Tachikoma.Model
    nb::Notebook
    workspace::Workspace
    notebook_view::NotebookView
    file_panel::FilePanel
    activity_bar::ActivityBar
    tq::Tachikoma.TaskQueue
    mode::Symbol        # :normal, :insert, :dropdown, or :confirm
    quit::Bool
    message::String     # Status message (temporary)
    cell_dropdown::Union{Nothing, CellDropdown}
    confirm_dialog::Union{Nothing, ConfirmDialog}
    undo_buffer::Vector{DeletedCell}
    sidebar_open::Bool         # whether file panel is visible
    sidebar_rect::Tachikoma.Rect   # cached for mouse hit testing
    activity_rect::Tachikoma.Rect  # cached for mouse hit testing
    screen_area::Tachikoma.Rect    # full screen area, cached for confirm dialog
    progress_recently::Set{UUID}   # cells seen running/queued this execution batch
    progress_done_tick::Int        # tick when batch completed (0 = not done yet)
    last_disk_nb::Union{Notebook, Nothing}  # snapshot of notebook as last loaded/saved from disk
    watcher::Union{DebouncedWatcher, Nothing}  # file watcher for external changes
    last_save_time::Float64  # time() of last save_notebook by us (for skip-reload guard)
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

function SessionsApp(nb::Notebook)
    ws = Workspace()
    nv = NotebookView(nb)
    dir = isempty(nb.path) ? pwd() : dirname(abspath(nb.path))
    fp = FilePanel(dir)
    ab = ActivityBar()
    snapshot = _snapshot_notebook(nb)
    SessionsApp(nb, ws, nv, fp, ab, Tachikoma.TaskQueue(), :normal, false, "", nothing, nothing,
        DeletedCell[], true, Tachikoma.Rect(), Tachikoma.Rect(), Tachikoma.Rect(), Set{UUID}(), 0, snapshot, nothing, 0.0)
end

function SessionsApp(path::String)
    nb = load_notebook_with_session(path)
    SessionsApp(nb)
end

Tachikoma.should_quit(app::SessionsApp) = app.quit
Tachikoma.task_queue(app::SessionsApp) = app.tq

"""Enable any-event mouse tracking (1003) for true hover support.
Also loads CommonMark.jl extension for markdown rendering.
Starts file watcher if notebook has a valid path."""
function Tachikoma.init!(app::SessionsApp, t::Tachikoma.Terminal)
    print(t.io, "\e[?1003h")  # upgrade to any-event tracking
    try; Tachikoma.enable_markdown(); catch; end  # load CommonMark extension
    _start_watcher!(app)
end

"""Start or restart the file watcher for external change detection."""
function _start_watcher!(app::SessionsApp)
    # Stop existing watcher if any
    if app.watcher !== nothing
        stop_watching!(app.watcher)
        app.watcher = nothing
    end

    path = app.nb.path
    (isempty(path) || !isfile(path)) && return

    app.watcher = DebouncedWatcher(app.nb, _ -> _on_external_change!(app);
                                    delay=0.5, poll_interval=0.3)
    start_watching!(app.watcher)
end

"""Handle external file change: smart merge + rebuild widgets."""
const SAVE_GUARD_TOLERANCE = 1.0  # seconds — skip reload if file changed within this window after our save

function _on_external_change!(app::SessionsApp)
    app.last_disk_nb === nothing && return

    # Skip reload if we just saved the file ourselves
    if app.last_save_time > 0.0 && (time() - app.last_save_time) < SAVE_GUARD_TOLERANCE
        return
    end

    try
        old_order = copy(app.last_disk_nb.cell_order)
        diff = merge_external_changes!(app.nb, app.last_disk_nb)
        app.last_disk_nb = _snapshot_notebook(app.nb)

        reordered = diff.new_order != old_order
        n_changes = length(diff.added) + length(diff.changed) + length(diff.removed) + length(diff.metadata_changed)
        n_changes == 0 && !reordered && return

        rebuild_widgets!(app.notebook_view)
        app.cell_dropdown = nothing
        app.confirm_dialog = nothing
        app.mode = :normal
        for cw in app.notebook_view.cell_widgets
            cw.selected = false
        end
        msg_parts = String[]
        n_changes > 0 && push!(msg_parts, "$n_changes cell(s)")
        reordered && push!(msg_parts, "reordered")
        app.message = join(msg_parts, " + ") * " changed externally"
    catch e
        app.message = "Reload error: $(sprint(showerror, e))"
    end
end

function Tachikoma.view(app::SessionsApp, frame::Tachikoma.Frame)
    Theme.advance_tick!()
    area = frame.area
    app.screen_area = area
    buf = frame.buffer
    g = Theme.ISLAND_GAP

    # Fill entire screen with pure black background — islands float on top
    for fy in area.y:(area.y + area.height - 1)
        Tachikoma.set_string!(buf, area.x, fy, " " ^ area.width, Theme.S_BG)
    end

    # Inset content by the same gap on all edges (uniform padding from terminal edge)
    content_rect = Tachikoma.Rect(area.x + g, area.y + g,
        max(1, area.width - 2 * g), max(1, area.height - 2 * g))

    # Horizontal layout: activity bar | gap | [file panel | gap] | notebook
    ab_w = Theme.ACTIVITY_BAR_W
    if app.sidebar_open
        h_layout = Tachikoma.Layout(Tachikoma.Horizontal,
            [Tachikoma.Fixed(ab_w), Tachikoma.Fixed(g),
             Tachikoma.Percent(Theme.SIDEBAR_PCT), Tachikoma.Fixed(g),
             Tachikoma.Fill()])
        h_rects = Tachikoma.split_layout(h_layout, content_rect)
        activity_rect = h_rects[1]
        sidebar_rect = h_rects[3]
        notebook_rect = h_rects[5]
    else
        h_layout = Tachikoma.Layout(Tachikoma.Horizontal,
            [Tachikoma.Fixed(ab_w), Tachikoma.Fixed(g), Tachikoma.Fill()])
        h_rects = Tachikoma.split_layout(h_layout, content_rect)
        activity_rect = h_rects[1]
        sidebar_rect = Tachikoma.Rect()
        notebook_rect = h_rects[3]
    end

    # Shrink activity bar to just fit its buttons (border=2 + 1 row per button)
    ab_content_h = 2 + length(ACTIVITY_BUTTONS) * 2
    ab_h = min(ab_content_h, activity_rect.height)
    activity_rect = Tachikoma.Rect(activity_rect.x, activity_rect.y,
        activity_rect.width, ab_h)

    # Cache rects for mouse hit testing
    app.activity_rect = activity_rect
    app.sidebar_rect = sidebar_rect

    # Render activity bar (always visible)
    Tachikoma.render(app.activity_bar, activity_rect, buf)

    # Render file panel (only when open)
    if app.sidebar_open
        Tachikoma.render(app.file_panel, sidebar_rect, buf)
    end

    # Editor cursor only visible in insert mode on the focused cell
    for (i, cw) in enumerate(app.notebook_view.cell_widgets)
        cw.editor.focused = (i == app.notebook_view.focused_idx && app.mode == :insert)
    end

    # Notebook view (main content — fills remaining space)
    Tachikoma.render(app.notebook_view, notebook_rect, buf)

    # Repaint areas above/below notebook to hide cell/output overflow past notebook boundary
    for fy in area.y:(notebook_rect.y - 1)
        Tachikoma.set_string!(buf, area.x, fy, " " ^ area.width, Theme.S_BG)
    end
    nb_bottom = notebook_rect.y + notebook_rect.height
    screen_bottom = area.y + area.height - 1
    for fy in nb_bottom:screen_bottom
        Tachikoma.set_string!(buf, area.x, fy, " " ^ area.width, Theme.S_BG)
    end

    # Progress bar — overlays notebook pane top border during execution
    _update_and_render_progress!(app, notebook_rect, buf)

    # Cell dropdown overlay
    if app.cell_dropdown !== nothing
        _render_dropdown!(app.cell_dropdown, buf, area)
    end

    # Confirm dialog overlay (centered, with dimmed backdrop)
    if app.confirm_dialog !== nothing
        _render_confirm_dialog!(app.confirm_dialog, buf, area)
    end
end

"""Update progress tracking state and render the progress bar on the notebook top border."""
function _update_and_render_progress!(app::SessionsApp, notebook_rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    # Scan cell states — build current active set
    currently_active = Set{UUID}()
    for cell in ordered_cells(app.nb)
        if cell.state == cell_running || cell.state == cell_queued
            push!(currently_active, cell.id)
            push!(app.progress_recently, cell.id)
        end
    end

    n_active = length(currently_active)
    n_recent = length(app.progress_recently)

    if n_recent == 0
        return  # nothing to show
    end

    if n_active == 0
        # All done — show green completion bar briefly
        if app.progress_done_tick == 0
            app.progress_done_tick = Theme.tick()
        end
        elapsed = Theme.tick() - app.progress_done_tick
        if elapsed > Theme.PROGRESS_HOLD
            # Fade out — clear tracking
            empty!(app.progress_recently)
            app.progress_done_tick = 0
            return
        end
        _render_progress_bar!(buf, notebook_rect, 1.0, true)
    else
        # In progress — Pluto's formula: subtract 0.3 for smooth visual
        app.progress_done_tick = 0
        progress = 1.0 - max(0, n_active - 0.3) / n_recent
        _render_progress_bar!(buf, notebook_rect, progress, false)
    end
end

"""Render a progress bar on the top border of the notebook pane."""
function _render_progress_bar!(buf::Tachikoma.Buffer, rect::Tachikoma.Rect, progress::Float64, complete::Bool)
    hi = Theme.CELL_H_INSET
    vi = Theme.CELL_V_INSET
    bx = rect.x + hi
    by = rect.y + vi  # top border row
    bw = max(rect.width - 2 * hi, 3)

    # Bar spans the top border between corners (bx+1 to bx+bw-2)
    bar_start = bx + 1
    bar_total = bw - 2
    bar_total < 1 && return
    bar_filled = round(Int, bar_total * clamp(progress, 0.0, 1.0))

    fg = complete ? Theme.PROGRESS_DONE_FG : Theme.PROGRESS_FG
    style = Tachikoma.Style(; fg=fg, bg=Theme.CANVAS_BG)

    for x in bar_start:(bar_start + bar_filled - 1)
        Tachikoma.set_char!(buf, x, by, '━', style)
    end
end

"""Handle mouse events in the file panel sidebar."""
function _handle_file_panel_mouse!(app::SessionsApp, evt::Tachikoma.MouseEvent)
    fp = app.file_panel

    # Scroll in sidebar
    if evt.button == Tachikoma.mouse_scroll_down
        cursor_down!(fp)
        return
    end
    if evt.button == Tachikoma.mouse_scroll_up
        cursor_up!(fp)
        return
    end

    # Click on a file entry
    if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press
        idx = entry_at_y(fp, evt.y)
        if idx !== nothing
            fp.cursor_idx = idx
            result = activate!(fp)
            if result !== nothing
                # Clicked a file — open it as notebook if it's .jl
                if endswith(result, ".jl")
                    _open_file!(app, result)
                end
            end
        end
    end
end

"""Handle mouse events in the folder picker."""
function _handle_picker_mouse!(app::SessionsApp, evt::Tachikoma.MouseEvent)
    fp = app.file_panel

    if evt.button == Tachikoma.mouse_scroll_down
        fp.picker_cursor = min(length(fp.picker_entries), fp.picker_cursor + 1)
        return
    end
    if evt.button == Tachikoma.mouse_scroll_up
        fp.picker_cursor = max(1, fp.picker_cursor - 1)
        return
    end

    if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press
        hit = picker_hit_at_y(fp, evt.y)
        if hit == :parent
            picker_go_up!(fp)
        elseif hit == :select
            # Select current picker_dir as workspace
            reset_to_folder!(app, fp.picker_dir)
            exit_picker_mode!(fp)
            app.activity_bar.active = :explorer
        elseif hit isa Integer && hit >= 1 && hit <= length(fp.picker_entries)
            fp.picker_cursor = hit
            # Double-purpose: click enters the directory to browse deeper
            picker_enter!(fp, fp.picker_entries[hit].path)
        end
    end
end

"""Open a .jl file as a notebook."""
function _open_file!(app::SessionsApp, path::String)
    try
        nb = load_notebook_with_session(path)
        app.nb = nb
        app.workspace = Workspace()
        app.notebook_view = NotebookView(nb)
        app.last_disk_nb = _snapshot_notebook(nb)
        _start_watcher!(app)
        app.message = "Opened: $(basename(path))"
    catch e
        app.message = "Error: $(sprint(showerror, e))"
    end
end

"""Reset the entire workspace to a new folder. Creates an empty notebook and refreshes the file panel."""
function reset_to_folder!(app::SessionsApp, dir::String)
    dir = abspath(dir)
    isdir(dir) || return

    # Find first .jl file to auto-open, or create empty notebook
    jl_files = filter(f -> endswith(f, ".jl"), try readdir(dir) catch; String[] end)
    nb = if !isempty(jl_files)
        path = joinpath(dir, first(jl_files))
        try
            load_notebook_with_session(path)
        catch
            nb = Notebook(; path=joinpath(dir, "Untitled.jl"))
            add_cell!(nb, "")
            nb
        end
    else
        nb = Notebook(; path=joinpath(dir, "Untitled.jl"))
        add_cell!(nb, "")
        nb
    end

    app.nb = nb
    app.workspace = Workspace()
    app.notebook_view = NotebookView(nb)
    app.file_panel = FilePanel(dir)
    app.undo_buffer = DeletedCell[]
    app.cell_dropdown = nothing
    app.confirm_dialog = nothing
    app.mode = :normal
    app.last_disk_nb = _snapshot_notebook(nb)
    _start_watcher!(app)
    app.message = "Opened workspace: $(basename(dir))"
end

function Tachikoma.update!(app::SessionsApp, evt::Tachikoma.KeyEvent)
    app.message = ""  # Clear status message on any key

    # Confirm dialog mode — arrow keys navigate, Enter submits, Escape dismisses
    if app.mode == :confirm && app.confirm_dialog !== nothing
        cd = app.confirm_dialog
        if evt.key == :escape
            close_confirm!(app)
        elseif evt.key == :left || evt.key == :right
            cd.selected = cd.selected == :no ? :yes : :no
        elseif evt.key == :enter
            if cd.selected == :yes
                cd.on_confirm()
            end
            close_confirm!(app)
        else
            # Any other key = dismiss (No)
            close_confirm!(app)
        end
        return
    end

    # Dropdown mode — only Escape closes it (all interaction is mouse)
    if app.mode == :dropdown && app.cell_dropdown !== nothing
        if evt.key == :escape
            close_dropdown!(app)
        end
        return
    end

    # --- Essential keybindings only (everything else is mouse-driven) ---

    # Ctrl+Q: quit
    if evt.key == :ctrl && evt.char == 'q'
        if app.watcher !== nothing
            stop_watching!(app.watcher)
            app.watcher = nothing
        end
        app.quit = true
        return
    end

    # Ctrl+S: save + run stale
    if evt.key == :ctrl && evt.char == 's'
        save_notebook(app.nb)
        app.last_save_time = time()
        app.last_disk_nb = _snapshot_notebook(app.nb)
        n_stale = run_stale_cells!(app)
        if n_stale > 0
            app.message = "Saved + ran $n_stale stale cell$(n_stale == 1 ? "" : "s")"
        else
            app.message = "Saved: $(app.nb.path)"
        end
        return
    end

    # Run focused cell: Ctrl+R, Shift+Enter, Ctrl+Enter
    if (evt.key == :ctrl && evt.char == 'r') ||
       evt.key == :shift_enter || evt.key == :ctrl_enter || evt.key == :shift_ctrl_enter
        run_focused_cell_async!(app)
        return
    end

    # Escape: exit insert mode → normal mode, or clear selection
    if evt.key == :escape
        if app.mode == :insert
            _exit_insert_mode!(app)
        elseif has_selection(app.notebook_view)
            clear_selection!(app.notebook_view)
        end
        return
    end

    # --- Insert mode: all keys (including Delete/Backspace) go to the editor ---
    if app.mode == :insert
        cw = focused_widget(app.notebook_view)
        if cw !== nothing
            Tachikoma.handle_key!(cw, evt)
        end
        return
    end

    # --- Normal mode keybindings ---

    # Arrow keys: navigate cells
    if evt.key == :up
        focus_prev!(app.notebook_view)
        return
    end
    if evt.key == :down
        focus_next!(app.notebook_view)
        return
    end

    # Enter: enter insert mode on focused cell
    if evt.key == :enter
        _enter_insert_mode!(app)
        return
    end

    # Delete/Backspace: open delete cell confirm dialog
    if evt.key == :delete || evt.key == :backspace
        nv = app.notebook_view
        idx = nv.focused_idx
        if !isempty(nv.cell_widgets) && length(nv.cell_widgets) > 1
            _open_confirm_delete!(app, idx)
        end
        return
    end

    # All other keys go to the focused cell's code editor
    cw = focused_widget(app.notebook_view)
    if cw !== nothing
        Tachikoma.handle_key!(cw, evt)
    end
end

"""Handle mouse events — Pluto-style click zones for cell controls."""
function Tachikoma.update!(app::SessionsApp, evt::Tachikoma.MouseEvent)
    nv = app.notebook_view

    # Activity bar clicks — toggle sidebar / open folder picker
    ar = app.activity_rect
    if ar.width > 0 && evt.x >= ar.x && evt.x < ar.x + ar.width &&
       evt.y >= ar.y && evt.y < ar.y + ar.height
        if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press
            btn_id = button_at_y(app.activity_bar, evt.y)
            if btn_id == :explorer
                # If in picker mode, exit it first
                if app.file_panel.picker_mode
                    exit_picker_mode!(app.file_panel)
                end
                toggle!(app.activity_bar, btn_id)
                app.sidebar_open = app.activity_bar.active == :explorer
            elseif btn_id == :open_folder
                # Toggle folder picker mode
                if app.file_panel.picker_mode
                    exit_picker_mode!(app.file_panel)
                    app.activity_bar.active = :explorer
                else
                    enter_picker_mode!(app.file_panel)
                    app.activity_bar.active = :open_folder
                    app.sidebar_open = true
                end
            end
        elseif evt.action == Tachikoma.mouse_move
            app.activity_bar.hovered = something(button_at_y(app.activity_bar, evt.y), :none)
        end
        return
    end

    # File panel clicks — if click is in sidebar area
    sr = app.sidebar_rect
    if sr.width > 0 && evt.x >= sr.x && evt.x < sr.x + sr.width &&
       evt.y >= sr.y && evt.y < sr.y + sr.height
        if app.file_panel.picker_mode
            _handle_picker_mouse!(app, evt)
        else
            _handle_file_panel_mouse!(app, evt)
        end
        return
    end

    # Confirm dialog mode: Yes button confirms, anything else dismisses
    if app.mode == :confirm && app.confirm_dialog !== nothing
        if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press
            hit = _confirm_hit_test(app.confirm_dialog, app.screen_area, evt.x, evt.y)
            if hit == :yes
                app.confirm_dialog.on_confirm()
                close_confirm!(app)
            else
                close_confirm!(app)
            end
            return
        end
        if evt.action == Tachikoma.mouse_move
            hit = _confirm_hit_test(app.confirm_dialog, app.screen_area, evt.x, evt.y)
            app.confirm_dialog.yes_hovered = (hit == :yes)
            app.confirm_dialog.no_hovered = (hit == :no)
            return
        end
        return
    end

    # Dropdown mode: handle clicks inside dropdown or click-away to dismiss
    if app.mode == :dropdown && app.cell_dropdown !== nothing
        if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press
            item_idx = _dropdown_hit_test(app.cell_dropdown, evt.x, evt.y)
            if item_idx !== nothing
                _execute_dropdown_action!(app, item_idx)
            end
            # Don't close dropdown if action transitioned to confirm dialog
            if app.mode == :dropdown
                close_dropdown!(app)
            end
            return
        end
        # Mouse move: update hover highlight in dropdown
        if evt.action == Tachikoma.mouse_move
            app.cell_dropdown.hovered_idx = something(_dropdown_hit_test(app.cell_dropdown, evt.x, evt.y), 0)
            return
        end
        return
    end

    # ── All remaining events require the click to be inside the notebook pane ──
    nb_vp = nv.viewport
    in_notebook = nb_vp.width > 0 &&
        evt.x >= nb_vp.x && evt.x < nb_vp.x + nb_vp.width &&
        evt.y >= nb_vp.y && evt.y < nb_vp.y + nb_vp.height

    if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press && in_notebook
        # Shift+click: range selection
        if evt.shift
            idx = cell_at_y(nv, evt.y)
            if idx !== nothing
                select_range!(nv, nv.focused_idx, idx)
            end
            return
        end

        # Compute cell layout dimensions (must match notebook_view rendering)
        hi = Theme.CELL_H_INSET
        vi = Theme.CELL_V_INSET
        inner_x = nb_vp.x + hi + 1
        inner_w = max(1, nb_vp.width - 2 * hi - 2)
        pad = max(1, round(Int, inner_w * Theme.CELL_PAD_FRACTION))
        pad = min(pad, max(0, div(inner_w - 10, 2)))
        cell_left = inner_x + pad
        cell_right = inner_x + inner_w - pad
        margin_x = max(cell_left - Theme.MARGIN_CTRL_WIDTH, inner_x)

        # Check if click is in the left margin area (for ▲, +, ▼, eye controls)
        # Expand hit zone: covers ▲ at margin_x-2 through ▼ at margin_x+4
        if evt.x >= max(margin_x - 1, nb_vp.x) && evt.x <= margin_x + 5
            hit = _hit_test_margin_control(nv, evt.x, evt.y, margin_x)
            if hit !== nothing
                _handle_margin_click!(app, hit)
                return
            end
        end

        # Check if click is on ⋯ button or ▶ run in gap
        if _hit_test_cell_controls(app, nv, evt.x, evt.y, cell_left, cell_right)
            return
        end

        # Cell click — only enter insert mode if click is inside the cell body
        idx = cell_at_y(nv, evt.y)
        if idx !== nothing
            clear_selection!(nv)
            focus_cell!(nv, idx)
            if evt.x >= cell_left && evt.x < cell_right
                _enter_insert_mode!(app)
            else
                # Click in margin/padding area — focus cell in normal mode
                _exit_insert_mode!(app)
            end
        else
            # Click in empty gap area — exit insert mode
            _exit_insert_mode!(app)
        end
        return
    end

    if in_notebook && evt.button == Tachikoma.mouse_scroll_down
        vi = Theme.CELL_V_INSET
        inner_h = max(1, nb_vp.height - 2 * vi - 2)  # subtract inset + border
        max_scroll = max(0, content_height(nv) - inner_h)
        nv.scroll_offset = min(nv.scroll_offset + 2, max_scroll)
        nv.user_scrolling = true
        return
    end

    if in_notebook && evt.button == Tachikoma.mouse_scroll_up
        nv.scroll_offset = max(nv.scroll_offset - 2, 0)
        nv.user_scrolling = true
        return
    end

    # Mouse move: update hover state only within notebook
    if evt.action == Tachikoma.mouse_move
        # Clear ellipsis hover on all cells
        for cw in nv.cell_widgets
            cw.ellipsis_hovered = false
        end

        if in_notebook
            idx = cell_at_y(nv, evt.y)
            nv.hovered_idx = idx !== nothing ? idx : 0

            # Detect margin control hover for color feedback
            hi = Theme.CELL_H_INSET
            vi = Theme.CELL_V_INSET
            inner_x = nb_vp.x + hi + 1
            inner_w = max(1, nb_vp.width - 2 * hi - 2)
            pad = max(1, round(Int, inner_w * Theme.CELL_PAD_FRACTION))
            pad = min(pad, max(0, div(inner_w - 10, 2)))
            cell_left = inner_x + pad
            cell_right = inner_x + inner_w - pad
            margin_x = max(cell_left - Theme.MARGIN_CTRL_WIDTH, inner_x)

            if evt.x >= max(margin_x - 1, nb_vp.x) && evt.x <= margin_x + 5
                hit = _hit_test_margin_control(nv, evt.x, evt.y, margin_x)
                if hit !== nothing
                    nv.hovered_control = hit[1]
                    nv.hovered_control_idx = hit[2]
                else
                    nv.hovered_control = :none
                    nv.hovered_control_idx = 0
                end
            else
                nv.hovered_control = :none
                nv.hovered_control_idx = 0
            end

            # Detect ellipsis button hover
            _update_cell_control_hover!(nv, evt.x, evt.y, cell_right)
        else
            nv.hovered_idx = 0
            nv.hovered_control = :none
            nv.hovered_control_idx = 0
        end
        return
    end
end

"""Update ellipsis and run button hover states during mouse move."""
function _update_cell_control_hover!(nv::NotebookView, mx::Int, my::Int, cell_right::Int)
    vp = nv.viewport
    hi = Theme.CELL_H_INSET
    vi = Theme.CELL_V_INSET
    border_right = cell_right - hi

    for target_idx in (nv.focused_idx, nv.hovered_idx)
        (target_idx < 1 || target_idx > length(nv.cell_widgets)) && continue
        cw = nv.cell_widgets[target_idx]

        y = vp.y + vi + 1 + Theme.TOP_MARGIN - nv.scroll_offset
        for j in 1:target_idx-1
            j_oh = output_height(nv.output_widgets[j])
            y += cell_height(nv.cell_widgets[j]; has_output=j_oh > 0)
            y += j_oh
            y += Theme.CELL_GAP
        end

        oh = output_height(nv.output_widgets[target_idx])
        ch = cell_height(cw; has_output=oh > 0)

        # Ellipsis button hover
        ellipsis_y = y + vi + 1
        ellipsis_x_start = border_right - 4
        if my >= ellipsis_y - 1 && my <= ellipsis_y + 1 &&
           mx >= ellipsis_x_start - 2 && mx <= border_right
            cw.ellipsis_hovered = true
            return
        end

        # Run button hover (row 0 of gap, directly below cell+output)
        run_y = y + ch + oh
        run_text = run_button_text(cw.cell)
        run_x = cell_right - length(run_text)
        if my >= run_y - 1 && my <= run_y + 1 &&
           mx >= run_x - 2 && mx <= cell_right + 2
            nv.hovered_control = :run
            nv.hovered_control_idx = target_idx
            return
        end
    end
end

"""Hit test margin controls. Returns (:plus_gap, pos), (:eye, idx), (:move_up, idx), (:move_down, idx), or nothing.
Hit zones are expanded ±1 row around each icon for easier clicking."""
function _hit_test_margin_control(nv::NotebookView, click_x::Int, click_y::Int, margin_x::Int)
    isempty(nv.cell_widgets) && return nothing
    vp = nv.viewport
    gap_mid = div(Theme.CELL_GAP, 2)
    n_cells = length(nv.cell_widgets)

    # Controls appear on focused OR hovered cell
    for target_idx in (nv.focused_idx, nv.hovered_idx)
        (target_idx < 1 || target_idx > n_cells) && continue

        vi = Theme.CELL_V_INSET
        y = vp.y + vi + 1 + Theme.TOP_MARGIN - nv.scroll_offset
        for j in 1:target_idx-1
            j_oh = output_height(nv.output_widgets[j])
            y += cell_height(nv.cell_widgets[j]; has_output=j_oh > 0)
            y += j_oh
            y += Theme.CELL_GAP
        end

        oh = output_height(nv.output_widgets[target_idx])
        ch = cell_height(nv.cell_widgets[target_idx]; has_output=oh > 0)

        # Eye icon first (highest priority)
        eye_y = y + div(ch, 2)
        if click_y >= eye_y - 1 && click_y <= eye_y + 1
            return (:eye, target_idx)
        end

        # Gap ABOVE this cell — + (add) then ▲ (move up) to the right
        gap_above_y = target_idx == 1 ? y - 1 : y - Theme.CELL_GAP + gap_mid
        if click_y >= gap_above_y - 1 && click_y <= gap_above_y + 1
            # ▲ at margin_x+3..margin_x+4 (right of +), only on active cell's top gap
            if click_x >= margin_x + 3 && click_x <= margin_x + 5 && target_idx > 1
                return (:move_up, target_idx)
            end
            # + at margin_x..margin_x+2
            if click_x >= margin_x - 1 && click_x <= margin_x + 2
                return (:plus_gap, target_idx)
            end
        end

        # Gap BELOW this cell — + (add) then ▼ (move down) to the right
        gap_below_y = y + ch + oh + gap_mid
        if click_y >= gap_below_y - 1 && click_y <= gap_below_y + 1
            # ▼ at margin_x+3..margin_x+4 (right of +), only on active cell's bottom gap
            if click_x >= margin_x + 3 && click_x <= margin_x + 5 && target_idx < n_cells
                return (:move_down, target_idx)
            end
            # + at margin_x..margin_x+2
            if click_x >= margin_x - 1 && click_x <= margin_x + 2
                return (:plus_gap, target_idx + 1)
            end
        end
    end

    nothing
end

"""Handle margin control clicks."""
function _handle_margin_click!(app::SessionsApp, hit::Tuple{Symbol, Int})
    action, idx = hit
    nv = app.notebook_view

    if action == :plus_gap
        # Insert cell at the gap position and enter insert mode to start editing
        cell = Cell()
        insert_cell!(nv.nb, idx, cell)
        rebuild_widgets!(nv)
        nv.focused_idx = idx
        update_focus!(nv)
        _enter_insert_mode!(app)
    elseif action == :eye
        cells = ordered_cells(nv.nb)
        if idx >= 1 && idx <= length(cells)
            cells[idx].folded = !cells[idx].folded
            rebuild_widgets!(nv)
        end
    elseif action == :move_up
        # Move cell at idx up (swap with idx - 1)
        focus_cell!(nv, idx)
        move_cell_up!(nv)
    elseif action == :move_down
        # Move cell at idx down (swap with idx + 1)
        focus_cell!(nv, idx)
        move_cell_down!(nv)
    end
end

"""Hit test ⋯ button (inside cell, top-right) and ▶ run (gap below). Returns true if handled."""
function _hit_test_cell_controls(app::SessionsApp, nv::NotebookView,
                                  click_x::Int, click_y::Int,
                                  cell_left::Int, cell_right::Int)
    isempty(nv.cell_widgets) && return false

    checked = Set{Int}()
    for target_idx in (nv.focused_idx, nv.hovered_idx)
        (target_idx < 1 || target_idx > length(nv.cell_widgets)) && continue
        target_idx in checked && continue
        push!(checked, target_idx)
        cw = nv.cell_widgets[target_idx]

        vp = nv.viewport
        vi = Theme.CELL_V_INSET
        y = vp.y + vi + 1 + Theme.TOP_MARGIN - nv.scroll_offset  # inset + border
        for j in 1:target_idx-1
            j_oh = output_height(nv.output_widgets[j])
            y += cell_height(nv.cell_widgets[j]; has_output=j_oh > 0)
            y += j_oh
            y += Theme.CELL_GAP
        end
        oh = output_height(nv.output_widgets[target_idx])
        ch = cell_height(cw; has_output=oh > 0)

        # ⋯ button inside border (first inner row of border, right-aligned)
        # Rendered at border_rect top-right. Hit zone: ±1 row, ±2 cols for easier clicking.
        hi = Theme.CELL_H_INSET
        vi = Theme.CELL_V_INSET
        border_right = cell_right - hi
        ellipsis_y = y + vi + 1  # v-inset + first row inside border
        ellipsis_x_start = border_right - 4
        if click_y >= ellipsis_y - 1 && click_y <= ellipsis_y + 1 &&
           click_x >= ellipsis_x_start - 2 && click_x <= border_right
            focus_cell!(nv, target_idx)
            open_dropdown!(app, target_idx, border_right - 1, ellipsis_y + 1)
            return true
        end

        # ▶ run button centered in gap below cell (right-aligned)
        # Hit zone: ±1 row, ±2 cols padding
        run_gap_y = y + ch + oh  # row 0 of gap (directly below cell)
        run_text = run_button_text(cw.cell)
        run_x = cell_right - length(run_text)
        if click_y >= run_gap_y - 1 && click_y <= run_gap_y + 1 &&
           click_x >= run_x - 2 && click_x <= cell_right + 2
            focus_cell!(nv, target_idx)
            run_cell_at_index!(app, target_idx)
            return true
        end
    end

    false
end

"""Handle task completion events from background execution."""
function Tachikoma.update!(app::SessionsApp, evt::Tachikoma.TaskEvent)
    if evt.id == :execute_cell
        if evt.value isa Exception
            app.message = "Execution error: $(evt.value)"
        else
            app.message = "Execution complete"
        end
    elseif evt.id == :execute_all
        if evt.value isa Exception
            app.message = "Run all error: $(evt.value)"
        else
            app.message = "Ran all cells"
        end
    end
end

"""Execute the currently focused cell and dependents in the background."""
function run_focused_cell_async!(app::SessionsApp)
    cell = focused_cell(app.notebook_view)
    cell === nothing && return

    # Sync editor text to cell
    cw = focused_widget(app.notebook_view)
    cw !== nothing && sync_to_cell!(cw)

    # Mark cell as queued
    cell.state = cell_queued
    app.message = "Executing..."

    Tachikoma.spawn_task!(app.tq, :execute_cell) do
        execute_changed!(app.nb, [cell]; workspace=app.workspace)
        save_session!(app.nb)
    end
end

"""Execute the currently focused cell synchronously (for testing)."""
function run_focused_cell!(app::SessionsApp)
    cell = focused_cell(app.notebook_view)
    cell === nothing && return

    cw = focused_widget(app.notebook_view)
    cw !== nothing && sync_to_cell!(cw)

    execute_changed!(app.nb, [cell]; workspace=app.workspace)
    save_session!(app.nb)
    app.message = "Ran cell + dependents"
end

"""Execute all stale cells in topological order. Returns the count of cells executed."""
function run_stale_cells!(app::SessionsApp)
    # Sync all editors first
    for cw in app.notebook_view.cell_widgets
        sync_to_cell!(cw)
    end

    sc = stale_cells(app.nb)
    isempty(sc) && return 0

    # Use execute_changed! which computes the right topological order
    # and includes downstream dependents
    execute_changed!(app.nb, sc; workspace=app.workspace)
    save_session!(app.nb)
    length(sc)
end

"""Execute all cells in the notebook in the background."""
function run_all_cells_async!(app::SessionsApp)
    for cw in app.notebook_view.cell_widgets
        sync_to_cell!(cw)
    end

    # Mark all as queued
    for cell in ordered_cells(app.nb)
        cell.state = cell_queued
    end
    app.message = "Running all cells..."

    Tachikoma.spawn_task!(app.tq, :execute_all) do
        execute_notebook!(app.nb; workspace=app.workspace)
        save_session!(app.nb)
    end
end

"""Execute all cells synchronously (for testing)."""
function run_all_cells!(app::SessionsApp)
    for cw in app.notebook_view.cell_widgets
        sync_to_cell!(cw)
    end

    execute_notebook!(app.nb; workspace=app.workspace)
    save_session!(app.nb)
    app.message = "Ran all cells"
end

"""Check if any background tasks are running."""
is_busy(app::SessionsApp) = app.tq.active[] > 0

"""Launch the TUI app for a notebook file."""
function open(path::String)
    nb = load_notebook_with_session(path)
    open(nb)
end

"""Launch the TUI app for a notebook."""
function open(nb::Notebook)
    a = SessionsApp(nb)
    Tachikoma.app(a; fps=30, default_bindings=false)
end

"""Create a new empty notebook and open it."""
function new(path::String="Untitled.jl")
    nb = Notebook(; path)
    add_cell!(nb, "")
    open(nb)
end

"""Run a cell by its index (for indicator click)."""
function run_cell_at_index!(app::SessionsApp, idx::Int)
    cells = ordered_cells(app.nb)
    (idx < 1 || idx > length(cells)) && return
    cell = cells[idx]
    # Sync editor text first
    if idx <= length(app.notebook_view.cell_widgets)
        sync_to_cell!(app.notebook_view.cell_widgets[idx])
    end
    execute_changed!(app.nb, [cell]; workspace=app.workspace)
    save_session!(app.nb)
    app.message = "Ran cell $idx"
end

"""Delete focused cell and store in undo buffer."""
function delete_focused_cell_with_undo!(app::SessionsApp)
    nv = app.notebook_view
    length(nv.cell_widgets) <= 1 && return
    cell = focused_cell(nv)
    cell === nothing && return
    pos = nv.focused_idx
    push!(app.undo_buffer, DeletedCell(cell, pos))
    delete_focused_cell!(nv)
    app.message = "Deleted cell (Ctrl+Z to undo)"
end

"""Delete all selected cells, storing in undo buffer. Keeps at least one cell."""
function delete_selected_cells!(app::SessionsApp)
    nv = app.notebook_view
    selected_indices = sort([i for (i, cw) in enumerate(nv.cell_widgets) if cw.selected]; rev=true)
    isempty(selected_indices) && return

    # Ensure at least one cell survives
    if length(selected_indices) >= length(nv.cell_widgets)
        selected_indices = selected_indices[1:end-1]  # keep one cell
    end
    isempty(selected_indices) && return

    # Delete in reverse order (highest index first) to preserve indices
    for i in selected_indices
        cell = nv.cell_widgets[i].cell
        push!(app.undo_buffer, DeletedCell(cell, i))
        remove_cell!(nv.nb, cell.id)
    end
    nv.focused_idx = min(nv.focused_idx, length(nv.nb))
    rebuild_widgets!(nv)
    clear_selection!(nv)
    app.message = "Deleted $(length(selected_indices)) cell(s) (Ctrl+Z to undo)"
end

"""Undo last cell deletion."""
function undo_delete!(app::SessionsApp)
    isempty(app.undo_buffer) && return
    dc = pop!(app.undo_buffer)
    pos = min(dc.position, length(app.nb) + 1)
    insert_cell!(app.nb, pos, dc.cell)
    rebuild_widgets!(app.notebook_view)
    app.notebook_view.focused_idx = pos
    update_focus!(app.notebook_view)
    app.message = "Restored cell"
end

"""Open the cell dropdown menu anchored next to the ⋯ button."""
function open_dropdown!(app::SessionsApp, cell_idx::Int, x::Int, y::Int)
    app.cell_dropdown = CellDropdown(cell_idx, x, y, collect(DROPDOWN_ITEMS), 0)
    app.mode = :dropdown
end

"""Close the cell dropdown."""
function close_dropdown!(app::SessionsApp)
    app.cell_dropdown = nothing
    app.mode = :normal
end

"""Hit test a click against dropdown items. Returns item index or nothing."""
function _dropdown_hit_test(dd::CellDropdown, click_x::Int, click_y::Int)
    # Dropdown layout: border row, then one row per item, then border row
    # Width = max item width + icon + padding + borders
    w = _dropdown_width(dd)
    # Check bounds
    click_x < dd.x && return nothing
    click_x >= dd.x + w && return nothing
    click_y <= dd.y && return nothing  # top border
    click_y > dd.y + length(dd.items) && return nothing  # past bottom border
    item_idx = click_y - dd.y
    (item_idx >= 1 && item_idx <= length(dd.items)) ? item_idx : nothing
end

"""Execute a dropdown action by item index."""
function _execute_dropdown_action!(app::SessionsApp, item_idx::Int)
    dd = app.cell_dropdown
    dd === nothing && return
    item_idx < 1 || item_idx > length(dd.items) && return

    _, label = dd.items[item_idx]
    if label == "Delete cell"
        target_idx = dd.cell_idx
        close_dropdown!(app)
        focus_cell!(app.notebook_view, target_idx)
        _open_confirm_delete!(app, target_idx)
    end
end

"""Open a centered confirm dialog for cell deletion."""
function _open_confirm_delete!(app::SessionsApp, cell_idx::Int)
    app.confirm_dialog = ConfirmDialog(
        "Delete Cell",
        "Are you sure you want to delete this cell?",
        () -> begin
            delete_focused_cell_with_undo!(app)
        end,
        :no, false, false)
    app.mode = :confirm
end

"""Close the confirm dialog (cancel)."""
function close_confirm!(app::SessionsApp)
    app.confirm_dialog = nothing
    app.mode = :normal
end

"""Enter insert mode — focused cell's editor receives all keys including Delete/Backspace."""
function _enter_insert_mode!(app::SessionsApp)
    app.mode = :insert
    # Clear all editor cursors, then show only the focused one
    for cw in app.notebook_view.cell_widgets
        cw.editor.focused = false
    end
    cw = focused_widget(app.notebook_view)
    if cw !== nothing
        cw.editor.focused = true  # show cursor
    end
end

"""Exit insert mode — return to normal mode, hide all editor cursors."""
function _exit_insert_mode!(app::SessionsApp)
    app.mode = :normal
    for cw in app.notebook_view.cell_widgets
        cw.editor.focused = false
    end
end

"""Compute dropdown width from items."""
function _dropdown_width(dd::CellDropdown)
    max_label = maximum(length(label) for (_, label) in dd.items)
    max_label + 6  # icon(1) + spaces(3) + border(2)
end

"""Render the dropdown overlay."""
function _render_dropdown!(dd::CellDropdown, buf::Tachikoma.Buffer, area::Tachikoma.Rect)
    w = _dropdown_width(dd)
    h = length(dd.items) + 2  # +2 for top/bottom border

    # Clamp position to stay on screen
    x = min(dd.x, area.x + area.width - w)
    x = max(x, area.x)
    y = min(dd.y, area.y + area.height - h)
    y = max(y, area.y)

    box = Theme.BOX
    bg = Theme.DROPDOWN_BG
    border_style = Tachikoma.Style(; fg=Theme.DROPDOWN_BORDER_FG, bg)

    # Top border (rounded)
    top = string(box.tl) * repeat(string(box.h), w - 2) * string(box.tr)
    Tachikoma.set_string!(buf, x, y, top, border_style)

    # Items
    for (i, (icon, label)) in enumerate(dd.items)
        iy = y + i
        is_hovered = (i == dd.hovered_idx)
        item_bg = is_hovered ? Theme.DROPDOWN_HOVER_BG : bg
        item_fg = is_hovered ? Theme.DROPDOWN_HOVER_FG : Theme.DROPDOWN_ITEM_FG
        icon_fg = is_hovered ? Theme.DROPDOWN_HOVER_ICON : Theme.DROPDOWN_ICON_FG

        Tachikoma.set_char!(buf, x, iy, box.v, border_style)
        content = " $icon $label"
        pad_n = w - length(content) - 2
        Tachikoma.set_string!(buf, x + 1, iy, " ", Tachikoma.Style(; fg=item_fg, bg=item_bg))
        Tachikoma.set_string!(buf, x + 2, iy, icon, Tachikoma.Style(; fg=icon_fg, bg=item_bg))
        rest = " $label" * " " ^ max(0, pad_n)
        Tachikoma.set_string!(buf, x + 3, iy, rest, Tachikoma.Style(; fg=item_fg, bg=item_bg))
        Tachikoma.set_char!(buf, x + w - 1, iy, box.v, border_style)
    end

    # Bottom border (rounded)
    bot = string(box.bl) * repeat(string(box.h), w - 2) * string(box.br)
    Tachikoma.set_string!(buf, x, y + length(dd.items) + 1, bot, border_style)
end

# --- Confirm dialog (centered modal) ---

# Layout constants for confirm dialog
const CONFIRM_W = 38
const CONFIRM_H = 7  # border(1) + title(1) + blank(1) + message(1) + blank(1) + buttons(1) + border(1)
const CONFIRM_BTN_YES = " Yes "
const CONFIRM_BTN_NO = "  No  "

"""Compute the screen rect for the centered confirm dialog."""
function _confirm_rect(area::Tachikoma.Rect)
    cx = area.x + div(area.width - CONFIRM_W, 2)
    cy = area.y + div(area.height - CONFIRM_H, 2)
    (x=cx, y=cy, w=CONFIRM_W, h=CONFIRM_H)
end

"""Hit test confirm dialog buttons. Returns :yes, :no, or nothing."""
function _confirm_hit_test(cd::ConfirmDialog, area::Tachikoma.Rect, click_x::Int, click_y::Int)
    r = _confirm_rect(area)
    btn_y = r.y + 5  # buttons row

    # No button (left-aligned inside border)
    no_x = r.x + 2
    no_end = no_x + length(CONFIRM_BTN_NO) - 1
    # Yes button (right-aligned inside border)
    yes_x = r.x + r.w - length(CONFIRM_BTN_YES) - 2
    yes_end = yes_x + length(CONFIRM_BTN_YES) - 1

    # Expand hit zones ±1 row
    if click_y >= btn_y - 1 && click_y <= btn_y + 1
        if click_x >= yes_x - 1 && click_x <= yes_end + 1
            return :yes
        end
        if click_x >= no_x - 1 && click_x <= no_end + 1
            return :no
        end
    end

    nothing
end

"""Render the confirm dialog centered on screen with dimmed backdrop."""
function _render_confirm_dialog!(cd::ConfirmDialog, buf::Tachikoma.Buffer, area::Tachikoma.Rect)
    # Dim backdrop
    dim_style = Tachikoma.Style(; fg=Theme.FG_MUTED, bg=Tachikoma.ColorRGB(0x08, 0x08, 0x0a))
    for fy in area.y:(area.y + area.height - 1)
        Tachikoma.set_string!(buf, area.x, fy, " " ^ area.width, dim_style)
    end

    r = _confirm_rect(area)
    box = Theme.BOX
    bg = Theme.DROPDOWN_BG
    border_s = Tachikoma.Style(; fg=Theme.ACCENT, bg)
    fill_s = Tachikoma.Style(; fg=Theme.FG, bg)
    title_s = Tachikoma.Style(; fg=Theme.FG, bg, bold=true)

    # Fill interior
    for fy in r.y:(r.y + r.h - 1)
        Tachikoma.set_string!(buf, r.x, fy, " " ^ r.w, Tachikoma.Style(; bg))
    end

    # Border
    Tachikoma.set_char!(buf, r.x, r.y, box.tl, border_s)
    Tachikoma.set_char!(buf, r.x + r.w - 1, r.y, box.tr, border_s)
    Tachikoma.set_char!(buf, r.x, r.y + r.h - 1, box.bl, border_s)
    Tachikoma.set_char!(buf, r.x + r.w - 1, r.y + r.h - 1, box.br, border_s)
    for cx in (r.x + 1):(r.x + r.w - 2)
        Tachikoma.set_char!(buf, cx, r.y, box.h, border_s)
        Tachikoma.set_char!(buf, cx, r.y + r.h - 1, box.h, border_s)
    end
    for fy in (r.y + 1):(r.y + r.h - 2)
        Tachikoma.set_char!(buf, r.x, fy, box.v, border_s)
        Tachikoma.set_char!(buf, r.x + r.w - 1, fy, box.v, border_s)
    end

    # Title (row 1)
    title_text = " " * cd.title * " "
    tx = r.x + div(r.w - length(title_text), 2)
    Tachikoma.set_string!(buf, tx, r.y + 1, title_text, title_s)

    # Message (row 3)
    msg_text = cd.message
    mx = r.x + div(r.w - length(msg_text), 2)
    Tachikoma.set_string!(buf, mx, r.y + 3, msg_text, fill_s)

    # Buttons (row 5) — No on left (default), Yes on right
    btn_y = r.y + 5
    no_x = r.x + 2
    yes_x = r.x + r.w - length(CONFIRM_BTN_YES) - 2

    # Button states: keyboard selection OR mouse hover activates the highlight
    no_active = cd.selected == :no || cd.no_hovered
    yes_active = cd.selected == :yes || cd.yes_hovered

    # No button — blue when active
    no_bg = no_active ? Theme.ACCENT : Theme.ELEVATED_BG
    no_fg = no_active ? bg : Theme.FG_DIM
    Tachikoma.set_string!(buf, no_x, btn_y, CONFIRM_BTN_NO,
        Tachikoma.Style(; fg=no_fg, bg=no_bg, bold=no_active))

    # Yes button — red when active (danger)
    yes_bg = yes_active ? Theme.RED : Theme.ELEVATED_BG
    yes_fg = yes_active ? Theme.FG : Theme.FG_DIM
    Tachikoma.set_string!(buf, yes_x, btn_y, CONFIRM_BTN_YES,
        Tachikoma.Style(; fg=yes_fg, bg=yes_bg, bold=yes_active))
end
