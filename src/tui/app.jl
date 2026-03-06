# TUI: Main application — SessionsApp Model/update!/view

"""Sessions notebook TUI application model."""
mutable struct SessionsApp <: Tachikoma.Model
    nb::Notebook
    workspace::Workspace
    notebook_view::NotebookView
    mode::Symbol        # :normal or :insert
    quit::Bool
    message::String     # Status message (temporary)
end

function SessionsApp(nb::Notebook)
    ws = Workspace()
    nv = NotebookView(nb)
    SessionsApp(nb, ws, nv, :normal, false, "")
end

function SessionsApp(path::String)
    nb = load_notebook(path)
    SessionsApp(nb)
end

Tachikoma.should_quit(app::SessionsApp) = app.quit

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
end

function Tachikoma.update!(app::SessionsApp, evt::Tachikoma.KeyEvent)
    app.message = ""  # Clear status message on any key

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

    # Ctrl+Enter: execute cell or notebook
    if evt.key == :ctrl && evt.char == '\r'
        run_focused_cell!(app)
        return
    end

    # Alt+Enter or Ctrl+Shift+Enter: run all
    if evt.key == :ctrl && evt.char == 'a'
        run_all_cells!(app)
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

"""Execute the currently focused cell and its dependents."""
function run_focused_cell!(app::SessionsApp)
    cell = focused_cell(app.notebook_view)
    cell === nothing && return

    # Sync editor text to cell
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

"""Execute all cells in the notebook."""
function run_all_cells!(app::SessionsApp)
    # Sync all editors to cells
    for cw in app.notebook_view.cell_widgets
        sync_to_cell!(cw)
    end

    execute_notebook!(app.nb; workspace=app.workspace)
    app.message = "Ran all cells"
end

"""Launch the TUI app for a notebook file."""
function open(path::String)
    nb = load_notebook(path)
    open(nb)
end

"""Launch the TUI app for a notebook."""
function open(nb::Notebook)
    a = SessionsApp(nb)
    Tachikoma.app(a; fps=30)
end

"""Create a new empty notebook and open it."""
function new(path::String="Untitled.jl")
    nb = Notebook(; path)
    add_cell!(nb, "")
    open(nb)
end
