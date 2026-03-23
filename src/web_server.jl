# web_server.jl — Server state + channel handlers for Sessions.jl Web UI
#
# Bridges the notebook engine to Therapy.jl WebSocket channels.
# Handles: cell execution, add/delete/move cells, save, run all.
# All heavy lifting (execution, reactivity, analysis) stays server-side.

using Therapy
using UUIDs
# Note: Markdown is already imported by web.jl (included earlier in the module)

"""A single tab in the web UI — either a notebook or a plain file."""
mutable struct WebTab
    id::UUID
    tab_type::Symbol              # :notebook or :file
    nb::Union{Notebook, Nothing}  # Notebook (for :notebook tabs)
    worker::Union{NotebookWorker, Nothing}  # Malt worker (for :notebook tabs)
    label::String                 # display name (filename)
    path::String                  # absolute file path
    file_content::String          # raw file content (for :file tabs)
    last_disk_nb::Union{Notebook, Nothing}  # snapshot for external change detection
    watcher::Union{DebouncedWatcher, Nothing}
end

# Notebook tab constructor
WebTab(id, nb::Notebook, worker, label, path) = WebTab(id, :notebook, nb, worker, label, path, "", nothing, nothing)
# File tab constructor
WebTab(id, label, path, content::String) = WebTab(id, :file, nothing, nothing, label, path, content, nothing, nothing)

"""Server-side notebook state for the web UI (multi-tab)."""
mutable struct WebNotebookState
    tabs::Vector{WebTab}
    active_tab_idx::Int
    executing::Bool
end

"""Return the currently active tab."""
active_tab(state::WebNotebookState) = state.tabs[state.active_tab_idx]

"""Return the notebook of the currently active tab (nothing for file tabs)."""
active_nb(state::WebNotebookState) = active_tab(state).nb

"""Return the worker of the currently active tab (nothing for file tabs)."""
active_worker(state::WebNotebookState) = active_tab(state).worker

"""Check if the active tab is a notebook."""
is_notebook_tab(state::WebNotebookState) = active_tab(state).tab_type == :notebook

"""
    create_cell_signals!(state::WebNotebookState)

Create a server signal per cell for real-time state updates.
Signal names: `cell_{uuid}_state` with values like "idle", "running", "done".
Therapy's WS client auto-updates DOM elements with `data-server-signal` attrs.
"""
function create_cell_signals!(state::WebNotebookState)
    active_tab(state).tab_type == :notebook || return
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
            elseif action == "set_bond"
                handle_set_bond!(state, conn, data)
            elseif action == "save_file"
                handle_save_file!(state, conn, data)
            elseif action == "interrupt"
                handle_interrupt!(state, conn, data)
            elseif action == "format_cell"
                handle_format_cell!(state, conn, data)
            elseif action == "format_all"
                handle_format_all!(state, conn, data)
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
    tab = active_tab(state)
    if tab.tab_type == :file
        # File tab: send file content instead of cell state
        send_channel!("notebook", conn, Dict(
            "event" => "full_state",
            "tab_type" => "file",
            "file_path" => tab.path,
            "file_content" => tab.file_content
        ))
        return
    end
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

"""Render a bond widget as a BoundSlider @island (SSR + WASM hydration)."""
function _render_bond_island_html(bond_data::String)
    # Parse: "slider:varname:min:max:step:default" or "widget:varname:type"
    parts = split(bond_data, ":")
    if length(parts) >= 6 && parts[1] == "slider"
        var_name = String(parts[2])
        min_v = parse(Int, parts[3])
        max_v = parse(Int, parts[4])
        step_v = parse(Int, parts[5])
        def_v = parse(Int, parts[6])

        # Render BoundSlider @island via Therapy SSR
        # The @island is defined in web/src/components/BoundSlider.jl and loaded into
        # Therapy's module scope by Therapy.load_app!. Registered in ISLAND_REGISTRY
        # with Symbol key :BoundSlider.
        try
            island = get(Therapy.ISLAND_REGISTRY, :BoundSlider, nothing)
            if island !== nothing
                vnode = Base.invokelatest(island;
                    min_val=min_v, max_val=max_v, value=def_v, step_val=step_v, var_name=var_name)
                html = Therapy.render_to_string(vnode)
                # JS bridge for server re-execution (alongside WASM signal).
                # The @island's WASM on_input handles instant value display.
                # This JS bridge sends the value to the server for re-executing
                # dependent cells. Later: replaced by WASM channel.send() import.
                bridge_js = """<script>(function(){var el=document.currentScript.previousElementSibling;if(!el)return;var inp=el.querySelector('input[type=range]');if(!inp)return;inp.addEventListener('input',function(){if(window.TherapyWS)TherapyWS.sendMessage('notebook',{action:'set_bond',name:'$(var_name)',value:parseFloat(this.value)})})})();</script>"""
                return html * bridge_js
            end
        catch e
            @warn "[WebNotebook] BoundSlider SSR failed, falling back to plain HTML" exception=e
        end

        # Fallback: plain HTML slider (no WASM)
        return """<div style="display:flex;align-items:center;gap:12px;padding:8px 0;">
            <span style="font-size:13px;font-family:monospace;color:#6b7d93;">$(var_name) =</span>
            <input type="range" min="$(min_v)" max="$(max_v)" step="$(step_v)" value="$(def_v)"
                style="flex:1;max-width:300px;accent-color:#56d4a0;cursor:pointer;"
                oninput="this.nextElementSibling.textContent=this.value;if(window.TherapyWS)TherapyWS.sendMessage('notebook',{action:'set_bond',name:'$(var_name)',value:parseFloat(this.value)})">
            <span style="font-size:13px;font-family:monospace;color:#56d4a0;min-width:2em;text-align:right;">$(def_v)</span>
        </div>"""
    elseif length(parts) >= 3 && parts[1] == "widget"
        var_name = String(parts[2])
        wtype = String(parts[3])
        return """<span style="font-size:12px;font-family:monospace;color:#6b7d93;padding:4px 8px;border:1px solid #2a3a4f;border-radius:6px;">$(wtype) → :$(var_name)</span>"""
    end
    ""
end

"""Render a table from structured JSON into a Pluto-style HTML table.

Matches Pluto's table layout:
- Accent-colored top border, minimal horizontal rules
- Column headers in accent color, types shown on hover
- Bold row numbers, clean spacing
- First 10 rows visible, then "⋮ more", then last row always shown
"""
function _render_table_html(table_json::String)
    isempty(table_json) && return ""

    data = _parse_table_json(table_json)
    data === nothing && return ""

    cols = data[:cols]
    types = data[:types]
    rows = data[:rows]
    nrow = data[:nrow]
    ncol = data[:ncol]
    isempty(cols) && return ""

    initial_visible = 10  # Pluto shows 10 rows initially
    total_serialized = length(rows)
    truncated = total_serialized > initial_visible

    buf = IOBuffer()

    # Dimension label (above table, like Pluto)
    print(buf, """<div class="sst-wrap"><div style="font-size:13px;color:#6b7d93;padding:2px 0 8px;font-family:'JetBrains Mono',monospace;">$(nrow)×$(ncol) DataFrame</div>""")

    # Table
    print(buf, """<table class="sst-table"><thead>""")

    # Column name row
    print(buf, """<tr><th class="sst-th sst-row-label"></th>""")
    for name in cols
        print(buf, """<th class="sst-th">""", _html_esc(name), "</th>")
    end
    print(buf, "</tr>")

    # Column type row (visible on hover, like Pluto)
    print(buf, """<tr class="sst-type-row"><th class="sst-type-th"></th>""")
    for t in types
        print(buf, """<th class="sst-type-th">""", _html_esc(t), "</th>")
    end
    print(buf, "</tr></thead><tbody>")

    # Data rows — Pluto pattern: first N rows, "⋮ more", last row
    if truncated
        # First N rows (visible)
        for i in 1:initial_visible
            _write_table_row(buf, i, rows[i], ncol)
        end

        # Hidden middle rows (revealed by "more" click)
        for i in (initial_visible + 1):(total_serialized - 1)
            print(buf, """<tr class="sst-row sst-hidden" data-row-idx="$(i)" style="display:none">""")
            print(buf, """<th class="sst-row-label">""", i, "</th>")
            for cell in rows[i]
                print(buf, """<td class="sst-td">""", _html_esc(cell), "</td>")
            end
            print(buf, "</tr>")
        end

        # "⋮ more" button row
        hidden_count = total_serialized - initial_visible - 1
        if nrow > total_serialized
            more_label = "⋮ more"
        else
            more_label = "⋮ $(hidden_count) more"
        end
        print(buf, """<tr class="sst-more-row"><td colspan="$(ncol + 1)" class="sst-more" """)
        print(buf, """onclick="this.closest('table').querySelectorAll('.sst-hidden').forEach(function(r){r.style.display=''});this.closest('tr').style.display='none'">""")
        print(buf, more_label, "</td></tr>")

        # Last row (always visible, like Pluto)
        _write_table_row(buf, total_serialized, rows[end], ncol)
    else
        # All rows visible (small table)
        for (i, row) in enumerate(rows)
            _write_table_row(buf, i, row, ncol)
        end
    end

    print(buf, "</tbody></table></div>")
    String(take!(buf))
end

function _write_table_row(buf::IOBuffer, idx::Int, row::Vector{String}, ncol::Int)
    print(buf, """<tr class="sst-row" data-row-idx="$(idx)">""")
    print(buf, """<th class="sst-row-label">""", idx, "</th>")
    for cell in row
        print(buf, """<td class="sst-td">""", _html_esc(cell), "</td>")
    end
    print(buf, "</tr>")
end

"""Simple JSON parser for table data. Returns Dict or nothing."""
function _parse_table_json(json::String)
    # Minimal parser for our specific format:
    # {"cols":["a","b"],"types":["Int","String"],"nrow":N,"ncol":M,"rows":[["1","x"],["2","y"]]}
    try
        # Extract arrays and numbers by position
        cols = _extract_json_string_array(json, "cols")
        types = _extract_json_string_array(json, "types")
        rows_str = _extract_json_nested_array(json, "rows")
        nrow = _extract_json_int(json, "nrow")
        ncol = _extract_json_int(json, "ncol")

        rows = Vector{String}[]
        for row_str in rows_str
            push!(rows, _parse_json_string_array(row_str))
        end

        Dict(:cols => cols, :types => types, :rows => rows, :nrow => nrow, :ncol => ncol)
    catch e
        @warn "[WebNotebook] Failed to parse table JSON" exception=e
        nothing
    end
end

function _extract_json_string_array(json::String, key::String)
    # Find "key":[...] and extract the string array
    pat = "\"$(key)\":["
    idx = findfirst(pat, json)
    idx === nothing && return String[]
    start = last(idx) + 1
    depth = 1
    i = start
    while i <= length(json) && depth > 0
        c = json[i]
        c == '[' && (depth += 1)
        c == ']' && (depth -= 1)
        i += 1
    end
    arr_str = json[start:i-2]
    _parse_json_string_array(arr_str)
end

function _extract_json_nested_array(json::String, key::String)
    pat = "\"$(key)\":["
    idx = findfirst(pat, json)
    idx === nothing && return String[]
    start = last(idx) + 1
    depth = 1
    i = start
    while i <= length(json) && depth > 0
        c = json[i]
        c == '[' && (depth += 1)
        c == ']' && (depth -= 1)
        i += 1
    end
    arr_content = json[start:i-2]
    # Split into sub-arrays
    results = String[]
    j = 1
    while j <= length(arr_content)
        if arr_content[j] == '['
            d = 1
            k = j + 1
            while k <= length(arr_content) && d > 0
                arr_content[k] == '[' && (d += 1)
                arr_content[k] == ']' && (d -= 1)
                k += 1
            end
            push!(results, arr_content[j+1:k-2])
            j = k
        else
            j += 1
        end
    end
    results
end

function _extract_json_int(json::String, key::String)
    pat = "\"$(key)\":"
    idx = findfirst(pat, json)
    idx === nothing && return 0
    start = last(idx) + 1
    i = start
    while i <= length(json) && (json[i] in ('0':'9'))
        i += 1
    end
    parse(Int, json[start:i-1])
end

function _parse_json_string_array(s::String)
    results = String[]
    i = 1
    while i <= length(s)
        if s[i] == '"'
            j = i + 1
            buf = IOBuffer()
            while j <= length(s)
                if s[j] == '\\' && j + 1 <= length(s)
                    c = s[j+1]
                    if c == '"'; write(buf, '"')
                    elseif c == '\\'; write(buf, '\\')
                    elseif c == 'n'; write(buf, '\n')
                    elseif c == 'r'; write(buf, '\r')
                    else write(buf, c)
                    end
                    j += 2
                elseif s[j] == '"'
                    break
                else
                    write(buf, s[j])
                    j += 1
                end
            end
            push!(results, String(take!(buf)))
            i = j + 1
        else
            i += 1
        end
    end
    results
end

function _html_esc(s::AbstractString)
    replace(replace(replace(s, '&' => "&amp;"), '<' => "&lt;"), '>' => "&gt;")
end

"""Render cell output to HTML string via Sessions._render_output + Therapy.render_to_string."""
function _web_render_output_html(cell::Cell)
    # Markdown: HTML is in text_representation (from worker or session cache)
    if cell.output.output_type == :markdown
        md_html = if cell.output.result !== nothing
            sprint(io -> Markdown.html(io, cell.output.result))
        else
            cell.output.text_representation  # already HTML from worker/cache
        end
        return isempty(md_html) ? "" : """<div class="md-prose">$(md_html)</div>"""
    end
    # Bond: parse worker data and render BoundSlider @island via SSR
    if cell.output.output_type == :bond
        bond_data = cell.output.text_representation
        return _render_bond_island_html(bond_data)
    end
    # Table: parse structured JSON and render styled table
    if cell.output.output_type == :table
        return _render_table_html(cell.output.text_representation)
    end
    # HTML output: text_representation has the HTML
    if cell.output.output_type == :html
        html = cell.output.text_representation
        return isempty(html) ? "" : html
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
            n_total = length(order.runnable)
            for (i, c) in enumerate(order.runnable)
                c.state = cell_running
                broadcast_channel!("notebook", Dict(
                    "event" => "cell_state",
                    "cell_id" => string(c.id),
                    "state" => "cell_running"
                ))
                broadcast_channel!("notebook", Dict(
                    "event" => "run_progress",
                    "running_index" => i,
                    "total" => n_total,
                    "cell_id" => string(c.id)
                ))

                remote_execute_cell!(active_worker(state), c)

                broadcast_channel!("notebook", Dict(
                    "event" => "cell_output",
                    "cell_id" => string(c.id),
                    "output_html" => _web_render_output_html(c),
                    "runtime_ns" => c.output.runtime_ns,
                    "stdout" => c.output.stdout,
                    "state" => string(c.state)
                ))
            end

            # Clear progress indicator
            broadcast_channel!("notebook", Dict(
                "event" => "run_progress",
                "running_index" => 0,
                "total" => 0
            ))

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
    n_total = length(order.runnable)
    for (i, c) in enumerate(order.runnable)
        c.state = cell_running
        _update_cell_signal!(c)
        broadcast_channel!("notebook", Dict(
            "event" => "cell_state",
            "cell_id" => string(c.id),
            "state" => "cell_running"
        ))
        broadcast_channel!("notebook", Dict(
            "event" => "run_progress",
            "running_index" => i,
            "total" => n_total,
            "cell_id" => string(c.id)
        ))

        remote_execute_cell!(active_worker(state), c)
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

    # Clear progress indicator
    broadcast_channel!("notebook", Dict(
        "event" => "run_progress",
        "running_index" => 0,
        "total" => 0
    ))

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
    active_tab(state).tab_type == :notebook || return
    nb = active_nb(state)
    nb === nothing && return
    sc = stale_cells(nb)
    stale_ids = [string(c.id) for c in sc]
    broadcast_channel!("notebook", Dict(
        "event" => "stale_update",
        "count" => length(sc),
        "stale_ids" => stale_ids,
        "total_cells" => length(ordered_cells(nb))
    ))
end

# =============================================================================
# Cell CRUD handlers
# =============================================================================

"""Handle add-cell request."""
function handle_add_cell!(state::WebNotebookState, conn, data)
    nb = active_nb(state)
    after_cell_id_str = get(data, "after_cell_id", "")
    restore_code = get(data, "code", "")
    new_cell = Cell(; code=restore_code)

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

    nb = active_nb(state)
    cell_id = UUID(cell_id_str)

    # Capture code and index before removal (for undo)
    cell = get_cell(nb, cell_id)
    deleted_code = cell !== nothing ? cell.code : ""
    deleted_index = findfirst(==(cell_id), nb.cell_order)
    prev_cell_id = if deleted_index !== nothing && deleted_index > 1
        string(nb.cell_order[deleted_index - 1])
    else
        ""
    end

    removed = remove_cell!(nb, cell_id)
    removed === nothing && return

    println("[WebNotebook] Deleted cell $(cell_id_str)")

    broadcast_channel!("notebook", Dict(
        "event" => "cell_deleted",
        "cell_id" => cell_id_str,
        "code" => deleted_code,
        "index" => deleted_index !== nothing ? deleted_index : 0,
        "prev_cell_id" => prev_cell_id
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

"""Handle save request. Routes to notebook save or file save based on tab type."""
function handle_save!(state::WebNotebookState, conn, data)
    tab = active_tab(state)
    if tab.tab_type == :file
        # File tab: save raw content
        content = get(data, "content", nothing)
        if content !== nothing
            tab.file_content = String(content)
            write(tab.path, tab.file_content)
            broadcast_channel!("notebook", Dict(
                "event" => "saved",
                "notebook_path" => tab.path
            ))
            println("[WebNotebook] Saved file: $(tab.path)")
        end
        return
    end

    # Notebook tab: sync codes and save
    nb = active_nb(state)
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

"""Handle save_file action — explicit file content save."""
function handle_save_file!(state::WebNotebookState, conn, data)
    tab = active_tab(state)
    tab.tab_type == :file || return
    content = get(data, "content", nothing)
    content === nothing && return
    tab.file_content = String(content)
    write(tab.path, tab.file_content)
    broadcast_channel!("notebook", Dict(
        "event" => "saved",
        "notebook_path" => tab.path
    ))
    println("[WebNotebook] Saved file: $(tab.path)")
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

"""Handle interrupt request — sends SIGINT to the Malt worker, marks remaining cells as idle."""
function handle_interrupt!(state::WebNotebookState, conn, data)
    if !state.executing
        @warn "[WebNotebook] Interrupt requested but nothing is executing"
        return
    end

    worker = active_worker(state)
    if worker !== nothing
        try
            Malt.interrupt(worker.worker)
            println("[WebNotebook] Interrupted worker")
        catch e
            @warn "[WebNotebook] Interrupt failed" exception=e
        end
    end

    state.executing = false

    # Mark any queued/running cells as idle
    nb = active_nb(state)
    if nb !== nothing
        for cell in ordered_cells(nb)
            if cell.state == cell_queued || cell.state == cell_running
                cell.state = cell_idle
                _update_cell_signal!(cell)
                broadcast_channel!("notebook", Dict(
                    "event" => "cell_state",
                    "cell_id" => string(cell.id),
                    "state" => "cell_idle"
                ))
            end
        end
    end

    # Clear progress and notify clients
    broadcast_channel!("notebook", Dict(
        "event" => "run_progress",
        "running_index" => 0,
        "total" => 0
    ))
    broadcast_channel!("notebook", Dict(
        "event" => "interrupted"
    ))
end

"""Handle format single cell — format code via Runic.jl and broadcast update."""
function handle_format_cell!(state::WebNotebookState, conn, data)
    cell_id_str = get(data, "cell_id", "")
    isempty(cell_id_str) && return

    nb = active_nb(state)
    cell = get_cell(nb, UUID(cell_id_str))
    cell === nothing && return

    original = cell.code
    formatted = format_code(original)
    formatted == original && return  # no change

    cell.code = formatted
    update_topology!(nb)

    broadcast_channel!("notebook", Dict(
        "event" => "cell_formatted",
        "cell_id" => cell_id_str,
        "code" => formatted
    ))
    _broadcast_stale!(state)
    println("[WebNotebook] Formatted cell $cell_id_str")
end

"""Handle format all cells — format every cell via Runic.jl."""
function handle_format_all!(state::WebNotebookState, conn, data)
    nb = active_nb(state)
    cells = ordered_cells(nb)
    changed = 0

    for cell in cells
        original = cell.code
        formatted = format_code(original)
        if formatted != original
            cell.code = formatted
            changed += 1
            broadcast_channel!("notebook", Dict(
                "event" => "cell_formatted",
                "cell_id" => string(cell.id),
                "code" => formatted
            ))
        end
    end

    if changed > 0
        update_topology!(nb)
        _broadcast_stale!(state)
    end
    println("[WebNotebook] Formatted $changed/$(length(cells)) cells")
end

"""Handle bond value change — update bond in worker, re-execute downstream cells."""
function handle_set_bond!(state::WebNotebookState, conn, data)
    bond_name = get(data, "name", "")
    isempty(bond_name) && return
    new_value = get(data, "value", nothing)
    new_value === nothing && return

    nb = active_nb(state)
    worker = active_worker(state)
    name_sym = Symbol(bond_name)

    # Convert value to appropriate type (JSON sends floats)
    val = if new_value isa Float64 && new_value == floor(new_value)
        Int(new_value)
    else
        new_value
    end

    @async begin
        state.executing = true
        try
            # Update bond value in the worker process
            # Build the assignment expression explicitly to avoid nested interpolation issues
            assign_expr = Expr(:(=), name_sym, val)
            Malt.remote_eval_wait(worker.worker, :(Core.eval(_workspace.mod, $(QuoteNode(assign_expr)))))

            # Find the bond cell — look for the cell whose code contains @bind <name>
            bond_cell = nothing
            for cell in ordered_cells(nb)
                # Simple text match: cell code contains "@bind <varname>"
                if contains(cell.code, "@bind $(bond_name)")
                    bond_cell = cell
                    println("[WebNotebook] Found bond cell for :$(bond_name): $(cell.id)")
                    break
                end
            end

            if bond_cell !== nothing
                # Find downstream cells that depend on this bond variable
                deps = try
                    downstream_dependents(nb, [bond_cell])
                catch e
                    @warn "[WebNotebook] downstream_dependents failed" exception=e
                    Cell[]
                end
                println("[WebNotebook] Bond :$(bond_name) = $(val) → $(length(deps)) dependent cells")
                if !isempty(deps)
                    _execute_cells!(state, deps)
                end
            else
                println("[WebNotebook] No bond cell found for :$(bond_name)")
            end
        catch e
            @warn "[WebNotebook] set_bond error" exception=(e, catch_backtrace())
        finally
            state.executing = false
        end
    end
end

# =============================================================================
# Tab management handlers
# =============================================================================

"""Handle open file request — opens as notebook or plain file depending on format."""
function handle_open_notebook!(state::WebNotebookState, conn, data)
    raw_path = get(data, "path", "")
    isempty(raw_path) && return

    # Resolve path
    full_path = if isabspath(raw_path)
        abspath(raw_path)
    else
        _active_dir = let t = active_tab(state)
            dirname(abspath(t.path))
        end
        abspath(joinpath(_active_dir, raw_path))
    end

    !isfile(full_path) && (@warn "[WebNotebook] File not found" path=full_path; return)

    # Check if already open (dedup by absolute path)
    for (i, tab) in enumerate(state.tabs)
        if tab.path == full_path
            state.active_tab_idx = i
            if tab.tab_type == :notebook
                create_cell_signals!(state)
            end
            _broadcast_nb_html!(state)
            return
        end
    end

    # Determine if this is a Pluto notebook or a plain file
    is_nb = endswith(full_path, ".jl") && is_notebook_file(full_path)

    if is_nb
        # Open as notebook (with worker, cell execution, etc.)
        nb = load_notebook(full_path)
        session_data = load_session(session_path(nb.path))
        if session_data !== nothing
            apply_session!(nb, session_data)
        end
        worker = NotebookWorker(; notebook_path=nb.path)
        tab = WebTab(uuid4(), nb, worker, basename(full_path), full_path)
        push!(state.tabs, tab)
        state.active_tab_idx = length(state.tabs)
        _start_tab_watcher!(state, tab)
        create_cell_signals!(state)
        println("[WebNotebook] Opened notebook tab: $(tab.label)")
    else
        # Open as plain file (read-only editor, no execution)
        content = read(full_path, String)
        tab = WebTab(uuid4(), basename(full_path), full_path, content)
        push!(state.tabs, tab)
        state.active_tab_idx = length(state.tabs)
        println("[WebNotebook] Opened file tab: $(tab.label)")
    end

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

    total = if active_tab(state).tab_type == :notebook && active_nb(state) !== nothing
        length(ordered_cells(active_nb(state)))
    else
        0
    end
    broadcast_channel!("notebook", Dict(
        "event" => "nb_replaced",
        "nb_html" => nb_html,
        "total_cells" => total
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

    closed_tab = state.tabs[tab_idx]
    closed_label = closed_tab.label
    # Stop the worker process
    if closed_tab.worker !== nothing
        try stop_worker!(closed_tab.worker) catch; end
    end
    # Stop file watcher
    if closed_tab.watcher !== nothing
        try stop_watching!(closed_tab.watcher) catch; end
    end
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

# =============================================================================
# File Explorer channel handlers (Shoelace sl-tree)
# =============================================================================

"""Determine the file explorer root directory from the active notebook."""
function _explorer_root_dir(state::WebNotebookState)::String
    nb = active_nb(state)
    nb_path = nb.path
    if isfile(nb_path)
        dir = dirname(abspath(nb_path))
        found = dir
        for _ in 1:5
            if isfile(joinpath(dir, "Project.toml")) || isdir(joinpath(dir, "src"))
                found = dir
                break
            end
            parent = dirname(dir)
            parent == dir && break
            dir = parent
        end
        return found
    end
    return isdefined(Main, :USER_CWD) ? Main.USER_CWD : pwd()
end

# Mutable root so navigate_up can change it within a session
const _FILE_EXPLORER_ROOT = Ref("")

"""Get or initialize the file explorer root directory."""
function _get_explorer_root(state::WebNotebookState)::String
    if isempty(_FILE_EXPLORER_ROOT[])
        _FILE_EXPLORER_ROOT[] = _explorer_root_dir(state)
    end
    return _FILE_EXPLORER_ROOT[]
end

"""Render a FileNode as a Shoelace sl-tree-item HTML string (server-side, for lazy loading)."""
function _render_tree_item_html(node::FileNode, active_path::String; root_dir::String="")::String
    esc(s) = replace(replace(replace(replace(s, "&" => "&amp;"), "<" => "&lt;"), ">" => "&gt;"), "\"" => "&quot;")
    esc_path = esc(node.path)

    icon_jl = """<svg width="14" height="14" viewBox="0 0 20 20"><circle cx="10" cy="6" r="2.8" fill="#e06b65"/><circle cx="5.5" cy="14" r="2.8" fill="#56d4a0"/><circle cx="14.5" cy="14" r="2.8" fill="#b08fd8"/></svg>"""
    icon_toml = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><rect x="3" y="3" width="14" height="14" rx="2" stroke="#6b7d93" stroke-width="1.3"/><path d="M7 7h6M7 10h4M7 13h5" stroke="#6b7d93" stroke-width="1.2" stroke-linecap="round"/></svg>"""
    icon_md = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><rect x="2" y="4" width="16" height="12" rx="1.5" stroke="#7bb8e8" stroke-width="1.3"/><path d="M5 13V7l2.5 3L10 7v6M13 10l2-3 2 3M15 7v6" stroke="#7bb8e8" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/></svg>"""
    icon_yml = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><path d="M6 4l4 5.5L14 4M10 9.5V16" stroke="#d4a056" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>"""
    icon_git = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><circle cx="10" cy="10" r="6" stroke="#e06b65" stroke-width="1.3"/><path d="M10 6v4l2.5 2.5" stroke="#e06b65" stroke-width="1.2" stroke-linecap="round"/></svg>"""
    icon_lic = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><rect x="4" y="2" width="12" height="16" rx="1.5" stroke="#d4a056" stroke-width="1.2"/><path d="M7 6h6M7 9h6M7 12h4" stroke="#d4a056" stroke-width="1" stroke-linecap="round"/></svg>"""
    icon_folder = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><path d="M2 5.5A1.5 1.5 0 013.5 4H8l1.5 2h7A1.5 1.5 0 0118 7.5v7a1.5 1.5 0 01-1.5 1.5h-13A1.5 1.5 0 012 14.5v-9z" fill="#3d5068" opacity=".5" stroke="#5a7a99" stroke-width="1"/></svg>"""
    icon_generic = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><path d="M5 2h7l4 4v12a1 1 0 01-1 1H5a1 1 0 01-1-1V3a1 1 0 011-1z" stroke="#4a6178" stroke-width="1.2"/><path d="M12 2v4h4" stroke="#4a6178" stroke-width="1.2"/></svg>"""

    function _icon(ft::Symbol)
        ft === :jl && return icon_jl
        ft === :toml && return icon_toml
        ft === :md && return icon_md
        ft === :yml && return icon_yml
        ft === :git && return icon_git
        ft === :lic && return icon_lic
        return icon_generic
    end

    if node.is_dir
        return string(
            "<sl-tree-item data-is-dir data-path=\"", esc_path, "\"",
            " data-abs-path=\"", esc(joinpath(root_dir, node.path)), "\"",
            " lazy>",
            icon_folder,
            "<span class=\"tree-label\">", esc(node.name), "</span>",
            "</sl-tree-item>"
        )
    else
        icon = _icon(node.file_type)
        selected_attr = (node.path == active_path) ? " selected" : ""
        return string(
            "<sl-tree-item data-path=\"", esc_path, "\"",
            " data-abs-path=\"", esc(joinpath(root_dir, node.path)), "\"",
            " data-file-type=\"", node.file_type, "\"",
            selected_attr, ">",
            icon,
            "<span class=\"tree-label\">", esc(node.name), "</span>",
            "</sl-tree-item>"
        )
    end
end

"""
    setup_file_explorer!(state::WebNotebookState)

Set up WebSocket channel handlers for file explorer operations.
Creates the "file_explorer" channel and registers message handlers for:
list_dir, rename, delete, create_file, create_dir, navigate_up.
"""
function setup_file_explorer!(state::WebNotebookState)
    if !haskey(Therapy.MESSAGE_CHANNELS, "file_explorer")
        create_channel("file_explorer")
    end

    on_channel_message("file_explorer") do conn, data
        action = get(data, "action", "")
        try
            if action == "list_dir"
                _handle_list_dir!(state, conn, data)
            elseif action == "rename"
                _handle_file_rename!(state, conn, data)
            elseif action == "delete"
                _handle_file_delete!(state, conn, data)
            elseif action == "create_file"
                _handle_file_create!(state, conn, data)
            elseif action == "create_dir"
                _handle_dir_create!(state, conn, data)
            elseif action == "navigate_up"
                _handle_navigate_up!(state, conn, data)
            else
                @warn "[FileExplorer] Unknown action" action=action
            end
        catch e
            @warn "[FileExplorer] Handler error" action=action exception=(e, catch_backtrace())
        end
    end
end

"""Validate that a resolved path is safely under root_dir (prevent traversal)."""
function _safe_path(root_dir::String, rel_path::String)::Union{String, Nothing}
    full = abspath(joinpath(root_dir, rel_path))
    startswith(full, abspath(root_dir)) || return nothing
    return full
end

"""Handle lazy-load: list directory contents and send back sl-tree-item HTML."""
function _handle_list_dir!(state::WebNotebookState, conn, data)
    rel_path = get(data, "path", "")
    root_dir = _get_explorer_root(state)
    println("[FileExplorer] list_dir: rel_path=$rel_path root_dir=$root_dir")
    full_path = _safe_path(root_dir, rel_path)
    if full_path === nothing
        println("[FileExplorer] list_dir: path traversal blocked")
        return
    end
    if !isdir(full_path)
        println("[FileExplorer] list_dir: not a directory: $full_path")
        return
    end

    # Build one level of children
    children = _build_tree_recursive(full_path, root_dir, 0, 1)

    # Active notebook path for highlighting
    nb = active_nb(state)
    active_rel = isfile(nb.path) ? relpath(abspath(nb.path), root_dir) : ""

    children_html = IOBuffer()
    for child in children
        write(children_html, _render_tree_item_html(child, active_rel; root_dir=root_dir))
    end

    send_channel!("file_explorer", conn, Dict(
        "event" => "dir_contents",
        "path" => rel_path,
        "children_html" => String(take!(children_html))
    ))
end

"""Handle rename file/directory."""
function _handle_file_rename!(state::WebNotebookState, conn, data)
    rel_path = get(data, "path", "")
    new_name = get(data, "new_name", "")
    isempty(new_name) && return

    root_dir = _get_explorer_root(state)
    old_full = _safe_path(root_dir, rel_path)
    old_full === nothing && return
    (isfile(old_full) || isdir(old_full)) || return

    new_full = joinpath(dirname(old_full), new_name)
    startswith(abspath(new_full), abspath(root_dir)) || return

    # Don't overwrite existing
    (isfile(new_full) || isdir(new_full)) && return

    mv(old_full, new_full)
    new_rel = relpath(new_full, root_dir)

    broadcast_channel!("file_explorer", Dict(
        "event" => "file_renamed",
        "old_path" => rel_path,
        "new_path" => new_rel,
        "new_abs_path" => new_full,
        "new_name" => new_name
    ))
    println("[FileExplorer] Renamed: $rel_path → $new_rel")
end

"""Handle delete file/directory."""
function _handle_file_delete!(state::WebNotebookState, conn, data)
    rel_path = get(data, "path", "")
    root_dir = _get_explorer_root(state)
    full_path = _safe_path(root_dir, rel_path)
    full_path === nothing && return
    full_path == abspath(root_dir) && return  # never delete root

    if isdir(full_path)
        rm(full_path; recursive=true)
    elseif isfile(full_path)
        rm(full_path)
    else
        return
    end

    broadcast_channel!("file_explorer", Dict(
        "event" => "file_deleted",
        "path" => rel_path
    ))
    println("[FileExplorer] Deleted: $rel_path")
end

"""Handle create new file."""
function _handle_file_create!(state::WebNotebookState, conn, data)
    parent_path = get(data, "parent_path", "")
    name = get(data, "name", "")
    isempty(name) && return

    root_dir = _get_explorer_root(state)
    parent_full = _safe_path(root_dir, parent_path)
    parent_full === nothing && return
    isdir(parent_full) || return

    file_full = joinpath(parent_full, name)
    startswith(abspath(file_full), abspath(root_dir)) || return
    isfile(file_full) && return  # already exists

    write(file_full, "")  # create empty file
    file_rel = relpath(file_full, root_dir)
    node = FileNode(name, file_rel, false, FileNode[], _detect_file_type(name))

    broadcast_channel!("file_explorer", Dict(
        "event" => "item_created",
        "parent_path" => parent_path,
        "item_html" => _render_tree_item_html(node, ""; root_dir=root_dir)
    ))
    println("[FileExplorer] Created file: $file_rel")
end

"""Handle create new directory."""
function _handle_dir_create!(state::WebNotebookState, conn, data)
    parent_path = get(data, "parent_path", "")
    name = get(data, "name", "")
    isempty(name) && return

    root_dir = _get_explorer_root(state)
    parent_full = _safe_path(root_dir, parent_path)
    parent_full === nothing && return
    isdir(parent_full) || return

    dir_full = joinpath(parent_full, name)
    startswith(abspath(dir_full), abspath(root_dir)) || return
    isdir(dir_full) && return  # already exists

    mkpath(dir_full)
    dir_rel = relpath(dir_full, root_dir)
    node = FileNode(name, dir_rel, true, FileNode[], :generic)

    broadcast_channel!("file_explorer", Dict(
        "event" => "item_created",
        "parent_path" => parent_path,
        "item_html" => _render_tree_item_html(node, ""; root_dir=root_dir)
    ))
    println("[FileExplorer] Created directory: $dir_rel")
end

"""Handle navigate to parent directory — rebuilds the full tree."""
function _handle_navigate_up!(state::WebNotebookState, conn, data)
    current_root = _get_explorer_root(state)
    parent = dirname(current_root)
    parent == current_root && return  # already at filesystem root

    _FILE_EXPLORER_ROOT[] = parent
    tree = _build_file_tree(parent; max_depth=4)

    nb = active_nb(state)
    active_rel = isfile(nb.path) ? relpath(abspath(nb.path), parent) : ""

    tree_html = IOBuffer()
    write(tree_html, "<sl-tree id=\"file-tree\" selection=\"leaf\" data-root-dir=\"")
    # Escape the root dir for HTML attribute
    for ch in parent
        if ch == '"'
            write(tree_html, "&quot;")
        elseif ch == '&'
            write(tree_html, "&amp;")
        elseif ch == '<'
            write(tree_html, "&lt;")
        else
            write(tree_html, ch)
        end
    end
    write(tree_html, "\">")
    for node in tree
        write(tree_html, _render_tree_item_html(node, active_rel; root_dir=parent))
    end
    write(tree_html, "</sl-tree>")

    broadcast_channel!("file_explorer", Dict(
        "event" => "tree_replaced",
        "tree_html" => String(take!(tree_html)),
        "root_name" => basename(parent),
        "root_dir" => parent
    ))
    println("[FileExplorer] Navigated up to: $parent")
end
