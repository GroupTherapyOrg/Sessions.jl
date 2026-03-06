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

"""Sessions notebook TUI application model."""
mutable struct SessionsApp <: Tachikoma.Model
    nb::Notebook
    workspace::Workspace
    notebook_view::NotebookView
    file_panel::FilePanel
    activity_bar::ActivityBar
    tq::Tachikoma.TaskQueue
    mode::Symbol        # :normal, :insert, or :dropdown
    quit::Bool
    message::String     # Status message (temporary)
    cell_dropdown::Union{Nothing, CellDropdown}
    undo_buffer::Vector{DeletedCell}
    sidebar_open::Bool         # whether file panel is visible
    sidebar_rect::Tachikoma.Rect   # cached for mouse hit testing
    activity_rect::Tachikoma.Rect  # cached for mouse hit testing
end

function SessionsApp(nb::Notebook)
    ws = Workspace()
    nv = NotebookView(nb)
    dir = isempty(nb.path) ? pwd() : dirname(abspath(nb.path))
    fp = FilePanel(dir)
    ab = ActivityBar()
    SessionsApp(nb, ws, nv, fp, ab, Tachikoma.TaskQueue(), :normal, false, "", nothing,
        DeletedCell[], true, Tachikoma.Rect(), Tachikoma.Rect())
end

function SessionsApp(path::String)
    nb = load_notebook(path)
    SessionsApp(nb)
end

Tachikoma.should_quit(app::SessionsApp) = app.quit
Tachikoma.task_queue(app::SessionsApp) = app.tq

"""Enable any-event mouse tracking (1003) for true hover support.
Also loads CommonMark.jl extension for markdown rendering."""
function Tachikoma.init!(app::SessionsApp, t::Tachikoma.Terminal)
    print(t.io, "\e[?1003h")  # upgrade to any-event tracking
    try; Tachikoma.enable_markdown(); catch; end  # load CommonMark extension
end

function Tachikoma.view(app::SessionsApp, frame::Tachikoma.Frame)
    Theme.advance_tick!()
    area = frame.area
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

    # Cursor always visible in the focused cell
    for (i, cw) in enumerate(app.notebook_view.cell_widgets)
        cw.editor.focused = (i == app.notebook_view.focused_idx && app.mode != :dropdown)
    end

    # Notebook view (main content — fills remaining space)
    Tachikoma.render(app.notebook_view, notebook_rect, buf)

    # Cell dropdown overlay
    if app.cell_dropdown !== nothing
        _render_dropdown!(app.cell_dropdown, buf, area)
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
        nb = load_notebook(path)
        app.nb = nb
        app.workspace = Workspace()
        app.notebook_view = NotebookView(nb)
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
            load_notebook(path)
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
    app.mode = :normal
    app.message = "Opened workspace: $(basename(dir))"
end

function Tachikoma.update!(app::SessionsApp, evt::Tachikoma.KeyEvent)
    app.message = ""  # Clear status message on any key

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
        app.quit = true
        return
    end

    # Ctrl+S: save + run stale
    if evt.key == :ctrl && evt.char == 's'
        save_notebook(app.nb)
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

    # Escape: clear selection
    if evt.key == :escape
        if has_selection(app.notebook_view)
            clear_selection!(app.notebook_view)
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

    # Dropdown mode: handle clicks inside dropdown or click-away to dismiss
    if app.mode == :dropdown && app.cell_dropdown !== nothing
        if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press
            item_idx = _dropdown_hit_test(app.cell_dropdown, evt.x, evt.y)
            if item_idx !== nothing
                _execute_dropdown_action!(app, item_idx)
            end
            close_dropdown!(app)
            return
        end
        # Mouse move: update hover highlight in dropdown
        if evt.action == Tachikoma.mouse_move
            app.cell_dropdown.hovered_idx = something(_dropdown_hit_test(app.cell_dropdown, evt.x, evt.y), 0)
            return
        end
        return
    end

    if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press
        # Shift+click: range selection
        if evt.shift
            idx = cell_at_y(nv, evt.y)
            if idx !== nothing
                select_range!(nv, nv.focused_idx, idx)
            end
            return
        end

        # Compute cell layout dimensions
        pad = max(1, round(Int, nv.viewport.width * Theme.CELL_PAD_FRACTION))
        pad = min(pad, max(0, div(nv.viewport.width - 10, 2)))
        cell_left = nv.viewport.x + pad
        cell_right = nv.viewport.x + nv.viewport.width - pad
        margin_x = cell_left - Theme.MARGIN_CTRL_WIDTH

        # Check if click is in the left margin area (for +, eye controls)
        if evt.x >= margin_x && evt.x < cell_left
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

        # Regular cell click — focus it (cell adding is only via + buttons)
        idx = cell_at_y(nv, evt.y)
        if idx !== nothing
            clear_selection!(nv)
            focus_cell!(nv, idx)
        end
        return
    end

    if evt.button == Tachikoma.mouse_scroll_down
        vi = Theme.CELL_V_INSET
        inner_h = max(1, nv.viewport.height - 2 * vi - 2)  # subtract inset + border
        max_scroll = max(0, content_height(nv) - inner_h)
        nv.scroll_offset = min(nv.scroll_offset + 2, max_scroll)
        nv.user_scrolling = true
        return
    end

    if evt.button == Tachikoma.mouse_scroll_up
        nv.scroll_offset = max(nv.scroll_offset - 2, 0)
        nv.user_scrolling = true
        return
    end

    # Mouse move: update hover state
    if evt.action == Tachikoma.mouse_move
        idx = cell_at_y(nv, evt.y)
        nv.hovered_idx = idx !== nothing ? idx : 0
        return
    end
end

"""Hit test margin controls. Returns (:plus_above, idx), (:plus_below, idx), (:eye, idx), or nothing."""
function _hit_test_margin_control(nv::NotebookView, click_x::Int, click_y::Int, margin_x::Int)
    isempty(nv.cell_widgets) && return nothing
    vp = nv.viewport

    # Controls appear on focused OR hovered cell
    for target_idx in (nv.focused_idx, nv.hovered_idx)
        (target_idx < 1 || target_idx > length(nv.cell_widgets)) && continue

        vi = Theme.CELL_V_INSET
        y = vp.y + vi + 1 + Theme.TOP_MARGIN - nv.scroll_offset  # inset + border
        for j in 1:target_idx-1
            y += cell_height(nv.cell_widgets[j])
            y += output_height(nv.output_widgets[j])
            y += Theme.CELL_GAP
        end

        ch = cell_height(nv.cell_widgets[target_idx])
        oh = output_height(nv.output_widgets[target_idx])

        if click_y == y - 1
            return (:plus_above, target_idx)
        end

        eye_y = y + div(ch, 2)
        if click_y == eye_y
            return (:eye, target_idx)
        end

        plus_below_y = y + ch + oh
        if click_y == plus_below_y
            return (:plus_below, target_idx)
        end
    end

    nothing
end

"""Handle margin control clicks."""
function _handle_margin_click!(app::SessionsApp, hit::Tuple{Symbol, Int})
    action, idx = hit
    nv = app.notebook_view

    if action == :plus_above
        # Insert cell above the target cell
        cell = Cell()
        insert_cell!(nv.nb, idx, cell)
        rebuild_widgets!(nv)
        nv.focused_idx = idx
        update_focus!(nv)
    elseif action == :plus_below
        # Insert cell below the target cell
        pos = idx + 1
        cell = Cell()
        insert_cell!(nv.nb, pos, cell)
        rebuild_widgets!(nv)
        nv.focused_idx = pos
        update_focus!(nv)
    elseif action == :eye
        cells = ordered_cells(nv.nb)
        if idx >= 1 && idx <= length(cells)
            cells[idx].folded = !cells[idx].folded
            rebuild_widgets!(nv)
        end
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
            y += cell_height(nv.cell_widgets[j])
            y += output_height(nv.output_widgets[j])
            y += Theme.CELL_GAP
        end
        ch = cell_height(cw)
        oh = output_height(nv.output_widgets[target_idx])

        # ⋯ button inside border (first inner row of border, right-aligned)
        hi = Theme.CELL_H_INSET
        vi = Theme.CELL_V_INSET
        border_right = cell_right - hi
        ellipsis_y = y + vi + 1  # v-inset + first row inside border
        ellipsis_x_start = border_right - 4
        if click_y == ellipsis_y && click_x >= ellipsis_x_start && click_x <= border_right - 2
            focus_cell!(nv, target_idx)
            open_dropdown!(app, target_idx, border_right - 1, ellipsis_y + 1)
            return true
        end

        # ▶ run button in gap below cell (right-aligned)
        gap_y = y + ch + oh
        run_text = run_button_text(cw.cell)
        run_x = cell_right - length(run_text)
        if click_y == gap_y && click_x >= run_x && click_x <= cell_right
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
    end
end

"""Execute the currently focused cell synchronously (for testing)."""
function run_focused_cell!(app::SessionsApp)
    cell = focused_cell(app.notebook_view)
    cell === nothing && return

    cw = focused_widget(app.notebook_view)
    cw !== nothing && sync_to_cell!(cw)

    execute_changed!(app.nb, [cell]; workspace=app.workspace)
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
    end
end

"""Execute all cells synchronously (for testing)."""
function run_all_cells!(app::SessionsApp)
    for cw in app.notebook_view.cell_widgets
        sync_to_cell!(cw)
    end

    execute_notebook!(app.nb; workspace=app.workspace)
    app.message = "Ran all cells"
end

"""Check if any background tasks are running."""
is_busy(app::SessionsApp) = app.tq.active[] > 0

"""Launch the TUI app for a notebook file."""
function open(path::String)
    nb = load_notebook(path)
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
        # Focus the target cell, then delete it
        focus_cell!(app.notebook_view, dd.cell_idx)
        delete_focused_cell_with_undo!(app)
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
