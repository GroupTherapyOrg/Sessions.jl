# TUI: Status bar — top and bottom bars for notebook info and keybindings

"""Create the top status bar showing notebook info."""
function make_top_bar(nb::Notebook)
    n_cells = length(nb)
    n_done = count(c -> c.state == cell_done, values(nb.cells))
    n_err = count(c -> c.state == cell_errored, values(nb.cells))

    path_span = Tachikoma.Span(basename(nb.path), Tachikoma.tstyle(:accent))
    status = if n_err > 0
        Tachikoma.Span(" $(n_done)/$(n_cells) cells, $(n_err) errors",
            Tachikoma.Style(; fg=Tachikoma.Color256(196)))
    else
        Tachikoma.Span(" $(n_done)/$(n_cells) cells",
            Tachikoma.Style(; fg=Tachikoma.Color256(245)))
    end

    Tachikoma.StatusBar(; left=[path_span, status])
end

"""Create the bottom status bar showing keybindings."""
function make_bottom_bar(; mode::Symbol=:normal)
    keys = if mode == :normal
        "Shift+Enter: Run  Tab: Next  Ctrl+N: New  Ctrl+S: Save+Run  Ctrl+A: Select All  Ctrl+Q: Quit"
    elseif mode == :insert
        "Esc: Normal Mode  Shift+Enter: Run Cell"
    else
        "Ctrl+Q: Quit"
    end

    Tachikoma.StatusBar(; left=[Tachikoma.Span(keys,
        Tachikoma.Style(; fg=Tachikoma.Color256(245)))])
end
