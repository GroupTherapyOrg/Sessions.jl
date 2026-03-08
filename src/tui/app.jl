# TUI: Main application — SessionsApp Model/update!/view

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

"""Floating completion popup (triggered by Ctrl+Space)."""
mutable struct CompletionPopup
    items::Vector{LspCompletionItem}
    x::Int                  # screen x of popup top-left
    y::Int                  # screen y of popup top-left
    selected_idx::Int       # 1-based index of highlighted item (0 if empty)
end

const COMPLETION_MAX_VISIBLE = 10

"""Return icon character for a completion kind."""
function _completion_kind_icon(kind::Symbol)
    kind == :function    && return "ƒ"
    kind == :method      && return "ƒ"
    kind == :variable    && return "v"
    kind == :module      && return "M"
    kind == :keyword     && return "k"
    kind == :constant    && return "c"
    kind == :field       && return "□"
    kind == :class       && return "T"
    kind == :constructor && return "T"
    kind == :property    && return "□"
    kind == :interface   && return "I"
    kind == :text        && return "·"
    return "·"
end

"""Return the number of visible items in the popup (clamped to max)."""
_popup_visible_count(popup::CompletionPopup) = min(length(popup.items), COMPLETION_MAX_VISIBLE)

"""Extract the word (identifier) before the cursor position."""
function _completion_prefix(lines::Vector{Vector{Char}}, row::Int, col::Int)
    (row < 1 || row > length(lines) || col <= 0) && return ""
    line = lines[row]
    start = col
    while start > 0 && start <= length(line)
        c = line[start]
        (isletter(c) || isdigit(c) || c == '_' || c == '!') || break
        start -= 1
    end
    start < col ? String(line[start+1:col]) : ""
end

"""Floating hover tooltip (triggered by mouse stillness)."""
mutable struct HoverTooltip
    text::String            # markdown/plaintext content
    x::Int                  # screen x of tooltip top-left
    y::Int                  # screen y of tooltip top-left
end

mutable struct SignatureHelpTooltip
    label::String
    parameters::Vector{String}
    active_param::Int  # 0-based
    x::Int
    y::Int
end

mutable struct RenamePrompt
    old_name::String
    new_name::String
    cursor::Int  # cursor position in new_name (0-based character offset)
end

const HOVER_DEBOUNCE = 0.5  # seconds of mouse stillness before requesting hover

"""Sessions notebook TUI application model."""
mutable struct SessionsApp <: Tachikoma.Model
    nb::Notebook
    workspace::Workspace
    notebook_view::NotebookView
    file_editor_view::Union{Nothing, FileEditorView}  # non-nothing in file editor mode
    editor_type::Symbol      # :notebook or :file
    file_panel::FilePanel
    activity_bar::ActivityBar
    tq::Tachikoma.TaskQueue
    mode::Symbol        # :panel, :normal, :insert, :dropdown, or :confirm
    quit::Bool
    message::String     # Status message (temporary)
    cell_dropdown::Union{Nothing, CellDropdown}
    confirm_dialog::Union{Nothing, ConfirmDialog}
    completion_popup::Union{Nothing, CompletionPopup}
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
    drag_active::Bool        # mouse drag in progress (for text selection)
    drag_cell_idx::Int       # cell index where drag started
    slider_drag::Bool        # mouse drag on a slider track
    slider_drag_idx::Int     # cell index of slider being dragged
    # Tab management
    tabs::Vector{EditorTab}
    active_tab_idx::Int
    tab_rects::Vector{Tachikoma.Rect}    # cached for mouse hit testing
    close_rects::Vector{Tachikoma.Rect}  # cached for × button hit testing
    # REPL panel
    repl_panel::ReplPanel
    repl_open::Bool                       # whether REPL panel is visible
    repl_rect::Tachikoma.Rect            # cached for mouse hit testing
    # JETLS / Diagnostics
    lsp::LspClient                        # LSP client for JETLS
    diagnostics_panel::DiagnosticsPanel   # diagnostics sidebar panel
    diagnostics_open::Bool                # whether diagnostics panel is visible
    cell_diagnostics_cache::Dict{UUID, Vector{Diagnostic}}  # cell_id -> diagnostics
    lsp_doc_version::Int                  # LSP document version counter
    jet_diagnostics_cache::Dict{UUID, CellDiagnostics}      # JET direct analysis cache
    lsp_sync_needed::Float64              # time() of last edit that needs LSP sync (0.0 = none pending)
    # Hover tooltip
    hover_tooltip::Union{Nothing, HoverTooltip}
    hover_last_mouse_x::Int               # last mouse x for stillness detection
    hover_last_mouse_y::Int               # last mouse y for stillness detection
    hover_still_since::Float64            # time() when mouse became still (0.0 = moving)
    hover_requested::Bool                 # true if hover request already sent for this position
    # Signature help tooltip
    signature_tooltip::Union{Nothing, SignatureHelpTooltip}
    # Scrollbar state (set during render for mouse hit testing)
    scrollbar_col::Int
    scrollbar_y::Int
    scrollbar_h::Int
    # Rename prompt
    rename_prompt::Union{Nothing, RenamePrompt}
    # Raster debounce: suppress sixel/kitty re-encoding during active interaction
    last_interaction_time::Float64
end

"""Check if notebook differs from the last saved snapshot."""
function _is_notebook_dirty(app::SessionsApp)
    app.last_disk_nb === nothing && return false
    snap = app.last_disk_nb
    nb = app.nb
    nb.cell_order != snap.cell_order && return true
    for id in nb.cell_order
        haskey(snap.cells, id) || return true
        nb.cells[id].code != snap.cells[id].code && return true
        nb.cells[id].folded != snap.cells[id].folded && return true
        nb.cells[id].disabled != snap.cells[id].disabled && return true
    end
    false
end

# ── Tab management ──────────────────────────────────────────────────────

"""Sync a field to the active tab after reassignment."""
function _sync_to_active_tab!(app::SessionsApp)
    isempty(app.tabs) && return
    tab = app.tabs[app.active_tab_idx]
    tab.last_disk_nb = app.last_disk_nb
    tab.last_save_time = app.last_save_time
    tab.watcher = app.watcher
end

"""Save current app state into the active tab."""
function _save_to_tab!(app::SessionsApp)
    isempty(app.tabs) && return
    tab = app.tabs[app.active_tab_idx]
    tab.nb = app.nb
    tab.workspace = app.workspace
    tab.notebook_view = app.notebook_view
    tab.file_editor_view = app.file_editor_view
    tab.last_disk_nb = app.last_disk_nb
    tab.watcher = app.watcher
    tab.last_save_time = app.last_save_time
    tab.undo_buffer = app.undo_buffer
    tab.progress_recently = app.progress_recently
    tab.progress_done_tick = app.progress_done_tick
    # Persist mode (collapse transient modes to :normal)
    tab.mode = (app.mode in (:dropdown, :confirm, :completion, :rename, :datatable)) ? :normal : app.mode
end

"""Load state from a tab into the app fields."""
function _load_from_tab!(app::SessionsApp, idx::Int)
    tab = app.tabs[idx]
    app.nb = tab.nb
    app.workspace = tab.workspace
    app.notebook_view = tab.notebook_view
    app.file_editor_view = tab.file_editor_view
    app.editor_type = tab.tab_type
    app.last_disk_nb = tab.last_disk_nb
    app.watcher = tab.watcher
    app.last_save_time = tab.last_save_time
    app.undo_buffer = tab.undo_buffer
    app.progress_recently = tab.progress_recently
    app.progress_done_tick = tab.progress_done_tick
    app.active_tab_idx = idx
    # Restore mode; dismiss any transient UI
    app.mode = tab.mode
    app.cell_dropdown = nothing
    app.confirm_dialog = nothing

    # Clear interaction state so stale hovers don't carry over
    app.notebook_view.hovered_idx = 0
    app.notebook_view.hovered_control = :none
    app.notebook_view.hovered_control_idx = 0
    app.notebook_view.hovered_bond_idx = 0
    app.notebook_view.run_all_hovered = false
    app.notebook_view.save_hovered = false
    app.drag_active = false
    app.slider_drag = false
    app.file_panel.hovered_idx = 0

    # Sync file panel cursor to the active tab's file
    _sync_file_panel_cursor!(app)
end

"""Move the file panel cursor to match the active tab's file."""
function _sync_file_panel_cursor!(app::SessionsApp)
    tab = app.tabs[app.active_tab_idx]
    target = basename(tab.path)
    for (i, entry) in enumerate(app.file_panel.entries)
        if entry.name == target
            app.file_panel.cursor_idx = i
            return
        end
    end
end

"""Toggle the REPL panel open/closed. Creates first tab on first open."""
function _toggle_repl!(app::SessionsApp)
    app.repl_open = !app.repl_open
    if app.repl_open
        # Create first REPL tab if none exist
        if isempty(app.repl_panel.tabs)
            dir = isempty(app.nb.path) ? pwd() : dirname(abspath(app.nb.path))
            add_repl_tab!(app.repl_panel, dir)
        end
        app.mode = :repl
        app.repl_panel.focused = true
        push!(app.activity_bar.active, :terminal)
    else
        if app.mode == :repl
            app.mode = :normal
        end
        app.repl_panel.focused = false
        delete!(app.activity_bar.active, :terminal)
    end
end

"""Toggle the diagnostics panel open/closed."""
function _toggle_diagnostics!(app::SessionsApp)
    app.diagnostics_open = !app.diagnostics_open
    if app.diagnostics_open
        push!(app.activity_bar.active, :diagnostics)
        # Refresh diagnostics from LSP + JET
        _refresh_diagnostics!(app)
    else
        delete!(app.activity_bar.active, :diagnostics)
    end
end

"""Refresh diagnostics from all sources (LSP + JET direct)."""
function _refresh_diagnostics!(app::SessionsApp)
    # Merge LSP diagnostics
    if app.lsp.status == lsp_ready
        app.cell_diagnostics_cache = lsp_cell_diagnostics(app.lsp, app.nb)
    end

    # Also run JET direct analysis as fallback if LSP isn't ready
    if app.lsp.status != lsp_ready
        Tachikoma.spawn_task!(app.tq, :jet_analyze) do
            jet_results = analyze_notebook_jet(app.nb)
            app.jet_diagnostics_cache = jet_results
            # Convert to cell diagnostics format
            for (id, cd) in jet_results
                app.cell_diagnostics_cache[id] = cd.diagnostics
            end
            update_entries!(app.diagnostics_panel, app.jet_diagnostics_cache, app.nb)
        end
    else
        # Build CellDiagnostics from LSP data for the panel
        jet_cache = Dict{UUID, CellDiagnostics}()
        for (id, diags) in app.cell_diagnostics_cache
            jet_cache[id] = CellDiagnostics(id, diags, UInt64(0), :error)
        end
        update_entries!(app.diagnostics_panel, jet_cache, app.nb)
    end
end

"""Sync notebook changes to LSP and refresh diagnostics."""
function _lsp_sync_and_refresh!(app::SessionsApp)
    if app.lsp.status == lsp_ready
        app.lsp_doc_version += 1
        lsp_sync_notebook!(app.lsp, app.nb, app.lsp_doc_version)
        # Schedule diagnostic refresh after a brief delay to let LSP process
        @async begin
            sleep(0.5)
            app.cell_diagnostics_cache = lsp_cell_diagnostics(app.lsp, app.nb)
            if app.diagnostics_open
                jet_cache = Dict{UUID, CellDiagnostics}()
                for (id, diags) in app.cell_diagnostics_cache
                    jet_cache[id] = CellDiagnostics(id, diags, UInt64(0), :error)
                end
                update_entries!(app.diagnostics_panel, jet_cache, app.nb)
            end
        end
    end
end

"""Format all notebook cells using Runic.jl. Returns number of cells that changed."""
function _format_notebook_cells!(app::SessionsApp)::Int
    n_formatted = 0
    nv = app.notebook_view
    for (i, cw) in enumerate(nv.cell_widgets)
        cell = cw.cell
        cell.disabled && continue
        original = cell.code
        formatted = format_code(original)
        if formatted != original
            n_formatted += 1
            cell.code = formatted
            # Update editor text, preserving cursor as best we can
            old_row = cw.editor.cursor_row
            old_col = cw.editor.cursor_col
            Tachikoma.set_text!(cw.editor, formatted)
            new_nlines = length(cw.editor.lines)
            cw.editor.cursor_row = clamp(old_row, 1, max(1, new_nlines))
            cw.editor.cursor_col = clamp(old_col, 0, length(cw.editor.lines[cw.editor.cursor_row]))
        end
    end
    n_formatted
end

"""Quit the app, cleaning up all resources."""
function _quit_app!(app::SessionsApp)
    for tab in app.tabs
        if tab.watcher !== nothing
            stop_watching!(tab.watcher)
            tab.watcher = nothing
        end
    end
    app.watcher = nothing
    stop_repl!(app.repl_panel)
    stop_lsp!(app.lsp)
    _cleanup_virtual_notebook!(app.nb)
    app.quit = true
end

"""Switch to a different tab by index."""
function _switch_tab!(app::SessionsApp, idx::Int)
    (idx < 1 || idx > length(app.tabs) || idx == app.active_tab_idx) && return
    _save_to_tab!(app)
    _load_from_tab!(app, idx)
end

"""Open a file in a new tab (or switch to existing tab if already open)."""
function _open_in_tab!(app::SessionsApp, path::String)
    # Check if already open
    apath = abspath(path)
    for (i, tab) in enumerate(app.tabs)
        if abspath(tab.path) == apath
            _switch_tab!(app, i)
            return
        end
    end

    # Save current tab state
    _save_to_tab!(app)

    try
        if is_notebook_file(path)
            nb = load_notebook_with_session(path)
            tab = EditorTab(nb)
            push!(app.tabs, tab)
            _load_from_tab!(app, length(app.tabs))
            _start_watcher!(app)
            app.message = "Opened notebook: $(basename(path))"
        else
            fev = FileEditorView(path)
            tab = EditorTab(fev)
            push!(app.tabs, tab)
            _load_from_tab!(app, length(app.tabs))
            app.message = "Opened file: $(basename(path))"
        end
    catch e
        app.message = "Error: $(sprint(showerror, e))"
    end
end

"""Close a tab by index. Returns true if closed, false if cancelled."""
function _close_tab!(app::SessionsApp, idx::Int)
    (idx < 1 || idx > length(app.tabs)) && return true
    length(app.tabs) <= 1 && return false  # keep at least one tab

    tab = app.tabs[idx]

    # Stop watcher if this tab has one
    if tab.watcher !== nothing
        stop_watching!(tab.watcher)
        tab.watcher = nothing
    end

    deleteat!(app.tabs, idx)

    # Adjust active index
    if app.active_tab_idx == idx
        # Switch to nearest tab
        new_idx = min(idx, length(app.tabs))
        _load_from_tab!(app, new_idx)
        _start_watcher!(app)
    elseif app.active_tab_idx > idx
        app.active_tab_idx -= 1
    end
    true
end

"""Request to close a tab — shows confirmation if notebook or unsaved file."""
function _request_close_tab!(app::SessionsApp, idx::Int)
    (idx < 1 || idx > length(app.tabs)) && return
    length(app.tabs) <= 1 && return  # keep at least one tab

    tab = app.tabs[idx]
    dirty = is_tab_dirty(tab)

    if tab.tab_type == :notebook
        title = dirty ? "Close Unsaved Notebook" : "Close Notebook"
        msg = dirty ? "\"$(tab.label)\" has unsaved changes. Close anyway?" :
                      "Close notebook \"$(tab.label)\"?"
        app.confirm_dialog = ConfirmDialog(title, msg,
            () -> begin
                _close_tab!(app, idx)
                app.message = "Closed: $(tab.label)"
            end, :no, false, false)
        app.mode = :confirm
    elseif dirty
        app.confirm_dialog = ConfirmDialog("Close Unsaved File",
            "\"$(tab.label)\" has unsaved changes. Close anyway?",
            () -> begin
                _close_tab!(app, idx)
                app.message = "Closed: $(tab.label)"
            end, :no, false, false)
        app.mode = :confirm
    else
        _close_tab!(app, idx)
        app.message = "Closed: $(tab.label)"
    end
end

function SessionsApp(nb::Notebook)
    ws = Workspace()
    nv = NotebookView(nb)
    dir = isempty(nb.path) ? pwd() : dirname(abspath(nb.path))
    fp = FilePanel(dir)
    ab = ActivityBar()
    snapshot = _snapshot_notebook(nb)
    tab = EditorTab(nb)
    tab.workspace = ws
    tab.notebook_view = nv
    tab.last_disk_nb = snapshot
    SessionsApp(nb, ws, nv, nothing, :notebook, fp, ab, Tachikoma.TaskQueue(), :normal, false, "", nothing, nothing, nothing,
        DeletedCell[], true, Tachikoma.Rect(), Tachikoma.Rect(), Tachikoma.Rect(), Set{UUID}(), 0, snapshot, nothing, 0.0,
        false, 0, false, 0,
        [tab], 1, Tachikoma.Rect[], Tachikoma.Rect[],
        ReplPanel(), false, Tachikoma.Rect(),
        LspClient(; enabled=true), DiagnosticsPanel(), false, Dict{UUID, Vector{Diagnostic}}(), 0,
        Dict{UUID, CellDiagnostics}(), 0.0,
        nothing, 0, 0, 0.0, false,
        nothing,
        0, 0, 0,
        nothing,
        0.0)
end

function SessionsApp(fev::FileEditorView)
    # File editor mode: create a dummy notebook for compatibility
    nb = Notebook(; path=fev.path)
    ws = Workspace()
    nv = NotebookView(nb)
    dir = dirname(abspath(fev.path))
    fp = FilePanel(dir)
    ab = ActivityBar()
    tab = EditorTab(fev)
    tab.nb = nb
    tab.workspace = ws
    tab.notebook_view = nv
    SessionsApp(nb, ws, nv, fev, :file, fp, ab, Tachikoma.TaskQueue(), :insert, false, "", nothing, nothing, nothing,
        DeletedCell[], true, Tachikoma.Rect(), Tachikoma.Rect(), Tachikoma.Rect(), Set{UUID}(), 0, nothing, nothing, 0.0,
        false, 0, false, 0,
        [tab], 1, Tachikoma.Rect[], Tachikoma.Rect[],
        ReplPanel(), false, Tachikoma.Rect(),
        LspClient(; enabled=true), DiagnosticsPanel(), false, Dict{UUID, Vector{Diagnostic}}(), 0,
        Dict{UUID, CellDiagnostics}(), 0.0,
        nothing, 0, 0, 0.0, false,
        nothing,
        0, 0, 0,
        nothing,
        0.0)
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
    # Start JETLS language server (on by default)
    if app.lsp.enabled
        dir = _find_project_root(app.nb.path)
        @async begin
            start_lsp!(app.lsp; project_dir=dir)
            # Wait for initialize handshake to complete (up to 45s)
            for _ in 1:90
                app.lsp.status in (lsp_ready, lsp_error, lsp_off) && break
                sleep(0.5)
            end
            # Once ready, sync the current document
            if app.lsp.status == lsp_ready
                if app.editor_type == :file && app.file_editor_view !== nothing
                    fev = app.file_editor_view
                    lsp_did_open!(app.lsp, "file://" * abspath(fev.path),
                        Tachikoma.text(fev.editor))
                else
                    app.lsp_doc_version += 1
                    lsp_sync_notebook!(app.lsp, app.nb, app.lsp_doc_version)
                end
            end
        end
    end
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

    # Sync watcher to active tab
    if !isempty(app.tabs) && app.active_tab_idx <= length(app.tabs)
        app.tabs[app.active_tab_idx].watcher = app.watcher
    end
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
        _sync_to_active_tab!(app)

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

    # Debounced LSP sync: after 1s of no typing, push changes to JETLS
    if app.lsp_sync_needed > 0.0 && app.lsp.status == lsp_ready
        elapsed = time() - app.lsp_sync_needed
        if elapsed >= 1.0
            app.lsp_sync_needed = 0.0
            app.lsp_doc_version += 1
            lsp_sync_notebook!(app.lsp, app.nb, app.lsp_doc_version)
        end
    end

    # Debounced hover: after HOVER_DEBOUNCE of mouse stillness, request hover info
    # Only in file editor mode — notebook cells are virtual documents where
    # screen position doesn't map cleanly to LSP document positions
    if app.hover_still_since > 0.0 && !app.hover_requested && app.lsp.status == lsp_ready &&
       app.hover_tooltip === nothing && app.mode in (:file_editor, :file_editor_insert)
        elapsed = time() - app.hover_still_since
        if elapsed >= HOVER_DEBOUNCE
            app.hover_requested = true
            _request_hover!(app, app.hover_last_mouse_x, app.hover_last_mouse_y)
        end
    end

    # Poll LSP diagnostics (async notifications arrive on reader task)
    if app.lsp.status == lsp_ready
        app.cell_diagnostics_cache = lsp_cell_diagnostics(app.lsp, app.nb)
        # Update diagnostics panel entries if panel is open
        if app.diagnostics_open
            jet_cache = Dict{UUID, CellDiagnostics}()
            for (id, diags) in app.cell_diagnostics_cache
                jet_cache[id] = CellDiagnostics(id, diags, UInt64(0), :lsp)
            end
            update_entries!(app.diagnostics_panel, jet_cache, app.nb)
        end
    end

    # Fill entire screen with pure black background — islands float on top
    for fy in area.y:(area.y + area.height - 1)
        Tachikoma.set_string!(buf, area.x, fy, " " ^ area.width, Theme.S_BG)
    end

    # Inset content: minimal top padding (1 row), standard gap on other edges
    top_pad = 1
    content_rect = Tachikoma.Rect(area.x + g, area.y + top_pad,
        max(1, area.width - 2 * g), max(1, area.height - top_pad - g))

    # Horizontal layout: activity bar | gap | [sidebar | gap] | notebook
    # Sidebar opens if file explorer OR diagnostics is active
    sidebar_visible = app.sidebar_open || app.diagnostics_open
    ab_w = Theme.ACTIVITY_BAR_W
    if sidebar_visible
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

    # Render sidebar panels (file explorer and/or diagnostics)
    if sidebar_visible
        both = app.sidebar_open && app.diagnostics_open
        if both
            # Split sidebar: file panel on top, diagnostics on bottom
            side_layout = Tachikoma.Layout(Tachikoma.Vertical,
                [Tachikoma.Percent(60), Tachikoma.Fill()])
            side_rects = Tachikoma.split_layout(side_layout, sidebar_rect)
            Tachikoma.render(app.file_panel, side_rects[1], buf)
            Tachikoma.render(app.diagnostics_panel, side_rects[2], buf)
        elseif app.sidebar_open
            Tachikoma.render(app.file_panel, sidebar_rect, buf)
        elseif app.diagnostics_open
            Tachikoma.render(app.diagnostics_panel, sidebar_rect, buf)
        end
    end

    # ── Tab bar (only when multiple tabs are open) ──
    editor_rect = notebook_rect
    if length(app.tabs) > 1
        tab_h = TAB_BAR_HEIGHT
        tab_bar_rect = Tachikoma.Rect(notebook_rect.x, notebook_rect.y,
            notebook_rect.width, tab_h)
        editor_rect = Tachikoma.Rect(notebook_rect.x, notebook_rect.y + tab_h,
            notebook_rect.width, max(1, notebook_rect.height - tab_h))
        app.tab_rects, app.close_rects = render_tab_bar!(app.tabs, app.active_tab_idx,
            tab_bar_rect, buf)
    else
        app.tab_rects = Tachikoma.Rect[]
        app.close_rects = Tachikoma.Rect[]
    end

    # ── REPL panel layout (calculate rects, but render AFTER notebook) ──
    if app.repl_open
        repl_h = max(5, div(editor_rect.height * Theme.REPL_PCT, 100))
        main_h = max(3, editor_rect.height - repl_h - 1)  # -1 for gap
        main_rect = Tachikoma.Rect(editor_rect.x, editor_rect.y,
            editor_rect.width, main_h)
        repl_rect = Tachikoma.Rect(editor_rect.x, editor_rect.y + main_h + 1,
            editor_rect.width, repl_h)
        app.repl_rect = repl_rect
        app.repl_panel.focused = (app.mode == :repl)
        editor_rect = main_rect
    else
        app.repl_rect = Tachikoma.Rect()
    end

    # ── Render editor (notebook or file) ──
    if app.editor_type == :file && app.file_editor_view !== nothing
        fev = app.file_editor_view
        fev.editor.focused = (app.mode == :insert)
        # Sync file diagnostics from LSP
        if app.lsp.status == lsp_ready
            fev.diagnostics = lsp_file_diagnostics(app.lsp, abspath(fev.path))
        end
        Tachikoma.render(fev, editor_rect, buf)
        # Scrollbar for file editor
        sb_x = editor_rect.x + editor_rect.width - 1
        sb_y = editor_rect.y
        sb_h = editor_rect.height
        total_lines = length(fev.editor.lines)
        vi = Theme.CELL_V_INSET
        viewport_h = max(1, editor_rect.height - 2 * vi - 2)
        _render_scrollbar!(buf, sb_x, sb_y, sb_h, total_lines, viewport_h, fev.editor.scroll_offset)
        app.scrollbar_col = sb_x
        app.scrollbar_y = sb_y
        app.scrollbar_h = sb_h
    else
        for (i, cw) in enumerate(app.notebook_view.cell_widgets)
            cw.editor.focused = (i == app.notebook_view.focused_idx && app.mode == :insert)
            if app.mode == :panel
                cw.focused = false
            end
        end
        app.notebook_view.dirty = _is_notebook_dirty(app)
        app.notebook_view.cell_diags = app.cell_diagnostics_cache
        app.notebook_view.lsp_status = app.lsp.status
        # Thread Frame for image rendering — suppress during ALL active interaction.
        # Sixel/Kitty re-encoding is ~5-20ms per image. During interaction (typing,
        # scrolling, arrow keys, clicks), suppress raster → braille fallback (fast).
        # After 200ms of no events, allow raster → sharp images settle in.
        interacting = app.last_interaction_time > 0.0 && (time() - app.last_interaction_time) < 0.2
        suppress_raster = app.slider_drag || interacting
        app.notebook_view.current_frame = suppress_raster ? nothing : frame
        Tachikoma.render(app.notebook_view, editor_rect, buf)
        _update_and_render_progress!(app, editor_rect, buf)
        # Scrollbar for notebook
        sb_x = editor_rect.x + editor_rect.width - 1
        sb_y = editor_rect.y
        sb_h = editor_rect.height
        nv = app.notebook_view
        total_h = content_height(nv)
        vi = Theme.CELL_V_INSET
        viewport_h = max(1, editor_rect.height - 2 * vi - 2)
        _render_scrollbar!(buf, sb_x, sb_y, sb_h, total_h, viewport_h, nv.scroll_offset)
        app.scrollbar_col = sb_x
        app.scrollbar_y = sb_y
        app.scrollbar_h = sb_h
    end

    # Repaint overflow areas — scoped to editor column only (don't overwrite sidebar)
    ox = notebook_rect.x
    ow = notebook_rect.width
    for fy in area.y:(notebook_rect.y - 1)
        Tachikoma.set_string!(buf, ox, fy, " " ^ ow, Theme.S_BG)
    end
    nb_bottom = editor_rect.y + editor_rect.height
    screen_bottom = area.y + area.height - 1
    for fy in nb_bottom:screen_bottom
        Tachikoma.set_string!(buf, ox, fy, " " ^ ow, Theme.S_BG)
    end

    # ── Render REPL panel AFTER overflow cleanup (so it's never overwritten) ──
    if app.repl_open
        Tachikoma.render(app.repl_panel, app.repl_rect, buf)
    end

    # Cell dropdown overlay
    if app.cell_dropdown !== nothing
        _render_dropdown!(app.cell_dropdown, buf, area)
    end

    # Completion popup overlay
    if app.completion_popup !== nothing
        _render_completion_popup!(app.completion_popup, buf, area)
    end

    # Hover tooltip overlay
    if app.hover_tooltip !== nothing
        _render_hover_tooltip!(app.hover_tooltip, buf, area)
    end

    # Signature help tooltip overlay
    if app.signature_tooltip !== nothing
        _render_signature_help!(app.signature_tooltip, buf, area)
    end

    # Rename prompt overlay
    if app.rename_prompt !== nothing
        _render_rename_prompt!(app.rename_prompt, buf, area)
    end

    # Confirm dialog overlay (centered, with dimmed backdrop)
    if app.confirm_dialog !== nothing
        _render_confirm_dialog!(app.confirm_dialog, buf, area)
    end

    # Message bar at bottom of screen (temporary feedback)
    if !isempty(app.message)
        msg_y = area.y + area.height - 1
        # Dim the bottom row, then overlay the message
        msg_style = Tachikoma.Style(; fg=Theme.ACCENT, bg=Theme.BG)
        Tachikoma.set_string!(buf, area.x, msg_y, " " ^ area.width, msg_style)
        display_msg = " " * app.message
        if length(display_msg) > area.width
            display_msg = display_msg[1:area.width]
        end
        Tachikoma.set_string!(buf, area.x, msg_y, display_msg, msg_style)
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

    # Hover — highlight entry under mouse
    if evt.action == Tachikoma.mouse_move
        idx = entry_at_y(fp, evt.y)
        fp.hovered_idx = idx !== nothing ? idx : 0
        return
    end

    # Left click on a file entry
    if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press
        idx = entry_at_y(fp, evt.y)
        if idx !== nothing
            entry = fp.entries[idx]
            # Trash icon click — delete with confirmation
            if entry.name != ".." && is_trash_click(fp, evt.x, evt.y)
                _request_delete_file!(app, entry)
                return
            end
            # Normal click — open file or enter directory
            fp.cursor_idx = idx
            result = activate!(fp)
            if result !== nothing
                _open_file!(app, result)
            end
        end
    end
end

"""Request deletion of a file or directory with confirmation dialog."""
function _request_delete_file!(app::SessionsApp, entry::FileEntry)
    kind = entry.is_dir ? "directory" : "file"
    title = "Delete $(titlecase(kind))"
    msg = "Permanently delete $(kind) \"$(entry.name)\"?"

    app.confirm_dialog = ConfirmDialog(title, msg,
        () -> begin
            try
                if entry.is_dir
                    rm(entry.path; recursive=true)
                else
                    rm(entry.path)
                end
                app.message = "Deleted: $(entry.name)"
                # Close any open tabs for this file
                for i in length(app.tabs):-1:1
                    if app.tabs[i].path == entry.path
                        _close_tab!(app, i)
                    end
                end
                refresh_entries!(app.file_panel)
            catch e
                app.message = "Delete failed: $(sprint(showerror, e))"
            end
        end, :no, false, false)
    app.mode = :confirm
end

"""Open a file in a new tab (or switch to existing)."""
function _open_file!(app::SessionsApp, path::String)
    _open_in_tab!(app, path)
end

"""Reset the entire workspace to a new folder. Creates an empty notebook and refreshes the file panel."""
function reset_to_folder!(app::SessionsApp, dir::String)
    dir = abspath(dir)
    isdir(dir) || return

    # Stop all tab watchers
    for tab in app.tabs
        if tab.watcher !== nothing
            stop_watching!(tab.watcher)
            tab.watcher = nothing
        end
    end

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

    tab = EditorTab(nb)
    app.tabs = [tab]
    app.active_tab_idx = 1

    app.nb = nb
    app.workspace = tab.workspace
    app.notebook_view = tab.notebook_view
    app.file_editor_view = nothing
    app.editor_type = :notebook
    app.file_panel = FilePanel(dir)
    app.undo_buffer = DeletedCell[]
    app.cell_dropdown = nothing
    app.confirm_dialog = nothing
    app.mode = :normal
    app.last_disk_nb = tab.last_disk_nb
    app.watcher = nothing
    app.last_save_time = 0.0
    app.progress_recently = Set{UUID}()
    app.progress_done_tick = 0
    _start_watcher!(app)
    app.message = "Opened workspace: $(basename(dir))"
end

function Tachikoma.update!(app::SessionsApp, evt::Tachikoma.KeyEvent)
    # Only suppress raster during rapid navigation that scrolls content
    if evt.key in (:up, :down, :pageup, :pagedown)
        app.last_interaction_time = time()
    end
    app.message = ""  # Clear status message on any key
    # Dismiss hover tooltip on any keypress
    app.hover_tooltip = nothing
    # Dismiss signature help on non-typing keys (movement, escape, enter, etc.)
    if app.signature_tooltip !== nothing && !(evt.key in (:char, :backspace, :delete))
        app.signature_tooltip = nothing
    end

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

    # Completion popup mode — Up/Down navigate, Enter accepts, Escape/other dismisses
    if app.mode == :completion && app.completion_popup !== nothing
        popup = app.completion_popup
        if evt.key == :escape
            _close_completion!(app)
            return
        elseif evt.key == :down
            n = length(popup.items)
            popup.selected_idx = popup.selected_idx >= n ? 1 : popup.selected_idx + 1
            return
        elseif evt.key == :up
            n = length(popup.items)
            popup.selected_idx = popup.selected_idx <= 1 ? n : popup.selected_idx - 1
            return
        elseif evt.key == :enter
            if popup.selected_idx >= 1 && popup.selected_idx <= length(popup.items)
                _accept_completion!(app, popup.items[popup.selected_idx])
            end
            _close_completion!(app)
            return
        else
            # Any other key dismisses and gets forwarded
            _close_completion!(app)
            # Fall through to normal key handling
        end
    end

    # --- Rename mode: handle rename prompt input ---
    if app.mode == :rename && app.rename_prompt !== nothing
        rp = app.rename_prompt
        if evt.key == :escape
            app.rename_prompt = nothing
            app.mode = :insert
            return
        elseif evt.key == :enter
            if rp.new_name == rp.old_name || isempty(rp.new_name)
                app.rename_prompt = nothing
                app.mode = :insert
                return
            end
            # Try LSP rename first, fall back to local
            edits = lsp_rename_with_timeout!(app.lsp, _current_uri(app),
                _current_editor(app).cursor_row, _current_editor(app).cursor_col,
                rp.new_name; timeout=3.0)
            if isempty(edits)
                _apply_rename_local!(app, rp.old_name, rp.new_name)
                app.message = "Renamed '$(rp.old_name)' → '$(rp.new_name)' (local)"
            else
                app.message = "Renamed '$(rp.old_name)' → '$(rp.new_name)' ($(length(edits)) edits)"
            end
            app.rename_prompt = nothing
            app.mode = :insert
            return
        elseif evt.key == :backspace
            if rp.cursor > 0
                rp.new_name = rp.new_name[1:rp.cursor-1] * rp.new_name[rp.cursor+1:end]
                rp.cursor -= 1
            end
            return
        elseif evt.key == :char
            rp.new_name = rp.new_name[1:rp.cursor] * string(evt.char) * rp.new_name[rp.cursor+1:end]
            rp.cursor += 1
            return
        end
        return
    end

    # --- DataTable mode: forward keys to focused datatable ---
    if app.mode == :datatable
        dt = _focused_datatable(app)
        if dt !== nothing
            if evt.key == :escape
                app.mode = :normal
                return
            end
            # Number keys sort by column
            if evt.key == :char && '1' <= evt.char <= '9'
                col_num = Int(evt.char) - Int('0')
                col_num <= length(dt.columns) && Tachikoma.sort_by!(dt, col_num)
                return
            end
            Tachikoma.handle_key!(dt, evt)
        else
            app.mode = :normal
        end
        return
    end

    # --- Image interaction mode: pan/zoom focused image ---
    if app.mode == :image_interact
        nv = app.notebook_view
        ow = nv.output_widgets[nv.focused_idx]
        if evt.key == :escape || (evt.key == :char && evt.char == 'q')
            app.mode = :normal
            app.message = ""
            return
        elseif evt.key == :char && evt.char == 'r'
            _reset_viewport!(ow)
            app.message = "Image: reset"
            return
        elseif evt.key == :up
            _pan!(ow, 0, -_PAN_STEP)
            return
        elseif evt.key == :down
            _pan!(ow, 0, _PAN_STEP)
            return
        elseif evt.key == :left
            _pan!(ow, -_PAN_STEP, 0)
            return
        elseif evt.key == :right
            _pan!(ow, _PAN_STEP, 0)
            return
        elseif evt.key == :char && (evt.char == '+' || evt.char == '=')
            _zoom_in!(ow)
            app.message = "Image: zoom $(ow._img_zoom)x"
            return
        elseif evt.key == :char && evt.char == '-'
            _zoom_out!(ow)
            app.message = "Image: zoom $(ow._img_zoom)x"
            return
        end
        return  # absorb all other keys in image interaction mode
    end

    # --- REPL mode: forward keys to REPL panel ---
    if app.mode == :repl && app.repl_open
        # Ctrl+Q still quits
        if evt.key == :ctrl && evt.char == 'q'
            _quit_app!(app)
            return
        end
        # Escape exits REPL focus back to normal mode
        repl_tab = active_tab(app.repl_panel)
        if evt.key == :escape && (repl_tab === nothing || repl_tab.repl_mode == :julia)
            app.mode = :normal
            app.repl_panel.focused = false
            return
        end
        # Ctrl+` toggles REPL off
        if evt.key == :ctrl && evt.char == '`'
            _toggle_repl!(app)
            return
        end
        # Forward to REPL
        handle_repl_key!(app.repl_panel, evt)
        return
    end

    # --- File editor mode: route keys to CodeEditor ---
    if app.editor_type == :file && app.file_editor_view !== nothing
        _handle_file_editor_key!(app, evt)
        return
    end

    # --- Essential keybindings only (everything else is mouse-driven) ---

    # Ctrl+` or backtick: toggle REPL panel
    if evt.key == :ctrl && evt.char == '`'
        _toggle_repl!(app)
        return
    end

    # Ctrl+W: close current tab (when multiple tabs open)
    if evt.key == :ctrl && evt.char == 'w'
        if length(app.tabs) > 1
            _request_close_tab!(app, app.active_tab_idx)
        end
        return
    end

    # Ctrl+Q: quit (always)
    if evt.key == :ctrl && evt.char == 'q'
        _quit_app!(app)
        return
    end

    # Ctrl+C: behavior depends on mode
    #   panel  → quit (like Ctrl+C in a normal terminal)
    #   normal → copy entire focused cell code
    #   insert → copy text selection (or current line if no selection)
    if evt.key == :ctrl && evt.char == 'c'
        if app.mode == :panel
            _quit_app!(app)
            return
        elseif app.mode == :insert
            cw = focused_widget(app.notebook_view)
            if cw !== nothing && cw.selection.active
                text = _selected_text(cw.editor.lines, cw.selection,
                    cw.editor.cursor_row, cw.editor.cursor_col)
                _clipboard_copy!(text)
                app.message = "Copied $(length(text)) chars"
            elseif cw !== nothing
                # No selection — copy current line (VS Code behavior)
                line = String(cw.editor.lines[cw.editor.cursor_row])
                _clipboard_copy!(line)
                app.message = "Copied line"
            end
            return
        else  # :normal
            cw = focused_widget(app.notebook_view)
            if cw !== nothing
                _clipboard_copy!(cw.cell.code)
                app.message = "Copied cell"
            end
            return
        end
    end

    # Ctrl+S / Cmd+S: format + save + run stale + sync LSP
    if evt.key == :ctrl && evt.char == 's'
        n_formatted = _format_notebook_cells!(app)
        save_notebook(app.nb)
        app.last_save_time = time()
        app.last_disk_nb = _snapshot_notebook(app.nb)
        _sync_to_active_tab!(app)
        n_stale = run_stale_cells!(app)
        # Re-sync to JETLS after save for updated diagnostics
        _lsp_sync_and_refresh!(app)
        if n_stale > 0
            app.message = "Saved + ran $n_stale stale cell$(n_stale == 1 ? "" : "s")"
        elseif n_formatted > 0
            app.message = "Formatted $(n_formatted) cell$(n_formatted == 1 ? "" : "s") + Saved"
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

    # Ctrl+G: go to definition (LSP)
    if evt.key == :ctrl && evt.char == 'g'
        _goto_definition!(app)
        return
    end

    # F2: rename symbol
    if evt.key == :f2
        _start_rename!(app)
        return
    end

    # Escape: insert → normal → panel (progressive de-focus)
    if evt.key == :escape
        if app.mode == :insert
            _exit_insert_mode!(app)
        elseif app.mode == :normal
            if has_selection(app.notebook_view)
                clear_selection!(app.notebook_view)
            else
                _enter_panel_mode!(app)
            end
        end
        return
    end

    # Ctrl+Space: trigger completion popup (insert mode only)
    if evt.key == :ctrl_space && app.mode == :insert
        _trigger_completion!(app)
        return
    end

    # --- Insert mode: all keys (including Delete/Backspace) go to the editor ---
    if app.mode == :insert
        cw = focused_widget(app.notebook_view)
        if cw !== nothing
            Tachikoma.handle_key!(cw, evt)
            # Mark that LSP needs re-sync (debounced in view loop)
            if app.lsp.status == lsp_ready
                app.lsp_sync_needed = time()
            end
            # Signature help triggers
            if evt.key == :char
                if evt.char == '('
                    _trigger_signature_help!(app)
                elseif evt.char == ')'
                    app.signature_tooltip = nothing
                elseif evt.char == ',' && app.signature_tooltip !== nothing
                    _advance_signature_param!(app)
                end
            end
        end
        return
    end

    # --- Panel mode: arrow keys re-enter normal, Enter goes to insert ---
    if app.mode == :panel
        if evt.key == :up || evt.key == :down
            _exit_panel_mode!(app)
            if evt.key == :down
                focus_next!(app.notebook_view)
            end
        elseif evt.key == :enter
            _exit_panel_mode!(app)
            _enter_insert_mode!(app)
        end
        # All other keys are ignored in panel mode (except Ctrl+C/Q/S/R handled above)
        return
    end

    # --- Normal mode keybindings ---

    # Left/Right: adjust bond slider if focused cell has one
    if evt.key in (:left, :right)
        if _try_adjust_bond!(app, evt.key == :right ? 1 : -1)
            return
        end
    end

    # Arrow keys: navigate cells
    if evt.key == :up
        focus_prev!(app.notebook_view)
        return
    end
    if evt.key == :down
        focus_next!(app.notebook_view)
        return
    end

    # Enter: enter image interaction mode if focused cell has image output, else insert mode
    if evt.key == :enter
        nv = app.notebook_view
        if !isempty(nv.output_widgets) && nv.focused_idx <= length(nv.output_widgets)
            fc = nv.output_widgets[nv.focused_idx].cell
            if _is_image_cell(fc)
                app.mode = :image_interact
                app.message = "Image: ←→↑↓ pan, +/- zoom, r reset, q/Esc exit"
                return
            end
        end
        _enter_insert_mode!(app)
        return
    end

    # Shift+R: Run all cells (normal mode only)
    if evt.key == :char && evt.char == 'R'
        run_all_cells_async!(app)
        return
    end

    # Delete/Backspace: confirm delete of selected cells or focused cell
    if evt.key == :delete || evt.key == :backspace
        nv = app.notebook_view
        if has_selection(nv)
            n_sel = count(cw -> cw.selected, nv.cell_widgets)
            _open_confirm_delete_selection!(app, n_sel)
        elseif !isempty(nv.cell_widgets) && length(nv.cell_widgets) > 1
            _open_confirm_delete!(app, nv.focused_idx)
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
    # Only debounce raster during scroll events — clicks/hover don't move images
    if evt.button in (Tachikoma.mouse_scroll_up, Tachikoma.mouse_scroll_down)
        app.last_interaction_time = time()
    end
    nv = app.notebook_view

    # Clear status message on any click
    if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press
        app.message = ""
    end

    # Ctrl+Click: go to definition
    if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press && evt.ctrl
        _goto_definition!(app)
        return
    end

    # Scrollbar click: jump to relative position
    if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press &&
       app.scrollbar_col > 0 && evt.x == app.scrollbar_col &&
       evt.y >= app.scrollbar_y && evt.y < app.scrollbar_y + app.scrollbar_h
        relative = (evt.y - app.scrollbar_y) / max(1, app.scrollbar_h - 1)
        if app.editor_type == :file && app.file_editor_view !== nothing
            fev = app.file_editor_view
            total_lines = length(fev.editor.lines)
            vi = Theme.CELL_V_INSET
            viewport_h = max(1, app.scrollbar_h - 2 * vi - 2)
            max_scroll = max(0, total_lines - viewport_h)
            fev.editor.scroll_offset = clamp(round(Int, relative * max_scroll), 0, max_scroll)
        else
            nv = app.notebook_view
            vi = Theme.CELL_V_INSET
            viewport_h = max(1, app.scrollbar_h - 2 * vi - 2)
            max_scroll = max(0, content_height(nv) - viewport_h)
            nv.scroll_offset = clamp(round(Int, relative * max_scroll), 0, max_scroll)
        end
        return
    end

    # Dismiss hover on scroll — content under cursor changes
    if evt.button in (Tachikoma.mouse_scroll_up, Tachikoma.mouse_scroll_down)
        app.hover_tooltip = nothing
        app.hover_still_since = 0.0
        app.hover_requested = false
    end

    # Clear hover states on every mouse move (specific handlers re-set them)
    if evt.action == Tachikoma.mouse_move
        app.activity_bar.hovered = :none
        app.file_panel.hovered_idx = 0
        # Track mouse position for hover tooltip debounce
        if evt.x != app.hover_last_mouse_x || evt.y != app.hover_last_mouse_y
            app.hover_last_mouse_x = evt.x
            app.hover_last_mouse_y = evt.y
            app.hover_still_since = time()
            app.hover_requested = false
            app.hover_tooltip = nothing  # dismiss on move
        end
    end

    # ── Tab bar clicks ──
    if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press
        # Check × close buttons first (they overlap tab rects)
        for (i, cr) in enumerate(app.close_rects)
            if cr.width > 0 && evt.x >= cr.x && evt.x < cr.x + cr.width && evt.y == cr.y
                _request_close_tab!(app, i)
                return
            end
        end
        # Check tab label clicks
        for (i, tr) in enumerate(app.tab_rects)
            if tr.width > 0 && evt.x >= tr.x && evt.x < tr.x + tr.width && evt.y == tr.y
                _switch_tab!(app, i)
                return
            end
        end
    end

    # ── REPL panel clicks ──
    rr = app.repl_rect
    if app.repl_open && rr.width > 0 &&
       evt.x >= rr.x && evt.x < rr.x + rr.width &&
       evt.y >= rr.y && evt.y < rr.y + rr.height
        # Scroll
        if evt.button == Tachikoma.mouse_scroll_up || evt.button == Tachikoma.mouse_scroll_down
            handle_repl_scroll!(app.repl_panel, evt)
            return
        end
        # Click — handle tab bar clicks, then focus
        if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press
            handle_repl_click!(app.repl_panel, evt)
            app.mode = :repl
            app.repl_panel.focused = true
            return
        end
        return
    end

    # Activity bar clicks — toggle sidebar or REPL
    ar = app.activity_rect
    if ar.width > 0 && evt.x >= ar.x && evt.x < ar.x + ar.width &&
       evt.y >= ar.y && evt.y < ar.y + ar.height
        if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press
            btn_id = button_at_y(app.activity_bar, evt.y)
            if btn_id == :explorer
                toggle!(app.activity_bar, btn_id)
                app.sidebar_open = is_active(app.activity_bar, :explorer)
            elseif btn_id == :terminal
                _toggle_repl!(app)
            elseif btn_id == :diagnostics
                toggle!(app.activity_bar, btn_id)
                app.diagnostics_open = is_active(app.activity_bar, :diagnostics)
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
        _handle_file_panel_mouse!(app, evt)
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

    # ── File editor mode: handle scroll and basic mouse interactions ──
    if app.editor_type == :file && app.file_editor_view !== nothing
        fev = app.file_editor_view
        ce = fev.editor
        n_lines = length(ce.lines)

        # Compute visible height from viewport
        hi = Theme.CELL_H_INSET
        vi = Theme.CELL_V_INSET
        vp = fev.viewport
        visible_h = max(1, vp.height - 2 * vi - 2)

        if evt.button == Tachikoma.mouse_scroll_down
            ce.scroll_offset = min(ce.scroll_offset + 3, max(0, n_lines - 5))
            # Move cursor into visible range so render doesn't snap back
            if ce.cursor_row < ce.scroll_offset + 1
                ce.cursor_row = min(ce.scroll_offset + 1, n_lines)
                ce.cursor_col = 0
            end
            return
        end
        if evt.button == Tachikoma.mouse_scroll_up
            ce.scroll_offset = max(ce.scroll_offset - 3, 0)
            # Move cursor into visible range so render doesn't snap back
            if ce.cursor_row > ce.scroll_offset + visible_h
                ce.cursor_row = max(ce.scroll_offset + visible_h, 1)
                ce.cursor_col = 0
            end
            return
        end

        # Click to position cursor
        if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press
            vp = fev.viewport
            if vp.width > 0 && evt.x >= vp.x && evt.x < vp.x + vp.width &&
               evt.y >= vp.y && evt.y < vp.y + vp.height
                hi = Theme.CELL_H_INSET
                vi = Theme.CELL_V_INSET
                inner_x = vp.x + hi + 1
                inner_y = vp.y + vi + 1
                # Account for line number gutter
                gw = ndigits(n_lines) + 1
                code_x = inner_x + gw
                row = (evt.y - inner_y) + 1 + ce.scroll_offset
                col = evt.x - code_x
                row = clamp(row, 1, n_lines)
                col = clamp(col, 0, length(ce.lines[row]))
                ce.cursor_row = row
                ce.cursor_col = col
                # Enter insert mode on click
                ce.mode = :insert
                app.mode = :insert
            end
            return
        end

        return
    end

    # ── "Run All" button in notebook top border ──
    ra = nv.run_all_rect
    if ra.width > 0 && evt.x >= ra.x && evt.x < ra.x + ra.width && evt.y == ra.y
        if evt.action == Tachikoma.mouse_move
            nv.run_all_hovered = true
        end
        if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press
            run_all_cells_async!(app)
        end
        return
    elseif evt.action == Tachikoma.mouse_move
        nv.run_all_hovered = false
    end

    # ── "Save" button in notebook top border ──
    sa = nv.save_rect
    if sa.width > 0 && evt.x >= sa.x && evt.x < sa.x + sa.width && evt.y == sa.y
        if evt.action == Tachikoma.mouse_move
            nv.save_hovered = true
        end
        if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press
            save_notebook(app.nb)
            app.last_save_time = time()
            app.last_disk_nb = _snapshot_notebook(app.nb)
            _sync_to_active_tab!(app)
            n_stale = run_stale_cells!(app)
            if n_stale > 0
                app.message = "Saved + ran $n_stale stale cell$(n_stale == 1 ? "" : "s")"
            else
                app.message = "Saved: $(basename(app.nb.path))"
            end
        end
        return
    elseif evt.action == Tachikoma.mouse_move
        nv.save_hovered = false
    end

    # ── All remaining events require the click to be inside the notebook pane ──
    nb_vp = nv.viewport
    in_notebook = nb_vp.width > 0 &&
        evt.x >= nb_vp.x && evt.x < nb_vp.x + nb_vp.width &&
        evt.y >= nb_vp.y && evt.y < nb_vp.y + nb_vp.height

    if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press && in_notebook
        # Exit REPL focus when clicking in notebook
        if app.mode == :repl
            app.mode = :normal
            app.repl_panel.focused = false
        end
        # Shift+click: range selection (enter normal mode)
        if evt.shift
            idx = cell_at_y(nv, evt.y)
            if idx !== nothing
                select_range!(nv, nv.focused_idx, idx)
                _exit_insert_mode!(app)
            end
            return
        end

        # Ctrl+click or Alt+click (Cmd+click on macOS): toggle individual cell selection
        if evt.ctrl || evt.alt
            idx = cell_at_y(nv, evt.y)
            if idx !== nothing
                nv.cell_widgets[idx].selected = !nv.cell_widgets[idx].selected
                focus_cell!(nv, idx)
                _exit_insert_mode!(app)
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
        cw_width = max(1, inner_w - 2 * pad)
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

        # Check if click is on a slider output area (bond widget)
        slider_handled = _try_slider_click(app, nv, evt.x, evt.y, cell_left, cw_width)
        if slider_handled
            return
        end

        # Check if click is on a DataTable output area — enter datatable mode
        dt_idx = _datatable_cell_at_y(nv, evt.y)
        if dt_idx > 0
            dt = _datatable_at_idx(app, dt_idx)
            if dt !== nothing
                # Focus without auto-scrolling — user already sees the table output
                nv.focused_idx = dt_idx
                update_focus!(nv)
                _exit_insert_mode!(app)
                app.mode = :datatable
                # Forward click to DataTable's mouse handler
                Tachikoma.handle_mouse!(dt, evt)
                return
            end
        end

        # Cell click — only enter insert mode if click is inside the cell body
        idx = cell_at_y(nv, evt.y)
        if idx !== nothing
            clear_selection!(nv)
            focus_cell!(nv, idx)
            if evt.x >= cell_left && evt.x < cell_right
                _enter_insert_mode!(app)
                # Position cursor at click location
                cw = nv.cell_widgets[idx]
                code_area = _cell_code_area(nv, idx, cell_left, cw_width)
                row, col = click_to_editor_pos(cw.editor, code_area, evt.x, evt.y)
                cw.editor.cursor_row = row
                cw.editor.cursor_col = col
                cw.selection.active = false
                # Start drag tracking for text selection
                app.drag_active = true
                app.drag_cell_idx = idx
            else
                # Click in margin/padding area — focus cell in normal mode
                _exit_insert_mode!(app)
            end
        else
            # Click in empty gap area — enter panel mode (no cell focused)
            _enter_panel_mode!(app)
        end
        return
    end

    # Mouse drag: slider dragging
    if evt.action == Tachikoma.mouse_drag && app.slider_drag && in_notebook
        nv = app.notebook_view
        idx = app.slider_drag_idx
        if idx >= 1 && idx <= length(nv.cell_widgets)
            cw = nv.cell_widgets[idx]
            cell = cw.cell
            cell.output.output_type == :bond || @goto end_slider_drag
            bond = cell.output.result
            bond isa Bond || @goto end_slider_drag
            bond.element isa Slider || @goto end_slider_drag

            hi = Theme.CELL_H_INSET
            inner_x = nb_vp.x + hi + 1
            inner_w = max(1, nb_vp.width - 2 * hi - 2)
            pad = max(1, round(Int, inner_w * Theme.CELL_PAD_FRACTION))
            pad = min(pad, max(0, div(inner_w - 10, 2)))
            cell_left = inner_x + pad
            cw_width = max(1, inner_w - 2 * pad)

            new_val, hit = _slider_x_to_value(bond, evt.x, cell_left, cw_width)
            if hit
                _apply_slider_value!(app, cell, bond, new_val)
            end
        end
        @label end_slider_drag
        return
    end

    # Mouse drag: extend text selection within a cell
    if evt.action == Tachikoma.mouse_drag && app.drag_active && app.mode == :insert && in_notebook
        idx = app.drag_cell_idx
        if idx >= 1 && idx <= length(nv.cell_widgets)
            cw = nv.cell_widgets[idx]
            hi = Theme.CELL_H_INSET
            vi = Theme.CELL_V_INSET
            inner_x = nb_vp.x + hi + 1
            inner_w = max(1, nb_vp.width - 2 * hi - 2)
            pad = max(1, round(Int, inner_w * Theme.CELL_PAD_FRACTION))
            pad = min(pad, max(0, div(inner_w - 10, 2)))
            cell_left = inner_x + pad
            cw_width = max(1, inner_w - 2 * pad)
            code_area = _cell_code_area(nv, idx, cell_left, cw_width)
            row, col = click_to_editor_pos(cw.editor, code_area, evt.x, evt.y)
            # Start selection from original click position if not already selecting
            if !cw.selection.active
                cw.selection.active = true
                cw.selection.anchor_row = cw.editor.cursor_row
                cw.selection.anchor_col = cw.editor.cursor_col
            end
            cw.editor.cursor_row = row
            cw.editor.cursor_col = col
        end
        return
    end

    # Mouse release: stop drag tracking, auto-copy selection to clipboard
    if evt.action == Tachikoma.mouse_release
        if app.drag_active && app.drag_cell_idx >= 1
            idx = app.drag_cell_idx
            if idx <= length(nv.cell_widgets)
                _auto_copy_selection!(nv.cell_widgets[idx])
            end
        end
        app.drag_active = false
        app.slider_drag = false
        return
    end

    # DataTable mode: forward scroll and click events to the DataTable
    if app.mode == :datatable && in_notebook
        dt = _focused_datatable(app)
        if dt !== nothing
            if evt.button in (Tachikoma.mouse_scroll_up, Tachikoma.mouse_scroll_down) ||
               (evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press)
                Tachikoma.handle_mouse!(dt, evt)
                return
            end
        end
    end

    if in_notebook && evt.button == Tachikoma.mouse_scroll_down
        vi = Theme.CELL_V_INSET
        inner_h = max(1, nb_vp.height - 2 * vi - 2)  # subtract inset + border
        max_scroll = max(0, content_height(nv) - inner_h)
        nv.scroll_offset = min(nv.scroll_offset + 2, max_scroll)
        nv.user_scrolling = true
        nv.last_scroll_time = time()
        return
    end

    if in_notebook && evt.button == Tachikoma.mouse_scroll_up
        nv.scroll_offset = max(nv.scroll_offset - 2, 0)
        nv.user_scrolling = true
        nv.last_scroll_time = time()
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

            # Detect bond widget hover (slider, checkbox, button, select)
            bond_idx, _ = _slider_cell_at_y(nv, evt.y)
            if bond_idx == 0
                # Check all bond types, not just slider
                bond_idx = _bond_cell_at_y(nv, evt.y)
            end
            nv.hovered_bond_idx = bond_idx
        else
            nv.hovered_idx = 0
            nv.hovered_control = :none
            nv.hovered_control_idx = 0
            nv.hovered_bond_idx = 0
        end
        return
    end

    # Click outside all panels (background) → enter panel mode
    if evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press && !in_notebook
        _enter_panel_mode!(app)
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

"""Compute the code area rect for a cell (where the CodeEditor renders).
Used for mapping mouse clicks to editor coordinates."""
function _cell_code_area(nv::NotebookView, idx::Int, cell_x::Int, cw_width::Int)
    vp = nv.viewport
    hi = Theme.CELL_H_INSET
    vi = Theme.CELL_V_INSET
    hp = Theme.CELL_H_PAD

    cell_y = vp.y + vi + 1 + Theme.TOP_MARGIN - nv.scroll_offset
    for j in 1:idx-1
        j_oh = output_height(nv.output_widgets[j])
        cell_y += cell_height(nv.cell_widgets[j]; has_output=j_oh > 0)
        cell_y += j_oh
        cell_y += Theme.CELL_GAP
    end

    cw = nv.cell_widgets[idx]
    oh = output_height(nv.output_widgets[idx])
    ch = cell_height(cw; has_output=oh > 0)

    border_w = cw_width - 2 * hi
    border_h = ch - 2 * vi
    border_x = cell_x + hi
    border_y = cell_y + vi

    inner_w = max(1, border_w - 2 - 2 * hp)
    inner_h = max(1, border_h - 2)
    inner_x = border_x + 1 + hp
    inner_y = border_y + 1

    return Tachikoma.Rect(inner_x, inner_y, inner_w, inner_h)
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

"""Map an x-coordinate to a slider value. Returns (new_value, hit) or (nothing, false)."""
function _slider_x_to_value(bond::Bond, click_x::Int, cell_left::Int, cw_width::Int)
    bond.element isa Slider || return (nothing, false)
    slider = bond.element::Slider
    name = bond.defines
    total = length(slider.values)

    # Compute slider track position (must match _render_slider_widget layout)
    label = "$(name) "
    label_width = length(label)
    val_str = slider.show_value ? " $(_bond_current_value(bond))" : ""
    val_width = length(val_str)
    avail = cw_width - 4 - label_width - val_width
    track_width = clamp(avail, 5, 50)

    track_start_x = cell_left + 2 + label_width + 1  # left pad + label + ◄
    track_end_x = track_start_x + track_width - 1

    # Clamp x into track range (allows dragging past edges)
    clamped_x = clamp(click_x, track_start_x, track_end_x)
    frac = (clamped_x - track_start_x) / max(track_width - 1, 1)
    new_idx = clamp(round(Int, frac * (total - 1)) + 1, 1, total)
    (slider.values[new_idx], true)
end

"""Find which cell index has a slider bond at the given screen y. Returns (cell_index, Bond) or (0, nothing)."""
function _slider_cell_at_y(nv::NotebookView, screen_y::Int)
    isempty(nv.cell_widgets) && return (0, nothing)
    vp = nv.viewport
    vi = Theme.CELL_V_INSET
    content_y = screen_y - (vp.y + vi + 1) + nv.scroll_offset - Theme.TOP_MARGIN

    y = 0
    for i in eachindex(nv.cell_widgets)
        ow = nv.output_widgets[i]
        oh = output_height(ow)
        ch = cell_height(nv.cell_widgets[i]; has_output=oh > 0)
        y += ch
        if oh > 0 && content_y >= y && content_y < y + oh
            cell = nv.cell_widgets[i].cell
            cell.output.output_type == :bond || return (0, nothing)
            bond = cell.output.result
            bond isa Bond || return (0, nothing)
            bond.element isa Slider || return (0, nothing)
            return (i, bond)
        end
        y += oh
        y += Theme.CELL_GAP
    end
    (0, nothing)
end

"""Find which cell index has any bond at the given screen y. Returns cell_index or 0."""
function _bond_cell_at_y(nv::NotebookView, screen_y::Int)::Int
    isempty(nv.cell_widgets) && return 0
    vp = nv.viewport
    vi = Theme.CELL_V_INSET
    content_y = screen_y - (vp.y + vi + 1) + nv.scroll_offset - Theme.TOP_MARGIN

    y = 0
    for i in eachindex(nv.cell_widgets)
        ow = nv.output_widgets[i]
        oh = output_height(ow)
        ch = cell_height(nv.cell_widgets[i]; has_output=oh > 0)
        y += ch
        if oh > 0 && content_y >= y && content_y < y + oh
            cell = nv.cell_widgets[i].cell
            cell.output.output_type == :bond || return 0
            cell.output.result isa Bond || return 0
            return i
        end
        y += oh
        y += Theme.CELL_GAP
    end
    0
end

"""Find which cell index has a DataTable output at the given screen y. Returns cell_index or 0."""
function _datatable_cell_at_y(nv::NotebookView, screen_y::Int)::Int
    isempty(nv.cell_widgets) && return 0
    vp = nv.viewport
    vi = Theme.CELL_V_INSET
    content_y = screen_y - (vp.y + vi + 1) + nv.scroll_offset - Theme.TOP_MARGIN

    y = 0
    for i in eachindex(nv.cell_widgets)
        ow = nv.output_widgets[i]
        oh = output_height(ow)
        ch = cell_height(nv.cell_widgets[i]; has_output=oh > 0)
        y += ch
        if oh > 0 && content_y >= y && content_y < y + oh
            cell = nv.cell_widgets[i].cell
            cell.output.output_type == :dataframe || return 0
            return i
        end
        y += oh
        y += Theme.CELL_GAP
    end
    0
end

"""Apply a slider value: update registry, workspace variable, re-execute dependents."""
function _apply_slider_value!(app::SessionsApp, cell::Cell, bond::Bond, new_val)
    name = bond.defines
    old_val = _bond_current_value(bond)
    new_val == old_val && return  # no change

    set_bond_value!(name, new_val)
    try
        Core.eval(app.workspace.mod, :($(name) = $(new_val)))
    catch; end
    _rerun_bond_dependents!(app, name, cell)
end

"""Try to handle a mouse click on a slider widget. Returns true if handled."""
function _try_slider_click(app::SessionsApp, nv::NotebookView, click_x::Int, click_y::Int,
                           cell_left::Int, cw_width::Int)
    idx, bond = _slider_cell_at_y(nv, click_y)
    idx == 0 && return false

    new_val, hit = _slider_x_to_value(bond, click_x, cell_left, cw_width)
    !hit && return false

    cell = nv.cell_widgets[idx].cell
    # Focus without auto-scrolling — user already sees the slider output
    nv.focused_idx = idx
    update_focus!(nv)
    _exit_insert_mode!(app)
    _apply_slider_value!(app, cell, bond, new_val)

    # Start slider drag tracking
    app.slider_drag = true
    app.slider_drag_idx = idx
    return true
end

"""Try to adjust a bond slider on the focused cell. Returns true if handled."""
function _try_adjust_bond!(app::SessionsApp, delta::Int)
    cw = focused_widget(app.notebook_view)
    cw === nothing && return false

    cell = cw.cell
    cell.output.output_type == :bond || return false
    bond = cell.output.result
    bond isa Bond || return false
    bond.element isa Slider || return false

    slider = bond.element::Slider
    name = bond.defines
    haskey(_BOND_REGISTRY, name) || return false

    _, current_val, _ = _BOND_REGISTRY[name]
    idx = _slider_index(slider, current_val)
    new_idx = clamp(idx + delta, 1, length(slider.values))
    new_idx == idx && return true  # at boundary, still handled

    new_val = slider.values[new_idx]
    set_bond_value!(name, new_val)

    # Assign new value to workspace variable
    try
        Core.eval(app.workspace.mod, :($(name) = $(new_val)))
    catch; end

    # Find and re-execute dependent cells (not the bond cell itself)
    _rerun_bond_dependents!(app, name, cell)
    return true
end

"""Re-execute cells that depend on a bond variable."""
function _rerun_bond_dependents!(app::SessionsApp, name::Symbol, bond_cell::Cell)
    # Find cells that reference this variable (downstream dependents)
    deps = downstream_dependents(app.nb, [bond_cell])
    isempty(deps) && return

    # Mark as queued
    for cell in deps
        cell.disabled && continue
        cell.state = cell_queued
    end

    # Execute in background
    Tachikoma.spawn_task!(app.tq, :bond_update) do
        order = execution_order(app.nb, deps)
        for cell in order.runnable
            cell.disabled && continue
            execute_cell!(app.workspace, cell)
        end
    end
end

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
        # Sync to LSP after execution for updated diagnostics
        _lsp_sync_and_refresh!(app)
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
    try
        execute_changed!(app.nb, sc; workspace=app.workspace)
        save_session!(app.nb)
    catch e
        app.message = "Execution error: $(sprint(showerror, e))"
    end
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

"""Launch the TUI app for a .jl file — auto-detects notebook vs plain file."""
function open(path::String)
    if is_notebook_file(path)
        nb = load_notebook_with_session(path)
        open(nb)
    else
        edit(path)
    end
end

"""Launch the TUI app for a notebook."""
function open(nb::Notebook)
    a = SessionsApp(nb)
    Tachikoma.app(a; fps=30, default_bindings=false)
end

"""Launch the TUI file editor for a plain .jl file."""
function edit(path::String)
    fev = FileEditorView(path)
    a = SessionsApp(fev)
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

"""Open completion popup with items. No-op if items are empty."""
function _open_completion!(app::SessionsApp, items::Vector{LspCompletionItem})
    isempty(items) && return
    app.completion_popup = CompletionPopup(items, 0, 0, 1)
    app.mode = :completion
end

"""Close completion popup, restoring insert mode."""
function _close_completion!(app::SessionsApp)
    app.completion_popup = nothing
    app.mode = :insert
end

"""Accept a completion item — replace the prefix before cursor with the completion label."""
function _accept_completion!(app::SessionsApp, item::LspCompletionItem)
    editor = if app.editor_type == :file && app.file_editor_view !== nothing
        app.file_editor_view.editor
    else
        cw = focused_widget(app.notebook_view)
        cw === nothing && return
        cw.editor
    end
    prefix = _completion_prefix(editor.lines, editor.cursor_row, editor.cursor_col)
    label = item.label
    # Delete prefix characters backward
    prefix_len = length(prefix)
    if prefix_len > 0
        line = editor.lines[editor.cursor_row]
        start_col = editor.cursor_col - prefix_len
        deleteat!(line, start_col+1:editor.cursor_col)
        editor.cursor_col = start_col
        Tachikoma._mark_dirty!(editor, editor.cursor_row)
    end
    # Insert the completion label
    _insert_text!(editor, label)
    # Sync cell if in notebook mode
    if app.editor_type == :notebook
        cw = focused_widget(app.notebook_view)
        cw !== nothing && sync_to_cell!(cw)
    elseif app.file_editor_view !== nothing
        app.file_editor_view.dirty = true
    end
end

"""Trigger completion request — queries LSP or uses cached completions."""
function _trigger_completion!(app::SessionsApp)
    editor = if app.editor_type == :file && app.file_editor_view !== nothing
        app.file_editor_view.editor
    else
        cw = focused_widget(app.notebook_view)
        cw === nothing && return
        cw.editor
    end
    uri = if app.editor_type == :file && app.file_editor_view !== nothing
        "file://" * abspath(app.file_editor_view.path)
    else
        notebook_uri(app.nb)
    end
    # Try LSP completion (with timeout)
    items = lsp_complete_with_timeout!(app.lsp, uri, editor.cursor_row, editor.cursor_col; timeout=1.0)
    if isempty(items)
        app.message = "No completions"
        return
    end
    _open_completion!(app, items)
end

"""Request hover info at the given screen position. Converts screen coords to editor coords."""
function _request_hover!(app::SessionsApp, screen_x::Int, screen_y::Int)
    # Determine URI and editor for hover
    uri = if app.editor_type == :file && app.file_editor_view !== nothing
        "file://" * abspath(app.file_editor_view.path)
    else
        notebook_uri(app.nb)
    end
    # For now, use a simple approach: request hover at the mouse position
    # The screen coords need to be converted to editor line/col, which requires
    # knowing the editor viewport rect. For simplicity, we attempt hover at
    # the cursor position or approximate from screen coords.
    # TODO: In a full implementation, map screen coords → editor line/col
    editor = if app.editor_type == :file && app.file_editor_view !== nothing
        app.file_editor_view.editor
    else
        cw = focused_widget(app.notebook_view)
        cw === nothing && return
        cw.editor
    end
    # Use the cursor position for hover (mouse position mapping is complex)
    result = lsp_hover_with_timeout!(app.lsp, uri, editor.cursor_row, editor.cursor_col; timeout=0.5)
    result === nothing && return
    app.hover_tooltip = HoverTooltip(result.contents, screen_x, screen_y)
end

"""Show hover tooltip at a given position with given text. Used by tests."""
function _show_hover!(app::SessionsApp, text::String, x::Int, y::Int)
    app.hover_tooltip = HoverTooltip(text, x, y)
end

"""Dismiss hover tooltip."""
function _dismiss_hover!(app::SessionsApp)
    app.hover_tooltip = nothing
end

"""Get the DataTable from the focused cell's output widget (if it has one)."""
function _focused_datatable(app::SessionsApp)
    nv = app.notebook_view
    idx = nv.focused_idx
    (idx < 1 || idx > length(nv.output_widgets)) && return nothing
    ow = nv.output_widgets[idx]
    ow._cached_datatable
end

"""Get the DataTable from a specific cell index's output widget."""
function _datatable_at_idx(app::SessionsApp, idx::Int)
    nv = app.notebook_view
    (idx < 1 || idx > length(nv.output_widgets)) && return nothing
    ow = nv.output_widgets[idx]
    ow._cached_datatable
end

"""Go to definition at the current cursor position. Opens new tab for cross-file."""
function _goto_definition!(app::SessionsApp)
    editor = if app.editor_type == :file && app.file_editor_view !== nothing
        app.file_editor_view.editor
    else
        cw = focused_widget(app.notebook_view)
        cw === nothing && return
        cw.editor
    end
    uri = if app.editor_type == :file && app.file_editor_view !== nothing
        "file://" * abspath(app.file_editor_view.path)
    else
        notebook_uri(app.nb)
    end
    loc = lsp_definition_with_timeout!(app.lsp, uri, editor.cursor_row, editor.cursor_col; timeout=2.0)
    if loc === nothing
        app.message = "No definition found"
        return
    end
    # Extract file path from URI
    target_path = _uri_to_path(loc.uri)
    current_path = if app.editor_type == :file && app.file_editor_view !== nothing
        abspath(app.file_editor_view.path)
    else
        abspath(app.nb.path)
    end
    if target_path == current_path
        # Same file — scroll to target line
        editor.cursor_row = loc.line
        editor.cursor_col = loc.col
        if editor.cursor_row <= editor.scroll_offset
            editor.scroll_offset = max(0, editor.cursor_row - 3)
        end
        app.message = "Jumped to line $(loc.line)"
    else
        # Cross-file — open in new tab, then jump to line
        if isfile(target_path)
            _open_in_tab!(app, target_path)
            # After opening, set cursor to target position
            ed = if app.editor_type == :file && app.file_editor_view !== nothing
                app.file_editor_view.editor
            else
                cw2 = focused_widget(app.notebook_view)
                cw2 !== nothing ? cw2.editor : nothing
            end
            if ed !== nothing
                ed.cursor_row = min(loc.line, length(ed.lines))
                ed.cursor_col = loc.col
            end
            app.message = "Opened $(basename(target_path)):$(loc.line)"
        else
            app.message = "File not found: $(target_path)"
        end
    end
end

"""Convert a file:// URI to an absolute path."""
function _uri_to_path(uri::String)
    if startswith(uri, "file://")
        return uri[8:end]
    end
    uri
end

"""Trigger signature help request at the current cursor position."""
function _trigger_signature_help!(app::SessionsApp)
    editor = if app.editor_type == :file && app.file_editor_view !== nothing
        app.file_editor_view.editor
    else
        cw = focused_widget(app.notebook_view)
        cw === nothing && return
        cw.editor
    end
    uri = if app.editor_type == :file && app.file_editor_view !== nothing
        "file://" * abspath(app.file_editor_view.path)
    else
        notebook_uri(app.nb)
    end
    result = lsp_signature_help_with_timeout!(app.lsp, uri, editor.cursor_row, editor.cursor_col; timeout=1.0)
    result === nothing && return
    app.signature_tooltip = SignatureHelpTooltip(result.label, result.parameters, result.active_param, 0, 0)
end

"""Dismiss the signature help tooltip."""
function _dismiss_signature_help!(app::SessionsApp)
    app.signature_tooltip = nothing
end

"""Advance the active parameter index in the signature help tooltip."""
function _advance_signature_param!(app::SessionsApp)
    st = app.signature_tooltip
    st === nothing && return
    if st.active_param < length(st.parameters) - 1
        st.active_param += 1
    end
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

"""Open a centered confirm dialog for deleting selected cells."""
function _open_confirm_delete_selection!(app::SessionsApp, n_sel::Int)
    msg = n_sel == 1 ? "Delete 1 selected cell?" : "Delete $n_sel selected cells?"
    app.confirm_dialog = ConfirmDialog(
        "Delete Cells",
        msg,
        () -> begin
            delete_selected_cells!(app)
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
    # Flush any pending LSP sync immediately on mode exit
    if app.lsp_sync_needed > 0.0
        app.lsp_sync_needed = 0.0
        _lsp_sync_and_refresh!(app)
    end
end

"""Enter panel mode — no cell focused, Ctrl+C quits, click canvas to stay here."""
function _enter_panel_mode!(app::SessionsApp)
    app.mode = :panel
    for cw in app.notebook_view.cell_widgets
        cw.editor.focused = false
        cw.focused = false
    end
    app.message = "Panel mode — Ctrl+C to quit, arrow keys to navigate"
end

"""Exit panel mode — return to normal mode, restore cell focus."""
function _exit_panel_mode!(app::SessionsApp)
    app.mode = :normal
    app.message = ""
    update_focus!(app.notebook_view)
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

# --- Completion popup rendering ---

function _render_completion_popup!(popup::CompletionPopup, buf::Tachikoma.Buffer, area::Tachikoma.Rect)
    isempty(popup.items) && return
    n_visible = _popup_visible_count(popup)
    # Compute scroll offset for long lists
    scroll = 0
    if popup.selected_idx > n_visible
        scroll = popup.selected_idx - n_visible
    end

    # Calculate popup width: icon(2) + label + detail padding
    max_label_w = maximum(length(item.label) for item in popup.items)
    max_detail_w = maximum(length(item.detail) for item in popup.items)
    content_w = 3 + max_label_w + (max_detail_w > 0 ? min(max_detail_w, 20) + 1 : 0)
    w = min(max(content_w + 2, 20), area.width - 2)  # +2 for borders
    h = n_visible + 2  # +2 for borders

    # Clamp position
    x = min(popup.x, area.x + area.width - w)
    x = max(x, area.x)
    y = min(popup.y, area.y + area.height - h)
    y = max(y, area.y)

    box = Theme.BOX
    bg = Theme.DROPDOWN_BG
    border_style = Tachikoma.Style(; fg=Theme.DROPDOWN_BORDER_FG, bg)

    # Top border
    top = string(box.tl) * repeat(string(box.h), w - 2) * string(box.tr)
    Tachikoma.set_string!(buf, x, y, top, border_style)

    # Items
    for vi in 1:n_visible
        idx = scroll + vi
        idx > length(popup.items) && break
        item = popup.items[idx]
        iy = y + vi
        is_selected = (idx == popup.selected_idx)
        item_bg = is_selected ? Theme.SELECTION_BG : bg
        item_fg = is_selected ? Theme.FG : Theme.DROPDOWN_ITEM_FG
        icon_fg = is_selected ? Theme.ACCENT : Theme.FG_MUTED

        Tachikoma.set_char!(buf, x, iy, box.v, border_style)
        icon = _completion_kind_icon(item.kind)
        label = item.label
        inner_w = w - 2
        # Render icon part: " icon"
        Tachikoma.set_string!(buf, x + 1, iy, " ", Tachikoma.Style(; fg=icon_fg, bg=item_bg))
        Tachikoma.set_string!(buf, x + 2, iy, icon, Tachikoma.Style(; fg=icon_fg, bg=item_bg))
        # Render label part: " label" + padding
        label_area = inner_w - 3  # subtract space + icon + space
        display_label = " " * label
        if length(display_label) > label_area
            display_label = first(display_label, label_area)
        else
            display_label = display_label * " " ^ (label_area - length(display_label))
        end
        Tachikoma.set_string!(buf, x + 3, iy, display_label, Tachikoma.Style(; fg=item_fg, bg=item_bg))
        Tachikoma.set_char!(buf, x + w - 1, iy, box.v, border_style)
    end

    # Bottom border
    bot = string(box.bl) * repeat(string(box.h), w - 2) * string(box.br)
    Tachikoma.set_string!(buf, x, y + n_visible + 1, bot, border_style)
end

# --- Hover tooltip rendering ---

function _render_hover_tooltip!(tooltip::HoverTooltip, buf::Tachikoma.Buffer, area::Tachikoma.Rect)
    text = tooltip.text
    isempty(text) && return

    # Split text into lines and clamp width
    raw_lines = split(text, '\n')
    max_line_w = maximum(length(l) for l in raw_lines)
    max_w = min(max_line_w + 2, area.width - 4)  # +2 for padding, cap at screen
    n_lines = min(length(raw_lines), div(area.height, 2))  # don't take more than half screen

    w = max(max_w + 2, 10)  # +2 for borders
    h = n_lines + 2  # +2 for borders

    # Position: try below mouse, fall back to above
    x = min(tooltip.x, area.x + area.width - w)
    x = max(x, area.x)
    y = tooltip.y + 1  # below mouse
    if y + h > area.y + area.height
        y = tooltip.y - h  # above mouse
    end
    y = max(y, area.y)

    box = Theme.BOX
    bg = Theme.ELEVATED_BG
    border_style = Tachikoma.Style(; fg=Theme.BORDER_BRIGHT, bg)
    text_style = Tachikoma.Style(; fg=Theme.FG, bg)

    # Top border
    top = string(box.tl) * repeat(string(box.h), w - 2) * string(box.tr)
    Tachikoma.set_string!(buf, x, y, top, border_style)

    # Content lines
    for i in 1:n_lines
        iy = y + i
        Tachikoma.set_char!(buf, x, iy, box.v, border_style)
        line_text = i <= length(raw_lines) ? string(raw_lines[i]) : ""
        inner_w = w - 2
        display = " " * line_text
        if length(display) > inner_w
            display = first(display, inner_w)
        else
            display = display * " " ^ (inner_w - length(display))
        end
        Tachikoma.set_string!(buf, x + 1, iy, display, text_style)
        Tachikoma.set_char!(buf, x + w - 1, iy, box.v, border_style)
    end

    # Bottom border
    bot = string(box.bl) * repeat(string(box.h), w - 2) * string(box.br)
    Tachikoma.set_string!(buf, x, y + n_lines + 1, bot, border_style)
end

# --- Scrollbar rendering ---

"""Compute scrollbar thumb position and size. Returns NamedTuple or nothing."""
function _scrollbar_metrics(total_content::Int, viewport::Int, scroll_offset::Int, track_height::Int)
    total_content <= viewport && return nothing
    thumb_size = max(1, round(Int, viewport / total_content * track_height))
    max_scroll = total_content - viewport
    thumb_start = round(Int, scroll_offset / max(1, max_scroll) * (track_height - thumb_size))
    (thumb_start=thumb_start, thumb_size=thumb_size)
end

"""Render a 1-char wide scrollbar on the right edge."""
function _render_scrollbar!(buf::Tachikoma.Buffer, x::Int, y_start::Int, track_height::Int,
                             total_content::Int, viewport::Int, scroll_offset::Int)
    metrics = _scrollbar_metrics(total_content, viewport, scroll_offset, track_height)
    metrics === nothing && return
    track_style = Tachikoma.Style(; fg=Theme.FG_FAINT, bg=Theme.CANVAS_BG)
    thumb_style = Tachikoma.Style(; fg=Theme.FG_MUTED, bg=Theme.ELEVATED_BG)
    for i in 0:track_height-1
        y = y_start + i
        in_thumb = i >= metrics.thumb_start && i < metrics.thumb_start + metrics.thumb_size
        Tachikoma.set_char!(buf, x, y, in_thumb ? '█' : '│', in_thumb ? thumb_style : track_style)
    end
end

# --- Signature help tooltip rendering ---

function _render_signature_help!(tooltip::SignatureHelpTooltip, buf::Tachikoma.Buffer, area::Tachikoma.Rect)
    label = tooltip.label
    isempty(label) && return

    content_w = length(label) + 2  # +2 for padding
    w = min(max(content_w + 2, 12), area.width - 4)  # +2 for borders
    h = 3  # border + content + border

    # Position: centered horizontally, near top of area
    x = area.x + max(0, div(area.width - w, 2))
    y = area.y + 2
    y = max(y, area.y)

    box = Theme.BOX
    bg = Theme.ELEVATED_BG
    border_style = Tachikoma.Style(; fg=Theme.BORDER_BRIGHT, bg)
    text_style = Tachikoma.Style(; fg=Theme.FG, bg)
    active_style = Tachikoma.Style(; fg=Theme.ACCENT, bg, bold=true)

    # Top border
    top = string(box.tl) * repeat(string(box.h), w - 2) * string(box.tr)
    Tachikoma.set_string!(buf, x, y, top, border_style)

    # Content line
    iy = y + 1
    Tachikoma.set_char!(buf, x, iy, box.v, border_style)
    inner_w = w - 2
    display = " " * label
    if length(display) > inner_w
        display = first(display, inner_w)
    else
        display = display * " " ^ (inner_w - length(display))
    end
    # Render full label with normal style
    Tachikoma.set_string!(buf, x + 1, iy, display, text_style)
    # Overlay active parameter with accent style
    active_label = if tooltip.active_param >= 0 && tooltip.active_param < length(tooltip.parameters)
        tooltip.parameters[tooltip.active_param + 1]
    else
        ""
    end
    if !isempty(active_label)
        idx = findfirst(active_label, label)
        if idx !== nothing
            offset = first(idx)  # position in label (1-based)
            Tachikoma.set_string!(buf, x + 1 + offset, iy, active_label, active_style)
        end
    end
    Tachikoma.set_char!(buf, x + w - 1, iy, box.v, border_style)

    # Bottom border
    bot = string(box.bl) * repeat(string(box.h), w - 2) * string(box.br)
    Tachikoma.set_string!(buf, x, y + 2, bot, border_style)
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

# ── File Editor Mode ─────────────────────────────────────────────────

"""Delete the selected text in file editor and position cursor at selection start."""
function _fev_delete_selection!(fev::FileEditorView)
    sel = fev.selection
    !sel.active && return
    editor = fev.editor
    Tachikoma._push_undo!(editor; force=true)
    sr, sc, er, ec = _selection_range(sel, editor.cursor_row, editor.cursor_col)
    if sr == er
        line = editor.lines[sr]
        to_del = min(ec, length(line))
        from_del = sc + 1
        if from_del <= to_del
            deleteat!(line, from_del:to_del)
        end
    else
        first_part = editor.lines[sr][1:sc]
        last_line = editor.lines[er]
        last_part = ec < length(last_line) ? last_line[ec+1:end] : Char[]
        editor.lines[sr] = vcat(first_part, last_part)
        if er > sr
            deleteat!(editor.lines, sr+1:er)
        end
    end
    editor.cursor_row = sr
    editor.cursor_col = sc
    sel.active = false
    editor.token_cache = [Tachikoma.tokenize_line(l) for l in editor.lines]
    empty!(editor.dirty_lines)
end

function _format_file_editor!(fev::FileEditorView)::Bool
    original = Tachikoma.text(fev.editor)
    formatted = format_code(original)
    formatted == original && return false
    old_row = fev.editor.cursor_row
    old_col = fev.editor.cursor_col
    Tachikoma.set_text!(fev.editor, formatted)
    new_nlines = length(fev.editor.lines)
    fev.editor.cursor_row = clamp(old_row, 1, max(1, new_nlines))
    fev.editor.cursor_col = clamp(old_col, 0, length(fev.editor.lines[fev.editor.cursor_row]))
    true
end

function _handle_file_editor_key!(app::SessionsApp, evt::Tachikoma.KeyEvent)
    fev = app.file_editor_view

    # Ctrl+Q / Ctrl+C: quit (force quit if dirty warning already shown)
    # When selection is active, Ctrl+C copies instead of quitting
    if evt.key == :ctrl && (evt.char == 'q' || (evt.char == 'c' && !fev.selection.active))
        if fev.dirty && !startswith(app.message, "Unsaved")
            app.message = "Unsaved changes! Ctrl+Q again or Ctrl+S to save"
        else
            app.quit = true
        end
        return
    end

    # Ctrl+S: format + save file
    if evt.key == :ctrl && evt.char == 's'
        did_format = _format_file_editor!(fev)
        save_file!(fev)
        # Notify LSP of save (triggers deep analysis)
        if app.lsp.status == lsp_ready
            lsp_did_save!(app.lsp, "file://" * abspath(fev.path), Tachikoma.text(fev.editor))
        end
        if did_format
            app.message = "Formatted + Saved: $(fev.path)"
        else
            app.message = "Saved: $(fev.path)"
        end
        return
    end

    # Ctrl+B: toggle sidebar
    if evt.key == :ctrl && evt.char == 'b'
        app.sidebar_open = !app.sidebar_open
        return
    end

    # Ctrl+Space: trigger completion popup
    if evt.key == :ctrl_space
        _trigger_completion!(app)
        return
    end

    # Ctrl+G: go to definition
    if evt.key == :ctrl && evt.char == 'g'
        _goto_definition!(app)
        return
    end

    # F2: rename symbol
    if evt.key == :f2
        _start_rename!(app)
        return
    end

    editor = fev.editor
    sel = fev.selection

    # ── Ctrl+A: move to line start (REPL ^A) ──
    if evt.key == :ctrl && evt.char == 'a'
        sel.active = false
        editor.cursor_col = 0
        return
    end

    # ── Ctrl+E: move to line end (REPL ^E) ──
    if evt.key == :ctrl && evt.char == 'e'
        sel.active = false
        editor.cursor_col = length(editor.lines[editor.cursor_row])
        return
    end

    # ── Ctrl+K: kill line forward (REPL ^K) ──
    if evt.key == :ctrl && evt.char == 'k'
        Tachikoma._push_undo!(editor; force=true)
        line = editor.lines[editor.cursor_row]
        if editor.cursor_col < length(line)
            killed = String(line[editor.cursor_col+1:end])
            deleteat!(line, editor.cursor_col+1:length(line))
            _clipboard_copy!(killed)
            Tachikoma._mark_dirty!(editor, editor.cursor_row)
        elseif editor.cursor_row < length(editor.lines)
            append!(editor.lines[editor.cursor_row], editor.lines[editor.cursor_row + 1])
            deleteat!(editor.lines, editor.cursor_row + 1)
            Tachikoma._mark_dirty!(editor, editor.cursor_row)
        end
        Tachikoma._ensure_tokens!(editor)
        fev.dirty = true
        return
    end

    # ── Ctrl+U: kill line backward (REPL ^U) ──
    if evt.key == :ctrl && evt.char == 'u'
        Tachikoma._push_undo!(editor; force=true)
        line = editor.lines[editor.cursor_row]
        if editor.cursor_col > 0
            killed = String(line[1:editor.cursor_col])
            deleteat!(line, 1:editor.cursor_col)
            editor.cursor_col = 0
            _clipboard_copy!(killed)
            Tachikoma._mark_dirty!(editor, editor.cursor_row)
        end
        Tachikoma._ensure_tokens!(editor)
        fev.dirty = true
        return
    end

    # ── Ctrl+W: delete word backward (REPL ^W) ──
    if evt.key == :ctrl && evt.char == 'w'
        Tachikoma._push_undo!(editor; force=true)
        start_row = editor.cursor_row
        start_col = editor.cursor_col
        _word_left!(editor)
        sel.active = true
        sel.anchor_row = start_row
        sel.anchor_col = start_col
        _fev_delete_selection!(fev)
        fev.dirty = true
        return
    end

    # ── Ctrl+Y: yank/paste (REPL ^Y) ──
    if evt.key == :ctrl && evt.char == 'y'
        clip = _clipboard_paste()
        isempty(clip) && return
        if sel.active
            _fev_delete_selection!(fev)
        end
        _insert_text!(editor, clip)
        fev.dirty = true
        return
    end

    # ── Ctrl+C / Cmd+C: copy selection ──
    if evt.key == :ctrl && evt.char == 'c' && sel.active
        text = _selected_text(editor.lines, sel, editor.cursor_row, editor.cursor_col)
        _clipboard_copy!(text)
        return
    end

    # ── Ctrl+X / Cmd+X: cut selection ──
    if evt.key == :ctrl && evt.char == 'x' && sel.active
        text = _selected_text(editor.lines, sel, editor.cursor_row, editor.cursor_col)
        _clipboard_copy!(text)
        _fev_delete_selection!(fev)
        fev.dirty = true
        return
    end

    # ── Ctrl+V / Cmd+V: paste ──
    if evt.key == :ctrl && evt.char == 'v'
        clip = _clipboard_paste()
        isempty(clip) && return
        if sel.active
            _fev_delete_selection!(fev)
        end
        _insert_text!(editor, clip)
        fev.dirty = true
        return
    end

    # ── Shift+Arrow: extend selection ──
    if evt.key in (:shift_left, :shift_right, :shift_up, :shift_down, :shift_home, :shift_end)
        if !sel.active
            sel.active = true
            sel.anchor_row = editor.cursor_row
            sel.anchor_col = editor.cursor_col
        end
        _move_cursor_for_shift!(editor, evt.key)
        return
    end

    # ── Alt+Arrow: word jump ──
    if evt.key == :alt_left || (evt.key == :alt && evt.char == 'b')
        sel.active = false
        _word_left!(editor)
        return
    end
    if evt.key == :alt_right || (evt.key == :alt && evt.char == 'f')
        sel.active = false
        _word_right!(editor)
        return
    end

    # Clear selection on any non-selection key
    if sel.active && !(evt.key in (:shift_left, :shift_right, :shift_up, :shift_down,
                                    :shift_home, :shift_end, :ctrl_shift_left, :ctrl_shift_right))
        sel.active = false
    end

    # Track dirty state — any key that modifies the buffer marks dirty
    old_lines = length(fev.editor.lines)
    old_text_hash = hash(Tachikoma.text(fev.editor))

    # Auto-close brackets (before passing to editor)
    if _handle_auto_close!(fev.editor, evt)
        # Skip Tachikoma.handle_key! — auto-close handled the event
        @goto fev_post_edit
    end

    # Delegate all other keys to the CodeEditor (vim keybindings, undo, search, etc.)
    Tachikoma.handle_key!(fev.editor, evt)

    @label fev_post_edit

    # Sync mode: CodeEditor's mode ↔ app.mode
    ce_mode = fev.editor.mode
    if ce_mode == :insert
        app.mode = :insert
    elseif ce_mode == :normal
        app.mode = :normal
    elseif ce_mode == :search
        app.mode = :insert  # search is still "active editing"
    end

    # Check if text changed
    new_text_hash = hash(Tachikoma.text(fev.editor))
    if new_text_hash != old_text_hash
        fev.dirty = true
        # Debounced LSP sync for file editor
        if app.lsp.status == lsp_ready
            fev.lsp_doc_version += 1
            lsp_did_change!(app.lsp, "file://" * abspath(fev.path),
                Tachikoma.text(fev.editor), fev.lsp_doc_version)
        end
    end

    # Signature help triggers
    if evt.key == :char
        if evt.char == '('
            _trigger_signature_help!(app)
        elseif evt.char == ')'
            app.signature_tooltip = nothing
        elseif evt.char == ',' && app.signature_tooltip !== nothing
            _advance_signature_param!(app)
        end
    end
end

# --- Rename support ---

"""Get the current editor (file or focused cell)."""
function _current_editor(app::SessionsApp)
    if app.editor_type == :file && app.file_editor_view !== nothing
        return app.file_editor_view.editor
    else
        cw = focused_widget(app.notebook_view)
        cw === nothing && return nothing
        return cw.editor
    end
end

"""Get the current file URI."""
function _current_uri(app::SessionsApp)
    if app.editor_type == :file && app.file_editor_view !== nothing
        "file://" * abspath(app.file_editor_view.path)
    else
        notebook_uri(app.nb)
    end
end

"""Extract the word (identifier) at cursor position. Returns empty string if none."""
function _word_at_cursor(lines::Vector{Vector{Char}}, row::Int, col::Int)::String
    (row < 1 || row > length(lines)) && return ""
    line = lines[row]
    isempty(line) && return ""
    # col is 0-based cursor position
    # Find start and end of word containing position
    pos = clamp(col, 0, length(line) - 1) + 1  # 1-based index into line
    _is_ident(c) = isletter(c) || isdigit(c) || c == '_' || c == '!'
    (pos > length(line) || !_is_ident(line[pos])) && pos > 1 && _is_ident(line[pos-1]) && (pos -= 1)
    (!_is_ident(line[pos])) && return ""
    lo = pos
    while lo > 1 && _is_ident(line[lo-1])
        lo -= 1
    end
    hi = pos
    while hi < length(line) && _is_ident(line[hi+1])
        hi += 1
    end
    String(line[lo:hi])
end

"""Start the rename prompt for the word under cursor."""
function _start_rename!(app::SessionsApp)
    editor = _current_editor(app)
    editor === nothing && return
    word = _word_at_cursor(editor.lines, editor.cursor_row, editor.cursor_col)
    if isempty(word)
        app.message = "No symbol under cursor"
        return
    end
    app.rename_prompt = RenamePrompt(word, word, length(word))
    app.mode = :rename
end

"""Apply local find-replace rename in the current editor."""
function _apply_rename_local!(app::SessionsApp, old_name::String, new_name::String)
    if app.editor_type == :file && app.file_editor_view !== nothing
        editor = app.file_editor_view.editor
        _replace_in_editor!(editor, old_name, new_name)
    else
        cw = focused_widget(app.notebook_view)
        cw === nothing && return
        _replace_in_editor!(cw.editor, old_name, new_name)
    end
end

"""Replace all whole-word occurrences of old_name with new_name in a CodeEditor."""
function _replace_in_editor!(editor, old_name::String, new_name::String)
    _is_ident(c) = isletter(c) || isdigit(c) || c == '_' || c == '!'
    for (row_idx, line) in enumerate(editor.lines)
        line_str = String(line)
        new_line = ""
        i = 1
        while i <= length(line_str)
            # Check if old_name starts here
            if i + length(old_name) - 1 <= length(line_str) &&
               line_str[i:i+length(old_name)-1] == old_name
                # Check word boundaries
                before_ok = (i == 1) || !_is_ident(line_str[i-1])
                after_pos = i + length(old_name)
                after_ok = (after_pos > length(line_str)) || !_is_ident(line_str[after_pos])
                if before_ok && after_ok
                    new_line *= new_name
                    i += length(old_name)
                    continue
                end
            end
            new_line *= string(line_str[i])
            i += 1
        end
        editor.lines[row_idx] = collect(new_line)
    end
end

"""Render the rename prompt as a centered overlay."""
function _render_rename_prompt!(rp::RenamePrompt, buf::Tachikoma.Buffer, area::Tachikoma.Rect)
    prompt_text = "Rename: "
    label = prompt_text * rp.new_name
    content_w = length(label) + 2  # padding
    w = min(max(content_w + 2, 30), area.width - 4)
    h = 3

    x = area.x + max(0, div(area.width - w, 2))
    y = area.y + 2

    box = Theme.BOX
    bg = Theme.ELEVATED_BG
    border_style = Tachikoma.Style(; fg=Theme.ACCENT, bg)
    text_style = Tachikoma.Style(; fg=Theme.FG, bg)
    cursor_style = Tachikoma.Style(; fg=Theme.BG, bg=Theme.FG)

    # Top border with title
    title = " Rename Symbol "
    top_left = string(box.tl) * repeat(string(box.h), 1) * title
    remaining = w - 2 - length(title)
    top = top_left * repeat(string(box.h), max(0, remaining)) * string(box.tr)
    Tachikoma.set_string!(buf, x, y, top, border_style)

    # Content line
    iy = y + 1
    Tachikoma.set_char!(buf, x, iy, box.v, border_style)
    inner_w = w - 2
    display = " " * label
    if length(display) > inner_w
        display = first(display, inner_w)
    else
        display = display * " " ^ (inner_w - length(display))
    end
    Tachikoma.set_string!(buf, x + 1, iy, display, text_style)
    # Draw cursor
    cursor_x = x + 1 + 1 + length(prompt_text) + rp.cursor  # +1 for padding, +1 for border
    if cursor_x < x + w - 1
        c = rp.cursor < length(rp.new_name) ? rp.new_name[rp.cursor+1] : ' '
        Tachikoma.set_char!(buf, cursor_x, iy, c, cursor_style)
    end
    Tachikoma.set_char!(buf, x + w - 1, iy, box.v, border_style)

    # Bottom border
    bot = string(box.bl) * repeat(string(box.h), w - 2) * string(box.br)
    Tachikoma.set_string!(buf, x, y + 2, bot, border_style)
end
