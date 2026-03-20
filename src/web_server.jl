# web_server.jl — Server state + channel handlers for Sessions.jl Web UI
#
# Bridges the notebook engine to Therapy.jl WebSocket channels.
# Handles: cell execution, add/delete/move cells, save, run all.
# All heavy lifting (execution, reactivity, analysis) stays server-side.

using Therapy
using UUIDs
# Note: Markdown is already imported by web.jl (included earlier in the module)

"""A single notebook tab in the web UI."""
mutable struct WebTab
    id::UUID
    nb::Notebook
    workspace::Workspace
    label::String   # display name (filename)
    path::String    # absolute file path
    last_disk_nb::Union{Notebook, Nothing}  # snapshot for external change detection
    watcher::Union{DebouncedWatcher, Nothing}
end

WebTab(id, nb, ws, label, path) = WebTab(id, nb, ws, label, path, nothing, nothing)

"""Server-side notebook state for the web UI (multi-tab)."""
mutable struct WebNotebookState
    tabs::Vector{WebTab}
    active_tab_idx::Int
    executing::Bool
end

"""Return the currently active tab."""
active_tab(state::WebNotebookState) = state.tabs[state.active_tab_idx]

"""Return the notebook of the currently active tab."""
active_nb(state::WebNotebookState) = active_tab(state).nb

"""Return the workspace of the currently active tab."""
active_workspace(state::WebNotebookState) = active_tab(state).workspace

"""
    create_cell_signals!(state::WebNotebookState)

Create a server signal per cell for real-time state updates.
Signal names: `cell_{uuid}_state` with values like "idle", "running", "done".
Therapy's WS client auto-updates DOM elements with `data-server-signal` attrs.
"""
function create_cell_signals!(state::WebNotebookState)
    for cell in ordered_cells(active_nb(state))
        sig_name = "cell_$(cell.id)_state"
        if !haskey(Therapy.SERVER_SIGNALS, sig_name)
            create_server_signal(sig_name, string(cell.state); use_patches=false)
        end
    end
end

"""Update a cell's server signal to broadcast its state to all clients."""
function _update_cell_signal!(cell::Cell)
    sig_name = "cell_$(cell.id)_state"
    sig = get(Therapy.SERVER_SIGNALS, sig_name, nothing)
    if sig !== nothing
        set_server_signal!(sig, string(cell.state))
    end
end

"""
    setup_web_notebook!(state::WebNotebookState)

Set up WebSocket channel handlers for notebook communication.
Creates the "notebook" channel and registers message handlers.
"""
function setup_web_notebook!(state::WebNotebookState)
    # Create channel (safe for HMR reloads)
    if !haskey(Therapy.MESSAGE_CHANNELS, "notebook")
        create_channel("notebook")
    end

    on_channel_message("notebook") do conn, data
        action = get(data, "action", "")
        try
            if action == "execute"
                handle_execute_cell!(state, conn, data)
            elseif action == "run_all"
                handle_run_all!(state, conn, data)
            elseif action == "add_cell"
                handle_add_cell!(state, conn, data)
            elseif action == "delete_cell"
                handle_delete_cell!(state, conn, data)
            elseif action == "move_cell"
                handle_move_cell!(state, conn, data)
            elseif action == "update_code"
                handle_update_code!(state, conn, data)
            elseif action == "toggle_fold"
                handle_toggle_fold!(state, conn, data)
            elseif action == "save"
                handle_save!(state, conn, data)
            elseif action == "run_stale"
                handle_run_stale!(state, conn, data)
            elseif action == "open_notebook"
                handle_open_notebook!(state, conn, data)
            elseif action == "switch_tab"
                handle_switch_tab!(state, conn, data)
            elseif action == "close_tab"
                handle_close_tab!(state, conn, data)
            else
                @warn "[WebNotebook] Unknown action" action=action
            end
        catch e
            @warn "[WebNotebook] Handler error" action=action exception=(e, catch_backtrace())
        end
    end
end

# =============================================================================
# Full state sync (on WebSocket connect)
# =============================================================================

"""Send complete notebook state to a newly connected client."""
function send_full_state!(state::WebNotebookState, conn)
    nb = active_nb(state)
    cells_data = []
    for cell in ordered_cells(nb)
        push!(cells_data, _cell_to_dict(cell))
    end

    send_channel!("notebook", conn, Dict(
        "event" => "full_state",
        "notebook_path" => nb.path,
        "cells" => cells_data,
        "cell_order" => [string(id) for id in nb.cell_order]
    ))
end

"""Convert a Cell to a serializable Dict for the client."""
function _cell_to_dict(cell::Cell)
    output_html = _web_render_output_html(cell)
    Dict(
        "cell_id" => string(cell.id),
        "code" => cell.code,
        "state" => string(cell.state),
        "output_html" => output_html,
        "runtime_ns" => cell.output.runtime_ns,
        "stdout" => cell.output.stdout,
        "folded" => cell.folded,
        "disabled" => cell.disabled,
        "stale" => is_stale(cell)
    )
end

"""Render cell output to HTML string via Sessions._render_output + Therapy.render_to_string."""
function _web_render_output_html(cell::Cell)
    # Markdown cells: render prose with md-prose class for styling
    if cell.output.output_type == :markdown && cell.output.result !== nothing
        md_html = sprint(io -> Markdown.html(io, cell.output.result))
        return """<div class="md-prose">$(md_html)</div>"""
    end
    vnode = _render_output(cell)
    vnode === nothing && return ""
    Therapy.render_to_string(vnode)
end

# =============================================================================
# Cell execution handlers
# =============================================================================

"""Handle a single cell execution request."""
function handle_execute_cell!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    isempty(cell_id_str) && return

    cell_id = UUID(cell_id_str)
    cell = get_cell(active_nb(state), cell_id)
    cell === nothing && return

    # Update code if provided
    new_code = get(data, "code", nothing)
    if new_code !== nothing
        cell.code = new_code
    end

    @async begin
        state.executing = true
        try
            _execute_cells!(state, [cell])
        finally
            state.executing = false
        end
    end
end

"""Handle run-all request."""
function handle_run_all!(state::WebNotebookState, conn, data)
    @async begin
        state.executing = true
        try
            nb = active_nb(state)
            update_topology!(nb)
            order = execution_order(nb)

            # Mark all as queued
            for c in order.runnable
                c.state = cell_queued
                broadcast_channel!("notebook", Dict(
                    "event" => "cell_state",
                    "cell_id" => string(c.id),
                    "state" => "cell_queued"
                ))
            end

            # Execute in topological order
            for c in order.runnable
                c.state = cell_running
                broadcast_channel!("notebook", Dict(
                    "event" => "cell_state",
                    "cell_id" => string(c.id),
                    "state" => "cell_running"
                ))

                execute_cell!(active_workspace(state), c)

                broadcast_channel!("notebook", Dict(
                    "event" => "cell_output",
                    "cell_id" => string(c.id),
                    "output_html" => _web_render_output_html(c),
                    "runtime_ns" => c.output.runtime_ns,
                    "stdout" => c.output.stdout,
                    "state" => string(c.state)
                ))
            end

            save_session!(nb)
        finally
            state.executing = false
        end
    end
end

"""Execute cells with reactive dependencies: topology → queued → running → done."""
function _execute_cells!(state::WebNotebookState, changed_cells::Vector{Cell})
    nb = active_nb(state)
    update_topology!(nb, changed_cells)
    order = execution_order(nb, changed_cells)

    # Mark all runnable as queued — update both channel + server signal
    for c in order.runnable
        c.state = cell_queued
        _update_cell_signal!(c)
        broadcast_channel!("notebook", Dict(
            "event" => "cell_state",
            "cell_id" => string(c.id),
            "state" => "cell_queued"
        ))
    end

    # Execute in topological order
    for c in order.runnable
        c.state = cell_running
        _update_cell_signal!(c)
        broadcast_channel!("notebook", Dict(
            "event" => "cell_state",
            "cell_id" => string(c.id),
            "state" => "cell_running"
        ))

        execute_cell!(active_workspace(state), c)
        _update_cell_signal!(c)

        broadcast_channel!("notebook", Dict(
            "event" => "cell_output",
            "cell_id" => string(c.id),
            "output_html" => _web_render_output_html(c),
            "runtime_ns" => c.output.runtime_ns,
            "stdout" => c.output.stdout,
            "state" => string(c.state)
        ))
    end

    # Broadcast errors
    for (c, _err) in order.errable
        c.state = cell_errored
        _update_cell_signal!(c)
        broadcast_channel!("notebook", Dict(
            "event" => "cell_state",
            "cell_id" => string(c.id),
            "state" => "cell_errored"
        ))
    end

    save_session!(nb)
    _broadcast_stale!(state)
end

"""Broadcast stale cell info to all clients (Run Stale button + cell accent bars)."""
function _broadcast_stale!(state::WebNotebookState)
    sc = stale_cells(active_nb(state))
    stale_ids = [string(c.id) for c in sc]
    broadcast_channel!("notebook", Dict(
        "event" => "stale_update",
        "count" => length(sc),
        "stale_ids" => stale_ids
    ))
end

# =============================================================================
# Cell CRUD handlers
# =============================================================================

"""Handle add-cell request."""
function handle_add_cell!(state::WebNotebookState, conn, data)
    nb = active_nb(state)
    after_cell_id_str = get(data, "after_cell_id", "")
    new_cell = Cell(; code="")

    if isempty(after_cell_id_str)
        # Insert at beginning
        insert_cell!(nb, 1, new_cell)
    else
        after_id = UUID(after_cell_id_str)
        idx = findfirst(==(after_id), nb.cell_order)
        if idx !== nothing
            insert_cell!(nb, idx + 1, new_cell)
        else
            add_cell!(nb, new_cell)
        end
    end

    # Create server signal for the new cell
    sig_name = "cell_$(new_cell.id)_state"
    if !haskey(Therapy.SERVER_SIGNALS, sig_name)
        create_server_signal(sig_name, string(new_cell.state); use_patches=false)
    end

    println("[WebNotebook] Added cell $(new_cell.id) after $(after_cell_id_str)")

    # Render the new cell to HTML server-side (same as SSR)
    # CellView and CellGap are loaded into Therapy's module scope by load_app!
    cell_html = try
        _CellView = getfield(Therapy, :CellView)
        _CellGap = getfield(Therapy, :CellGap)
        cell_vnode = Base.invokelatest(_CellView, new_cell; index=0)
        gap_vnode = Base.invokelatest(_CellGap; after_cell_id=string(new_cell.id))
        cell_str = cell_vnode !== nothing ? Therapy.render_to_string(cell_vnode) : ""
        gap_str = Therapy.render_to_string(gap_vnode)
        cell_str * gap_str
    catch e
        @warn "[WebNotebook] Failed to render new cell" exception=e
        ""
    end

    broadcast_channel!("notebook", Dict(
        "event" => "cell_added",
        "cell_id" => string(new_cell.id),
        "after_cell_id" => after_cell_id_str,
        "cell_html" => cell_html
    ))
end

"""Handle delete-cell request."""
function handle_delete_cell!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    isempty(cell_id_str) && return

    cell_id = UUID(cell_id_str)
    removed = remove_cell!(active_nb(state), cell_id)
    removed === nothing && return

    println("[WebNotebook] Deleted cell $(cell_id_str)")

    broadcast_channel!("notebook", Dict(
        "event" => "cell_deleted",
        "cell_id" => cell_id_str
    ))
end

"""Handle move-cell request."""
function handle_move_cell!(state::WebNotebookState, conn, data)
    nb = active_nb(state)
    cell_id_str = get(data, "cell_id", "")
    direction = get(data, "direction", "")
    isempty(cell_id_str) && return

    cell_id = UUID(cell_id_str)
    idx = findfirst(==(cell_id), nb.cell_order)
    idx === nothing && return

    swapped = if direction == "up"
        swap_cell_up!(nb, idx)
    elseif direction == "down"
        swap_cell_down!(nb, idx)
    else
        false
    end

    swapped || return

    broadcast_channel!("notebook", Dict(
        "event" => "cell_moved",
        "cell_id" => cell_id_str,
        "direction" => direction
    ))
end

"""Handle fold/unfold toggle — persisted in .jl file as ╟─ (folded) vs ╠═ (visible)."""
function handle_toggle_fold!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    isempty(cell_id_str) && return
    cell = get_cell(active_nb(state), UUID(cell_id_str))
    cell === nothing && return
    cell.folded = get(data, "folded", false)
end

"""Handle code update (without execution). Broadcasts stale count so UI updates."""
function handle_update_code!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    new_code = get(data, "code", "")
    isempty(cell_id_str) && return

    cell = get_cell(active_nb(state), UUID(cell_id_str))
    cell === nothing && return
    cell.code = new_code

    # Broadcast stale info — same path as agent editing .jl file
    _broadcast_stale!(state)
end

"""Handle save request. Syncs codes from client first if provided."""
function handle_save!(state::WebNotebookState, conn, data)
    nb = active_nb(state)
    # Sync any codes sent with the save request
    codes = get(data, "codes", nothing)
    if codes !== nothing
        for (cid, code) in codes
            cell = get_cell(nb, UUID(String(cid)))
            cell !== nothing && (cell.code = String(code))
        end
    end

    save_notebook(nb)
    save_session!(nb)
    broadcast_channel!("notebook", Dict(
        "event" => "saved",
        "notebook_path" => nb.path
    ))
    println("[WebNotebook] Saved: $(nb.path)")
end

"""Handle run-stale request — execute only stale cells (like TUI's Ctrl+Shift+Enter)."""
function handle_run_stale!(state::WebNotebookState, conn, data)
    nb = active_nb(state)
    # Sync codes from client first
    codes = get(data, "codes", nothing)
    if codes !== nothing
        for (cid, code) in codes
            cell = get_cell(nb, UUID(String(cid)))
            cell !== nothing && (cell.code = String(code))
        end
    end

    @async begin
        state.executing = true
        try
            sc = stale_cells(nb)
            if isempty(sc)
                broadcast_channel!("notebook", Dict(
                    "event" => "info",
                    "message" => "No stale cells"
                ))
                return
            end

            println("[WebNotebook] Running $(length(sc)) stale cells...")
            _execute_cells!(state, sc)
        finally
            state.executing = false
        end
    end
end

# =============================================================================
# Tab management handlers
# =============================================================================

"""Handle open-notebook request — deduplicates by absolute path."""
function handle_open_notebook!(state::WebNotebookState, conn, data)
    raw_path = get(data, "path", "")
    isempty(raw_path) && return

    # Resolve path: if absolute, use as-is; if relative, resolve from notebook dir
    full_path = if isabspath(raw_path)
        abspath(raw_path)
    else
        nb_dir = dirname(abspath(active_nb(state).path))
        abspath(joinpath(nb_dir, raw_path))
    end

    if !isfile(full_path)
        @warn "[WebNotebook] File not found" path=full_path
        return
    end

    if !endswith(full_path, ".jl")
        @warn "[WebNotebook] Not a Julia file" path=full_path
        return
    end

    # Check if already open (dedup by absolute path)
    for (i, tab) in enumerate(state.tabs)
        if tab.path == full_path
            # Already open — just switch to it
            state.active_tab_idx = i
            create_cell_signals!(state)
            _broadcast_nb_html!(state)
            return
        end
    end

    # Load notebook, create workspace, restore session
    nb = load_notebook(full_path)
    session_data = load_session(session_path(nb.path))
    if session_data !== nothing
        apply_session!(nb, session_data)
    end
    ws = Workspace(; notebook_path=nb.path)

    # Create new tab, start watcher, and switch to it
    tab = WebTab(uuid4(), nb, ws, basename(full_path), full_path)
    push!(state.tabs, tab)
    state.active_tab_idx = length(state.tabs)
    _start_tab_watcher!(state, tab)
    create_cell_signals!(state)

    println("[WebNotebook] Opened tab: $(tab.label) ($(length(state.tabs)) tabs)")
    _broadcast_nb_html!(state)
end

"""Handle switch-tab request — renders new tab content server-side."""
function handle_switch_tab!(state::WebNotebookState, conn, data)
    tab_idx = get(data, "tab_idx", 0)
    (tab_idx isa Number) || return
    tab_idx = Int(tab_idx)
    (tab_idx < 1 || tab_idx > length(state.tabs)) && return
    tab_idx == state.active_tab_idx && return  # already active

    state.active_tab_idx = tab_idx
    create_cell_signals!(state)

    # Render the full notebook panel (tab bar + cells) server-side
    nb_html = try
        _NotebookPanel = getfield(Therapy, :NotebookPanel)
        vnode = Base.invokelatest(_NotebookPanel)
        vnode !== nothing ? Therapy.render_to_string(vnode) : ""
    catch e
        @warn "[WebNotebook] Failed to render notebook panel" exception=e
        ""
    end

    _broadcast_nb_html!(state)
end

"""Render the full NotebookPanel to HTML and broadcast to all clients."""
function _broadcast_nb_html!(state::WebNotebookState)
    nb_html = try
        _NotebookPanel = getfield(Therapy, :NotebookPanel)
        vnode = Base.invokelatest(_NotebookPanel)
        vnode !== nothing ? Therapy.render_to_string(vnode) : ""
    catch e
        @warn "[WebNotebook] Failed to render notebook panel" exception=e
        ""
    end

    broadcast_channel!("notebook", Dict(
        "event" => "nb_replaced",
        "nb_html" => nb_html
    ))
end

"""Handle close-tab request — enforces minimum 1 tab."""
function handle_close_tab!(state::WebNotebookState, conn, data)
    tab_idx = get(data, "tab_idx", 0)
    (tab_idx isa Number) || return
    tab_idx = Int(tab_idx)
    (tab_idx < 1 || tab_idx > length(state.tabs)) && return

    # Enforce minimum 1 tab
    length(state.tabs) <= 1 && return

    closed_label = state.tabs[tab_idx].label
    deleteat!(state.tabs, tab_idx)

    # Adjust active index
    if state.active_tab_idx > length(state.tabs)
        state.active_tab_idx = length(state.tabs)
    elseif state.active_tab_idx > tab_idx
        state.active_tab_idx -= 1
    elseif state.active_tab_idx == tab_idx && state.active_tab_idx > length(state.tabs)
        state.active_tab_idx = length(state.tabs)
    end

    create_cell_signals!(state)
    println("[WebNotebook] Closed tab: $(closed_label) ($(length(state.tabs)) tabs)")
    _broadcast_nb_html!(state)
end

# =============================================================================
# File watcher — detect external changes (agent edits, git, IDE)
# =============================================================================

"""Snapshot a notebook for later diffing."""
function _snapshot_notebook(nb::Notebook)
    snap = Notebook(; path=nb.path)
    for id in nb.cell_order
        haskey(nb.cells, id) || continue
        cell = nb.cells[id]
        add_cell!(snap, Cell(; id=cell.id, code=cell.code, folded=cell.folded, disabled=cell.disabled))
    end
    snap.cell_order = copy(nb.cell_order)
    snap
end

"""Start file watchers for all tabs."""
function start_web_watchers!(state::WebNotebookState)
    for tab in state.tabs
        _start_tab_watcher!(state, tab)
    end
end

"""Start a file watcher for a single tab."""
function _start_tab_watcher!(state::WebNotebookState, tab::WebTab)
    tab.watcher !== nothing && stop_watching!(tab.watcher)
    (!isfile(tab.path) || isempty(tab.path)) && return

    tab.last_disk_nb = _snapshot_notebook(tab.nb)
    tab.watcher = DebouncedWatcher(tab.nb, _ -> _on_web_external_change!(state, tab);
                                    delay=0.5, poll_interval=0.5)
    start_watching!(tab.watcher)
end

"""Handle external file change for a web tab — reload, diff, broadcast."""
function _on_web_external_change!(state::WebNotebookState, tab::WebTab)
    tab.last_disk_nb === nothing && return
    state.executing && return  # don't reload during execution

    try
        old_order = copy(tab.last_disk_nb.cell_order)
        diff = merge_external_changes!(tab.nb, tab.last_disk_nb)
        tab.last_disk_nb = _snapshot_notebook(tab.nb)

        reordered = diff.new_order != old_order
        n_changes = length(diff.added) + length(diff.changed) + length(diff.removed) + length(diff.metadata_changed)
        n_changes == 0 && !reordered && return

        # Create signals for any new cells
        create_cell_signals!(state)

        # Broadcast stale state + structural change
        _broadcast_stale!(state)

        if !isempty(diff.added) || !isempty(diff.removed) || reordered
            # Structural change — re-render notebook panel
            println("[WebNotebook] External change: $(n_changes) cells changed in $(tab.label)")
            _broadcast_nb_html!(state)
        else
            # Code-only changes — just update stale indicators
            println("[WebNotebook] External code change: $(n_changes) cells in $(tab.label)")
        end
    catch e
        @warn "[WebNotebook] External change handler error" exception=(e, catch_backtrace())
    end
end

# =============================================================================
# File tree for web explorer
# =============================================================================

"""A node in the file tree (file or directory)."""
struct FileNode
    name::String
    path::String        # relative path from root
    is_dir::Bool
    children::Vector{FileNode}
    file_type::Symbol   # :jl, :toml, :md, :yml, :git, :lic, :generic
end

"""Detect file type from filename/extension."""
function _detect_file_type(name::String)::Symbol
    name == "LICENSE" && return :lic
    name == ".gitignore" && return :git
    endswith(name, ".jl") && return :jl
    endswith(name, ".toml") && return :toml
    endswith(name, ".md") && return :md
    (endswith(name, ".yml") || endswith(name, ".yaml")) && return :yml
    return :generic
end

const _SKIP_NAMES = Set(["node_modules", ".git", "Manifest.toml", "__pycache__", ".DS_Store"])

"""
    _build_file_tree(root_dir::String; max_depth::Int=4)

Walk `root_dir` and return a `Vector{FileNode}` representing its contents.
Skips hidden files/directories (names starting with `.`), `node_modules`,
`Manifest.toml`, and `.git`. Directories are sorted first, then files,
alphabetical within each group. Recurses up to `max_depth` levels.
"""
function _build_file_tree(root_dir::String; max_depth::Int=4)
    _build_tree_recursive(root_dir, root_dir, 0, max_depth)
end

function _build_tree_recursive(dir::String, root::String, depth::Int, max_depth::Int)::Vector{FileNode}
    depth >= max_depth && return FileNode[]
    entries = try
        readdir(dir)
    catch
        return FileNode[]
    end

    dirs = FileNode[]
    files = FileNode[]

    for name in entries
        # Skip hidden files (starting with .) except .gitignore
        if startswith(name, '.') && name != ".gitignore"
            continue
        end
        # Skip blocklisted names
        name in _SKIP_NAMES && continue

        full = joinpath(dir, name)
        rel = relpath(full, root)

        if isdir(full)
            children = _build_tree_recursive(full, root, depth + 1, max_depth)
            push!(dirs, FileNode(name, rel, true, children, :generic))
        elseif isfile(full)
            push!(files, FileNode(name, rel, false, FileNode[], _detect_file_type(name)))
        end
    end

    sort!(dirs; by=n -> lowercase(n.name))
    sort!(files; by=n -> lowercase(n.name))
    return vcat(dirs, files)
end
