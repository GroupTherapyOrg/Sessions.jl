# TUI: Status bar — Islands Dark themed top and bottom bars

"""Create the top status bar showing notebook info."""
function make_top_bar(nb::Notebook)
    n_cells = length(nb)
    n_done = count(c -> c.state == cell_done, values(nb.cells))
    n_err = count(c -> c.state == cell_errored, values(nb.cells))

    path_span = Tachikoma.Span(" " * basename(nb.path),
        Tachikoma.Style(; fg=Theme.ACCENT, bold=true))
    status = if n_err > 0
        Tachikoma.Span("  $(n_done)/$(n_cells) cells  $(n_err) errors",
            Tachikoma.Style(; fg=Theme.RED))
    elseif n_done > 0
        Tachikoma.Span("  $(n_done)/$(n_cells) cells",
            Tachikoma.Style(; fg=Theme.GREEN))
    else
        Tachikoma.Span("  $(n_done)/$(n_cells) cells", Theme.S_MUTED)
    end

    Tachikoma.StatusBar(; left=[path_span, status])
end

"""Create top status bar for file editor mode."""
function make_top_bar(fev::FileEditorView)
    name = file_basename(fev)
    dirty = fev.dirty ? " ●" : ""
    path_span = Tachikoma.Span(" " * name * dirty,
        Tachikoma.Style(; fg=Theme.ACCENT, bold=true))
    row, col = cursor_pos(fev)
    lines = line_count(fev)
    info = Tachikoma.Span("  $(lines) lines  Ln $(row), Col $(col)",
        Theme.S_DIM)
    Tachikoma.StatusBar(; left=[path_span, info])
end

"""Create the bottom status bar showing keybindings."""
function make_bottom_bar(; mode::Symbol=:normal, editor_type::Symbol=:notebook)
    keys = if editor_type == :file
        if mode == :insert
            "Esc: Normal  Ctrl+S: Save  Ctrl+Q: Quit  /: Search"
        else
            "i: Insert  Ctrl+S: Save  Ctrl+Q: Quit  /: Search  u: Undo"
        end
    elseif mode == :dropdown
        "Click action  Esc: Close"
    elseif mode == :panel
        "Ctrl+C: Quit  Arrow: Navigate  Enter: Edit"
    elseif mode == :insert
        "Esc: Normal mode  Ctrl+R: Run  Ctrl+S: Save  Ctrl+C: Copy"
    else  # :normal
        "Esc: Panel  Enter: Edit  Ctrl+R: Run  Ctrl+S: Save  Ctrl+C: Copy cell"
    end

    Tachikoma.StatusBar(; left=[Tachikoma.Span(" " * keys, Theme.S_DIM)])
end
