using Test
using Sessions
import Tachikoma
using Markdown: MD, Paragraph

# --- Mock image type that supports MIME"image/png" ---
struct MockImageResult end

# Minimal valid 1x1 red PNG (67 bytes)
const TINY_PNG = UInt8[
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,  # PNG signature
    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,  # IHDR chunk
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,  # 1x1
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,  # 8-bit RGB
    0xde, 0x00, 0x00, 0x00, 0x0c, 0x49, 0x44, 0x41,  # IDAT chunk
    0x54, 0x08, 0xd7, 0x63, 0xf8, 0xcf, 0xc0, 0x00,  # compressed data
    0x00, 0x00, 0x02, 0x00, 0x01, 0xe2, 0x21, 0xbc,
    0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e,  # IEND chunk
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

        # Without graphics protocol (gfx_none): text/plain wins
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_none
            @test classify_output(mock) == :text

            # With graphics protocol (gfx_kitty): image/png wins
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty
            @test classify_output(mock) == :image_png

            # With graphics protocol (gfx_sixel): image/png wins
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
            @test c.output.output_type == :text  # text/plain wins when no graphics
            @test c.output.image_data === nothing
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
end
