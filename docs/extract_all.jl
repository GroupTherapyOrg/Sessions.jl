#!/usr/bin/env julia
# Extract all docs notebooks from test/fixtures/*.jl into
# docs/src/components/notebooks/<Name>.jl. Run from the repo root:
#
#   julia +1.12 --project=docs docs/extract_all.jl

import Pkg
let docs_env = @__DIR__
    if Base.active_project() != joinpath(docs_env, "Project.toml")
        Pkg.activate(docs_env; io = devnull)
    end
end

using Sessions

const ROOT     = dirname(@__DIR__)
const FIXTURES = joinpath(ROOT, "test", "fixtures")
const OUT_DIR  = joinpath(ROOT, "docs", "src", "components", "notebooks")

# slug => PascalCase component name
const NOTEBOOKS = [
    "welcome"     => "Welcome",
    "markdown"    => "Markdown",
    "interactive" => "Interactive",
    "plots"       => "Plots",
    "reactivity"  => "Reactivity",
]

function main()
    isdir(OUT_DIR) || mkpath(OUT_DIR)
    for (slug, name) in NOTEBOOKS
        src = joinpath(FIXTURES, "$(slug).jl")
        dst = joinpath(OUT_DIR,  "$(name).jl")
        isfile(src) || (println("  [skip] missing $(src)"); continue)
        println("▸ Extracting $(slug) → $(dst)")
        Sessions.extract_notebook(src, dst, name;
                                  overwrite = true,
                                  progress  = msg -> println("    $(msg)"))
    end
    println("✓ done")
end

main()
