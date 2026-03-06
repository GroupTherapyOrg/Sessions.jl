# TUI: Integrated Julia REPL — pipe-based subprocess with async I/O

"""Integrated Julia REPL panel."""
mutable struct ReplPanel
    process::Union{Base.Process, Nothing}
    proc_in::Union{IO, Nothing}       # write to julia's stdin
    proc_out::Union{IO, Nothing}      # read from julia's stdout+stderr
    output_lines::Vector{String}       # output transcript (raw with ANSI codes)
    input_buffer::Vector{Char}         # current input line
    input_cursor::Int                  # 0-based cursor position in input
    scroll_offset::Int                 # lines scrolled up from bottom
    focused::Bool
    viewport::Tachikoma.Rect
    history::Vector{String}            # input history
    history_idx::Int                   # 0 = current input, 1+ = history
    history_stash::String              # stashed current input when browsing history
    alive::Bool                        # process is running
    read_task::Union{Task, Nothing}    # async output reader
    prompt::String                     # current display prompt
    repl_mode::Symbol                  # :julia, :pkg, :help, :shell
    max_scrollback::Int                # max output lines to keep
end

function ReplPanel()
    ReplPanel(nothing, nothing, nothing, String[], Char[], 0, 0, false, Tachikoma.Rect(),
        String[], 0, "", false, nothing, "julia> ", :julia, 5000)
end

"""Start the Julia subprocess with explicit pipes."""
function spawn_repl!(panel::ReplPanel, dir::String=".")
    panel.alive && return  # already running

    julia_bin = joinpath(Sys.BINDIR, "julia")
    dir = abspath(dir)
    isdir(dir) || (dir = pwd())

    env = copy(ENV)
    env["TERM"] = "dumb"
    cmd = setenv(`$julia_bin -i --color=yes --banner=short --startup-file=no`, env; dir)

    # Use explicit Pipe objects so we get proper read/write ends
    inp = Pipe()
    out = Pipe()
    proc = Base.run(pipeline(cmd; stdin=inp, stdout=out, stderr=out); wait=false)
    close(out.in)   # close write end in parent (subprocess writes to it)
    close(inp.out)   # close read end in parent (subprocess reads from it)

    panel.process = proc
    panel.proc_in = inp.in
    panel.proc_out = out.out
    panel.alive = true
    panel.output_lines = String[]

    # Async output reader — uses blocking readline (not bytesavailable polling)
    panel.read_task = @async _read_output_loop!(panel, out.out, proc)
    nothing
end

"""Async loop: read julia output line by line (blocking readline)."""
function _read_output_loop!(panel::ReplPanel, out::IO, proc::Base.Process)
    try
        while panel.alive && !eof(out)
            line = readline(out; keep=false)
            # Filter signal crash dump lines from kill
            _is_signal_noise(line) && continue
            push!(panel.output_lines, replace(line, '\r' => ""))
            # Trim scrollback
            if length(panel.output_lines) > panel.max_scrollback
                excess = length(panel.output_lines) - panel.max_scrollback
                deleteat!(panel.output_lines, 1:excess)
                panel.scroll_offset = max(0, panel.scroll_offset - excess)
            end
        end
    catch e
        e isa EOFError && return
        e isa Base.IOError && return
        @warn "REPL reader error" exception=e
    finally
        panel.alive = false
    end
end

"""Filter noise from signal termination (crash dump, psynch_cvwait, etc.)."""
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

"""Send a line of input to the Julia subprocess."""
function send_input!(panel::ReplPanel, line::String)
    panel.alive || return
    panel.proc_in === nothing && return

    # Echo input to output transcript
    prompt_display = _mode_prompt(panel.repl_mode)
    push!(panel.output_lines, prompt_display * line)

    # Translate REPL modes to actual Julia code
    actual_input = if panel.repl_mode == :pkg
        "import Pkg; Pkg.REPLMode.pkgstr(\"$(escape_string(line))\")"
    elseif panel.repl_mode == :help
        "@doc $(line)"
    elseif panel.repl_mode == :shell
        "Base.run(`$(line)`)"
    else
        line
    end

    try
        write(panel.proc_in, actual_input * "\n")
        flush(panel.proc_in)
    catch e
        push!(panel.output_lines, "# REPL disconnected: $(sprint(showerror, e))")
        panel.alive = false
    end

    # Reset mode after sending (like the real REPL)
    if panel.repl_mode != :julia
        panel.repl_mode = :julia
        panel.prompt = "julia> "
    end

    # Add to history (skip empty and duplicates)
    if !isempty(line) && (isempty(panel.history) || panel.history[end] != line)
        push!(panel.history, line)
    end
    panel.history_idx = 0
    panel.history_stash = ""

    # Auto-scroll to bottom on new input
    panel.scroll_offset = 0
end

"""Stop the Julia subprocess."""
function stop_repl!(panel::ReplPanel)
    panel.alive = false
    if panel.proc_in !== nothing
        try close(panel.proc_in) catch end
        panel.proc_in = nothing
    end
    if panel.process !== nothing
        try
            kill(panel.process)
        catch; end
        panel.process = nothing
    end
    if panel.proc_out !== nothing
        try close(panel.proc_out) catch end
        panel.proc_out = nothing
    end
    panel.read_task = nothing
end

"""Get the mode-specific prompt string."""
function _mode_prompt(mode::Symbol)
    mode == :pkg    && return "pkg> "
    mode == :help   && return "help?> "
    mode == :shell  && return "shell> "
    return "julia> "
end

"""Handle a key event when the REPL is focused. Returns true if consumed."""
function handle_repl_key!(panel::ReplPanel, evt::Tachikoma.KeyEvent)
    # Character input
    if evt.key == :char
        c = evt.char

        # Mode switching at position 0 with empty buffer
        if panel.input_cursor == 0 && isempty(panel.input_buffer)
            if c == ']'
                panel.repl_mode = :pkg
                panel.prompt = "pkg> "
                return true
            elseif c == '?'
                panel.repl_mode = :help
                panel.prompt = "help?> "
                return true
            elseif c == ';'
                panel.repl_mode = :shell
                panel.prompt = "shell> "
                return true
            end
        end

        insert!(panel.input_buffer, panel.input_cursor + 1, c)
        panel.input_cursor += 1
        return true
    end

    # Ctrl+key combos
    if evt.key == :ctrl
        if evt.char == 'c'
            # Ctrl+C: interrupt or clear input
            if !isempty(panel.input_buffer)
                empty!(panel.input_buffer)
                panel.input_cursor = 0
                panel.repl_mode = :julia
                panel.prompt = "julia> "
            elseif panel.alive && panel.process !== nothing
                try
                    Base.kill(panel.process, Base.SIGINT)
                catch; end
            end
            return true
        elseif evt.char == 'l'
            # Ctrl+L: clear output
            empty!(panel.output_lines)
            panel.scroll_offset = 0
            return true
        elseif evt.char == 'a'
            panel.input_cursor = 0
            return true
        elseif evt.char == 'e'
            panel.input_cursor = length(panel.input_buffer)
            return true
        elseif evt.char == 'u'
            # Ctrl+U: clear line before cursor
            deleteat!(panel.input_buffer, 1:panel.input_cursor)
            panel.input_cursor = 0
            return true
        elseif evt.char == 'k'
            # Ctrl+K: clear line after cursor
            if panel.input_cursor < length(panel.input_buffer)
                deleteat!(panel.input_buffer, (panel.input_cursor+1):length(panel.input_buffer))
            end
            return true
        end
    end

    if evt.key == :enter
        line = String(panel.input_buffer)
        empty!(panel.input_buffer)
        panel.input_cursor = 0
        panel.scroll_offset = 0  # scroll to bottom
        send_input!(panel, line)
        return true
    end

    if evt.key == :backspace
        if panel.input_cursor > 0
            deleteat!(panel.input_buffer, panel.input_cursor)
            panel.input_cursor -= 1
        elseif isempty(panel.input_buffer) && panel.repl_mode != :julia
            # Backspace on empty in special mode → return to julia mode
            panel.repl_mode = :julia
            panel.prompt = "julia> "
        end
        return true
    end

    if evt.key == :delete
        if panel.input_cursor < length(panel.input_buffer)
            deleteat!(panel.input_buffer, panel.input_cursor + 1)
        end
        return true
    end

    if evt.key == :left
        panel.input_cursor = max(0, panel.input_cursor - 1)
        return true
    end

    if evt.key == :right
        panel.input_cursor = min(length(panel.input_buffer), panel.input_cursor + 1)
        return true
    end

    if evt.key == :home
        panel.input_cursor = 0
        return true
    end

    if evt.key == :end_key
        panel.input_cursor = length(panel.input_buffer)
        return true
    end

    if evt.key == :up
        # History navigation — up
        if panel.history_idx == 0 && !isempty(panel.history)
            panel.history_stash = String(panel.input_buffer)
            panel.history_idx = length(panel.history)
            _load_history_entry!(panel)
        elseif panel.history_idx > 1
            panel.history_idx -= 1
            _load_history_entry!(panel)
        end
        return true
    end

    if evt.key == :down
        # History navigation — down
        if panel.history_idx > 0
            panel.history_idx += 1
            if panel.history_idx > length(panel.history)
                # Back to current input
                panel.history_idx = 0
                panel.input_buffer = collect(panel.history_stash)
                panel.input_cursor = length(panel.input_buffer)
            else
                _load_history_entry!(panel)
            end
        end
        return true
    end

    if evt.key == :escape
        # Escape: exit REPL focus (handled by app, but clear mode first)
        if panel.repl_mode != :julia
            panel.repl_mode = :julia
            panel.prompt = "julia> "
            return true
        end
        return false  # let app handle escape
    end

    false
end

"""Load a history entry into the input buffer."""
function _load_history_entry!(panel::ReplPanel)
    entry = panel.history[panel.history_idx]
    panel.input_buffer = collect(entry)
    panel.input_cursor = length(panel.input_buffer)
end

"""Handle mouse scroll in the REPL panel."""
function handle_repl_scroll!(panel::ReplPanel, evt::Tachikoma.MouseEvent)
    if evt.button == Tachikoma.mouse_scroll_up
        panel.scroll_offset = min(panel.scroll_offset + 3,
            max(0, length(panel.output_lines) - 1))
    elseif evt.button == Tachikoma.mouse_scroll_down
        panel.scroll_offset = max(0, panel.scroll_offset - 3)
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

    # Title in top border
    title = panel.alive ? " REPL " : " REPL (stopped) "
    title_x = bx + 2
    if title_x + length(title) < bx + bw - 2
        title_fg = panel.alive ? Theme.REPL_INDICATOR : Theme.FG_MUTED
        Tachikoma.set_string!(buf, title_x, by, title,
            Tachikoma.Style(; fg=title_fg, bg=Theme.REPL_BG, bold=panel.focused))
    end

    inner_x = bx + 1
    inner_y = by + 1
    inner_w = bw - 2
    inner_h = bh - 2
    inner_w < 2 && return
    inner_h < 2 && return

    # ── Input line at bottom ──
    input_y = inner_y + inner_h - 1

    # Prompt
    prompt = panel.prompt
    prompt_fg = if panel.repl_mode == :pkg; Theme.REPL_PKG_FG
    elseif panel.repl_mode == :help; Theme.REPL_HELP_FG
    elseif panel.repl_mode == :shell; Theme.REPL_SHELL_FG
    else; Theme.REPL_PROMPT_FG end
    prompt_style = Tachikoma.Style(; fg=prompt_fg, bg=Theme.REPL_BG, bold=true)
    Tachikoma.set_string!(buf, inner_x + 1, input_y, prompt, prompt_style)

    # Input text
    input_x = inner_x + 1 + length(prompt)
    input_text = String(panel.input_buffer)
    max_input_w = inner_w - length(prompt) - 2
    if max_input_w > 0
        # Scroll input if wider than available space
        visible_start = max(0, panel.input_cursor - max_input_w + 1)
        visible_text = if visible_start > 0
            input_text[nextind(input_text, 0, visible_start+1):end]
        else
            input_text
        end
        if length(visible_text) > max_input_w
            visible_text = first(visible_text, max_input_w)
        end
        Tachikoma.set_string!(buf, input_x, input_y, visible_text, Theme.S_REPL_INPUT)

        # Cursor
        if panel.focused
            cursor_screen_x = input_x + panel.input_cursor - visible_start
            if cursor_screen_x >= input_x && cursor_screen_x < input_x + max_input_w
                c = if panel.input_cursor < length(panel.input_buffer)
                    panel.input_buffer[panel.input_cursor + 1]
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
    if divider_y > inner_y
        for cx in inner_x:(inner_x + inner_w - 1)
            Tachikoma.set_char!(buf, cx, divider_y, '─',
                Tachikoma.Style(; fg=Theme.BORDER_DIM, bg=Theme.REPL_BG))
        end
    end

    # ── Output area (above divider) ──
    output_h = divider_y - inner_y
    output_h < 1 && return

    # Filter out bare prompt lines from julia output (we show our own echo)
    filtered = _filter_prompts(panel.output_lines)

    n_lines = length(filtered)
    # Visible window: show the last `output_h` lines, offset by scroll
    end_idx = max(0, n_lines - panel.scroll_offset)
    start_idx = max(1, end_idx - output_h + 1)

    text_style = Tachikoma.Style(; fg=Theme.FG_DIM, bg=Theme.REPL_BG)

    for row_offset in 0:(output_h - 1)
        line_idx = start_idx + row_offset
        screen_y = inner_y + row_offset
        screen_y >= divider_y && break

        if line_idx >= 1 && line_idx <= n_lines
            line = filtered[line_idx]
            # Parse ANSI and render styled segments
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
    if panel.scroll_offset > 0
        indicator = " ↓$(panel.scroll_offset) "
        ind_x = bx + bw - 1 - length(indicator) - 1
        if ind_x > bx + 2
            Tachikoma.set_string!(buf, ind_x, by + bh - 1, indicator,
                Tachikoma.Style(; fg=Theme.FG_MUTED, bg=Theme.REPL_BG))
        end
    end
end

"""Filter out bare prompt lines from julia output (we render our own prompt)."""
function _filter_prompts(lines::Vector{String})
    filtered = String[]
    for line in lines
        stripped = _strip_ansi_simple(line)
        # Skip bare prompts (julia> , pkg> , help?> , shell> ) with nothing after
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
