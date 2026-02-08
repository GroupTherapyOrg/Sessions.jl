module Sessions

# =============================================================================
# Dependencies
# =============================================================================

# Core framework - provides reactivity, components, SSR, WebSocket handling
using Therapy

# HTTP server - Sessions needs to handle custom routes
# (Therapy.jl uses HTTP internally but doesn't expose all server utilities)
using HTTP

# Data handling
using JSON3
using UUIDs
using OrderedCollections

# Code analysis for reactive notebooks
using ExpressionExplorer
import Malt
import PlutoDependencyExplorer as PDE

# =============================================================================
# Core Engine
# =============================================================================

include("Engine/Cell.jl")
include("Engine/Notebook.jl")
include("Engine/Output.jl")      # Must come before Worker.jl (defines escape_html)
include("Engine/Reactivity.jl")  # ExpressionExplorer & PDE integration
include("Engine/Workspace.jl")   # Module-based isolation for cell evaluation
include("Engine/Worker.jl")      # Malt worker execution

# =============================================================================
# File Format (Pluto-compatible)
# =============================================================================

include("Engine/FileFormat/Parse.jl")
include("Engine/FileFormat/Write.jl")

# =============================================================================
# Components - Organized into Islands (interactive Wasm) and Server (SSR)
# =============================================================================
#
# Islands: Interactive components compiled to WebAssembly
# - CellEditor.jl: Interactive cell editing (run button, state indicators)
# - DarkModeToggle.jl: Theme toggle with signal-based state
#
# Server: Server-side rendered components
# - Layout.jl: Main application layout with nav, footer
# - CellView.jl: Cell rendering with reactive signal bindings
#
# See SESSIONS-003 in ralph_loop/prd.json for architecture details.
# =============================================================================

# Islands - Interactive Wasm components
include("components/islands/DarkModeToggle.jl")
include("components/islands/CellEditor.jl")

# Server - SSR components (must come after islands for DarkModeToggle)
include("components/server/CellView.jl")
include("components/server/Layout.jl")

# =============================================================================
# Server - Comprehensive Server Module
# =============================================================================
#
# server/server.jl is a comprehensive file containing:
# - Pluto org packages (ExpressionExplorer, PlutoDependencyExplorer, Malt)
# - Therapy WebSocket signal handlers
# - Cell execution logic
# - Notebook state management
#
# See SESSIONS-001 in ralph_loop/prd.json for details.
# =============================================================================

include("server/server.jl")

# FileBrowser component (must come after server.jl for FileEntry type)
include("components/server/FileBrowser.jl")

# Terminal component (SESSIONS-2110)
include("components/server/TerminalPanel.jl")

# Notebook tabs component (SESSIONS-2200)
include("components/server/NotebookTabs.jl")

# Sidebar component with panel switching (SESSIONS-2201)
include("components/server/Sidebar.jl")

# StatusBar component with kernel/git/connection status (SESSIONS-2203)
include("components/server/StatusBar.jl")

# =============================================================================
# Widgets - PlutoUI-compatible widgets for @bind macro
# =============================================================================
#
# These must come after server/server.jl because they extend the bond interface
# functions (initial_value, transform_value, etc.) defined there.
#
# Available widgets:
# - Slider: Range slider for numeric values
# - TextField: Text input for string values
# - CheckBox: Checkbox for boolean values
# - Select: Dropdown for selecting from options
# - NumberField: Numeric input with optional range
#
# See SESSIONS-012 in ralph_loop/prd.json for details.
# =============================================================================

include("components/islands/widgets/Slider.jl")
include("components/islands/widgets/TextField.jl")
include("components/islands/widgets/CheckBox.jl")
include("components/islands/widgets/Select.jl")
include("components/islands/widgets/NumberField.jl")

# =============================================================================
# App Entry Point - Embeddable Therapy.jl Component
# =============================================================================
#
# app.jl provides the NotebookApp component that makes Sessions.jl notebooks
# embeddable in any Therapy.jl application. See SESSIONS-004 in prd.json.
#
# Usage:
#   using Therapy, Sessions
#   Sessions.NotebookApp(notebook_path = "/path/to/notebook.jl")
# =============================================================================

include("app.jl")

# =============================================================================
# Server/App.jl - HTTP Server (standalone mode)
# =============================================================================

include("Server/App.jl")

# =============================================================================
# Public API
# =============================================================================

export Cell, CellState, CellOutput, CellType
export CELL_IDLE, CELL_QUEUED, CELL_RUNNING, CELL_ERROR, CELL_STALE
export Notebook, add_cell!, delete_cell!, move_cell!, get_cell
export analyze_cell!, get_execution_order, get_all_execution_order
export execute_cell!, execute_reactive!, run_all!, cancel_cell!
export load_notebook, save_notebook, is_pluto_notebook

# Dependency tracking (SESSIONS-1902)
export SessionsCell, update_topology!, compute_topology
export get_downstream_cells, get_upstream_cells, get_dependency_info
export has_cycle, detect_and_mark_cycles!

# Workspace API (module-based isolation)
export Workspace, create_workspace, run_cell!, cleanup_variables!
export reset_workspace!, get_variable, set_variable!, is_defined, list_defined

# Phase 2: Smart multi-line cells and Pluto paste
export parse_cell_code, get_executable_code
export parse_pluto_content, is_pluto_content

# Server API
export serve

# App Entry Point (embeddable component)
export NotebookApp, NotebookOptions, notebook_head_extra, init_notebook_server!

# Bond API (@bind macro support)
export @bind, SessionsBond
export initial_value, transform_value, possible_values, validate_value
export create_bond

# PlutoUI-compatible widgets
export Slider, TextField, CheckBox, Select, NumberField

# File browser (SESSIONS-2100)
export FileBrowser, BrowserToolbar, Breadcrumbs, FileList, FileItem, FileContextMenu, ContextMenuItem
export FileEntry, list_directory, format_file_size

# Terminal (SESSIONS-2110)
export TerminalPanel, TerminalTabs, TerminalUISession
export create_terminal_ui_session, get_terminal_ui_session, close_terminal_ui_session!

# Notebook tabs (SESSIONS-2200)
export NotebookTabs, Tab, EmptyTabsState, notebook_tabs_script

# Sidebar (SESSIONS-2201)
export Sidebar, SidebarTabs, SidebarTabButton, RunningPanel, SettingsPanel, RunningItem
export SidebarPanel, PANEL_FILES, PANEL_RUNNING, PANEL_SETTINGS
export sidebar_script, CollapsedSidebar

# StatusBar (SESSIONS-2203)
export StatusBar, KernelStatus, GitStatus, ConnectionStatus, statusbar_script

end # module
