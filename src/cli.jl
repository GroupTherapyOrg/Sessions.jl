# cli.jl — Entry point for `sessions` CLI command
#
# Installed via: Pkg.Apps.add(url="https://github.com/GroupTherapyOrg/Sessions.jl")
# Creates ~/.julia/bin/sessions
#
# Usage:
#   sessions                              # New empty notebook
#   sessions notebook.jl                  # Open notebook
#   sessions run notebook.jl              # Run headlessly (CI/scripts)
#   sessions --help                       # Show usage

function (@main)(args)
    if "--help" in args || "-h" in args
        println("""
        Sessions.jl — Web-native reactive Julia notebook

        Usage:
          sessions                       Open new notebook in browser
          sessions <notebook.jl>         Open existing notebook
          sessions run <notebook.jl>     Run notebook headlessly (CI/scripts)
          sessions --help                Show this help

        The web IDE opens at http://127.0.0.1:8080
        """)
        return
    end

    # Resolve paths relative to the user's actual working directory
    # (Pkg.Apps shims may change cwd before invoking Julia)
    user_cwd = pwd()

    # Headless run mode
    if !isempty(args) && args[1] == "run"
        nb_path = length(args) >= 2 ? abspath(user_cwd, args[2]) : nothing
        if nb_path === nothing
            println("Error: sessions run requires a notebook path")
            println("Usage: sessions run <notebook.jl>")
            return
        end
        if !isfile(nb_path)
            println("Error: file not found: $nb_path")
            return
        end
        Sessions.run(nb_path)
        return
    end

    # Web IDE mode — launch the web server
    nb_path = if !isempty(args) && endswith(args[1], ".jl")
        abspath(user_cwd, args[1])
    else
        nothing
    end

    _launch_web(nb_path)
end

function _launch_web(nb_path::Union{String, Nothing})
    # The web app entry point
    web_app_path = joinpath(@__DIR__, "web", "app.jl")
    if !isfile(web_app_path)
        println("Error: web app not found at $web_app_path")
        return
    end

    # Build ARGS for the web app
    web_args = ["dev"]
    if nb_path !== nothing
        push!(web_args, nb_path)
    end

    # Run in Main so that `Main.Sessions` and `Main.WEB_STATE` are accessible
    # to web components (they reference Main.Sessions.*, Main.WEB_STATE[], etc.)
    old_args = copy(ARGS)
    empty!(ARGS)
    append!(ARGS, web_args)
    try
        Main.eval(:(include($web_app_path)))
    finally
        empty!(ARGS)
        append!(ARGS, old_args)
    end
end
