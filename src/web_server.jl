# web_server.jl — Server state + channel handlers for Sessions.jl Web UI
#
# Bridges the notebook engine to Therapy.jl WebSocket channels.
# Handles: cell execution, add/delete/move cells, save, run all.
# All heavy lifting (execution, reactivity, analysis) stays server-side.

using Therapy
# Note: Markdown is already imported by web.jl (included earlier in the module)

"""Server-side notebook state for the web UI."""
mutable struct WebNotebookState
    nb::Notebook
    workspace::Workspace
    executing::Bool
end

"""
    create_cell_signals!(state::WebNotebookState)

Create a server signal per cell for real-time state updates.
Signal names: `cell_{uuid}_state` with values like "idle", "running", "done".
Therapy's WS client auto-updates DOM elements with `data-server-signal` attrs.
"""
function create_cell_signals!(state::WebNotebookState)
    for cell in ordered_cells(state.nb)
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
    cells_data = []
    for cell in ordered_cells(state.nb)
        push!(cells_data, _cell_to_dict(cell))
    end

    send_channel!("notebook", conn, Dict(
        "event" => "full_state",
        "notebook_path" => state.nb.path,
        "cells" => cells_data,
        "cell_order" => [string(id) for id in state.nb.cell_order]
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
    cell = get_cell(state.nb, cell_id)
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
            update_topology!(state.nb)
            order = execution_order(state.nb)

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

                execute_cell!(state.workspace, c)

                broadcast_channel!("notebook", Dict(
                    "event" => "cell_output",
                    "cell_id" => string(c.id),
                    "output_html" => _web_render_output_html(c),
                    "runtime_ns" => c.output.runtime_ns,
                    "stdout" => c.output.stdout,
                    "state" => string(c.state)
                ))
            end

            save_session!(state.nb)
        finally
            state.executing = false
        end
    end
end

"""Execute cells with reactive dependencies: topology → queued → running → done."""
function _execute_cells!(state::WebNotebookState, changed_cells::Vector{Cell})
    update_topology!(state.nb, changed_cells)
    order = execution_order(state.nb, changed_cells)

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

        execute_cell!(state.workspace, c)
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

    save_session!(state.nb)
    _broadcast_stale!(state)
end

"""Broadcast stale cell info to all clients (Run Stale button + cell accent bars)."""
function _broadcast_stale!(state::WebNotebookState)
    sc = stale_cells(state.nb)
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
    after_cell_id_str = get(data, "after_cell_id", "")
    new_cell = Cell(; code="")

    if isempty(after_cell_id_str)
        # Insert at beginning
        insert_cell!(state.nb, 1, new_cell)
    else
        after_id = UUID(after_cell_id_str)
        idx = findfirst(==(after_id), state.nb.cell_order)
        if idx !== nothing
            insert_cell!(state.nb, idx + 1, new_cell)
        else
            add_cell!(state.nb, new_cell)
        end
    end

    broadcast_channel!("notebook", Dict(
        "event" => "cell_added",
        "cell" => _cell_to_dict(new_cell),
        "after_cell_id" => after_cell_id_str,
        "cell_order" => [string(id) for id in state.nb.cell_order]
    ))
end

"""Handle delete-cell request."""
function handle_delete_cell!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    isempty(cell_id_str) && return

    cell_id = UUID(cell_id_str)
    removed = remove_cell!(state.nb, cell_id)
    removed === nothing && return

    broadcast_channel!("notebook", Dict(
        "event" => "cell_deleted",
        "cell_id" => cell_id_str,
        "cell_order" => [string(id) for id in state.nb.cell_order]
    ))
end

"""Handle move-cell request."""
function handle_move_cell!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    direction = get(data, "direction", "")
    isempty(cell_id_str) && return

    cell_id = UUID(cell_id_str)
    idx = findfirst(==(cell_id), state.nb.cell_order)
    idx === nothing && return

    swapped = if direction == "up"
        swap_cell_up!(state.nb, idx)
    elseif direction == "down"
        swap_cell_down!(state.nb, idx)
    else
        false
    end

    swapped || return

    broadcast_channel!("notebook", Dict(
        "event" => "cell_order",
        "cell_order" => [string(id) for id in state.nb.cell_order]
    ))
end

"""Handle fold/unfold toggle — persisted in .jl file as ╟─ (folded) vs ╠═ (visible)."""
function handle_toggle_fold!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    isempty(cell_id_str) && return
    cell = get_cell(state.nb, UUID(cell_id_str))
    cell === nothing && return
    cell.folded = get(data, "folded", false)
end

"""Handle code update (without execution). Broadcasts stale count so UI updates."""
function handle_update_code!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    new_code = get(data, "code", "")
    isempty(cell_id_str) && return

    cell = get_cell(state.nb, UUID(cell_id_str))
    cell === nothing && return
    cell.code = new_code

    # Broadcast stale info — same path as agent editing .jl file
    _broadcast_stale!(state)
end

"""Handle save request. Syncs codes from client first if provided."""
function handle_save!(state::WebNotebookState, conn, data)
    # Sync any codes sent with the save request
    codes = get(data, "codes", nothing)
    if codes !== nothing
        for (cid, code) in codes
            cell = get_cell(state.nb, UUID(String(cid)))
            cell !== nothing && (cell.code = String(code))
        end
    end

    save_notebook(state.nb)
    save_session!(state.nb)
    broadcast_channel!("notebook", Dict(
        "event" => "saved",
        "notebook_path" => state.nb.path
    ))
    println("[WebNotebook] Saved: $(state.nb.path)")
end

"""Handle run-stale request — execute only stale cells (like TUI's Ctrl+Shift+Enter)."""
function handle_run_stale!(state::WebNotebookState, conn, data)
    # Sync codes from client first
    codes = get(data, "codes", nothing)
    if codes !== nothing
        for (cid, code) in codes
            cell = get_cell(state.nb, UUID(String(cid)))
            cell !== nothing && (cell.code = String(code))
        end
    end

    @async begin
        state.executing = true
        try
            sc = stale_cells(state.nb)
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
