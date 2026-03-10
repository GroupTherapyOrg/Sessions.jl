# TUI: Integrated REPL — multi-tab Julia + Shell via Tachikoma TerminalWidget
#
# Each tab owns a TerminalWidget (full VT terminal emulator with PTY).
# The real Julia REPL runs in the subprocess with native tab completion,
# history, mode switching (pkg/help/shell), and ANSI rendering.

"""Single REPL tab — wraps a Tachikoma TerminalWidget subprocess."""
mutable struct ReplTab
    name::String
    tab_type::Symbol              # :julia or :shell
    tw::Union{Tachikoma.TerminalWidget, Nothing}
    alive::Bool
end

function ReplTab(name::String="Julia", tab_type::Symbol=:julia)
    ReplTab(name, tab_type, nothing, false)
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
    _wake_fn::Union{Function, Nothing}   # app-loop wake notification
end

function ReplPanel()
    ReplPanel(ReplTab[], 0, false, Tachikoma.Rect(),
        Tachikoma.Rect[], Tachikoma.Rect[], Tachikoma.Rect(), Tachikoma.Rect(), 2, 1,
        nothing)
end

"""Get the active REPL tab, or nothing."""
active_tab(panel::ReplPanel) = panel.active_idx >= 1 && panel.active_idx <= length(panel.tabs) ?
    panel.tabs[panel.active_idx] : nothing

"""Convenience: is any tab alive?"""
is_alive(panel::ReplPanel) = (t = active_tab(panel); t !== nothing && t.alive)

# ── Spawning ──────────────────────────────────────────────────────

"""Start a Julia subprocess via TerminalWidget."""
function _spawn_julia_tab!(tab::ReplTab, dir::String; rows::Int=24, cols::Int=80, wake_fn=nothing)
    tab.alive && return

    julia_bin = joinpath(Sys.BINDIR, "julia")
    dir = abspath(dir)
    isdir(dir) || (dir = pwd())

    env = Dict{String,String}(k => v for (k, v) in ENV)
    env["TERM"] = "xterm-256color"

    tw = Tachikoma.TerminalWidget(
        [julia_bin, "-i", "--color=yes", "--banner=short", "--startup-file=no"];
        rows, cols, show_scrollbar=true, focused=false, scrollback_limit=5000,
        env,
        on_exit = () -> (tab.alive = false)
    )
    wake_fn !== nothing && Tachikoma.set_wake!(tw, wake_fn)
    tab.tw = tw
    tab.alive = true

    # Set working directory in the Julia subprocess
    Threads.@spawn try
        sleep(0.5)  # wait for REPL to start
        tab.alive || return
        Tachikoma.pty_write(tw.pty, "cd($(repr(dir))); \n")
    catch; end
    nothing
end

"""Start a Shell subprocess via TerminalWidget."""
function _spawn_shell_tab!(tab::ReplTab, dir::String; rows::Int=24, cols::Int=80, wake_fn=nothing)
    tab.alive && return

    dir = abspath(dir)
    isdir(dir) || (dir = pwd())

    shell = get(ENV, "SHELL", "/bin/sh")
    env = Dict{String,String}(k => v for (k, v) in ENV)
    env["TERM"] = "xterm-256color"

    tw = Tachikoma.TerminalWidget(
        [shell];
        rows, cols, show_scrollbar=true, focused=false, scrollback_limit=5000,
        env,
        on_exit = () -> (tab.alive = false)
    )
    wake_fn !== nothing && Tachikoma.set_wake!(tw, wake_fn)
    tab.tw = tw
    tab.alive = true

    # Set working directory in the shell subprocess
    Threads.@spawn try
        sleep(0.3)  # wait for shell to start
        tab.alive || return
        Tachikoma.pty_write(tw.pty, "cd $(repr(dir)) && clear\n")
    catch; end
    nothing
end

"""Spawn the appropriate subprocess type for a tab."""
function spawn_repl_tab!(tab::ReplTab, dir::String="."; rows::Int=24, cols::Int=80, wake_fn=nothing)
    if tab.tab_type == :shell
        _spawn_shell_tab!(tab, dir; rows, cols, wake_fn)
    else
        _spawn_julia_tab!(tab, dir; rows, cols, wake_fn)
    end
end

"""Spawn on the panel's active tab."""
function spawn_repl!(panel::ReplPanel, dir::String="."; rows::Int=24, cols::Int=80)
    tab = active_tab(panel)
    tab === nothing && return
    spawn_repl_tab!(tab, dir; rows, cols, wake_fn=panel._wake_fn)
end

# ── Input ─────────────────────────────────────────────────────────

"""Send input to the active tab's subprocess via PTY."""
function send_input!(panel::ReplPanel, line::String)
    tab = active_tab(panel)
    tab === nothing && return
    tab.tw === nothing && return
    tab.alive || return
    Tachikoma.pty_write(tab.tw.pty, line * "\n")
end

# ── Lifecycle ────────────────────────────────────────────────────

"""Stop a single tab's subprocess."""
function stop_repl_tab!(tab::ReplTab)
    tab.alive = false
    if tab.tw !== nothing
        Tachikoma.close!(tab.tw)
        tab.tw = nothing
    end
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
    spawn_repl_tab!(tab, dir; wake_fn=panel._wake_fn)
end

"""Add a new Shell tab."""
function add_shell_tab!(panel::ReplPanel, dir::String=".")
    name = "Shell $(panel.next_shell_num)"
    panel.next_shell_num += 1
    tab = ReplTab(name, :shell)
    push!(panel.tabs, tab)
    panel.active_idx = length(panel.tabs)
    spawn_repl_tab!(tab, dir; wake_fn=panel._wake_fn)
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

# ── Key handling ──────────────────────────────────────────────────

"""Handle a key event when the REPL is focused.

Panel-level shortcuts (Ctrl+T, Ctrl+W) are intercepted; everything
else is forwarded to the TerminalWidget which encodes it as ANSI
escape sequences and writes to the PTY."""
function handle_repl_key!(panel::ReplPanel, evt::Tachikoma.KeyEvent)
    tab = active_tab(panel)
    tab === nothing && return false

    # Panel-level shortcuts (not forwarded to PTY)
    if evt.key == :ctrl
        if evt.char == 't'
            add_repl_tab!(panel, pwd())
            return true
        elseif evt.char == 'w'
            if length(panel.tabs) > 1
                close_repl_tab!(panel, panel.active_idx)
            end
            return true
        end
    end

    # Forward everything else to the TerminalWidget
    tab.tw === nothing && return false
    tab.tw.focused = panel.focused
    return Tachikoma.handle_key!(tab.tw, evt)
end

"""Handle mouse events in the REPL panel (scroll, clicks)."""
function handle_repl_mouse!(panel::ReplPanel, evt::Tachikoma.MouseEvent)
    tab = active_tab(panel)
    tab === nothing && return
    tab.tw === nothing && return
    Tachikoma.handle_mouse!(tab.tw, evt)
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

    # Content area: TerminalWidget fills the rest
    content_y = tab_row_y + (has_tabs ? 1 : 0)
    content_h = (by + bh - 1) - content_y
    content_h < 1 && return

    tab = active_tab(panel)
    tab === nothing && return
    tab.tw === nothing && return

    # Sync focused state to the terminal widget
    tab.tw.focused = panel.focused

    # Delegate rendering to TerminalWidget
    tw_rect = Tachikoma.Rect(inner_x, content_y, inner_w, content_h)
    Tachikoma.render(tab.tw, tw_rect, buf)
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

    # + button for new Julia tab
    if cx + 3 <= max_x
        cx += 1
        Tachikoma.set_string!(buf, cx, y, "+",
            Tachikoma.Style(; fg=Theme.REPL_PROMPT_FG, bg=Theme.REPL_BG))
        panel.plus_rect = Tachikoma.Rect(cx, y, 1, 1)
    end

    # $ button for new Shell tab
    if cx + 3 <= max_x
        cx += 2
        Tachikoma.set_string!(buf, cx, y, "\$",
            Tachikoma.Style(; fg=Theme.REPL_SHELL_FG, bg=Theme.REPL_BG))
        panel.shell_rect = Tachikoma.Rect(cx, y, 1, 1)
    end
end
