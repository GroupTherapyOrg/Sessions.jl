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

"""Create the bottom status bar showing keybindings."""
function make_bottom_bar(; mode::Symbol=:normal)
    keys = if mode == :normal
        "Click cell to focus  Click ▶ to run  Click + to add  Ctrl+R: Run  Ctrl+S: Save  Ctrl+Q: Quit"
    elseif mode == :insert
        "Editing cell  Esc: Done  Ctrl+R: Run  Ctrl+S: Save"
    elseif mode == :dropdown
        "Click action  Esc: Close"
    else
        "Ctrl+Q: Quit"
    end

    Tachikoma.StatusBar(; left=[Tachikoma.Span(" " * keys, Theme.S_DIM)])
end
