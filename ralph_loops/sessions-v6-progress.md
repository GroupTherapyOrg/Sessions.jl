# Sessions.jl v6 — Progress Log

## Baseline
- v5 test count: 3455+ tests passing
- Branch: v2
- Key files: output_widget.jl, kernel.jl, notebook_view.jl, app.jl, png_decoder.jl

## Progress

### 2026-03-07: SESSIONS-9001 [PASS]
- Attempted: Cache output_lines() at OutputWidget level to avoid per-frame sprint(show,...)
- Result: Added _cached_output_lines + _cached_output_lines_id fields, cached_output_lines() function, render uses cached version
- Regression gate: 3473 tests pass (was 3455, +18 new)
- Learning: Simple objectid() check is sufficient for cache invalidation; output object is replaced atomically on each execution
- Next: SESSIONS-9002 (encoded raster bytes cache)

### 2026-03-07: SESSIONS-9002 [PASS]
- Attempted: Cache encoded sixel/kitty bytes at OutputWidget level to avoid per-frame re-encoding
- Result: Added _cached_encoded_data/rect/image_hash/protocol fields. New _render_image_cached_raster!() bypasses encode_sixel/encode_kitty on cache hit, calling render_graphics!() directly
- Regression gate: 3489 tests pass (was 3473, +16 new)
- Learning: Frame constructor requires 4 args (Buffer, Rect, gfx_regions, pixel_snapshots). encode_kitty needs cols/rows kwargs. Cache invalidates on image objectid, rect width/height, or protocol change
- Next: SESSIONS-9003 (aspect-aware image sizing)
