# channels/terminal.jl — Terminal WebSocket channel handlers
#
# Bridges PTY byte streams to WebSocket clients via Therapy's
# channel API. Handles: spawn, input, resize, close, switch, list.

using UUIDs
import Base64

const TERM_SCROLLBACK_BYTES = 64 * 1024

mutable struct TerminalTab
    id::String
    label::String
    pty::PTY
    relay_task::Union{Task, Nothing}
    scrollback::IOBuffer
end

mutable struct TerminalState
    tabs::Vector{TerminalTab}
    active_tab_id::String
    next_num::Int
end

TerminalState() = TerminalState(TerminalTab[], "", 1)

# ═══════════════════════════════════════════════════════════════
# Broadcast helpers
# ═══════════════════════════════════════════════════════════════

function _term_broadcast!(msg::Dict)
    msg["channel"] = "terminal"
    try; Therapy.broadcast_all(msg); catch; end
end

function _term_send!(conn, msg::Dict)
    msg["channel"] = "terminal"
    try; Therapy.send_ws_message(conn, msg); catch; end
end

# ═══════════════════════════════════════════════════════════════
# Channel registration
# ═══════════════════════════════════════════════════════════════

function setup_terminal_channel!(term_state::TerminalState, web_state)
    Therapy.on_channel_message() do channel, conn, msg
        channel == "terminal" || return
        action = get(msg, "action", "")
        try
            if action == "spawn"
                _handle_terminal_spawn!(term_state, web_state, conn, msg)
            elseif action == "input"
                _handle_terminal_input!(term_state, conn, msg)
            elseif action == "resize"
                _handle_terminal_resize!(term_state, conn, msg)
            elseif action == "close_tab"
                _handle_terminal_close!(term_state, conn, msg)
            elseif action == "switch_tab"
                _handle_terminal_switch!(term_state, conn, msg)
            elseif action == "list"
                _handle_terminal_list!(term_state, conn, msg)
            else
                @warn "[terminal] Unknown action" action=action
            end
        catch e
            @warn "[terminal] Handler error" action=action exception=(e, catch_backtrace())
        end
    end
end

# ═══════════════════════════════════════════════════════════════
# Handlers
# ═══════════════════════════════════════════════════════════════

function _default_shell()::Vector{String}
    shell = get(ENV, "SHELL", "/bin/sh")
    [shell, "-l"]
end

function _terminal_cwd(web_state)::String
    try
        nb = active_nb(web_state)
        if isfile(nb.path)
            return dirname(abspath(nb.path))
        end
    catch; end
    return isdefined(Main, :USER_CWD) ? Main.USER_CWD : pwd()
end

function _handle_terminal_spawn!(term_state::TerminalState, web_state, conn, data)
    rows = get(data, "rows", 24)
    cols = get(data, "cols", 80)
    cwd = _terminal_cwd(web_state)

    shell_cmd = _default_shell()
    pty = pty_spawn(shell_cmd; rows=rows, cols=cols,
                    env=Dict("TERM" => "xterm-256color"))
    pty_write(pty, "cd $(repr(cwd)) && clear\n")

    tab_id = string(uuid4())[1:8]
    num = term_state.next_num
    term_state.next_num += 1
    label = "Terminal $num"

    tab = TerminalTab(tab_id, label, pty, nothing, IOBuffer())
    push!(term_state.tabs, tab)
    term_state.active_tab_id = tab_id

    tab.relay_task = @async _relay_pty_output(tab)

    _term_broadcast!(Dict(
        "event" => "tab_opened",
        "tab_id" => tab_id,
        "label" => label,
        "tabs" => [Dict("id" => t.id, "label" => t.label, "active" => t.id == tab_id) for t in term_state.tabs]
    ))
end

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

            write(tab.scrollback, chunk)
            if tab.scrollback.size > TERM_SCROLLBACK_BYTES
                all_data = take!(tab.scrollback)
                write(tab.scrollback, all_data[max(1, end - TERM_SCROLLBACK_BYTES + 1):end])
            end

            b64 = Base64.base64encode(chunk)
            try
                _term_broadcast!(Dict(
                    "event" => "output",
                    "tab_id" => tab.id,
                    "data" => b64
                ))
            catch e
                e isa KeyError && break
                rethrow()
            end
        end
    catch e
        e isa InvalidStateException || e isa Base.IOError ||
            @warn "[terminal] Relay error" tab=tab.label exception=(e, catch_backtrace())
    end

    try
        _term_broadcast!(Dict("event" => "tab_exited", "tab_id" => tab.id))
    catch; end
end

function _handle_terminal_input!(term_state::TerminalState, conn, data)
    tab_id = get(data, "tab_id", term_state.active_tab_id)
    input_b64 = get(data, "data", "")
    isempty(input_b64) && return

    tab = _find_terminal_tab(term_state, tab_id)
    tab === nothing && return

    bytes = Base64.base64decode(input_b64)
    pty_write(tab.pty, bytes)
end

function _handle_terminal_resize!(term_state::TerminalState, conn, data)
    tab_id = get(data, "tab_id", term_state.active_tab_id)
    rows = get(data, "rows", 24)
    cols = get(data, "cols", 80)

    tab = _find_terminal_tab(term_state, tab_id)
    tab === nothing && return

    pty_resize!(tab.pty, rows, cols)
end

function _handle_terminal_list!(term_state::TerminalState, conn, data)
    filter!(t -> pty_alive(t.pty), term_state.tabs)

    if !isempty(term_state.tabs) && !any(t -> t.id == term_state.active_tab_id, term_state.tabs)
        term_state.active_tab_id = term_state.tabs[end].id
    end

    tabs_data = [Dict(
        "id" => t.id,
        "label" => t.label,
        "active" => t.id == term_state.active_tab_id,
        "scrollback" => Base64.base64encode(copy(t.scrollback.data[1:t.scrollback.size]))
    ) for t in term_state.tabs]

    _term_send!(conn, Dict(
        "event" => "terminal_list",
        "tabs" => tabs_data,
        "active_tab_id" => term_state.active_tab_id
    ))
end

function _handle_terminal_close!(term_state::TerminalState, conn, data)
    tab_id = get(data, "tab_id", "")
    isempty(tab_id) && return

    idx = findfirst(t -> t.id == tab_id, term_state.tabs)
    idx === nothing && return

    tab = term_state.tabs[idx]
    pty_close!(tab.pty)
    deleteat!(term_state.tabs, idx)

    if term_state.active_tab_id == tab_id
        term_state.active_tab_id = isempty(term_state.tabs) ? "" : term_state.tabs[end].id
    end

    _term_broadcast!(Dict(
        "event" => "tab_closed",
        "tab_id" => tab_id,
        "active_tab_id" => term_state.active_tab_id,
        "tabs" => [Dict("id" => t.id, "label" => t.label, "active" => t.id == term_state.active_tab_id) for t in term_state.tabs]
    ))
end

function _handle_terminal_switch!(term_state::TerminalState, conn, data)
    tab_id = get(data, "tab_id", "")
    tab = _find_terminal_tab(term_state, tab_id)
    tab === nothing && return

    term_state.active_tab_id = tab_id
    _term_broadcast!(Dict(
        "event" => "tab_switched",
        "tab_id" => tab_id,
        "tabs" => [Dict("id" => t.id, "label" => t.label, "active" => t.id == tab_id) for t in term_state.tabs]
    ))
end

function _find_terminal_tab(term_state::TerminalState, tab_id::String)::Union{TerminalTab, Nothing}
    idx = findfirst(t -> t.id == tab_id, term_state.tabs)
    idx === nothing ? nothing : term_state.tabs[idx]
end

function stop_all_terminals!(term_state::TerminalState)
    for tab in term_state.tabs
        try pty_close!(tab.pty) catch; end
    end
    empty!(term_state.tabs)
end
