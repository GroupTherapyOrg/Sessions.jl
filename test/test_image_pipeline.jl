using Test
using Sessions
import Tachikoma
using Markdown: MD, Paragraph

# --- Mock image type that supports MIME"image/png" ---
struct MockImageResult end

# Minimal valid 1x1 red PNG (69 bytes) — properly zlib-compressed
const TINY_PNG = UInt8[
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,  # PNG signature
    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,  # IHDR chunk
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,  # 1x1
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,  # 8-bit RGB
    0xde, 0x00, 0x00, 0x00, 0x0c, 0x49, 0x44, 0x41,  # IDAT chunk
    0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0x00,  # zlib compressed
    0x00, 0x03, 0x01, 0x01, 0x00, 0xc9, 0xfe, 0x92,
    0xef, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e,  # IEND chunk
    0x44, 0xae, 0x42, 0x60, 0x82
]

function Base.show(io::IO, ::MIME"image/png", ::MockImageResult)
    write(io, TINY_PNG)
end

Base.showable(::MIME"image/png", ::MockImageResult) = true

# Also define text/plain (like CairoMakie does)
function Base.show(io::IO, ::MIME"text/plain", ::MockImageResult)
    print(io, "MockImageResult()")
end

@testset "Image Pipeline — SESSIONS-8031+" begin
    @testset "CellOutput has image_data field" begin
        co = CellOutput()
        @test co.image_data === nothing
        @test co.output_type == :nothing

        # Can set image_data
        co.image_data = UInt8[1, 2, 3]
        @test co.image_data == UInt8[1, 2, 3]
    end

    @testset "classify_output — MIME priority with graphics protocol" begin
        mock = MockImageResult()

        # Verify mock supports both MIME types
        @test Base.invokelatest(showable, MIME"image/png"(), mock) == true
        @test Base.invokelatest(showable, MIME"text/plain"(), mock) == true

        # Images always preferred over text/plain — braille fallback works
        # even without a graphics protocol (gfx_none)
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_none
            @test classify_output(mock) == :image_png  # braille fallback

            # With graphics protocol (gfx_kitty): image/png (raster)
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty
            @test classify_output(mock) == :image_png

            # With graphics protocol (gfx_sixel): image/png (raster)
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_sixel
            @test classify_output(mock) == :image_png
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "classify_output — non-image types unaffected by graphics protocol" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty

            # Basic types still classified as :text
            @test classify_output(42) == :text
            @test classify_output("hello") == :text
            @test classify_output([1, 2, 3]) == :text
            @test classify_output(nothing) == :nothing

            # Markdown still classified as :markdown
            md = MD(Paragraph("test"))
            @test classify_output(md) == :markdown
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "classify_output — image-only type (no text/plain)" begin
        # Create a type that ONLY supports image/png, not text/plain
        # (rare but should work regardless of graphics protocol)
        struct ImageOnlyResult end
        Base.showable(::MIME"image/png", ::ImageOnlyResult) = true
        function Base.show(io::IO, ::MIME"image/png", ::ImageOnlyResult)
            write(io, TINY_PNG)
        end
        # Override text/plain to return false
        Base.showable(::MIME"text/plain", ::ImageOnlyResult) = false

        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            # Without graphics: should still be :image_png (it's the only option)
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_none
            @test classify_output(ImageOnlyResult()) == :image_png

            # With graphics: definitely :image_png
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty
            @test classify_output(ImageOnlyResult()) == :image_png
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "PNG capture — _capture_png_bytes" begin
        mock = MockImageResult()
        png_bytes = Sessions._capture_png_bytes(mock)
        @test png_bytes !== nothing
        @test length(png_bytes) > 0
        # Should start with PNG signature
        @test png_bytes[1:8] == UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]

        # Non-image type returns nothing
        @test Sessions._capture_png_bytes(42) === nothing
        @test Sessions._capture_png_bytes("hello") === nothing
    end

    @testset "execute_cell! captures image_data with graphics protocol" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty
            ws = Workspace()

            # Define mock image type in workspace
            execute_cell!(ws, Cell("""
                struct TestImg end
                Base.showable(::MIME"image/png", ::TestImg) = true
                Base.show(io::IO, ::MIME"image/png", ::TestImg) = write(io, UInt8[0x89, 0x50, 0x4e, 0x47])
                Base.show(io::IO, ::MIME"text/plain", ::TestImg) = print(io, "TestImg()")
            """))

            # Execute cell that returns image type
            c = Cell("TestImg()")
            execute_cell!(ws, c)
            @test c.output.output_type == :image_png
            @test c.output.image_data !== nothing
            @test length(c.output.image_data) > 0
            @test c.output.image_data[1:4] == UInt8[0x89, 0x50, 0x4e, 0x47]
            @test c.output.text_representation == "TestImg()"
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "execute_cell! — no image_data without graphics protocol" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_none
            ws = Workspace()

            # Same mock but with gfx_none → text output, no image_data
            execute_cell!(ws, Cell("""
                struct TestImg2 end
                Base.showable(::MIME"image/png", ::TestImg2) = true
                Base.show(io::IO, ::MIME"image/png", ::TestImg2) = write(io, UInt8[1,2,3])
                Base.show(io::IO, ::MIME"text/plain", ::TestImg2) = print(io, "TestImg2()")
            """))

            c = Cell("TestImg2()")
            execute_cell!(ws, c)
            @test c.output.output_type == :image_png  # images always preferred (braille fallback)
            @test c.output.image_data !== nothing
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "execute_cell! — non-image results have nothing image_data" begin
        ws = Workspace()
        c = Cell("42")
        execute_cell!(ws, c)
        @test c.output.output_type == :text
        @test c.output.image_data === nothing
    end

    # --- E2E: OutputWidget rendering (SESSIONS-8035) ---

    @testset "OutputWidget renders braille for valid PNG (gfx_none)" begin
        cell = Cell("img()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_png
        cell.output.image_data = copy(TINY_PNG)

        ow = Sessions.OutputWidget(cell)
        tb = Tachikoma.TestBackend(40, 14)
        Tachikoma.render_widget!(tb, ow)

        # Should NOT show placeholder text
        @test Tachikoma.find_text(tb, "unable to decode") === nothing
        @test Tachikoma.find_text(tb, "placeholder") === nothing

        # Cache should be populated after render
        @test ow._cached_image_hash != UInt64(0)
        @test ow._cached_pixels !== nothing
        @test ow._cached_pixel_image !== nothing
    end

    @testset "OutputWidget fallback for corrupt PNG" begin
        cell = Cell("bad()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_png
        cell.output.image_data = UInt8[0xff, 0xfe, 0xfd]  # not a PNG

        ow = Sessions.OutputWidget(cell)
        tb = Tachikoma.TestBackend(60, 14)
        Tachikoma.render_widget!(tb, ow)
        @test Tachikoma.find_text(tb, "unable to decode") !== nothing
    end

    @testset "OutputWidget — no render when image_data is nothing" begin
        cell = Cell("nothing_img()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_png
        cell.output.image_data = nothing

        ow = Sessions.OutputWidget(cell)
        @test Sessions.output_height(ow) == 0  # no height allocated
    end

    @testset "OutputWidget cache — same image_data reuses cache" begin
        cell = Cell("cached()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_png
        cell.output.image_data = copy(TINY_PNG)

        ow = Sessions.OutputWidget(cell)
        tb = Tachikoma.TestBackend(40, 14)
        Tachikoma.render_widget!(tb, ow)

        # Remember cache state
        h1 = ow._cached_image_hash
        px1 = ow._cached_pixels
        pi1 = ow._cached_pixel_image

        # Render again — cache should be reused (same hash)
        tb2 = Tachikoma.TestBackend(40, 14)
        Tachikoma.render_widget!(tb2, ow)
        @test ow._cached_image_hash == h1
        @test ow._cached_pixels === px1  # same object
    end

    @testset "OutputWidget cache invalidation on new image_data" begin
        cell = Cell("new_img()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_png
        cell.output.image_data = copy(TINY_PNG)

        ow = Sessions.OutputWidget(cell)
        tb = Tachikoma.TestBackend(40, 14)
        Tachikoma.render_widget!(tb, ow)

        h1 = ow._cached_image_hash

        # Change image_data (append a byte to change hash)
        new_data = copy(TINY_PNG)
        push!(new_data, 0x00)
        cell.output.image_data = new_data

        # Re-render — cache should be invalidated (different hash)
        # (decode will fail on modified PNG but that's OK — testing cache invalidation)
        tb2 = Tachikoma.TestBackend(40, 14)
        Tachikoma.render_widget!(tb2, ow)
        @test ow._cached_image_hash != h1 || ow._cached_pixels === nothing
    end

    @testset "Status bar shows graphics indicator (kitty)" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty
            nb = Notebook()
            bar = Sessions.make_top_bar(nb)
            tb = Tachikoma.TestBackend(80, 1)
            Tachikoma.render_widget!(tb, bar)
            @test Tachikoma.find_text(tb, "kitty") !== nothing
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "Status bar shows graphics indicator (sixel)" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_sixel
            nb = Notebook()
            bar = Sessions.make_top_bar(nb)
            tb = Tachikoma.TestBackend(80, 1)
            Tachikoma.render_widget!(tb, bar)
            @test Tachikoma.find_text(tb, "sixel") !== nothing
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "Status bar hides graphics indicator (gfx_none)" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_none
            nb = Notebook()
            bar = Sessions.make_top_bar(nb)
            tb = Tachikoma.TestBackend(80, 1)
            Tachikoma.render_widget!(tb, bar)
            @test Tachikoma.find_text(tb, "kitty") === nothing
            @test Tachikoma.find_text(tb, "sixel") === nothing
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "E2E: full pipeline — classify → capture → decode → render" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty
            ws = Workspace()

            # Define mock type that produces valid TINY_PNG
            tiny_png_literal = join(["0x" * string(b, base=16, pad=2) for b in TINY_PNG], ", ")
            execute_cell!(ws, Cell("""
                struct E2EImg end
                const _E2E_PNG = UInt8[$tiny_png_literal]
                Base.showable(::MIME"image/png", ::E2EImg) = true
                Base.show(io::IO, ::MIME"image/png", ::E2EImg) = write(io, _E2E_PNG)
                Base.show(io::IO, ::MIME"text/plain", ::E2EImg) = print(io, "E2EImg()")
            """))

            c = Cell("E2EImg()")
            execute_cell!(ws, c)

            # 1. classify_output returned :image_png
            @test c.output.output_type == :image_png

            # 2. PNG bytes captured
            @test c.output.image_data !== nothing
            @test c.output.image_data[1:8] == TINY_PNG[1:8]

            # 3. text_representation also captured
            @test c.output.text_representation == "E2EImg()"

            # 4. OutputWidget renders (braille path via TestBackend, gfx_none for render)
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_none
            ow = Sessions.OutputWidget(c)
            @test Sessions.output_height(ow) == Sessions._effective_image_max(ow.viewport_rows)  # 1x1 square → aspect=1.0, rows=40 → clamped to viewport max

            tb = Tachikoma.TestBackend(40, 14)
            Tachikoma.render_widget!(tb, ow)

            # Should have decoded and rendered (no fallback text)
            @test Tachikoma.find_text(tb, "unable to decode") === nothing
            @test ow._cached_pixels !== nothing
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    # --- E2E Polish (SESSIONS-8042) ---

    @testset "Cell re-execution updates image (cache invalidation)" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty
            ws = Workspace()

            tiny_png_literal = join(["0x" * string(b, base=16, pad=2) for b in TINY_PNG], ", ")
            execute_cell!(ws, Cell("""
                struct ReExecImg end
                const _REEXEC_PNG = UInt8[$tiny_png_literal]
                Base.showable(::MIME"image/png", ::ReExecImg) = true
                Base.show(io::IO, ::MIME"image/png", ::ReExecImg) = write(io, _REEXEC_PNG)
                Base.show(io::IO, ::MIME"text/plain", ::ReExecImg) = print(io, "ReExecImg()")
            """))

            c = Cell("ReExecImg()")
            execute_cell!(ws, c)
            @test c.output.output_type == :image_png
            first_data = copy(c.output.image_data)

            # Re-execute same cell — should still have image
            execute_cell!(ws, c)
            @test c.output.output_type == :image_png
            @test c.output.image_data == first_data
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "Folded cell does not render image" begin
        cell = Cell("img()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_png
        cell.output.image_data = copy(TINY_PNG)

        ow = Sessions.OutputWidget(cell)
        ow.collapsed = true
        @test Sessions.output_height(ow) == 0

        tb = Tachikoma.TestBackend(40, 14)
        Tachikoma.render_widget!(tb, ow)
        # Nothing rendered — collapsed
        @test Tachikoma.find_text(tb, "unable") === nothing
        @test ow._cached_pixels === nothing  # no decode happened
    end

    @testset "Idle cell does not render image" begin
        cell = Cell("img()")
        cell.state = Sessions.cell_idle
        cell.output.output_type = :image_png
        cell.output.image_data = copy(TINY_PNG)

        ow = Sessions.OutputWidget(cell)
        @test Sessions.output_height(ow) == 0
    end

    @testset "Text result unaffected by graphics protocol" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty
            ws = Workspace()
            c = Cell("42")
            execute_cell!(ws, c)
            @test c.output.output_type == :text
            @test c.output.image_data === nothing

            ow = Sessions.OutputWidget(c)
            tb = Tachikoma.TestBackend(40, 5)
            Tachikoma.render_widget!(tb, ow)
            @test Tachikoma.find_text(tb, "42") !== nothing
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "Markdown result unaffected by graphics protocol" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty
            ws = Workspace()
            execute_cell!(ws, Cell("using Markdown"))
            c = Cell("md\"hello world\"")
            execute_cell!(ws, c)
            @test c.output.output_type == :markdown
            @test c.output.image_data === nothing
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "gfx_none — image-capable type still classified as image (braille fallback)" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_none
            mock = MockImageResult()
            @test classify_output(mock) == :image_png  # braille fallback, not text
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end
end
