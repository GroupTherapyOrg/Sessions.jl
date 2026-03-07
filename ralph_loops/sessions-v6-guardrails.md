# Sessions.jl v6 — Guardrails

## ABSOLUTE RULES

1. **Never break existing tests** — 3455+ tests must pass after every change
2. **Never add hard dependencies** — no new entries in Project.toml [deps]
3. **Never use browser tech** — no Therapy.jl, Suite.jl, HTTP.jl, WebSocket, HTML, CSS
4. **Never remove keybindings** — especially Ctrl+R for run cell
5. **Commit style** — `SESSIONS-9XXX: Description`

## ARCHITECTURE RULES

1. **Cache at OutputWidget level** — all caching happens in OutputWidget fields, not in Tachikoma
2. **Invalidate on objectid change** — use objectid() for O(1) identity checks
3. **Graceful degradation** — every optimization has a cold-cache fallback
4. **No new output types without kernel support** — classify_output must return the type
5. **Frame threading** — images use current_frame from NotebookView → OutputWidget

## TESTING RULES

1. **TDD** — write tests BEFORE implementation
2. **Test cache behavior** — verify cache hit, cache miss, cache invalidation
3. **Test with TestBackend** — use Tachikoma.TestBackend for render tests
4. **Regression gate** — run full suite before every commit
5. **Ratchet** — test count must never decrease

## CODE STYLE

1. **Minimize diff** — change only what's needed for the story
2. **Preserve APIs** — existing function signatures must not change
3. **Document cache fields** — comment what each cache field stores and when it invalidates
4. **No over-engineering** — implement the simplest correct solution
