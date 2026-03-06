# TUI: Integrated REPL — multi-tab Julia + Shell with PTY support

"""Single REPL tab — owns a subprocess (Julia or Shell) and its I/O state."""
mutable struct ReplTab
    name::String
    tab_type::Symbol              # :julia or :shell
    process::Union{Base.Process, Nothing}
    proc_in::Union{IO, Nothing}
    proc_out::Union{IO, Nothing}
    output_lines::Vector{String}
    input_buffer::Vector{Char}
    input_cursor::Int
    scroll_offset::Int
    history::Vector{String}
    history_idx::Int
    history_stash::String
    alive::Bool
    read_task::Union{Task, Nothing}
    prompt::String
    repl_mode::Symbol             # :julia, :pkg, :help, :shell (julia tabs only)
    max_scrollback::Int
end

function ReplTab(name::String="Julia", tab_type::Symbol=:julia)
    prompt = tab_type == :shell ? "\$ " : "julia> "
    ReplTab(name, tab_type, nothing, nothing, nothing, String[], Char[], 0, 0,
        String[], 0, "", false, nothing, prompt, :julia, 5000)
end

"""Multi-tab REPL panel."""
mutable struct ReplPanel
    tabs::Vector{ReplTab}
    active_idx::Int
    focused::Bool
    viewport::Tachikoma.Rect
    tab_rects::Vector{Tachikoma.Rect}
    close_rects::Vector{Tachikoma.Rect}
    plus_rect::Tachikoma.Rect            # + (Julia) button
    shell_rect::Tachikoma.Rect           # $ (Shell) button
    next_julia_num::Int
    next_shell_num::Int
end

function ReplPanel()
    ReplPanel(ReplTab[], 0, false, Tachikoma.Rect(),
        Tachikoma.Rect[], Tachikoma.Rect[], Tachikoma.Rect(), Tachikoma.Rect(), 2, 1)
end

"""Get the active REPL tab, or nothing."""
active_tab(panel::ReplPanel) = panel.active_idx >= 1 && panel.active_idx <= length(panel.tabs) ?
    panel.tabs[panel.active_idx] : nothing

"""Convenience: is any tab alive?"""
is_alive(panel::ReplPanel) = (t = active_tab(panel); t !== nothing && t.alive)

# ── Spawning ──────────────────────────────────────────────────────

"""Start a Julia subprocess for a tab."""
function _spawn_julia_tab!(tab::ReplTab, dir::String)
    tab.alive && return

    julia_bin = joinpath(Sys.BINDIR, "julia")
    dir = abspath(dir)
    isdir(dir) || (dir = pwd())

    env = copy(ENV)
    env["TERM"] = "dumb"
    cmd = setenv(`$julia_bin -i --color=yes --banner=short --startup-file=no`, env; dir)

    inp = Pipe()
    out = Pipe()
    proc = Base.run(pipeline(cmd; stdin=inp, stdout=out, stderr=out); wait=false)
    close(out.in)
    close(inp.out)

    tab.process = proc
    tab.proc_in = inp.in
    tab.proc_out = out.out
    tab.alive = true
    tab.output_lines = String[]

    tab.read_task = @async _read_julia_loop!(tab, out.out)
    nothing
end

"""Start a Shell subprocess with PTY via `script` (cross-platform)."""
function _spawn_shell_tab!(tab::ReplTab, dir::String)
    tab.alive && return

    dir = abspath(dir)
    isdir(dir) || (dir = pwd())

    shell = get(ENV, "SHELL", Sys.iswindows() ? "cmd.exe" : "/bin/sh")
    env = copy(ENV)
    env["TERM"] = "xterm-256color"

    # Use `script` to allocate a PTY — syntax differs by platform
    cmd = if Sys.isapple()
        # macOS: script -q /dev/null <shell>
        setenv(`script -q /dev/null $shell`, env; dir)
    elseif Sys.islinux()
        # Linux: script -qfc <shell> /dev/null
        setenv(`script -qfc $shell /dev/null`, env; dir)
    else
        # Fallback: no PTY, just run the shell directly (interactive programs may not work)
        env["TERM"] = "dumb"
        setenv(`$shell`, env; dir)
    end

    inp = Pipe()
    out = Pipe()
    proc = Base.run(pipeline(cmd; stdin=inp, stdout=out, stderr=out); wait=false)
    close(out.in)
    close(inp.out)

    tab.process = proc
    tab.proc_in = inp.in
    tab.proc_out = out.out
    tab.alive = true
    tab.output_lines = String[]

    # Disable shell prompt to reduce noise — we render our own
    # Send after a short delay so shell is ready
    tab.read_task = @async begin
        _init_shell!(tab)
        _read_shell_loop!(tab, out.out)
    end
    nothing
end

"""Send shell init commands to suppress the default prompt and clear."""
function _init_shell!(tab::ReplTab)
    sleep(0.3)  # wait for shell to start
    tab.alive || return
    tab.proc_in === nothing && return
    try
        # Set a minimal prompt and disable right-prompt, then clear
        write(tab.proc_in, "export PS1=''; export PS2=''; export RPS1=''; clear\n")
        flush(tab.proc_in)
        sleep(0.2)
        # Clear any startup noise
        empty!(tab.output_lines)
    catch; end
end

"""Spawn the appropriate subprocess type for a tab."""
function spawn_repl_tab!(tab::ReplTab, dir::String=".")
    if tab.tab_type == :shell
        _spawn_shell_tab!(tab, dir)
    else
        _spawn_julia_tab!(tab, dir)
    end
end

"""Spawn on the panel's active tab."""
function spawn_repl!(panel::ReplPanel, dir::String=".")
    tab = active_tab(panel)
    tab === nothing && return
    spawn_repl_tab!(tab, dir)
end

# ── Output reading ────────────────────────────────────────────────

"""Async loop: read Julia output line by line."""
function _read_julia_loop!(tab::ReplTab, out::IO)
    try
        while tab.alive && !eof(out)
            line = readline(out; keep=false)
            _is_signal_noise(line) && continue
            push!(tab.output_lines, replace(line, '\r' => ""))
            _trim_scrollback!(tab)
        end
    catch e
        e isa EOFError && return
        e isa Base.IOError && return
        @warn "REPL reader error" exception=e
    finally
        tab.alive = false
    end
end

"""Async loop: read Shell output line by line, filtering PTY noise."""
function _read_shell_loop!(tab::ReplTab, out::IO)
    try
        while tab.alive && !eof(out)
            line = readline(out; keep=false)
            _is_signal_noise(line) && continue
            # Clean up line
            cleaned = replace(line, '\r' => "")
            # Filter PTY control noise
            _is_pty_noise(cleaned) && continue
            push!(tab.output_lines, cleaned)
            _trim_scrollback!(tab)
        end
    catch e
        e isa EOFError && return
        e isa Base.IOError && return
        @warn "Shell reader error" exception=e
    finally
        tab.alive = false
    end
end

"""Trim scrollback if over limit."""
function _trim_scrollback!(tab::ReplTab)
    if length(tab.output_lines) > tab.max_scrollback
        excess = length(tab.output_lines) - tab.max_scrollback
        deleteat!(tab.output_lines, 1:excess)
        tab.scroll_offset = max(0, tab.scroll_offset - excess)
    end
end

"""Filter signal termination noise."""
function _is_signal_noise(line::String)
    s = _strip_ansi_simple(line)
    startswith(s, "[") && contains(s, "signal") && return true
    contains(s, "at /usr/lib/system/") && return true
    contains(s, "unknown function (ip:") && return true
    contains(s, "__psynch_cvwait") && return true
    startswith(s, "Allocations:") && return true
    contains(s, "in expression starting at none:") && return true
    false
end

"""Filter PTY/shell prompt noise (escape sequences for prompt rendering, bracket paste, etc.)."""
function _is_pty_noise(line::String)
    s = _strip_ansi_simple(line)
    # Empty after stripping
    stripped = strip(s)
    isempty(stripped) && return false  # keep blank lines from output
    # Shell prompt patterns (zsh %/$ markers)
    stripped == "%" && return true
    # Lines that are just whitespace padding from prompt rendering
    all(c -> c == ' ', s) && return true
    false
end

# ── Input ─────────────────────────────────────────────────────────

"""Send input to the active tab's subprocess."""
function send_input!(panel::ReplPanel, line::String)
    tab = active_tab(panel)
    tab === nothing && return
    _send_input_tab!(tab, line)
end

function _send_input_tab!(tab::ReplTab, line::String)
    tab.alive || return
    tab.proc_in === nothing && return

    if tab.tab_type == :shell
        _send_shell_input!(tab, line)
    else
        _send_julia_input!(tab, line)
    end
end

function _send_julia_input!(tab::ReplTab, line::String)
    prompt_display = _mode_prompt(tab.repl_mode)
    push!(tab.output_lines, prompt_display * line)

    actual_input = if tab.repl_mode == :pkg
        "import Pkg; Pkg.REPLMode.pkgstr(\"$(escape_string(line))\")"
    elseif tab.repl_mode == :help
        "@doc $(line)"
    elseif tab.repl_mode == :shell
        "Base.run(`$(line)`)"
    else
        line
    end

    try
        write(tab.proc_in, actual_input * "\n")
        flush(tab.proc_in)
    catch e
        push!(tab.output_lines, "# REPL disconnected: $(sprint(showerror, e))")
        tab.alive = false
    end

    if tab.repl_mode != :julia
        tab.repl_mode = :julia
        tab.prompt = "julia> "
    end

    _update_history!(tab, line)
end

function _send_shell_input!(tab::ReplTab, line::String)
    # Echo input to transcript with our prompt
    push!(tab.output_lines, "\$ " * line)

    try
        write(tab.proc_in, line * "\n")
        flush(tab.proc_in)
    catch e
        push!(tab.output_lines, "# Shell disconnected: $(sprint(showerror, e))")
        tab.alive = false
    end

    _update_history!(tab, line)
end

function _update_history!(tab::ReplTab, line::String)
    if !isempty(line) && (isempty(tab.history) || tab.history[end] != line)
        push!(tab.history, line)
    end
    tab.history_idx = 0
    tab.history_stash = ""
    tab.scroll_offset = 0
end

"""Stop a single tab's subprocess."""
function stop_repl_tab!(tab::ReplTab)
    tab.alive = false
    if tab.proc_in !== nothing
        try close(tab.proc_in) catch end
        tab.proc_in = nothing
    end
    if tab.process !== nothing
        try kill(tab.process) catch end
        tab.process = nothing
    end
    if tab.proc_out !== nothing
        try close(tab.proc_out) catch end
        tab.proc_out = nothing
    end
    tab.read_task = nothing
end

"""Stop all tabs."""
function stop_repl!(panel::ReplPanel)
    for tab in panel.tabs
        stop_repl_tab!(tab)
    end
end

"""Add a new Julia REPL tab."""
function add_repl_tab!(panel::ReplPanel, dir::String=".")
    name = "Julia $(panel.next_julia_num)"
    panel.next_julia_num += 1
    tab = ReplTab(name, :julia)
    push!(panel.tabs, tab)
    panel.active_idx = length(panel.tabs)
    spawn_repl_tab!(tab, dir)
end

"""Add a new Shell tab with PTY."""
function add_shell_tab!(panel::ReplPanel, dir::String=".")
    name = "Shell $(panel.next_shell_num)"
    panel.next_shell_num += 1
    tab = ReplTab(name, :shell)
    push!(panel.tabs, tab)
    panel.active_idx = length(panel.tabs)
    spawn_repl_tab!(tab, dir)
end

"""Close a tab by index."""
function close_repl_tab!(panel::ReplPanel, idx::Int)
    (idx < 1 || idx > length(panel.tabs)) && return
    stop_repl_tab!(panel.tabs[idx])
    deleteat!(panel.tabs, idx)
    if isempty(panel.tabs)
        panel.active_idx = 0
    elseif panel.active_idx > length(panel.tabs)
        panel.active_idx = length(panel.tabs)
    elseif panel.active_idx > idx
        panel.active_idx -= 1
    end
end

"""Switch to a different tab."""
function switch_repl_tab!(panel::ReplPanel, idx::Int)
    (idx < 1 || idx > length(panel.tabs) || idx == panel.active_idx) && return
    panel.active_idx = idx
end

"""Get the mode-specific prompt string."""
function _mode_prompt(mode::Symbol)
    mode == :pkg    && return "pkg> "
    mode == :help   && return "help?> "
    mode == :shell  && return "shell> "
    return "julia> "
end

# ── Key handling ──────────────────────────────────────────────────

"""Handle a key event when the REPL is focused."""
function handle_repl_key!(panel::ReplPanel, evt::Tachikoma.KeyEvent)
    tab = active_tab(panel)
    tab === nothing && return false

    is_shell = tab.tab_type == :shell

    # Character input
    if evt.key == :char
        c = evt.char
        # Mode switching only for Julia tabs
        if !is_shell && tab.input_cursor == 0 && isempty(tab.input_buffer)
            if c == ']'
                tab.repl_mode = :pkg
                tab.prompt = "pkg> "
                return true
            elseif c == '?'
                tab.repl_mode = :help
                tab.prompt = "help?> "
                return true
            elseif c == ';'
                tab.repl_mode = :shell
                tab.prompt = "shell> "
                return true
            end
        end
        insert!(tab.input_buffer, tab.input_cursor + 1, c)
        tab.input_cursor += 1
        return true
    end

    if evt.key == :ctrl
        if evt.char == 'c'
            if !isempty(tab.input_buffer)
                empty!(tab.input_buffer)
                tab.input_cursor = 0
                if !is_shell
                    tab.repl_mode = :julia
                    tab.prompt = "julia> "
                end
            elseif tab.alive && tab.process !== nothing
                try Base.kill(tab.process, Base.SIGINT) catch end
            end
            return true
        elseif evt.char == 'l'
            empty!(tab.output_lines)
            tab.scroll_offset = 0
            return true
        elseif evt.char == 'a'
            tab.input_cursor = 0
            return true
        elseif evt.char == 'e'
            tab.input_cursor = length(tab.input_buffer)
            return true
        elseif evt.char == 'u'
            deleteat!(tab.input_buffer, 1:tab.input_cursor)
            tab.input_cursor = 0
            return true
        elseif evt.char == 'k'
            if tab.input_cursor < length(tab.input_buffer)
                deleteat!(tab.input_buffer, (tab.input_cursor+1):length(tab.input_buffer))
            end
            return true
        elseif evt.char == 't'
            # Ctrl+T: new Julia tab
            add_repl_tab!(panel, pwd())
            return true
        elseif evt.char == 'w'
            # Ctrl+W: close current tab (if >1)
            if length(panel.tabs) > 1
                close_repl_tab!(panel, panel.active_idx)
            end
            return true
        end
    end

    if evt.key == :enter
        line = String(tab.input_buffer)
        empty!(tab.input_buffer)
        tab.input_cursor = 0
        tab.scroll_offset = 0
        _send_input_tab!(tab, line)
        return true
    end

    if evt.key == :backspace
        if tab.input_cursor > 0
            deleteat!(tab.input_buffer, tab.input_cursor)
            tab.input_cursor -= 1
        elseif !is_shell && isempty(tab.input_buffer) && tab.repl_mode != :julia
            tab.repl_mode = :julia
            tab.prompt = "julia> "
        end
        return true
    end

    if evt.key == :delete
        if tab.input_cursor < length(tab.input_buffer)
            deleteat!(tab.input_buffer, tab.input_cursor + 1)
        end
        return true
    end

    if evt.key == :left
        tab.input_cursor = max(0, tab.input_cursor - 1)
        return true
    end

    if evt.key == :right
        tab.input_cursor = min(length(tab.input_buffer), tab.input_cursor + 1)
        return true
    end

    if evt.key == :home
        tab.input_cursor = 0
        return true
    end

    if evt.key == :end_key
        tab.input_cursor = length(tab.input_buffer)
        return true
    end

    if evt.key == :up
        if tab.history_idx == 0 && !isempty(tab.history)
            tab.history_stash = String(tab.input_buffer)
            tab.history_idx = length(tab.history)
            _load_history_entry!(tab)
        elseif tab.history_idx > 1
            tab.history_idx -= 1
            _load_history_entry!(tab)
        end
        return true
    end

    if evt.key == :down
        if tab.history_idx > 0
            tab.history_idx += 1
            if tab.history_idx > length(tab.history)
                tab.history_idx = 0
                tab.input_buffer = collect(tab.history_stash)
                tab.input_cursor = length(tab.input_buffer)
            else
                _load_history_entry!(tab)
            end
        end
        return true
    end

    if evt.key == :escape
        if !is_shell && tab.repl_mode != :julia
            tab.repl_mode = :julia
            tab.prompt = "julia> "
            return true
        end
        return false
    end

    false
end

"""Load a history entry into the input buffer."""
function _load_history_entry!(tab::ReplTab)
    entry = tab.history[tab.history_idx]
    tab.input_buffer = collect(entry)
    tab.input_cursor = length(tab.input_buffer)
end

"""Handle mouse scroll in the REPL panel."""
function handle_repl_scroll!(panel::ReplPanel, evt::Tachikoma.MouseEvent)
    tab = active_tab(panel)
    tab === nothing && return
    if evt.button == Tachikoma.mouse_scroll_up
        tab.scroll_offset = min(tab.scroll_offset + 3,
            max(0, length(tab.output_lines) - 1))
    elseif evt.button == Tachikoma.mouse_scroll_down
        tab.scroll_offset = max(0, tab.scroll_offset - 3)
    end
end

"""Handle mouse click in the REPL panel (tab bar clicks)."""
function handle_repl_click!(panel::ReplPanel, evt::Tachikoma.MouseEvent)
    evt.button == Tachikoma.mouse_left && evt.action == Tachikoma.mouse_press || return

    # Check + (Julia) button
    pr = panel.plus_rect
    if pr.width > 0 && evt.x >= pr.x && evt.x < pr.x + pr.width && evt.y == pr.y
        add_repl_tab!(panel, pwd())
        return
    end

    # Check $ (Shell) button
    sr = panel.shell_rect
    if sr.width > 0 && evt.x >= sr.x && evt.x < sr.x + sr.width && evt.y == sr.y
        add_shell_tab!(panel, pwd())
        return
    end

    # Check × close buttons
    for (i, cr) in enumerate(panel.close_rects)
        if cr.width > 0 && evt.x >= cr.x && evt.x < cr.x + cr.width && evt.y == cr.y
            if length(panel.tabs) > 1
                close_repl_tab!(panel, i)
            end
            return
        end
    end

    # Check tab label clicks
    for (i, tr) in enumerate(panel.tab_rects)
        if tr.width > 0 && evt.x >= tr.x && evt.x < tr.x + tr.width && evt.y == tr.y
            switch_repl_tab!(panel, i)
            return
        end
    end
end

# ── Rendering ──────────────────────────────────────────────────────

function Tachikoma.render(panel::ReplPanel, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    panel.viewport = rect
    rect.width < 4 && return
    rect.height < 3 && return

    hi = Theme.CELL_H_INSET
    vi = Theme.CELL_V_INSET
    border_fg = panel.focused ? Theme.REPL_INDICATOR : Theme.REPL_BORDER_FG
    border_style = Tachikoma.Style(; fg=border_fg, bg=Theme.REPL_BG)

    # Fill background
    for fy in rect.y:(rect.y + rect.height - 1)
        Tachikoma.set_string!(buf, rect.x, fy, " " ^ rect.width,
            Tachikoma.Style(; bg=Theme.REPL_BG))
    end

    # Border
    bx = rect.x + hi
    by = rect.y + vi
    bw = max(rect.width - 2 * hi, 3)
    bh = max(rect.height - 2 * vi, 3)

    Tachikoma.set_char!(buf, bx, by, '╭', border_style)
    Tachikoma.set_char!(buf, bx + bw - 1, by, '╮', border_style)
    Tachikoma.set_char!(buf, bx, by + bh - 1, '╰', border_style)
    Tachikoma.set_char!(buf, bx + bw - 1, by + bh - 1, '╯', border_style)

    for cx in (bx + 1):(bx + bw - 2)
        Tachikoma.set_char!(buf, cx, by, '─', border_style)
        Tachikoma.set_char!(buf, cx, by + bh - 1, '─', border_style)
    end
    for fy in (by + 1):(by + bh - 2)
        Tachikoma.set_char!(buf, bx, fy, '│', border_style)
        Tachikoma.set_char!(buf, bx + bw - 1, fy, '│', border_style)
    end

    inner_x = bx + 1
    inner_w = bw - 2
    inner_w < 2 && return

    # ── Tab bar row (inside border, first inner row) ──
    has_tabs = length(panel.tabs) > 0
    tab_row_y = by + 1
    panel.tab_rects = Tachikoma.Rect[]
    panel.close_rects = Tachikoma.Rect[]
    panel.plus_rect = Tachikoma.Rect()
    panel.shell_rect = Tachikoma.Rect()

    if has_tabs
        _render_repl_tab_bar!(panel, inner_x, tab_row_y, inner_w, buf)
    end

    # Content area starts after tab bar row
    content_y = tab_row_y + (has_tabs ? 1 : 0)
    content_h = (by + bh - 1) - content_y - 1
    content_h < 2 && return

    tab = active_tab(panel)
    tab === nothing && return

    # ── Input line at bottom of content ──
    input_y = content_y + content_h - 1

    prompt = tab.prompt
    prompt_fg = if tab.tab_type == :shell
        Theme.REPL_SHELL_FG
    elseif tab.repl_mode == :pkg; Theme.REPL_PKG_FG
    elseif tab.repl_mode == :help; Theme.REPL_HELP_FG
    elseif tab.repl_mode == :shell; Theme.REPL_SHELL_FG
    else; Theme.REPL_PROMPT_FG end
    prompt_style = Tachikoma.Style(; fg=prompt_fg, bg=Theme.REPL_BG, bold=true)
    Tachikoma.set_string!(buf, inner_x + 1, input_y, prompt, prompt_style)

    input_x = inner_x + 1 + length(prompt)
    input_text = String(tab.input_buffer)
    max_input_w = inner_w - length(prompt) - 2
    if max_input_w > 0
        visible_start = max(0, tab.input_cursor - max_input_w + 1)
        visible_text = if visible_start > 0
            input_text[nextind(input_text, 0, visible_start+1):end]
        else
            input_text
        end
        if length(visible_text) > max_input_w
            visible_text = first(visible_text, max_input_w)
        end
        Tachikoma.set_string!(buf, input_x, input_y, visible_text, Theme.S_REPL_INPUT)

        if panel.focused
            cursor_screen_x = input_x + tab.input_cursor - visible_start
            if cursor_screen_x >= input_x && cursor_screen_x < input_x + max_input_w
                c = if tab.input_cursor < length(tab.input_buffer)
                    tab.input_buffer[tab.input_cursor + 1]
                else
                    ' '
                end
                Tachikoma.set_char!(buf, cursor_screen_x, input_y, c,
                    Tachikoma.Style(; fg=Theme.BG, bg=Theme.REPL_CURSOR_BG))
            end
        end
    end

    # ── Divider line above input ──
    divider_y = input_y - 1
    if divider_y > content_y
        for cx in inner_x:(inner_x + inner_w - 1)
            Tachikoma.set_char!(buf, cx, divider_y, '─',
                Tachikoma.Style(; fg=Theme.BORDER_DIM, bg=Theme.REPL_BG))
        end
    end

    # ── Output area ──
    output_h = divider_y - content_y
    output_h < 1 && return

    # Filter prompts only for Julia tabs (shell tabs handle their own)
    filtered = tab.tab_type == :julia ? _filter_prompts(tab.output_lines) : tab.output_lines
    n_lines = length(filtered)
    end_idx = max(0, n_lines - tab.scroll_offset)
    start_idx = max(1, end_idx - output_h + 1)

    text_style = Tachikoma.Style(; fg=Theme.FG_DIM, bg=Theme.REPL_BG)

    for row_offset in 0:(output_h - 1)
        line_idx = start_idx + row_offset
        screen_y = content_y + row_offset
        screen_y >= divider_y && break

        if line_idx >= 1 && line_idx <= n_lines
            line = filtered[line_idx]
            styled_segs = _parse_ansi_line(line, text_style)
            x = inner_x + 1
            max_x = inner_x + inner_w - 1
            for seg in styled_segs
                remaining = max_x - x + 1
                remaining <= 0 && break
                text = first(seg.text, remaining)
                Tachikoma.set_string!(buf, x, screen_y, text, seg.style)
                x += length(text)
            end
        end
    end

    # Scroll indicator
    if tab.scroll_offset > 0
        indicator = " ↓$(tab.scroll_offset) "
        ind_x = bx + bw - 1 - length(indicator) - 1
        if ind_x > bx + 2
            Tachikoma.set_string!(buf, ind_x, by + bh - 1, indicator,
                Tachikoma.Style(; fg=Theme.FG_MUTED, bg=Theme.REPL_BG))
        end
    end
end

"""Render the REPL tab bar row inside the panel."""
function _render_repl_tab_bar!(panel::ReplPanel, x::Int, y::Int, w::Int, buf::Tachikoma.Buffer)
    sep_style = Tachikoma.Style(; fg=Theme.BORDER_DIM, bg=Theme.REPL_BG)

    cx = x
    max_x = x + w

    for (i, tab) in enumerate(panel.tabs)
        is_active = (i == panel.active_idx)

        # Tab icon: ⊳ for Julia, $ for Shell
        icon = tab.tab_type == :shell ? "\$" : "⊳"
        label = " $(icon) $(tab.name) "
        close_char = "×"
        tab_w = length(label) + length(close_char) + 1

        cx + tab_w + 1 > max_x && break

        name_fg = is_active ? Theme.FG : Theme.FG_MUTED
        name_style = if is_active
            Tachikoma.Style(; fg=name_fg, bg=Theme.REPL_BG, bold=true)
        else
            Tachikoma.Style(; fg=name_fg, bg=Theme.REPL_BG)
        end
        Tachikoma.set_string!(buf, cx, y, label, name_style)
        push!(panel.tab_rects, Tachikoma.Rect(cx, y, length(label), 1))

        close_x = cx + length(label)
        close_fg = is_active ? Theme.FG_DIM : Theme.FG_FAINT
        Tachikoma.set_string!(buf, close_x, y, close_char,
            Tachikoma.Style(; fg=close_fg, bg=Theme.REPL_BG))
        push!(panel.close_rects, Tachikoma.Rect(close_x, y, 1, 1))

        cx += tab_w

        if i < length(panel.tabs)
            Tachikoma.set_string!(buf, cx, y, "│", sep_style)
            cx += 1
        end
    end

    # + (Julia) and $ (Shell) buttons
    if cx + 5 <= max_x
        cx += 1
        # + button for Julia
        Tachikoma.set_string!(buf, cx, y, "+",
            Tachikoma.Style(; fg=Theme.REPL_PROMPT_FG, bg=Theme.REPL_BG))
        panel.plus_rect = Tachikoma.Rect(cx, y, 1, 1)
        cx += 2

        # $ button for Shell
        Tachikoma.set_string!(buf, cx, y, "\$",
            Tachikoma.Style(; fg=Theme.REPL_SHELL_FG, bg=Theme.REPL_BG))
        panel.shell_rect = Tachikoma.Rect(cx, y, 1, 1)
    end
end

"""Filter out bare prompt lines from julia output."""
function _filter_prompts(lines::Vector{String})
    filtered = String[]
    for line in lines
        stripped = _strip_ansi_simple(line)
        is_prompt = stripped == "julia> " || stripped == "julia>" ||
                    stripped == "pkg> " || stripped == "pkg>" ||
                    stripped == "help?> " || stripped == "help?>" ||
                    stripped == "shell> " || stripped == "shell>"
        is_prompt && continue
        push!(filtered, line)
    end
    filtered
end

"""Simple ANSI stripping (just for prompt detection)."""
function _strip_ansi_simple(s::String)
    replace(s, r"\e\[[0-9;]*[A-Za-z]" => "")
end
