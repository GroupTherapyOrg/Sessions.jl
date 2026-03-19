# FileExplorer.jl — File tree panel (placeholder)
#
# Shows notebook filename and directory path, matching the TUI file panel aesthetic.

function FileExplorer()
    state = if isdefined(Main, :WEB_STATE) && Main.WEB_STATE[] !== nothing
        Main.WEB_STATE[]
    else
        nothing
    end

    nb_name = state !== nothing ? basename(state.nb.path) : "Untitled.jl"
    nb_dir = state !== nothing ? dirname(state.nb.path) : ""
    # Shorten directory display
    dir_display = if length(nb_dir) > 30
        "..." * nb_dir[end-27:end]
    else
        nb_dir
    end

    Div(:style => "flex: 1; padding: 8px;",
        # Directory path header
        !isempty(dir_display) ?
            Div(:style => "padding: 4px 8px; margin-bottom: 8px; font-size: 11px; font-weight: 600; color: #bcbec4; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;",
                "▾ " * dir_display) : nothing,

        # Current notebook file
        Div(:style => "display: flex; align-items: center; gap: 8px; padding: 4px 8px; border-radius: 4px; background: rgba(56,152,38,0.1);",
            # Diamond icon (active file)
            Span(:style => "color: #389826; font-size: 12px;", "◆"),
            Span(:style => "font-size: 13px; color: #bcbec4;", nb_name)),

        # Session file
        state !== nothing ?
            Div(:style => "display: flex; align-items: center; gap: 8px; padding: 4px 8px 4px 24px;",
                Span(:style => "color: #4e5157; font-size: 12px;", "◇"),
                Span(:style => "font-size: 13px; color: #7a7e85;",
                    replace(nb_name, ".jl" => ".sessions.toml"))) : nothing,

        # Bottom status
        Div(:style => "position: absolute; bottom: 8px; left: 8px; right: 8px; padding: 6px 8px; font-size: 11px; color: #4e5157;",
            "⚠ No issues"))
end
