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

@testset "Image Render Cache — SESSIONS-9002" begin
    @testset "OutputWidget has cache fields" begin
        cell = Cell("img()")
        ow = Sessions.OutputWidget(cell)
        @test ow._cached_encoded_data === nothing
        @test ow._cached_image_hash == UInt64(0)
        @test ow._cached_pixels === nothing
        @test ow._cached_pixel_image === nothing
    end

    @testset "Braille fallback (gfx_none) still works" begin
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

            # Should render braille, pixel cache populated
            @test ow._cached_pixels !== nothing
            @test ow._cached_pixel_image !== nothing
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "Pixel decode cache reused on second render" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_none
            cell = Cell("img()")
            cell.state = Sessions.cell_done
            cell.output.output_type = :image_png
            cell.output.image_data = copy(TINY_PNG_EC)

            ow = Sessions.OutputWidget(cell)

            # First render
            tb1 = Tachikoma.TestBackend(40, 14)
            Tachikoma.render_widget!(tb1, ow)
            px1 = ow._cached_pixels
            hash1 = ow._cached_image_hash
            @test px1 !== nothing

            # Second render — same image data
            tb2 = Tachikoma.TestBackend(40, 14)
            Tachikoma.render_widget!(tb2, ow)

            # Pixel cache reused (same object)
            @test ow._cached_pixels === px1
            @test ow._cached_image_hash == hash1
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "Pixel decode cache invalidated on image change" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_none
            cell = Cell("img()")
            cell.state = Sessions.cell_done
            cell.output.output_type = :image_png
            cell.output.image_data = copy(TINY_PNG_EC)

            ow = Sessions.OutputWidget(cell)

            # First render
            tb1 = Tachikoma.TestBackend(40, 14)
            Tachikoma.render_widget!(tb1, ow)
            hash1 = ow._cached_image_hash

            # Change image data (new object)
            new_data = copy(TINY_PNG_EC)
            cell.output.image_data = new_data

            # Second render — should re-decode
            tb2 = Tachikoma.TestBackend(40, 14)
            Tachikoma.render_widget!(tb2, ow)

            @test ow._cached_image_hash == objectid(new_data)
            @test ow._cached_image_hash != hash1
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "PixelImage cache invalidated on rect resize" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_none
            cell = Cell("img()")
            cell.state = Sessions.cell_done
            cell.output.output_type = :image_png
            cell.output.image_data = copy(TINY_PNG_EC)

            ow = Sessions.OutputWidget(cell)

            # First render at 40 wide
            tb1 = Tachikoma.TestBackend(40, 14)
            Tachikoma.render_widget!(tb1, ow)
            pi1 = ow._cached_pixel_image
            @test pi1 !== nothing

            # Render at different size — PixelImage should be rebuilt
            rect2 = Tachikoma.Rect(1, 1, 60, 12)
            buf2 = Tachikoma.Buffer(rect2)
            Tachikoma.render(ow, rect2, buf2)

            pi2 = ow._cached_pixel_image
            @test pi2 !== nothing
            @test pi2 !== pi1  # different PixelImage object (new size)
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "cached_output_lines caches text output" begin
        cell = Cell("42")
        cell.state = Sessions.cell_done
        cell.output.output_type = :text
        cell.output.result = 42

        ow = Sessions.OutputWidget(cell)
        lines1 = Sessions.cached_output_lines(ow)
        @test !isempty(lines1)

        # Second call returns same cached object
        lines2 = Sessions.cached_output_lines(ow)
        @test lines2 === lines1
    end
end
