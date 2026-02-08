# IDE/Layout.jl - Sessions.jl IDE Layout (Suite.jl rewrite)
#
# The root layout component for the Sessions.jl IDE.
# Uses Suite.jl components throughout — zero raw HTML for UI structure.
#
# Structure:
#   ┌─────────────────────────────────────────────────┐
#   │  Title Bar: Sessions.jl wordmark + theme toggle  │
#   ├────────┬────────────────────────────────────────┤
#   │  SIDE  │  Tab Bar + Run All                      │
#   │  BAR   │  ─────────────────────────────────────  │
#   │  220px │  Notebook cells                         │
#   │        │                                         │
#   │  FILE  │                                         │
#   │  TREE  │                                         │
#   │        │                                         │
#   │  PKGS  │                                         │
#   │        ├─────────────────────────────────────────┤
#   │ S.jl   │  Terminal panel (collapsible)            │
#   └────────┴─────────────────────────────────────────┘

import Suite

# =============================================================================
# SVG Icons
# =============================================================================

const _HAMBURGER_SVG = Svg(:class => "h-5 w-5", :fill => "none", :viewBox => "0 0 24 24",
    :stroke => "currentColor", :stroke_width => "2",
    Path(:stroke_linecap => "round", :stroke_linejoin => "round",
         :d => "M4 6h16M4 12h16M4 18h16")
)

# =============================================================================
# Sessions.jl Wordmark
# =============================================================================

"""
Sessions.jl wordmark using CSS custom properties for theme-aware colors.
Green is excluded from the wordmark since it's the primary accent.
"""
function SessionsWordmark(; class::String="")
    Span(:class => "flex items-baseline $class",
        Span(:class => "text-lg font-light text-warm-500 dark:text-warm-500", "Sessions"),
        Span(:class => "text-lg font-light",
            Span(:style => "color: var(--jl-dot)", "."),
            Span(:style => "color: var(--jl-j)", "j"),
            Span(:style => "color: var(--jl-l)", "l")
        )
    )
end

# =============================================================================
# Title Bar
# =============================================================================

"""
Title bar with wordmark, theme controls, and mobile hamburger.
"""
function TitleBar(; sidebar_content=nothing)
    Header(:class => "h-9 flex items-center justify-between px-4 bg-warm-50 dark:bg-warm-950 border-b border-warm-200 dark:border-[#252422] flex-shrink-0 z-50",
        # Left: mobile hamburger + wordmark
        Div(:class => "flex items-center gap-2",
            # Mobile sidebar toggle (Sheet)
            sidebar_content !== nothing ?
                Div(:class => "md:hidden",
                    Suite.Sheet(
                        Suite.SheetTrigger(
                            :class => "text-warm-500 hover:text-warm-700 dark:text-warm-400 dark:hover:text-warm-200 p-1",
                            :aria_label => "Open sidebar",
                            _HAMBURGER_SVG
                        ),
                        Suite.SheetContent(side="left",
                            Suite.SheetHeader(
                                Suite.SheetTitle("Sessions.jl"),
                            ),
                            Div(:class => "mt-4",
                                sidebar_content
                            ),
                        ),
                    )
                ) : nothing,
            # Wordmark
            A(:href => "/", :class => "flex items-center",
                SessionsWordmark()
            )
        ),

        # Right: theme controls
        Div(:class => "flex items-center gap-1",
            Suite.ThemeSwitcher(class="hidden sm:inline-flex"),
            Suite.ThemeToggle(),
        )
    )
end

# =============================================================================
# IDE Shell Layout
# =============================================================================

"""
    Layout(content; sidebar=nothing, tabs=nothing, statusbar=nothing, terminal=nothing)

Main IDE layout component for Sessions.jl.

# Arguments
- `content`: Main notebook content area
- `sidebar`: Sidebar component (file tree, packages, etc.)
- `tabs`: Notebook tab bar component
- `statusbar`: Status bar component
- `terminal`: Terminal panel component

# Structure
Uses a flexbox layout with:
- Title bar (fixed top)
- Sidebar (220px, collapsible, hidden on mobile → Sheet)
- Main area with tab bar + content + terminal
- Status bar (fixed bottom)
"""
function Layout(content;
    sidebar=nothing,
    tabs=nothing,
    statusbar=nothing,
    terminal=nothing
)
    Div(:class => "h-screen flex flex-col bg-warm-100 dark:bg-warm-900 overflow-hidden",
        # Title bar
        TitleBar(sidebar_content=sidebar),

        # Main body: sidebar + content
        Div(:class => "flex flex-1 overflow-hidden",
            # Desktop sidebar (hidden on mobile)
            sidebar !== nothing ?
                Aside(:id => "sessions-sidebar",
                    :class => "hidden md:flex md:flex-col w-[220px] flex-shrink-0 bg-warm-50 dark:bg-warm-950 border-r border-warm-200 dark:border-[#252422] overflow-y-auto",
                    sidebar
                ) : nothing,

            # Main content area
            Div(:class => "flex flex-1 flex-col overflow-hidden",
                # Tab bar
                tabs !== nothing ? tabs : nothing,

                # Notebook content (scrollable)
                MainEl(:id => "page-content",
                    :class => "flex-1 overflow-y-auto px-6 py-8",
                    Div(:class => "max-w-4xl mx-auto",
                        content
                    )
                ),

                # Terminal panel (collapsible, at bottom)
                terminal !== nothing ? terminal : nothing,
            )
        ),

        # Status bar (fixed bottom)
        statusbar !== nothing ? statusbar : nothing,

        # Suite.jl Toast notifications
        Suite.Toaster(position="bottom-right"),

        # Suite.jl JS Runtime (theme toggle, interactive components)
        Suite.suite_script()
    )
end

# =============================================================================
# Head Content
# =============================================================================

"""
    sessions_styles()

Head content for Sessions — fonts, CodeMirror, xterm.js CDN links.
Tailwind CSS is handled by Therapy.jl's build system (not CDN).
"""
function sessions_styles()
    """
    <!-- Google Fonts: Serif for headings, Mono for code -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=EB+Garamond:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">

    <!-- CodeMirror 6 via Pluto's pre-bundled setup -->
    <script type="importmap">
    {
        "imports": {
            "codemirror-pluto": "https://cdn.jsdelivr.net/gh/JuliaPluto/codemirror-pluto-setup@0.19.3/dist/index.es.min.js"
        }
    }
    </script>

    <!-- xterm.js for terminal emulation -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.css">
    <script src="https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.8.0/lib/xterm-addon-fit.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/xterm-addon-web-links@0.9.0/lib/xterm-addon-web-links.min.js"></script>
    """
end

# =============================================================================
# Sessions.jl JavaScript Bridge
# =============================================================================

"""
    sessions_script()

Minimal JavaScript bridge for Sessions.jl.

Therapy.jl handles: signals, channels, SPA router, external libraries.
Sessions.jl handles ONLY what Therapy.jl can't:
- Notebook ID context
- Global action functions (runAll, saveNotebook)
- Channel handlers for DOM manipulation (cell_added, cell_deleted)
- Bond event handling (@bind)
- Terminal initialization (xterm.js)
- Paste handler (Pluto notebook import)
"""
function sessions_script()
    """
    <script>
    // Sessions.jl - Minimal bridge (Therapy.jl does the heavy lifting)
    (function() {
        'use strict';

        // Singleton guard for SPA navigation
        if (window._sessionsInitialized) return;
        window._sessionsInitialized = true;

        let notebookId = null;

        // =====================================================================
        // Helpers
        // =====================================================================

        function sendAction(channel, data) {
            if (!data.notebook_id) {
                console.error('[Sessions] notebook_id is null for channel:', channel);
            }
            if (typeof TherapyWS !== 'undefined' && TherapyWS.isConnected()) {
                TherapyWS.sendMessage(channel, data);
            } else {
                console.warn('[Sessions] TherapyWS not connected, cannot send:', channel);
            }
        }

        function getCode(cellId) {
            var cell = document.querySelector('[data-cell-id="' + cellId + '"]');
            if (!cell) return '';
            var container = cell.querySelector('[data-codemirror]');
            if (container && container._cmView) {
                return container._cmView.state.doc.toString();
            }
            var pre = cell.querySelector('.cell-code');
            return pre ? pre.textContent : '';
        }

        // =====================================================================
        // Global API
        // =====================================================================

        window.setNotebookId = function(id) { notebookId = id; };
        window.getNotebookId = function() { return notebookId; };
        window.sendAction = function(channel, data) { return sendAction(channel, data); };

        window.runAll = function() {
            sendAction('run_all', { notebook_id: notebookId });
        };

        window.saveNotebook = function() {
            sendAction('save', { notebook_id: notebookId });
        };

        window.addCell = function(afterId) {
            sendAction('add_cell', { notebook_id: notebookId, after_cell_id: afterId });
        };

        window.addCellAfter = function(afterId, code) {
            var data = { notebook_id: notebookId, after_cell_id: afterId };
            if (code !== undefined && code !== null) data.code = code;
            sendAction('add_cell', data);
        };

        window.deleteCell = function(cellId) {
            if (confirm('Delete this cell?')) {
                sendAction('delete_cell', { notebook_id: notebookId, cell_id: cellId });
            }
        };

        window.executeCell = function(cellId) {
            sendAction('execute', {
                notebook_id: notebookId,
                cell_id: cellId,
                code: getCode(cellId)
            });
        };

        // =====================================================================
        // Bond Handling (@bind macro support)
        // =====================================================================

        function getBondEventType(el) {
            if (el.tagName === 'BUTTON') return 'click';
            if (el.type === 'file') return 'change';
            return 'input';
        }

        function extractBondValue(el) {
            if (el.type === 'range' || el.type === 'number') return el.valueAsNumber;
            if (el.type === 'checkbox') return el.checked;
            if (el.type === 'select-multiple') {
                return Array.from(el.selectedOptions).map(function(o) { return o.value; });
            }
            return el.value;
        }

        function setupBonds(container) {
            var bonds = container.querySelectorAll('bond');
            bonds.forEach(function(bond) {
                if (bond._bondSetup) return;
                bond._bondSetup = true;
                var name = bond.getAttribute('def');
                if (!name) return;
                var input = bond.querySelector('input, select, button, textarea');
                if (!input) return;
                var eventType = getBondEventType(input);
                input.addEventListener(eventType, function() {
                    var value = extractBondValue(input);
                    sendAction('set_bond', {
                        notebook_id: notebookId,
                        name: name,
                        value: value
                    });
                });
            });
        }

        function setupAllBonds() {
            var outputs = document.querySelectorAll('.cell-output');
            outputs.forEach(setupBonds);
        }

        // =====================================================================
        // Channel Handlers (cell_added, cell_deleted)
        // =====================================================================

        function setupChannelHandlers() {
            if (typeof TherapyWS === 'undefined') return;

            TherapyWS.onChannelMessage('cell_added', function(data) {
                var temp = document.createElement('div');
                temp.innerHTML = data.cell_html;
                var newCell = temp.firstElementChild;
                var container = document.querySelector('.cells-container');
                if (!container) return;

                // Animate insertion
                newCell.style.opacity = '0';
                newCell.style.transform = 'translateY(-8px)';

                if (data.after_cell_id) {
                    // Insert after the specified cell's group container
                    var afterCell = container.querySelector('[data-cell-id="' + data.after_cell_id + '"]');
                    if (afterCell) {
                        // Find parent .cell.group container
                        var afterGroup = afterCell.closest('.cell.group') || afterCell;
                        afterGroup.after(newCell);
                    } else {
                        container.appendChild(newCell);
                    }
                } else {
                    container.appendChild(newCell);
                }

                // Smooth fade-in animation
                requestAnimationFrame(function() {
                    newCell.style.transition = 'opacity 0.2s ease, transform 0.2s ease';
                    newCell.style.opacity = '1';
                    newCell.style.transform = 'translateY(0)';
                });

                if (window.TherapyExternalLibs && window.TherapyExternalLibs.reinit) {
                    window.TherapyExternalLibs.reinit();
                }
                if (typeof TherapyWS !== 'undefined' && TherapyWS.discoverAndSubscribe) {
                    TherapyWS.discoverAndSubscribe();
                }

                // Focus the new cell's CodeMirror editor
                setTimeout(function() {
                    var cellId = newCell.getAttribute('data-cell-id') ||
                                 (newCell.querySelector('[data-cell-id]') || {}).getAttribute('data-cell-id');
                    if (cellId) {
                        var cmEl = newCell.querySelector('[data-codemirror]');
                        if (cmEl && cmEl._cmView) {
                            cmEl._cmView.focus();
                        }
                    }
                    // Scroll new cell into view
                    newCell.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }, 100);

                var emptyState = container.querySelector('.text-center.py-20');
                if (emptyState) emptyState.remove();
            });

            TherapyWS.onChannelMessage('cell_deleted', function(data) {
                var cell = document.querySelector('[data-cell-id="' + data.cell_id + '"]');
                if (cell) cell.remove();
            });

            TherapyWS.onChannelMessage('cell_folded', function(data) {
                var cell = document.querySelector('[data-cell-id="' + data.cell_id + '"]');
                if (!cell) return;
                var group = cell.closest('.cell.group') || cell;
                group.setAttribute('data-folded', data.folded ? 'true' : 'false');
                if (data.folded) {
                    group.classList.add('cell-folded');
                } else {
                    group.classList.remove('cell-folded');
                }
            });

            TherapyWS.onChannelMessage('cell_moved', function(data) {
                // Reload to reflect new order (simple approach)
                window.location.reload();
            });

            TherapyWS.onChannelMessage('paste_complete', function(data) {
                if (data.cells_created > 0) {
                    console.log('[Sessions] Pasted ' + data.cells_created + ' cell(s)');
                }
            });
        }

        // =====================================================================
        // File Browser API
        // =====================================================================

        window.navigateToDirectory = function(path) {
            sendAction('navigate_directory', { path: path });
        };

        window.refreshFileBrowser = function() {
            sendAction('refresh_filebrowser', {});
        };

        window.createFile = function(name) {
            var filename = name || prompt('Enter file name:', 'untitled.jl');
            if (filename) sendAction('create_file', { name: filename });
        };

        window.createFolder = function(name) {
            var foldername = name || prompt('Enter folder name:', 'New Folder');
            if (foldername) sendAction('create_folder', { name: foldername });
        };

        window.deleteItem = function(path) {
            if (confirm('Delete this item?')) sendAction('delete_item', { path: path });
        };

        window.renameItem = function(oldPath) {
            var currentName = oldPath.split('/').pop();
            var newName = prompt('Enter new name:', currentName);
            if (newName && newName !== currentName) {
                sendAction('rename_item', { old_path: oldPath, new_name: newName });
            }
        };

        window.openNotebook = function(path) {
            sendAction('open_file', { path: path });
        };

        // =====================================================================
        // Context Menu API
        // =====================================================================

        var contextMenuPath = null;
        var contextMenuIsDirectory = false;
        var contextMenuIsJulia = false;

        window.showContextMenu = function(event, path, isDirectory, isJulia) {
            event.preventDefault();
            event.stopPropagation();
            contextMenuPath = path;
            contextMenuIsDirectory = isDirectory;
            contextMenuIsJulia = isJulia;
            var menu = document.getElementById('file-context-menu');
            if (!menu) return;
            var openItem = document.getElementById('ctx-menu-open');
            var openSeparator = document.getElementById('ctx-menu-separator-open');
            if (openItem && openSeparator) {
                openItem.style.display = (isJulia || isDirectory) ? 'block' : 'none';
                openSeparator.style.display = (isJulia || isDirectory) ? 'block' : 'none';
            }
            menu.classList.remove('hidden');
            menu.style.visibility = 'hidden';
            menu.style.left = event.clientX + 'px';
            menu.style.top = event.clientY + 'px';
            var rect = menu.getBoundingClientRect();
            if (rect.right > window.innerWidth) menu.style.left = (window.innerWidth - rect.width - 10) + 'px';
            if (rect.bottom > window.innerHeight) menu.style.top = (window.innerHeight - rect.height - 10) + 'px';
            menu.style.visibility = 'visible';
        };

        window.hideContextMenu = function() {
            var menu = document.getElementById('file-context-menu');
            if (menu) menu.classList.add('hidden');
            contextMenuPath = null;
        };

        window.contextMenuOpen = function() {
            hideContextMenu();
            if (contextMenuPath) {
                if (contextMenuIsDirectory) navigateToDirectory(contextMenuPath);
                else if (contextMenuIsJulia) openNotebook(contextMenuPath);
            }
        };
        window.contextMenuRename = function() { hideContextMenu(); if (contextMenuPath) renameItem(contextMenuPath); };
        window.contextMenuDelete = function() { hideContextMenu(); if (contextMenuPath) deleteItem(contextMenuPath); };
        window.contextMenuCopyPath = function() {
            hideContextMenu();
            if (contextMenuPath) {
                navigator.clipboard.writeText(contextMenuPath).catch(function(err) {
                    prompt('Copy this path:', contextMenuPath);
                });
            }
        };

        document.addEventListener('click', function(e) {
            var menu = document.getElementById('file-context-menu');
            if (menu && !menu.contains(e.target)) hideContextMenu();
        });
        document.addEventListener('keydown', function(e) {
            if (e.key === 'Escape') hideContextMenu();
        });

        // =====================================================================
        // Terminal API
        // =====================================================================

        window.terminalInstances = window.terminalInstances || {};
        var terminalInstances = window.terminalInstances;

        window.initTerminal = function(sessionId) {
            var container = document.getElementById('terminal-' + sessionId);
            if (!container || !container.hasAttribute('data-xterm')) return null;
            if (terminalInstances[sessionId]) return terminalInstances[sessionId];
            if (typeof Terminal === 'undefined') return null;

            var isDark = document.documentElement.classList.contains('dark');
            var term = new Terminal({
                fontFamily: "var(--font-mono, 'JuliaMono', 'SF Mono', 'Fira Code', monospace)",
                fontSize: 13,
                lineHeight: 1.5,
                cursorBlink: true,
                cursorStyle: 'bar',
                theme: isDark ? {
                    background: '#111110',
                    foreground: '#d4d0c8',
                    cursor: '#389826',
                    selectionBackground: 'rgba(56, 152, 38, 0.3)',
                    black: '#1a1918', red: '#cb3c33', green: '#389826',
                    yellow: '#f0c674', blue: '#4063d8', magenta: '#9558b2',
                    cyan: '#7dd3e8', white: '#d4d0c8',
                    brightBlack: '#5a5855', brightRed: '#e8a0a0',
                    brightGreen: '#56b648', brightYellow: '#f8d898',
                    brightBlue: '#6889f2', brightMagenta: '#c9a0dc',
                    brightCyan: '#98e0f0', brightWhite: '#f8f7f4'
                } : {
                    background: '#f8f7f4',
                    foreground: '#2c2a28',
                    cursor: '#389826',
                    selectionBackground: 'rgba(56, 152, 38, 0.2)',
                    black: '#2c2a28', red: '#cb3c33', green: '#389826',
                    yellow: '#b8860b', blue: '#4063d8', magenta: '#9558b2',
                    cyan: '#0077aa', white: '#f8f7f4',
                    brightBlack: '#8a8680', brightRed: '#e8a0a0',
                    brightGreen: '#56b648', brightYellow: '#f0c674',
                    brightBlue: '#6889f2', brightMagenta: '#c9a0dc',
                    brightCyan: '#7dd3e8', brightWhite: '#ffffff'
                }
            });

            var fitAddon = null;
            if (typeof FitAddon !== 'undefined') {
                fitAddon = new FitAddon.FitAddon();
                term.loadAddon(fitAddon);
            }
            if (typeof WebLinksAddon !== 'undefined') {
                term.loadAddon(new WebLinksAddon.WebLinksAddon());
            }

            var loading = document.getElementById('terminal-loading-' + sessionId);
            if (loading) loading.remove();

            term.open(container);
            if (fitAddon) { try { fitAddon.fit(); } catch (e) {} }

            var resizeHandler = function() {
                if (fitAddon) {
                    try {
                        fitAddon.fit();
                        sendAction('terminal_resize', {
                            session_id: sessionId, cols: term.cols, rows: term.rows
                        });
                    } catch (e) {}
                }
            };
            window.addEventListener('resize', resizeHandler);

            term.onData(function(data) {
                sendAction('terminal_input', { session_id: sessionId, data: data });
            });

            terminalInstances[sessionId] = { term: term, fitAddon: fitAddon, resizeHandler: resizeHandler };

            if (typeof TherapyWS !== 'undefined') {
                TherapyWS.onChannelMessage('terminal_output_' + sessionId, function(data) {
                    if (data.output) term.write(data.output);
                });
            }

            sendAction('create_terminal', { session_id: sessionId, cols: term.cols, rows: term.rows });
            term.writeln('\\x1b[2mConnecting to server...\\x1b[0m');
            return terminalInstances[sessionId];
        };

        function initAllTerminals() {
            var containers = document.querySelectorAll('[data-xterm]');
            containers.forEach(function(container) {
                var sessionId = container.getAttribute('data-session-id');
                if (sessionId && !terminalInstances[sessionId]) initTerminal(sessionId);
            });
        }

        window.clearTerminal = function(sessionId) {
            var inst = terminalInstances[sessionId];
            if (inst && inst.term) inst.term.clear();
        };

        window.closeTerminal = function(sessionId) {
            var inst = terminalInstances[sessionId];
            if (inst) {
                sendAction('close_terminal', { session_id: sessionId });
                if (inst.resizeHandler) window.removeEventListener('resize', inst.resizeHandler);
                if (inst.term) inst.term.dispose();
                delete terminalInstances[sessionId];
            }
            var panel = document.querySelector('[data-terminal-id="' + sessionId + '"]');
            if (panel) panel.remove();
        };

        window.createTerminal = function(title) {
            sendAction('new_terminal', { title: title || 'Terminal' });
        };

        window.switchTerminal = function(sessionId) {
            var panels = document.querySelectorAll('.terminal-panel-wrapper');
            panels.forEach(function(p) { p.style.display = 'none'; });
            var selected = document.querySelector('[data-panel-id="' + sessionId + '"]');
            if (selected) selected.style.display = 'block';
            var tabs = document.querySelectorAll('.terminal-tab');
            tabs.forEach(function(tab) {
                var isActive = tab.getAttribute('data-tab-id') === sessionId;
                tab.classList.toggle('sessions-terminal-tab-active', isActive);
            });
            var inst = terminalInstances[sessionId];
            if (inst && inst.fitAddon) {
                setTimeout(function() { try { inst.fitAddon.fit(); } catch (e) {} }, 50);
            }
        };

        // =====================================================================
        // Sidebar Panel Switching
        // =====================================================================

        function getSidebarState() {
            try {
                var state = localStorage.getItem('sessions-sidebar-state');
                return state ? JSON.parse(state) : { collapsed: false, panel: 'files' };
            } catch (e) { return { collapsed: false, panel: 'files' }; }
        }

        function saveSidebarState(state) {
            try { localStorage.setItem('sessions-sidebar-state', JSON.stringify(state)); } catch (e) {}
        }

        window.toggleSidebar = function() {
            var sidebar = document.getElementById('sessions-sidebar');
            if (!sidebar) return;
            var state = getSidebarState();
            state.collapsed = !state.collapsed;
            saveSidebarState(state);
            sidebar.classList.toggle('hidden', state.collapsed);
        };

        window.switchSidebarPanel = function(panelName) {
            var state = getSidebarState();
            state.panel = panelName;
            saveSidebarState(state);
            // Panels are toggled via data attributes
            var panels = document.querySelectorAll('[data-sidebar-panel]');
            panels.forEach(function(p) {
                p.classList.toggle('hidden', p.getAttribute('data-sidebar-panel') !== panelName);
            });
            var tabs = document.querySelectorAll('[data-sidebar-tab]');
            tabs.forEach(function(tab) {
                var isActive = tab.getAttribute('data-sidebar-tab') === panelName;
                tab.classList.toggle('sessions-sidebar-tab-active', isActive);
            });
        };

        // =====================================================================
        // Notebook Tab Management
        // =====================================================================

        window.switchTab = function(nbId) {
            sendAction('switch_notebook', { notebook_id: nbId });
        };

        window.closeTab = function(nbId) {
            var tabEl = document.querySelector('[data-tab-id="' + nbId + '"]');
            var hasUnsaved = tabEl && tabEl.querySelector('.bg-amber-500, .bg-amber-400');
            if (hasUnsaved && !confirm('This notebook has unsaved changes. Close anyway?')) return;
            sendAction('close_notebook', { notebook_id: nbId });
        };

        window.createNewNotebook = function() {
            sendAction('create_notebook', {});
        };

        function updateActiveTab(nbId) {
            var tabs = document.querySelectorAll('.notebook-tab');
            tabs.forEach(function(tab) {
                var isActive = tab.getAttribute('data-tab-id') === nbId;
                tab.classList.toggle('sessions-tab-active', isActive);
                tab.classList.toggle('sessions-tab-inactive', !isActive);
            });
            if (typeof setNotebookId === 'function') setNotebookId(nbId);
        }

        function setupTabChannelHandlers() {
            if (typeof TherapyWS === 'undefined') return;
            TherapyWS.onChannelMessage('notebook_switched', function(data) {
                updateActiveTab(data.notebook_id);
                window.location.reload();
            });
            TherapyWS.onChannelMessage('notebook_closed', function() {});
            TherapyWS.onChannelMessage('notebook_created', function() {});
            TherapyWS.onChannelMessage('notebook_opened', function() {});
        }

        // =====================================================================
        // Paste Handler
        // =====================================================================

        function setupPasteHandler() {
            document.addEventListener('paste', function(e) {
                var activeEl = document.activeElement;
                if (activeEl && (activeEl.closest('.cm-editor') ||
                    activeEl.tagName === 'TEXTAREA' || activeEl.tagName === 'INPUT')) return;
                if (!e.target.closest('.cells-container, #page-content, main')) return;
                var text = e.clipboardData && e.clipboardData.getData('text/plain');
                if (!text || text.trim().length === 0) return;
                var isPluto = text.indexOf('### A Pluto.jl notebook ###') !== -1;
                var isMultiLine = text.indexOf('\\n') !== -1 || text.split('\\n').length > 3;
                if (!isPluto && !isMultiLine) return;
                e.preventDefault();
                var cells = document.querySelectorAll('.cell');
                var lastCell = cells.length > 0 ? cells[cells.length - 1] : null;
                sendAction('paste_content', {
                    notebook_id: notebookId,
                    content: text,
                    after_cell_id: lastCell ? lastCell.dataset.cellId : null
                });
            });
        }

        // =====================================================================
        // Initialization
        // =====================================================================

        function init() {
            setupChannelHandlers();
            setupTabChannelHandlers();
            setupPasteHandler();
            setupAllBonds();
            initAllTerminals();

            // Watch for cell output changes (bond setup)
            if (!window._sessionsBondObserver) {
                window._sessionsBondObserver = new MutationObserver(function(mutations) {
                    mutations.forEach(function(mutation) {
                        if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
                            var target = mutation.target;
                            if (target.classList && target.classList.contains('cell-output')) {
                                setupBonds(target);
                            }
                            mutation.addedNodes.forEach(function(node) {
                                if (node.nodeType === 1) {
                                    if (node.classList && node.classList.contains('cell-output')) setupBonds(node);
                                    if (node.querySelectorAll) {
                                        var bonds = node.querySelectorAll('bond');
                                        if (bonds.length > 0) setupBonds(node);
                                    }
                                }
                            });
                        }
                    });
                });
                window._sessionsBondObserver.observe(document.body, { childList: true, subtree: true });
            }
        }

        function waitForWS() {
            if (typeof TherapyWS !== 'undefined') {
                init();
            } else {
                setTimeout(waitForWS, 100);
            }
        }

        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', waitForWS);
        } else {
            waitForWS();
        }

        window.addEventListener('therapy:router:loaded', init);
    })();
    </script>
    """
end

# =============================================================================
# Complete Head Extra
# =============================================================================

"""
    sessions_head_extra()

Get complete head content for render_page.
Includes: Suite.jl theme script (FOUC prevention), styles, WebSocket client,
client router (SPA), external libraries, and Sessions.jl JS bridge.
"""
function sessions_head_extra()
    # Register CodeMirror with Therapy.jl's external library pattern
    register_codemirror_pluto()

    # Suite.jl FOUC prevention (must be in <head>)
    theme_script = render_to_string(Suite.suite_theme_script())

    # WebSocket client script
    ws_script = websocket_client_script()
    ws_str = ws_script isa Therapy.RawHtml ? ws_script.content : string(ws_script)

    # Client-side router for SPA navigation
    router_script = client_router_script(content_selector="#page-content")
    router_str = router_script isa Therapy.RawHtml ? router_script.content : render_to_string(router_script)

    # External libraries (CodeMirror initialization)
    ext_libs = external_library_script()
    ext_libs_str = ext_libs isa Therapy.RawHtml ? ext_libs.content : render_to_string(ext_libs)

    theme_script * sessions_styles() * codemirror_sessions_theme() * cell_state_styles() * markdown_styles() * output_styles() * ws_str * router_str * ext_libs_str * sessions_script() * file_browser_script()
end
