# terminal_server.jl — WebSocket ↔ PTY bridge for xterm.js terminals
#
# Each terminal tab gets its own PTY (shell process). The server bridges
# raw bytes between the PTY output channel and the WebSocket, plus handles
# resize events. Multiple tabs are supported.

using UUIDs

"""A single terminal tab backed by a PTY."""
mutable struct TerminalTab
    id::String
    label::String
    pty::PTY
    relay_task::Union{Task, Nothing}
end

"""Server-side state for all terminal tabs."""
mutable struct TerminalState
    tabs::Vector{TerminalTab}
    active_tab_id::String
    next_num::Int
end

TerminalState() = TerminalState(TerminalTab[], "", 1)

"""Get the default shell command."""
function _default_shell()::Vector{String}
    shell = get(ENV, "SHELL", "/bin/sh")
    [shell, "-l"]  # login shell for proper PATH
end

"""Get working directory from notebook state."""
function _terminal_cwd(web_state)::String
    try
        nb = active_nb(web_state)
        if isfile(nb.path)
            return dirname(abspath(nb.path))
        end
    catch; end
    # Use the directory the user launched from, not the web app's cwd
    return isdefined(Main, :USER_CWD) ? Main.USER_CWD : pwd()
end

"""
    setup_terminal!(term_state::TerminalState, web_state::WebNotebookState)

Set up the 'terminal' WebSocket channel for xterm.js communication.
Handles: spawn, input, resize, close, switch_tab actions.
"""
function setup_terminal!(term_state::TerminalState, web_state::WebNotebookState)
    if !haskey(Therapy.MESSAGE_CHANNELS, "terminal")
        create_channel("terminal")
    end

    on_channel_message("terminal") do conn, data
        action = get(data, "action", "")
        try
            if action == "spawn"
                _handle_terminal_spawn!(term_state, web_state, conn, data)
            elseif action == "input"
                _handle_terminal_input!(term_state, conn, data)
            elseif action == "resize"
                _handle_terminal_resize!(term_state, conn, data)
            elseif action == "close_tab"
                _handle_terminal_close!(term_state, conn, data)
            elseif action == "switch_tab"
                _handle_terminal_switch!(term_state, conn, data)
            elseif action == "list"
                _handle_terminal_list!(term_state, conn, data)
            else
                @warn "[Terminal] Unknown action" action=action
            end
        catch e
            @warn "[Terminal] Handler error" action=action exception=(e, catch_backtrace())
        end
    end
end

"""Spawn a new terminal tab."""
function _handle_terminal_spawn!(term_state::TerminalState, web_state, conn, data)
    rows = get(data, "rows", 24)
    cols = get(data, "cols", 80)
    cwd = _terminal_cwd(web_state)

    # Spawn shell in PTY
    shell_cmd = _default_shell()
    pty = pty_spawn(shell_cmd; rows=rows, cols=cols,
                    env=Dict("TERM" => "xterm-256color"))

    # Set working directory
    pty_write(pty, "cd $(repr(cwd)) && clear\n")

    tab_id = string(uuid4())[1:8]
    num = term_state.next_num
    term_state.next_num += 1
    label = "Terminal $num"

    tab = TerminalTab(tab_id, label, pty, nothing)
    push!(term_state.tabs, tab)
    term_state.active_tab_id = tab_id

    # Start relay: PTY output → WebSocket broadcast
    tab.relay_task = @async _relay_pty_output(tab)

    broadcast_channel!("terminal", Dict(
        "event" => "tab_opened",
        "tab_id" => tab_id,
        "label" => label,
        "tabs" => [Dict("id" => t.id, "label" => t.label, "active" => t.id == tab_id) for t in term_state.tabs]
    ))
    println("[Terminal] Spawned: $label (id=$tab_id, pid=$(pty.child_pid))")
end

"""Relay PTY output bytes to all connected WebSocket clients."""
function _relay_pty_output(tab::TerminalTab)
    pty = tab.pty
    try
        while pty_alive(pty)
            chunk = try
                take!(pty.output)
            catch e
                e isa InvalidStateException && break
                rethrow()
            end
            isempty(chunk) && continue

            # Send raw bytes as base64 (WS text frames can't carry raw bytes cleanly)
            b64 = Base64.base64encode(chunk)
            try
                broadcast_channel!("terminal", Dict(
                    "event" => "output",
                    "tab_id" => tab.id,
                    "data" => b64
                ))
            catch e
                # Channel might be gone during shutdown
                e isa KeyError && break
                rethrow()
            end
        end
    catch e
        e isa InvalidStateException || e isa Base.IOError ||
            @warn "[Terminal] Relay error" tab=tab.label exception=(e, catch_backtrace())
    end

    # Notify clients that this terminal exited
    try
        broadcast_channel!("terminal", Dict(
            "event" => "tab_exited",
            "tab_id" => tab.id
        ))
    catch; end
    println("[Terminal] Process exited: $(tab.label)")
end

"""Handle input from xterm.js (keystrokes)."""
function _handle_terminal_input!(term_state::TerminalState, conn, data)
    tab_id = get(data, "tab_id", term_state.active_tab_id)
    input_b64 = get(data, "data", "")
    isempty(input_b64) && return

    tab = _find_tab(term_state, tab_id)
    tab === nothing && return

    # Decode base64 input and write to PTY
    bytes = Base64.base64decode(input_b64)
    pty_write(tab.pty, bytes)
end

"""Handle terminal resize."""
function _handle_terminal_resize!(term_state::TerminalState, conn, data)
    tab_id = get(data, "tab_id", term_state.active_tab_id)
    rows = get(data, "rows", 24)
    cols = get(data, "cols", 80)

    tab = _find_tab(term_state, tab_id)
    tab === nothing && return

    pty_resize!(tab.pty, rows, cols)
end

"""List existing terminal tabs. Sent to the requesting client only."""
function _handle_terminal_list!(term_state::TerminalState, conn, data)
    # Remove dead terminals
    filter!(t -> pty_alive(t.pty), term_state.tabs)

    # Fix active tab reference if it was removed
    if !isempty(term_state.tabs) && !any(t -> t.id == term_state.active_tab_id, term_state.tabs)
        term_state.active_tab_id = term_state.tabs[end].id
    end

    send_channel!("terminal", conn, Dict(
        "event" => "terminal_list",
        "tabs" => [Dict("id" => t.id, "label" => t.label, "active" => t.id == term_state.active_tab_id) for t in term_state.tabs],
        "active_tab_id" => term_state.active_tab_id
    ))
end

"""Close a terminal tab."""
function _handle_terminal_close!(term_state::TerminalState, conn, data)
    tab_id = get(data, "tab_id", "")
    isempty(tab_id) && return

    idx = findfirst(t -> t.id == tab_id, term_state.tabs)
    idx === nothing && return

    tab = term_state.tabs[idx]
    pty_close!(tab.pty)
    deleteat!(term_state.tabs, idx)

    # Switch to another tab if needed
    if term_state.active_tab_id == tab_id
        term_state.active_tab_id = isempty(term_state.tabs) ? "" : term_state.tabs[end].id
    end

    broadcast_channel!("terminal", Dict(
        "event" => "tab_closed",
        "tab_id" => tab_id,
        "active_tab_id" => term_state.active_tab_id,
        "tabs" => [Dict("id" => t.id, "label" => t.label, "active" => t.id == term_state.active_tab_id) for t in term_state.tabs]
    ))
    println("[Terminal] Closed: $(tab.label)")
end

"""Switch active terminal tab."""
function _handle_terminal_switch!(term_state::TerminalState, conn, data)
    tab_id = get(data, "tab_id", "")
    tab = _find_tab(term_state, tab_id)
    tab === nothing && return

    term_state.active_tab_id = tab_id
    broadcast_channel!("terminal", Dict(
        "event" => "tab_switched",
        "tab_id" => tab_id,
        "tabs" => [Dict("id" => t.id, "label" => t.label, "active" => t.id == tab_id) for t in term_state.tabs]
    ))
end

"""Find a terminal tab by ID."""
function _find_tab(term_state::TerminalState, tab_id::String)::Union{TerminalTab, Nothing}
    idx = findfirst(t -> t.id == tab_id, term_state.tabs)
    idx === nothing ? nothing : term_state.tabs[idx]
end

"""Stop all terminal processes (called on shutdown)."""
function stop_all_terminals!(term_state::TerminalState)
    for tab in term_state.tabs
        try pty_close!(tab.pty) catch; end
    end
    empty!(term_state.tabs)
end
