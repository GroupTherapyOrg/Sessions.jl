# FileExplorer.jl — File tree panel content (SSR)
#
# Renders the file tree and status bar for the sidebar panel.
# The panel wrapper (border, header) is in SessionsApp.jl.
# Uses the Sessions.jl color palette: deep/base/surf/island/hov + b1/b2 + t1-t4 + accent.

# --- SVG icon strings ---

const _ICON_JULIA = """<svg width="14" height="14" viewBox="0 0 20 20"><circle cx="10" cy="6" r="2.8" fill="#e06b65"/><circle cx="5.5" cy="14" r="2.8" fill="#56d4a0"/><circle cx="14.5" cy="14" r="2.8" fill="#b08fd8"/></svg>"""

const _ICON_TOML = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><rect x="3" y="3" width="14" height="14" rx="2" stroke="#6b7d93" stroke-width="1.3"/><path d="M7 7h6M7 10h4M7 13h5" stroke="#6b7d93" stroke-width="1.2" stroke-linecap="round"/></svg>"""

const _ICON_GENERIC = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><path d="M5 2h7l4 4v12a1 1 0 01-1 1H5a1 1 0 01-1-1V3a1 1 0 011-1z" stroke="#4a6178" stroke-width="1.2"/><path d="M12 2v4h4" stroke="#4a6178" stroke-width="1.2"/></svg>"""

const _ICON_STATUS_OK = """<svg width="7" height="7"><circle cx="3.5" cy="3.5" r="3.5" fill="#56d4a0"/></svg>"""

# Modified dot indicator (green circle)
const _ICON_MODIFIED = """<svg width="6" height="6" class="shrink-0"><circle cx="3" cy="3" r="3" fill="#56d4a0"/></svg>"""

"""
    FileExplorer()

Render the file tree content and bottom status bar.
Reads notebook state from `Main.WEB_STATE` to show the .jl file and its .sessions.toml companion.
"""
function FileExplorer()
    state = if isdefined(Main, :WEB_STATE) && Main.WEB_STATE[] !== nothing
        Main.WEB_STATE[]
    else
        nothing
    end

    nb_name = state !== nothing ? basename(state.nb.path) : "Untitled.jl"
    toml_name = replace(nb_name, ".jl" => ".sessions.toml")
    nb = state !== nothing ? state.nb : nothing
    cell_count = nb !== nothing ? length(Main.Sessions.ordered_cells(nb)) : 0
    done_count = if nb !== nothing
        count(c -> c.state == Main.Sessions.cell_done, Main.Sessions.ordered_cells(nb))
    else
        0
    end

    # Build tree items
    tree_items = Any[]

    # Active notebook file (with green accent border-left and modified dot)
    push!(tree_items,
        Div(:class => "flex items-center gap-1.5 py-[2px] rounded cursor-pointer text-xs font-mono whitespace-nowrap overflow-hidden select-none transition-colors",
            :style => "padding-left:6px; color:#d4dce8; border-left:2px solid #56d4a0; background:rgba(86,212,160,.06);",
            # Julia file icon
            RawHtml(_ICON_JULIA),
            # Filename
            Span(nb_name),
            # Spacer
            Span(:class => "flex-1"),
            # Modified dot
            RawHtml(_ICON_MODIFIED)))

    # Companion .sessions.toml file (dimmer)
    push!(tree_items,
        Div(:class => "flex items-center gap-1.5 py-[2px] rounded cursor-pointer text-xs font-mono whitespace-nowrap overflow-hidden select-none transition-colors",
            :style => "padding-left:20px; color:#6b7d93;",
            # TOML file icon
            RawHtml(_ICON_TOML),
            # Filename
            Span(toml_name)))

    Fragment(
        # File tree area
        Div(:class => "flex-1 overflow-y-auto py-1.5 px-1",
            :id => "ftree",
            tree_items...),

        # Status bar at bottom of panel
        Div(:class => "flex items-center gap-1.5 px-3 py-2 shrink-0",
            :style => "border-top:1px solid #1c2736; font-size:11px; color:#3d5068;",
            RawHtml(_ICON_STATUS_OK),
            Span("No issues"),
            Span(:class => "flex-1"),
            Span(:class => "font-mono",
                :style => "font-size:10px;",
                "$(done_count)/$(cell_count)")))
end
