# FileExplorer.jl — @island: Interactive file tree with folder toggle
#
# Folder items expand/collapse via WASM signals. Pure Julia interactivity.
# Renders the notebook's file tree and bottom status bar.

# --- SVG icon strings ---

const _ICON_JULIA = """<svg width="14" height="14" viewBox="0 0 20 20"><circle cx="10" cy="6" r="2.8" fill="#e06b65"/><circle cx="5.5" cy="14" r="2.8" fill="#56d4a0"/><circle cx="14.5" cy="14" r="2.8" fill="#b08fd8"/></svg>"""

const _ICON_TOML = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><rect x="3" y="3" width="14" height="14" rx="2" stroke="#6b7d93" stroke-width="1.3"/><path d="M7 7h6M7 10h4M7 13h5" stroke="#6b7d93" stroke-width="1.2" stroke-linecap="round"/></svg>"""

const _ICON_FOLDER_OPEN = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><path d="M2 5.5A1.5 1.5 0 013.5 4H8l1.5 2h7A1.5 1.5 0 0118 7.5V9H4.5L2 15.5v-10z" fill="#3d5068" opacity=".4" stroke="#7bb8e8" stroke-width="1"/><path d="M2 15.5L4.5 9H18l-2.5 6.5H2z" fill="#1a2332" stroke="#7bb8e8" stroke-width="1"/></svg>"""

const _ICON_FOLDER_CLOSED = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><path d="M2 5.5A1.5 1.5 0 013.5 4H8l1.5 2h7A1.5 1.5 0 0118 7.5v7a1.5 1.5 0 01-1.5 1.5h-13A1.5 1.5 0 012 14.5v-9z" fill="#3d5068" opacity=".5" stroke="#5a7a99" stroke-width="1"/></svg>"""

const _ICON_GENERIC = """<svg width="14" height="14" viewBox="0 0 20 20" fill="none"><path d="M5 2h7l4 4v12a1 1 0 01-1 1H5a1 1 0 01-1-1V3a1 1 0 011-1z" stroke="#4a6178" stroke-width="1.2"/><path d="M12 2v4h4" stroke="#4a6178" stroke-width="1.2"/></svg>"""

const _ICON_STATUS_OK = """<svg width="7" height="7"><circle cx="3.5" cy="3.5" r="3.5" fill="#56d4a0"/></svg>"""

const _ICON_MODIFIED = """<svg width="6" height="6" class="shrink-0"><circle cx="3" cy="3" r="3" fill="#56d4a0"/></svg>"""

# Shared tree item style
const _TREE_ITEM = "display:flex;align-items:center;gap:6px;padding:2px 0;border-radius:4px;cursor:pointer;font-size:12px;font-family:ui-monospace,monospace;white-space:nowrap;overflow:hidden;user-select:none;transition:color .15s,background .15s;"

@island function FileExplorer()
    # Folder open/close signal (Int32: 0=closed, 1=open)
    docs_open, set_docs_open = create_signal(Int32(1))
    notebooks_open, set_notebooks_open = create_signal(Int32(1))
    src_open, set_src_open = create_signal(Int32(0))

    # Server-side data (not compiled to WASM)
    state = if isdefined(Main, :WEB_STATE) && Main.WEB_STATE[] !== nothing
        Main.WEB_STATE[]
    else
        nothing
    end
    nb_name = state !== nothing ? basename(state.nb.path) : "Untitled.jl"
    toml_name = replace(nb_name, ".jl" => ".sessions.toml")
    nb = state !== nothing ? state.nb : nothing
    cell_count = nb !== nothing ? length(Main.Sessions.ordered_cells(nb)) : 0
    done_count = nb !== nothing ? count(c -> c.state == Main.Sessions.cell_done, Main.Sessions.ordered_cells(nb)) : 0

    Fragment(
        # ── File tree area ──
        Div(:class => "flex-1 overflow-y-auto py-1.5 px-1",

            # ── docs/ folder ──
            Div(:style => _TREE_ITEM * "padding-left:6px;color:#9baabd;",
                :on_click => () -> begin
                    if docs_open() == Int32(1)
                        set_docs_open(Int32(0))
                    else
                        set_docs_open(Int32(1))
                    end
                end,
                Span(:class => "chv open", :style => "width:12px;height:12px;font-size:8px;display:inline-flex;align-items:center;justify-content:center;flex-shrink:0;", "▸"),
                RawHtml(_ICON_FOLDER_OPEN),
                Span("docs")),

            # docs/ children
            Show(docs_open) do
                Div(
                    # ── notebooks/ subfolder ──
                    Div(:style => _TREE_ITEM * "padding-left:20px;color:#9baabd;",
                        :on_click => () -> begin
                            if notebooks_open() == Int32(1)
                                set_notebooks_open(Int32(0))
                            else
                                set_notebooks_open(Int32(1))
                            end
                        end,
                        Span(:class => "chv open", :style => "width:12px;height:12px;font-size:8px;display:inline-flex;align-items:center;justify-content:center;flex-shrink:0;", "▸"),
                        RawHtml(_ICON_FOLDER_OPEN),
                        Span("notebooks")),

                    # notebooks/ children
                    Show(notebooks_open) do
                        Div(
                            # Active notebook file
                            Div(:style => _TREE_ITEM * "padding-left:34px;color:#d4dce8;border-left:2px solid #56d4a0;background:rgba(86,212,160,.06);",
                                RawHtml(_ICON_JULIA),
                                Span(nb_name),
                                Span(:style => "flex:1;"),
                                RawHtml(_ICON_MODIFIED)),
                            # Session file
                            Div(:style => _TREE_ITEM * "padding-left:38px;color:#6b7d93;",
                                RawHtml(_ICON_TOML),
                                Span(toml_name)))
                    end)
            end,

            # ── src/ folder ──
            Div(:style => _TREE_ITEM * "padding-left:6px;color:#9baabd;",
                :on_click => () -> begin
                    if src_open() == Int32(1)
                        set_src_open(Int32(0))
                    else
                        set_src_open(Int32(1))
                    end
                end,
                Span(:class => "chv", :style => "width:12px;height:12px;font-size:8px;display:inline-flex;align-items:center;justify-content:center;flex-shrink:0;", "▸"),
                RawHtml(_ICON_FOLDER_CLOSED),
                Span("src")),

            Show(src_open) do
                Div(
                    Div(:style => _TREE_ITEM * "padding-left:34px;color:#6b7d93;",
                        RawHtml(_ICON_JULIA),
                        Span("Sessions.jl")),
                    Div(:style => _TREE_ITEM * "padding-left:34px;color:#6b7d93;",
                        RawHtml(_ICON_JULIA),
                        Span("kernel.jl")),
                    Div(:style => _TREE_ITEM * "padding-left:34px;color:#6b7d93;",
                        RawHtml(_ICON_JULIA),
                        Span("analysis.jl")))
            end,

            # ── Loose files ──
            Div(:style => _TREE_ITEM * "padding-left:20px;color:#6b7d93;",
                RawHtml(_ICON_TOML),
                Span("Project.toml")),
            Div(:style => _TREE_ITEM * "padding-left:20px;color:#6b7d93;",
                RawHtml(_ICON_GENERIC),
                Span("README.md"))),

        # ── Status bar at bottom ──
        Div(:class => "flex items-center gap-1.5 px-3 py-2 shrink-0",
            :style => "border-top:1px solid #1c2736; font-size:11px; color:#3d5068;",
            RawHtml(_ICON_STATUS_OK),
            Span("No issues"),
            Span(:class => "flex-1"),
            Span(:class => "font-mono",
                :style => "font-size:10px;",
                "$(done_count)/$(cell_count)")))
end
