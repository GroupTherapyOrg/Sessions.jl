using Test
using Sessions
import Tachikoma

# Minimal valid 1x1 red PNG
const TINY_PNG_RC = UInt8[
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

@testset "Terminal Resize Cache Invalidation — SESSIONS-9004" begin
    @testset "NotebookView has _last_viewport_size field" begin
        nb = Notebook()
        add_cell!(nb, "1+1")
        nv = Sessions.NotebookView(nb)
        @test nv._last_viewport_size == (0, 0)
    end

    @testset "flush_image_caches! clears encoded data" begin
        nb = Notebook()
        cell = add_cell!(nb, "img()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_png
        cell.output.image_data = copy(TINY_PNG_RC)

        nv = Sessions.NotebookView(nb)
        ow = nv.output_widgets[1]

        # Populate caches manually
        ow._cached_encoded_data = UInt8[1, 2, 3]
        ow._cached_pixel_image = Tachikoma.PixelImage(10, 10)

        Sessions.flush_image_caches!(nv)

        @test ow._cached_encoded_data === nothing
        @test ow._cached_pixel_image === nothing
        # Pixel decode cache should be preserved (decode is width-independent)
        # Text cache should be preserved
    end

    @testset "flush_image_caches! preserves text caches" begin
        nb = Notebook()
        cell = add_cell!(nb, "42")
        ws = Workspace()
        execute_cell!(ws, cell)

        nv = Sessions.NotebookView(nb)
        ow = nv.output_widgets[1]

        # Populate text cache
        lines = Sessions.cached_output_lines(ow)
        @test ow._cached_output_lines !== nothing
        cached_lines = ow._cached_output_lines

        Sessions.flush_image_caches!(nv)

        # Text cache preserved
        @test ow._cached_output_lines === cached_lines
    end

    @testset "detect_viewport_resize! triggers flush on size change" begin
        nb = Notebook()
        cell = add_cell!(nb, "img()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_png
        cell.output.image_data = copy(TINY_PNG_RC)

        nv = Sessions.NotebookView(nb)
        ow = nv.output_widgets[1]

        # Simulate first render at 80x24
        nv._last_viewport_size = (80, 24)
        ow._cached_encoded_data = UInt8[1, 2, 3]
        ow._cached_pixel_image = Tachikoma.PixelImage(10, 10)

        # Same size → no flush
        Sessions.detect_viewport_resize!(nv, 80, 24)
        @test ow._cached_encoded_data !== nothing

        # Different size → flush
        Sessions.detect_viewport_resize!(nv, 100, 30)
        @test ow._cached_encoded_data === nothing
        @test ow._cached_pixel_image === nothing
        @test nv._last_viewport_size == (100, 30)
    end

    @testset "first render initializes viewport size without flush" begin
        nb = Notebook()
        cell = add_cell!(nb, "img()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_png
        cell.output.image_data = copy(TINY_PNG_RC)

        nv = Sessions.NotebookView(nb)
        @test nv._last_viewport_size == (0, 0)

        # First call with actual size — should initialize, not flush
        Sessions.detect_viewport_resize!(nv, 80, 24)
        @test nv._last_viewport_size == (80, 24)
    end

    @testset "height cache flushed on resize (for image cells)" begin
        nb = Notebook()
        cell = add_cell!(nb, "img()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_png
        cell.output.image_data = copy(TINY_PNG_RC)

        nv = Sessions.NotebookView(nb)
        ow = nv.output_widgets[1]

        # Pre-populate height cache
        ow._cached_height = 12
        ow._cached_height_output_id = objectid(cell.output)
        ow._cached_height_state = Sessions.cell_done

        Sessions.flush_image_caches!(nv)

        # Height cache should be invalidated for image cells
        @test ow._cached_height == -1
    end
end
