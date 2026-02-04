# TerminalPanel.jl - Terminal UI Component (SSR + Island)
#
# Provides an embedded terminal in Sessions.jl using xterm.js.
# The terminal connects to a server-side PTY via WebSocket channels.
#
# Architecture:
# - SSR renders the container and initial state
# - xterm.js (Island) handles terminal rendering
# - WebSocket channels handle PTY input/output
#
# Reference: architecture.md Section 1.4, 2.4

using Therapy
using UUIDs

# =============================================================================
# Terminal UI State (component-level, separate from server PTY sessions)
# =============================================================================

"""
Terminal UI session state for rendering.
This is separate from the server-side PTY sessions (TERMINAL_SESSIONS in server.jl).
"""
mutable struct TerminalUISession
    id::UUID
    title::String
    active::Bool
    created_at::Float64
end

"""
Registry of terminal UI sessions (for component rendering).
"""
const TERMINAL_UI_SESSIONS = Dict{UUID, TerminalUISession}()

"""
Create a new terminal UI session for rendering.
Note: This only creates the UI state. The actual PTY is created via WebSocket channel.
"""
function create_terminal_ui_session(title::String = "Terminal")
    id = uuid4()
    session = TerminalUISession(id, title, true, time())
    TERMINAL_UI_SESSIONS[id] = session
    return session
end

"""
Get a terminal UI session by ID.
"""
function get_terminal_ui_session(id::UUID)
    return get(TERMINAL_UI_SESSIONS, id, nothing)
end

"""
Close a terminal UI session.
"""
function close_terminal_ui_session!(id::UUID)
    if haskey(TERMINAL_UI_SESSIONS, id)
        TERMINAL_UI_SESSIONS[id].active = false
    end
end

# =============================================================================
# Terminal Panel Component
# =============================================================================

"""
    TerminalPanel(; session_id=nothing, title="Terminal", height="300px")

Render a terminal panel with xterm.js.

# Arguments
- `session_id`: Existing session ID, or creates new session if nothing
- `title`: Terminal title displayed in header
- `height`: CSS height of terminal container

# Example
```julia
# In a layout
Div(:class => "my-workspace",
    NotebookApp(),
    TerminalPanel(title = "Julia REPL")
)
```
"""
function TerminalPanel(;
    session_id::Union{UUID, String, Nothing} = nothing,
    title::String = "Terminal",
    height::String = "300px"
)
    # Resolve or create session
    resolved_id = if session_id isa String
        UUID(session_id)
    elseif session_id === nothing
        session = create_terminal_ui_session(title)
        session.id
    else
        session_id
    end

    id_str = string(resolved_id)

    Div(:class => "terminal-panel border border-stone-200/40 dark:border-neutral-800/40 rounded-lg overflow-hidden shadow-sm",
        Symbol("data-terminal-id") => id_str,

        # Terminal Header - minimal, elegant
        Div(:class => "terminal-header flex items-center justify-between px-3 py-2 bg-stone-100/80 dark:bg-neutral-900/80 border-b border-stone-200/40 dark:border-neutral-800/40",
            # Title with shell icon
            Div(:class => "flex items-center gap-2",
                # Terminal icon
                Svg(:class => "w-3.5 h-3.5 text-stone-400 dark:text-stone-500",
                    :viewBox => "0 0 24 24",
                    :fill => "none",
                    :stroke => "currentColor",
                    Symbol("stroke-width") => "2",
                    Symbol("stroke-linecap") => "round",
                    Symbol("stroke-linejoin") => "round",
                    Path(:d => "M4 17l6-6-6-6"),
                    Path(:d => "M12 19h8")
                ),
                Span(:class => "text-xs font-medium text-stone-600 dark:text-stone-400 tracking-wide", title)
            ),

            # Controls
            Div(:class => "flex items-center gap-1",
                # Clear button
                Button(:class => "p-1 rounded hover:bg-stone-200/50 dark:hover:bg-neutral-800/50 text-stone-400 dark:text-stone-500 hover:text-stone-600 dark:hover:text-stone-300 transition-colors",
                    :onclick => "clearTerminal('$(id_str)')",
                    :title => "Clear terminal",
                    Svg(:class => "w-3.5 h-3.5",
                        :viewBox => "0 0 24 24",
                        :fill => "none",
                        :stroke => "currentColor",
                        Symbol("stroke-width") => "2",
                        Path(:d => "M3 6h18M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2m3 0v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6h14")
                    )
                ),
                # Close button
                Button(:class => "p-1 rounded hover:bg-red-100 dark:hover:bg-red-900/30 text-stone-400 dark:text-stone-500 hover:text-red-600 dark:hover:text-red-400 transition-colors",
                    :onclick => "closeTerminal('$(id_str)')",
                    :title => "Close terminal",
                    Svg(:class => "w-3.5 h-3.5",
                        :viewBox => "0 0 24 24",
                        :fill => "none",
                        :stroke => "currentColor",
                        Symbol("stroke-width") => "2",
                        Path(:d => "M6 18L18 6M6 6l12 12")
                    )
                )
            )
        ),

        # Terminal Container - xterm.js renders here
        Div(:class => "terminal-container bg-neutral-950",
            :id => "terminal-$(id_str)",
            Symbol("data-xterm") => "true",
            Symbol("data-session-id") => id_str,
            :style => "height: $(height); min-height: 200px;",

            # Loading state (shown until xterm.js initializes)
            Div(:class => "flex items-center justify-center h-full text-stone-500 dark:text-stone-600 text-sm",
                :id => "terminal-loading-$(id_str)",
                Span(:class => "animate-pulse", "Initializing terminal...")
            )
        ),

        # Terminal Footer - connection status
        Div(:class => "terminal-footer px-3 py-1 bg-stone-100/80 dark:bg-neutral-900/80 border-t border-stone-200/40 dark:border-neutral-800/40",
            Div(:class => "flex items-center gap-2",
                # Connection indicator
                Span(:class => "w-1.5 h-1.5 rounded-full bg-emerald-500",
                    :id => "terminal-status-$(id_str)",
                    Symbol("data-connected") => "true"
                ),
                Span(:class => "text-[10px] text-stone-400 dark:text-stone-600 tracking-wider uppercase",
                    :id => "terminal-status-text-$(id_str)",
                    "connected"
                )
            )
        )
    )
end

# =============================================================================
# Multiple Terminals Support
# =============================================================================

"""
    TerminalTabs(; sessions=[], active_session=nothing)

Render a tabbed terminal interface for multiple terminal sessions.

# Arguments
- `sessions`: List of TerminalUISession objects
- `active_session`: UUID of the currently active terminal

# Example
```julia
TerminalTabs(
    sessions = [session1, session2],
    active_session = session1.id
)
```
"""
function TerminalTabs(;
    sessions::Vector{TerminalUISession} = TerminalUISession[],
    active_session::Union{UUID, Nothing} = nothing
)
    # Determine active session
    active_id = if active_session !== nothing
        active_session
    elseif !isempty(sessions)
        sessions[1].id
    else
        nothing
    end

    Div(:class => "terminal-tabs",
        # Tab bar
        Div(:class => "flex items-center bg-stone-100/80 dark:bg-neutral-900/80 border-b border-stone-200/40 dark:border-neutral-800/40",
            # Tabs
            Div(:class => "flex-1 flex items-center gap-1 px-2",
                [terminal_tab(s, s.id == active_id) for s in sessions]...
            ),
            # New terminal button
            Button(:class => "p-2 text-stone-400 dark:text-stone-500 hover:text-stone-600 dark:hover:text-stone-300 hover:bg-stone-200/50 dark:hover:bg-neutral-800/50 transition-colors",
                :onclick => "createTerminal()",
                :title => "New terminal",
                Svg(:class => "w-4 h-4",
                    :viewBox => "0 0 24 24",
                    :fill => "none",
                    :stroke => "currentColor",
                    Symbol("stroke-width") => "2",
                    Path(:d => "M12 4v16m8-8H4")
                )
            )
        ),

        # Terminal panels (only active visible)
        Div(:class => "terminal-panels",
            [terminal_panel_hidden(s, s.id == active_id) for s in sessions]...
        )
    )
end

"""
Render a terminal tab.
"""
function terminal_tab(session::TerminalUISession, active::Bool)
    id_str = string(session.id)
    active_class = active ?
        "bg-white dark:bg-neutral-800 border-t-2 border-pluto-blue" :
        "bg-transparent hover:bg-stone-200/50 dark:hover:bg-neutral-800/50"

    Div(:class => "terminal-tab flex items-center gap-2 px-3 py-1.5 text-xs cursor-pointer transition-colors $(active_class)",
        :onclick => "switchTerminal('$(id_str)')",
        Symbol("data-tab-id") => id_str,

        # Terminal icon
        Svg(:class => "w-3 h-3 text-stone-400",
            :viewBox => "0 0 24 24",
            :fill => "none",
            :stroke => "currentColor",
            Symbol("stroke-width") => "2",
            Path(:d => "M4 17l6-6-6-6")
        ),

        # Title
        Span(:class => "text-stone-600 dark:text-stone-300 truncate max-w-[100px]",
            session.title
        ),

        # Close button
        Button(:class => "p-0.5 rounded hover:bg-stone-300/50 dark:hover:bg-neutral-700/50 text-stone-400 hover:text-red-500 transition-colors",
            :onclick => "event.stopPropagation(); closeTerminal('$(id_str)')",
            Svg(:class => "w-3 h-3",
                :viewBox => "0 0 24 24",
                :fill => "none",
                :stroke => "currentColor",
                Symbol("stroke-width") => "2",
                Path(:d => "M6 18L18 6M6 6l12 12")
            )
        )
    )
end

"""
Render a terminal panel (may be hidden if not active).
"""
function terminal_panel_hidden(session::TerminalUISession, active::Bool)
    display = active ? "block" : "none"
    id_str = string(session.id)

    Div(:class => "terminal-panel-wrapper",
        :style => "display: $(display);",
        Symbol("data-panel-id") => id_str,

        # Actual terminal container
        Div(:class => "terminal-container bg-neutral-950",
            :id => "terminal-$(id_str)",
            Symbol("data-xterm") => "true",
            Symbol("data-session-id") => id_str,
            :style => "height: 300px; min-height: 200px;"
        )
    )
end
