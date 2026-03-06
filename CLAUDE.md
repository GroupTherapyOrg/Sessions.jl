# Sessions.jl v2 — Developer Guide

## THIS IS A COMPLETE REWRITE. DO NOT USE v1 CODE.

Sessions.jl v2 is a **terminal-native** reactive Julia notebook built on **Tachikoma.jl**.

## FORBIDDEN — Do NOT use these:
- Therapy.jl (browser web framework)
- Suite.jl (browser UI components)
- HTTP.jl (web server)
- Malt.jl (subprocess execution)
- Any browser-related code (WebSocket, HTML, CSS, CodeMirror, JavaScript, WASM)

## Architecture
- **Layer 1: Engine** — types.jl, format.jl, analysis.jl, kernel.jl, run.jl (pure Julia, no UI)
- **Layer 2: TUI** — tui/*.jl (Tachikoma.jl terminal interface)
- **Layer 3: CLI** — cli.jl, watcher.jl (entry points)

## Key Dependencies
- Tachikoma.jl (terminal UI framework)
- ExpressionExplorer.jl (reactive analysis from Pluto ecosystem)
- PlutoDependencyExplorer.jl (topological sort from Pluto ecosystem)
- UUIDs, FileWatching (Julia stdlib)

## Workflow
Read the ralph loop files for full instructions:
1. `ralph_loops/sessions-v2-prd.json` — story list
2. `ralph_loops/sessions-v2-prompt.md` — execution guide
3. `ralph_loops/sessions-v2-guardrails.md` — rules
4. `ralph_loops/sessions-v2-progress.md` — log

## Commands
```bash
julia +1.12 --project=. test/runtests.jl    # Run tests
julia +1.12 --project=. -e 'using Sessions'  # Load package
```

## CRITICAL: Keybinding Requirements
- **Ctrl+R** MUST always be a "run cell" binding. Most macOS terminals (Terminal.app, iTerm2) do NOT send distinct keycodes for Shift+Enter or Ctrl+Enter. Ctrl+R (0x12) is the universal fallback that works everywhere.
- Keep Shift+Enter and Ctrl+Enter as secondary bindings for terminals with Kitty keyboard protocol support.
- NEVER remove Ctrl+R as a run binding.

## Commit Style
SESSIONS-5XXX: Description
