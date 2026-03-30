<div align="center">
  # Sessions.jl

  **A reactive Julia notebook IDE.**

  [![Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://grouptherapyorg.github.io/Sessions.jl/)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE.md)
</div>

---

> **Alpha software.** Rough edges everywhere. For a reliable reactive notebook, use [Pluto.jl](https://github.com/fonsp/Pluto.jl). Sessions.jl explores ideas at the intersection of reactive notebooks, file-based collaboration, and one-click interactive publishing.

## Install

Requires Julia 1.12+.

```julia
using Pkg
Pkg.Apps.add(url="https://github.com/GroupTherapyOrg/Sessions.jl")
```

Add `~/.julia/bin` to your PATH, then:

```bash
sessions notebook.jl        # Open notebook in browser
sessions                     # New empty notebook
sessions run notebook.jl     # Run headlessly (CI/scripts)
```

## What is it?

Sessions.jl is a reactive Julia notebook that runs as a local web IDE. Edit notebooks in the browser, from the terminal, or programmatically — a file watcher picks up all changes and the UI updates live.

- **Plain `.jl` files.** Same format as Pluto. Edit anywhere.
- **Code/state separation.** Code in `.jl`, cached outputs in `.sessions.toml`. Delete the cache anytime.
- **Full IDE.** CodeMirror editor, file explorer, integrated terminal. One window.
- **One-click publishing.** Export notebooks as static HTML with interactive `@bind` widgets compiled to JavaScript via [JavaScriptTarget.jl](https://github.com/GroupTherapyOrg/JavaScriptTarget.jl).

## Built on

- [Therapy.jl](https://github.com/GroupTherapyOrg/Therapy.jl) — SolidJS-inspired web framework for Julia
- [JavaScriptTarget.jl](https://github.com/GroupTherapyOrg/JavaScriptTarget.jl) — Julia-to-JavaScript transpiler
- [Pluto.jl](https://github.com/fonsp/Pluto.jl) file format and reactive engine
- [Malt.jl](https://github.com/JuliaPluto/Malt.jl), [CodeMirror](https://codemirror.net/), [xterm.js](https://xtermjs.org/), [Shoelace](https://shoelace.style/)

## License

MIT
