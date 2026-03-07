using Test
using Sessions
import Tachikoma

# Minimal valid 1x1 red PNG
const TINY_PNG_EC = UInt8[
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

"""Create a test Frame with proper 4-arg constructor."""
function _test_frame(rect::Tachikoma.Rect)
    buf = Tachikoma.Buffer(rect)
    Tachikoma.Frame(buf, rect, Tachikoma.GraphicsRegion[], Tuple{Int,Int,Matrix{Tachikoma.ColorRGB}}[])
end

@testset "Encoded Raster Cache — SESSIONS-9002" begin
    @testset "OutputWidget has encoded cache fields" begin
        cell = Cell("img()")
        ow = Sessions.OutputWidget(cell)
        @test ow._cached_encoded_data === nothing
        @test ow._cached_encoded_rect == Tachikoma.Rect()
        @test ow._cached_encoded_image_hash == UInt64(0)
        @test ow._cached_encoded_protocol == Tachikoma.gfx_none
    end

    @testset "Braille fallback (gfx_none) still works — no encoded cache used" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_none
            cell = Cell("img()")
            cell.state = Sessions.cell_done
            cell.output.output_type = :image_png
            cell.output.image_data = copy(TINY_PNG_EC)

            ow = Sessions.OutputWidget(cell)
            tb = Tachikoma.TestBackend(40, 14)
            Tachikoma.render_widget!(tb, ow)

            # Should render (braille), no encoded cache used
            @test ow._cached_encoded_data === nothing
            @test ow._cached_pixels !== nothing  # pixels still cached
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "Encoded cache populated on first raster render" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty
            cell = Cell("img()")
            cell.state = Sessions.cell_done
            cell.output.output_type = :image_png
            cell.output.image_data = copy(TINY_PNG_EC)

            ow = Sessions.OutputWidget(cell)
            rect = Tachikoma.Rect(1, 1, 40, 12)
            frame = _test_frame(Tachikoma.Rect(1, 1, 40, 14))
            ow.current_frame = frame
            Tachikoma.render(ow, rect, frame.buffer)

            # Encoded cache should be populated
            @test ow._cached_encoded_data !== nothing
            @test length(ow._cached_encoded_data) > 0
            @test ow._cached_encoded_image_hash == objectid(cell.output.image_data)
            @test ow._cached_encoded_protocol == Tachikoma.gfx_kitty
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "Encoded cache reused on second render (same image + rect)" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty
            cell = Cell("img()")
            cell.state = Sessions.cell_done
            cell.output.output_type = :image_png
            cell.output.image_data = copy(TINY_PNG_EC)

            ow = Sessions.OutputWidget(cell)
            rect = Tachikoma.Rect(1, 1, 40, 12)

            # First render
            frame1 = _test_frame(Tachikoma.Rect(1, 1, 40, 14))
            ow.current_frame = frame1
            Tachikoma.render(ow, rect, frame1.buffer)
            data1 = ow._cached_encoded_data

            # Second render — same image, same rect
            frame2 = _test_frame(Tachikoma.Rect(1, 1, 40, 14))
            ow.current_frame = frame2
            Tachikoma.render(ow, rect, frame2.buffer)

            # Should reuse same cached data
            @test ow._cached_encoded_data === data1
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "Encoded cache invalidated on image change" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty
            cell = Cell("img()")
            cell.state = Sessions.cell_done
            cell.output.output_type = :image_png
            cell.output.image_data = copy(TINY_PNG_EC)

            ow = Sessions.OutputWidget(cell)
            rect = Tachikoma.Rect(1, 1, 40, 12)

            # First render
            frame1 = _test_frame(Tachikoma.Rect(1, 1, 40, 14))
            ow.current_frame = frame1
            Tachikoma.render(ow, rect, frame1.buffer)
            data1 = ow._cached_encoded_data
            @test data1 !== nothing

            # Change image data
            new_data = copy(TINY_PNG_EC)
            cell.output.image_data = new_data  # new object

            # Second render — should re-encode
            frame2 = _test_frame(Tachikoma.Rect(1, 1, 40, 14))
            ow.current_frame = frame2
            Tachikoma.render(ow, rect, frame2.buffer)

            @test ow._cached_encoded_image_hash == objectid(new_data)
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "Encoded cache invalidated on rect resize" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty
            cell = Cell("img()")
            cell.state = Sessions.cell_done
            cell.output.output_type = :image_png
            cell.output.image_data = copy(TINY_PNG_EC)

            ow = Sessions.OutputWidget(cell)

            # First render at 40x12
            rect1 = Tachikoma.Rect(1, 1, 40, 12)
            frame1 = _test_frame(Tachikoma.Rect(1, 1, 40, 14))
            ow.current_frame = frame1
            Tachikoma.render(ow, rect1, frame1.buffer)
            data1 = ow._cached_encoded_data

            # Second render at different size — should re-encode
            rect2 = Tachikoma.Rect(1, 1, 60, 12)
            frame2 = _test_frame(Tachikoma.Rect(1, 1, 60, 14))
            ow.current_frame = frame2
            Tachikoma.render(ow, rect2, frame2.buffer)

            @test ow._cached_encoded_data !== data1  # different object
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "Encoded cache invalidated on protocol change" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            cell = Cell("img()")
            cell.state = Sessions.cell_done
            cell.output.output_type = :image_png
            cell.output.image_data = copy(TINY_PNG_EC)

            ow = Sessions.OutputWidget(cell)
            rect = Tachikoma.Rect(1, 1, 40, 12)

            # Render with kitty
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty
            frame1 = _test_frame(Tachikoma.Rect(1, 1, 40, 14))
            ow.current_frame = frame1
            Tachikoma.render(ow, rect, frame1.buffer)
            @test ow._cached_encoded_protocol == Tachikoma.gfx_kitty

            # Render with sixel — should re-encode
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_sixel
            frame2 = _test_frame(Tachikoma.Rect(1, 1, 40, 14))
            ow.current_frame = frame2
            Tachikoma.render(ow, rect, frame2.buffer)
            @test ow._cached_encoded_protocol == Tachikoma.gfx_sixel
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end
end
