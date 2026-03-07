using Test
using Sessions
import Tachikoma

@testset "Image Interaction Mode — SESSIONS-9007" begin
    @testset "OutputWidget has viewport transform fields" begin
        cell = Cell("x")
        ow = Sessions.OutputWidget(cell)
        @test ow._img_offset_x == 0
        @test ow._img_offset_y == 0
        @test ow._img_zoom == 1.0
    end

    @testset "_apply_viewport_transform — no transform" begin
        # 4x4 pixel matrix, no zoom/pan → returns full matrix
        pixels = [Tachikoma.ColorRGB(UInt8(i), UInt8(j), UInt8(0)) for i in 1:4, j in 1:4]
        result = Sessions._apply_viewport_transform(pixels, 0, 0, 1.0)
        @test result === pixels  # identity transform returns same object
    end

    @testset "_apply_viewport_transform — zoom 2x" begin
        # 8x8 pixel matrix, zoom 2x → center crop of 4x4
        pixels = [Tachikoma.ColorRGB(UInt8(i), UInt8(j), UInt8(0)) for i in 1:8, j in 1:8]
        result = Sessions._apply_viewport_transform(pixels, 0, 0, 2.0)
        # At zoom 2x: visible region is half the image, centered
        # Source: rows 3:6, cols 3:6 (center quarter)
        @test size(result) == (4, 4)
    end

    @testset "_apply_viewport_transform — pan right" begin
        # 8x8 pixels, zoom 2x, pan right by 1 pixel
        pixels = [Tachikoma.ColorRGB(UInt8(i), UInt8(j), UInt8(0)) for i in 1:8, j in 1:8]
        result = Sessions._apply_viewport_transform(pixels, 1, 0, 2.0)
        @test size(result) == (4, 4)
        # Pan shifts the visible region — should differ from centered version
        centered = Sessions._apply_viewport_transform(pixels, 0, 0, 2.0)
        @test result != centered
    end

    @testset "_apply_viewport_transform — clamped at edges" begin
        pixels = [Tachikoma.ColorRGB(UInt8(i), UInt8(j), UInt8(0)) for i in 1:4, j in 1:4]
        # Extreme pan should clamp, not crash
        result = Sessions._apply_viewport_transform(pixels, 100, 100, 2.0)
        @test size(result, 1) > 0
        @test size(result, 2) > 0
    end

    @testset "zoom increases/decreases correctly" begin
        cell = Cell("img()")
        ow = Sessions.OutputWidget(cell)
        @test ow._img_zoom == 1.0

        Sessions._zoom_in!(ow)
        @test ow._img_zoom > 1.0

        Sessions._zoom_out!(ow)
        @test ow._img_zoom ≈ 1.0

        # Zoom out below 1.0 should clamp
        Sessions._zoom_out!(ow)
        @test ow._img_zoom >= Sessions._ZOOM_MIN
    end

    @testset "pan updates offsets" begin
        cell = Cell("img()")
        ow = Sessions.OutputWidget(cell)

        Sessions._pan!(ow, 5, 0)
        @test ow._img_offset_x == 5
        @test ow._img_offset_y == 0

        Sessions._pan!(ow, 0, -3)
        @test ow._img_offset_x == 5
        @test ow._img_offset_y == -3
    end

    @testset "reset_viewport! clears transform" begin
        cell = Cell("img()")
        ow = Sessions.OutputWidget(cell)
        ow._img_offset_x = 10
        ow._img_offset_y = 5
        ow._img_zoom = 3.0

        Sessions._reset_viewport!(ow)
        @test ow._img_offset_x == 0
        @test ow._img_offset_y == 0
        @test ow._img_zoom == 1.0
    end

    @testset "_is_image_cell detects image outputs" begin
        cell = Cell("img()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_png
        cell.output.image_data = UInt8[1, 2, 3]
        @test Sessions._is_image_cell(cell) == true

        cell2 = Cell("img()")
        cell2.state = Sessions.cell_done
        cell2.output.output_type = :image_jpeg
        cell2.output.image_data = UInt8[1, 2, 3]
        @test Sessions._is_image_cell(cell2) == true

        cell3 = Cell("x = 1")
        cell3.state = Sessions.cell_done
        cell3.output.output_type = :text
        @test Sessions._is_image_cell(cell3) == false
    end

    @testset "zoom constants" begin
        @test Sessions._ZOOM_MIN > 0
        @test Sessions._ZOOM_MAX > Sessions._ZOOM_MIN
        @test Sessions._ZOOM_STEP > 0
        @test Sessions._PAN_STEP > 0
    end
end
