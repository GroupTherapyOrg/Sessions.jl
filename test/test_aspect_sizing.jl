using Test
using Sessions
import Tachikoma

# Minimal valid 1x1 red PNG (reuse from other tests)
const TINY_PNG_AS = UInt8[
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
    0xde, 0x00, 0x00, 0x00, 0x0c, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0x00,
    0x00, 0x03, 0x01, 0x01, 0x00, 0xc9, 0xfe, 0x92,
    0xef, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e,
    0x44, 0xae, 0x42, 0x60, 0x82
]

"""Create a minimal PNG with given dimensions (just IHDR, no valid IDAT)."""
function _make_png_header(width::Int, height::Int)
    # PNG signature
    sig = UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
    # IHDR chunk: length(13) + "IHDR" + data + CRC
    ihdr_data = UInt8[]
    # Width (4 bytes big-endian)
    append!(ihdr_data, reinterpret(UInt8, [hton(UInt32(width))]))
    # Height (4 bytes big-endian)
    append!(ihdr_data, reinterpret(UInt8, [hton(UInt32(height))]))
    # bit depth=8, color type=2 (RGB), compression=0, filter=0, interlace=0
    append!(ihdr_data, UInt8[0x08, 0x02, 0x00, 0x00, 0x00])

    chunk_len = reinterpret(UInt8, [hton(UInt32(13))])
    chunk_type = UInt8[0x49, 0x48, 0x44, 0x52]  # "IHDR"
    crc = UInt8[0x00, 0x00, 0x00, 0x00]  # dummy CRC (not validated by decoder)

    vcat(sig, chunk_len, chunk_type, ihdr_data, crc)
end

@testset "Aspect-Aware Image Sizing — SESSIONS-9003" begin
    @testset "decode_png_dimensions — valid 1x1 PNG" begin
        dims = Sessions.decode_png_dimensions(TINY_PNG_AS)
        @test dims !== nothing
        w, h = dims
        @test w == 1
        @test h == 1
    end

    @testset "decode_png_dimensions — custom dimensions" begin
        for (w, h) in [(100, 200), (640, 480), (1920, 1080), (50, 50)]
            png = _make_png_header(w, h)
            dims = Sessions.decode_png_dimensions(png)
            @test dims !== nothing
            @test dims == (w, h)
        end
    end

    @testset "decode_png_dimensions — invalid data" begin
        @test Sessions.decode_png_dimensions(UInt8[]) === nothing
        @test Sessions.decode_png_dimensions(UInt8[1, 2, 3]) === nothing
        @test Sessions.decode_png_dimensions(UInt8[0x89, 0x50]) === nothing  # truncated signature
    end

    @testset "image_output_height — square image" begin
        # Square image: aspect ratio = 1.0
        # With terminal cell ratio ~2:1 (char height ≈ 2× width),
        # a square image should use fewer rows than cols
        h = Sessions.image_output_height(100, 100, 80)
        @test h >= Sessions._IMAGE_HEIGHT_MIN
        @test h <= Sessions._IMAGE_HEIGHT_MAX
    end

    @testset "image_output_height — wide image" begin
        # 2:1 aspect ratio (wide) → fewer rows
        h_wide = Sessions.image_output_height(200, 100, 80)
        h_tall = Sessions.image_output_height(100, 200, 80)
        @test h_wide < h_tall  # wide image should use fewer rows than tall
    end

    @testset "image_output_height — tall image gets more rows" begin
        h = Sessions.image_output_height(100, 400, 80)
        @test h > Sessions._IMAGE_HEIGHT_MIN  # should use more than minimum
    end

    @testset "image_output_height — clamped to [min, max]" begin
        # Very tall image
        h_tall = Sessions.image_output_height(10, 10000, 80)
        @test h_tall == Sessions._IMAGE_HEIGHT_MAX

        # Very wide image
        h_wide = Sessions.image_output_height(10000, 10, 80)
        @test h_wide == Sessions._IMAGE_HEIGHT_MIN
    end

    @testset "image_output_height — zero/negative handled" begin
        @test Sessions.image_output_height(0, 100, 80) == Sessions._IMAGE_HEIGHT_MIN
        @test Sessions.image_output_height(100, 0, 80) == Sessions._IMAGE_HEIGHT_MIN
        @test Sessions.image_output_height(0, 0, 80) == Sessions._IMAGE_HEIGHT_MIN
    end

    @testset "output_height uses aspect ratio for valid PNG" begin
        cell = Cell("img()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_png
        cell.output.image_data = copy(TINY_PNG_AS)  # 1x1

        ow = Sessions.OutputWidget(cell)
        h = Sessions.output_height(ow)
        # 1x1 image (square) → aspect=1.0, rows=80/2=40 → clamped to max
        @test h == Sessions._IMAGE_HEIGHT_MAX
    end

    @testset "output_height falls back to default for corrupt PNG" begin
        cell = Cell("img()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_png
        cell.output.image_data = UInt8[0xff, 0xfe, 0xfd]  # not PNG

        ow = Sessions.OutputWidget(cell)
        h = Sessions.output_height(ow)
        @test h == Sessions._IMAGE_HEIGHT_DEFAULT
    end

    @testset "cached image dimensions" begin
        cell = Cell("img()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_png
        cell.output.image_data = copy(TINY_PNG_AS)

        ow = Sessions.OutputWidget(cell)
        h1 = Sessions.output_height(ow)

        # Second call should use cache (same output)
        h2 = Sessions.output_height(ow)
        @test h1 == h2
    end
end
