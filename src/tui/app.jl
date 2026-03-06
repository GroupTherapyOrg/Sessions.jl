# TUI: Main application — SessionsApp Model/update!/view

const CONTEXT_MENU_ITEMS = ["Run Cell", "Delete Cell", "Fold/Unfold", "Disable/Enable", "Move Up", "Move Down"]

"""Sessions notebook TUI application model."""
mutable struct SessionsApp <: Tachikoma.Model
    nb::Notebook
    workspace::Workspace
    notebook_view::NotebookView
    tq::Tachikoma.TaskQueue
    mode::Symbol        # :normal, :insert, or :context_menu
    quit::Bool
    message::String     # Status message (temporary)
    context_menu::Union{Nothing, Tachikoma.SelectableList}
end

function SessionsApp(nb::Notebook)
    ws = Workspace()
    nv = NotebookView(nb)
    SessionsApp(nb, ws, nv, Tachikoma.TaskQueue(), :normal, false, "", nothing)
end

function SessionsApp(path::String)
    nb = load_notebook(path)
    SessionsApp(nb)
end

Tachikoma.should_quit(app::SessionsApp) = app.quit
Tachikoma.task_queue(app::SessionsApp) = app.tq

function Tachikoma.view(app::SessionsApp, frame::Tachikoma.Frame)
    area = frame.area

    layout = Tachikoma.Layout(Tachikoma.Vertical,
        [Tachikoma.Fixed(1), Tachikoma.Fill(), Tachikoma.Fixed(1)])
    rects = Tachikoma.split_layout(layout, area)

    # Top status bar
    top_bar = make_top_bar(app.nb)
    if !isempty(app.message)
        top_bar = Tachikoma.StatusBar(; left=[Tachikoma.Span(app.message,
            Tachikoma.Style(; fg=Tachikoma.Color256(214)))])
    end
    Tachikoma.render(top_bar, rects[1], frame.buffer)

    # Notebook view (main content)
    Tachikoma.render(app.notebook_view, rects[2], frame.buffer)

    # Bottom keybindings bar
    bottom_bar = make_bottom_bar(; mode=app.mode)
    Tachikoma.render(bottom_bar, rects[3], frame.buffer)

    # Context menu overlay
    if app.context_menu !== nothing
        menu_w = 22
        menu_h = length(CONTEXT_MENU_ITEMS) + 2  # +2 for border
        menu_x = max(1, div(area.width - menu_w, 2) + area.x)
        menu_y = max(1, div(area.height - menu_h, 2) + area.y)
        menu_rect = Tachikoma.Rect(menu_x, menu_y, menu_w, menu_h)
        Tachikoma.render(app.context_menu, menu_rect, frame.buffer)
    end
end

function Tachikoma.update!(app::SessionsApp, evt::Tachikoma.KeyEvent)
    app.message = ""  # Clear status message on any key

    # Context menu mode — intercept all keys
    if app.mode == :context_menu && app.context_menu !== nothing
        handle_context_menu_key!(app, evt)
        return
    end

    # Global keybindings (always active)
    if evt.key == :ctrl && evt.char == 'q'
        app.quit = true
        return
    end

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

    if evt.key == :ctrl && evt.char == 'n'
        add_cell_after_focus!(app.notebook_view)
        return
    end

    # Ctrl+Enter or Shift+Enter: execute cell in background
    if (evt.key == :ctrl && evt.char == '\r') || evt.key == :shift_enter
        run_focused_cell_async!(app)
        return
    end

    # Alt+Enter or Ctrl+Shift+Enter: run all
    if evt.key == :ctrl && evt.char == 'a'
        run_all_cells_async!(app)
        return
    end

    # Cell reorder (Alt+Up/Down) — works in both modes
    if evt.key == :alt_up
        move_cell_up!(app.notebook_view)
        return
    end
    if evt.key == :alt_down
        move_cell_down!(app.notebook_view)
        return
    end

    # Cell fold/unfold toggle (normal mode only)
    if app.mode == :normal && evt.key == :ctrl && evt.char == 'f'
        cell = focused_cell(app.notebook_view)
        if cell !== nothing
            cell.folded = !cell.folded
            rebuild_widgets!(app.notebook_view)
        end
        return
    end

    # Cell disable/enable toggle (normal mode only)
    if app.mode == :normal && evt.key == :ctrl && evt.char == 'e'
        cell = focused_cell(app.notebook_view)
        if cell !== nothing
            cell.disabled = !cell.disabled
            rebuild_widgets!(app.notebook_view)
        end
        return
    end

    # Context menu trigger (normal mode only)
    if app.mode == :normal && evt.key == :char && evt.char == '.'
        open_context_menu!(app)
        return
    end

    # Navigation between cells
    if app.mode == :normal
        if evt.key == :tab
            focus_next!(app.notebook_view)
            return
        elseif evt.key == :shift_tab || (evt.key == :ctrl && evt.char == 'p')
            focus_prev!(app.notebook_view)
            return
        elseif evt.key == :ctrl && evt.char == 'd'
            delete_focused_cell!(app.notebook_view)
            return
        elseif evt.key == :enter || evt.key == :char && evt.char == 'i'
            app.mode = :insert
            return
        end
    end

    if app.mode == :insert
        if evt.key == :escape
            app.mode = :normal
            return
        end
    end

    # Pass to focused cell widget
    cw = focused_widget(app.notebook_view)
    if cw !== nothing
        if app.mode == :insert
            Tachikoma.handle_key!(cw, evt)
        end
    end
end

"""Handle mouse events — click to focus cells, scroll to navigate."""
function Tachikoma.update!(app::SessionsApp, evt::Tachikoma.MouseEvent)
    nv = app.notebook_view

    if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press
        idx = cell_at_y(nv, evt.y)
        if idx !== nothing
            focus_cell!(nv, idx)
        end
        return
    end

    if evt.button == Tachikoma.mouse_scroll_down
        nv.scroll_offset = max(0, nv.scroll_offset + 3)
        return
    end

    if evt.button == Tachikoma.mouse_scroll_up
        nv.scroll_offset = max(0, nv.scroll_offset - 3)
        return
    end
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

"""Open the cell context menu."""
function open_context_menu!(app::SessionsApp)
    block = Tachikoma.Block(; title="Cell Actions")
    app.context_menu = Tachikoma.SelectableList(CONTEXT_MENU_ITEMS; block, focused=true)
    app.mode = :context_menu
end

"""Close the context menu."""
function close_context_menu!(app::SessionsApp)
    app.context_menu = nothing
    app.mode = :normal
end

"""Handle key events in context menu mode."""
function handle_context_menu_key!(app::SessionsApp, evt::Tachikoma.KeyEvent)
    menu = app.context_menu

    if evt.key == :escape
        close_context_menu!(app)
        return
    end

    if evt.key == :up
        menu.selected = max(1, menu.selected - 1)
        return
    end

    if evt.key == :down
        menu.selected = min(length(CONTEXT_MENU_ITEMS), menu.selected + 1)
        return
    end

    if evt.key == :enter
        execute_context_action!(app, menu.selected)
        close_context_menu!(app)
        return
    end
end

"""Execute a context menu action by index."""
function execute_context_action!(app::SessionsApp, idx::Int)
    action = CONTEXT_MENU_ITEMS[idx]
    if action == "Run Cell"
        run_focused_cell!(app)
    elseif action == "Delete Cell"
        delete_focused_cell!(app.notebook_view)
    elseif action == "Fold/Unfold"
        cell = focused_cell(app.notebook_view)
        if cell !== nothing
            cell.folded = !cell.folded
            rebuild_widgets!(app.notebook_view)
        end
    elseif action == "Disable/Enable"
        cell = focused_cell(app.notebook_view)
        if cell !== nothing
            cell.disabled = !cell.disabled
            rebuild_widgets!(app.notebook_view)
        end
    elseif action == "Move Up"
        move_cell_up!(app.notebook_view)
    elseif action == "Move Down"
        move_cell_down!(app.notebook_view)
    end
end
