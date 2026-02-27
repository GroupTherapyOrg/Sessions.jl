# IDE/TerminalPanel.jl - Sessions.jl IDE Terminal Panel (Suite.jl rewrite)
#
# Bottom panel with embedded terminal using xterm.js.
# Matches the SVG design: collapsible panel at bottom of IDE, warm-* tokens.
#
# Architecture:
# - SSR renders container + header + collapse toggle
# - xterm.js initializes via sessions_script() initTerminal()
# - PTY I/O via WebSocket channels (create_terminal, terminal_input, etc.)
# - Server-side PTY management in server/server.jl (unchanged)
#
# SESSIONS-3601

import Suite

# =============================================================================
# SVG Icon Constants
# =============================================================================

const _TERM_ICON_TERMINAL = "M4 17l6-6-6-6M12 19h8"
const _TERM_ICON_CHEVRON_UP = "M18 15l-6-6-6 6"
const _TERM_ICON_CHEVRON_DOWN = "M6 9l6 6 6-6"
const _TERM_ICON_PLUS = "M12 4v16m8-8H4"
const _TERM_ICON_CLEAR = "M3 6h18M8 6V4h8v2m1 0v14a2 2 0 01-2 2H9a2 2 0 01-2-2V6h10"
const _TERM_ICON_X = "M6 18L18 6M6 6l12 12"

# =============================================================================
# Terminal Panel Header
# =============================================================================

"""
    IDETerminalHeader(; session_id, is_collapsed)

Header bar for the terminal panel with title, collapse toggle, and controls.
"""
function IDETerminalHeader(; session_id::String="default", is_collapsed::Bool=true)
    Div(:class => "flex items-center justify-between h-8 px-3 border-t border-warm-200 dark:border-warm-800 bg-warm-50 dark:bg-warm-950 cursor-pointer select-none",
        :onclick => "toggleTerminalPanel()",
        :id => "terminal-header",

        # Left: Terminal icon + label
        Div(:class => "flex items-center gap-2",
            # Terminal icon
            Svg(:class => "w-3.5 h-3.5 text-warm-500 dark:text-warm-400",
                :viewBox => "0 0 24 24", :fill => "none",
                :stroke => "currentColor", Symbol("stroke-width") => "2",
                Path(:d => _TERM_ICON_TERMINAL)
            ),
            Span(:class => "text-[11px] font-mono text-warm-600 dark:text-warm-400",
                "Terminal"
            ),
            # Keyboard shortcut hint
            Suite.Kbd("Ctrl+`";
                class="text-[9px] text-warm-400 dark:text-warm-500 ml-1"
            )
        ),

        # Right: Controls
        Div(:class => "flex items-center gap-1",
            :onclick => "event.stopPropagation()",

            # New terminal
            Suite.Button(
                Svg(:class => "w-3 h-3", :fill => "none", :viewBox => "0 0 24 24",
                    :stroke => "currentColor", Symbol("stroke-width") => "2",
                    Path(:d => _TERM_ICON_PLUS)
                );
                variant="ghost", size="icon",
                class="h-5 w-5 text-warm-400 hover:text-warm-600 dark:text-warm-500 dark:hover:text-warm-300",
                title="New Terminal",
                kwargs=Dict(:onclick => "createTerminal()")
            ),

            # Clear terminal
            Suite.Button(
                Svg(:class => "w-3 h-3", :fill => "none", :viewBox => "0 0 24 24",
                    :stroke => "currentColor", Symbol("stroke-width") => "2",
                    Path(:d => _TERM_ICON_CLEAR)
                );
                variant="ghost", size="icon",
                class="h-5 w-5 text-warm-400 hover:text-warm-600 dark:text-warm-500 dark:hover:text-warm-300",
                title="Clear Terminal",
                kwargs=Dict(:onclick => "clearTerminal('$(session_id)')")
            ),

            # Close terminal
            Suite.Button(
                Svg(:class => "w-3 h-3", :fill => "none", :viewBox => "0 0 24 24",
                    :stroke => "currentColor", Symbol("stroke-width") => "2",
                    Path(:d => _TERM_ICON_X)
                );
                variant="ghost", size="icon",
                class="h-5 w-5 text-warm-400 hover:text-rose-500 dark:text-warm-500 dark:hover:text-rose-400",
                title="Close Terminal",
                kwargs=Dict(:onclick => "closeTerminal('$(session_id)')")
            ),

            # Collapse/Expand chevron (updated by JS)
            Span(:id => "terminal-collapse-icon",
                :class => "text-warm-400 dark:text-warm-500",
                :onclick => "toggleTerminalPanel()",
                Svg(:class => "w-4 h-4", :fill => "none", :viewBox => "0 0 24 24",
                    :stroke => "currentColor", Symbol("stroke-width") => "2",
                    Path(:d => is_collapsed ? _TERM_ICON_CHEVRON_UP : _TERM_ICON_CHEVRON_DOWN)
                )
            )
        )
    )
end

# =============================================================================
# Terminal Panel Container
# =============================================================================

"""
    IDETerminalPanel(; session_id, height, collapsed)

Complete terminal panel for the Sessions.jl IDE.
Renders at the bottom of the main content area.

Features:
- Collapsible with header click or Ctrl+`
- xterm.js terminal with warm theme (initialized by sessions_script())
- PTY connection via WebSocket channels
- Multiple terminal support via tabs (future)

# Arguments
- `session_id`: Terminal session ID (creates new if "default")
- `height`: Height when expanded (CSS value)
- `collapsed`: Start collapsed (default: true)
"""
function IDETerminalPanel(;
    session_id::String="default",
    height::String="250px",
    collapsed::Bool=true
)
    # Create a terminal UI session if needed
    if session_id == "default"
        session = create_terminal_ui_session("Terminal")
        session_id = string(session.id)
    end

    Div(:id => "terminal-panel",
        :class => "flex-shrink-0 border-t border-warm-200 dark:border-warm-800",
        Symbol("data-terminal-id") => session_id,
        Symbol("data-collapsed") => collapsed ? "true" : "false",

        # Header (always visible)
        IDETerminalHeader(session_id=session_id, is_collapsed=collapsed),

        # Terminal body (hidden when collapsed)
        Div(:id => "terminal-body",
            :class => collapsed ? "hidden" : "",
            :style => "height: $(height);",

            # xterm.js container
            Div(:class => "h-full bg-warm-950 dark:bg-warm-950",
                :id => "terminal-$(session_id)",
                Symbol("data-xterm") => "true",
                Symbol("data-session-id") => session_id,
                :style => "height: 100%;",

                # Loading state (hidden when xterm initializes)
                Div(:class => "flex items-center justify-center h-full text-warm-500 dark:text-warm-600 text-[11px] font-mono",
                    :id => "terminal-loading-$(session_id)",
                    Span(:class => "animate-pulse", "Initializing terminal...")
                )
            )
        )
    )
end

# =============================================================================
# Terminal Panel Script
# =============================================================================

"""
    terminal_panel_script()

Client-side JS for terminal panel collapse/expand and Ctrl+` shortcut.
"""
function terminal_panel_script()
    """
    <script>
    (function() {
        if (window._terminalPanelInitialized) return;
        window._terminalPanelInitialized = true;

        // Toggle terminal panel collapse/expand
        window.toggleTerminalPanel = function() {
            var panel = document.getElementById('terminal-panel');
            var body = document.getElementById('terminal-body');
            var icon = document.getElementById('terminal-collapse-icon');
            if (!panel || !body) return;

            var isCollapsed = panel.getAttribute('data-collapsed') === 'true';

            if (isCollapsed) {
                // Expand
                body.classList.remove('hidden');
                panel.setAttribute('data-collapsed', 'false');
                if (icon) icon.innerHTML = '<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path d="M6 9l6 6 6-6"/></svg>';

                // Initialize terminal if needed
                var containers = body.querySelectorAll('[data-xterm]');
                containers.forEach(function(c) {
                    var sid = c.getAttribute('data-session-id');
                    if (sid && typeof initTerminal === 'function') {
                        // Small delay to let the container become visible
                        setTimeout(function() { initTerminal(sid); }, 100);
                    }
                });

                // Fit terminal after expand
                setTimeout(function() {
                    containers.forEach(function(c) {
                        var sid = c.getAttribute('data-session-id');
                        if (sid && window.terminalInstances && window.terminalInstances[sid]) {
                            window.terminalInstances[sid].fitAddon.fit();
                        }
                    });
                }, 200);
            } else {
                // Collapse
                body.classList.add('hidden');
                panel.setAttribute('data-collapsed', 'true');
                if (icon) icon.innerHTML = '<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path d="M18 15l-6-6-6 6"/></svg>';
            }
        };

        // Ctrl+` keyboard shortcut to toggle terminal
        document.addEventListener('keydown', function(e) {
            if ((e.ctrlKey || e.metaKey) && e.key === '`') {
                e.preventDefault();
                toggleTerminalPanel();
            }
        });
    })();
    </script>
    """
end
