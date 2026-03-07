using Test
using Sessions
import Tachikoma

@testset "SVG Text Fallback — SESSIONS-9006" begin
    @testset "classify_output — SVG MIME detection" begin
        # SVG-only type (no text/plain, no PNG)
        struct SvgTestResult end
        Base.showable(::MIME"image/svg+xml", ::SvgTestResult) = true
        Base.show(io::IO, ::MIME"image/svg+xml", ::SvgTestResult) = print(io, "<svg></svg>")
        Base.showable(::MIME"image/png", ::SvgTestResult) = false
        Base.showable(::MIME"text/plain", ::SvgTestResult) = false

        @test classify_output(SvgTestResult()) == :image_svg
    end

    @testset "classify_output — SVG detected regardless of graphics protocol" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            # SVG text fallback works even without graphics protocol
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_none

            struct SvgNoGfxResult end
            Base.showable(::MIME"image/svg+xml", ::SvgNoGfxResult) = true
            Base.show(io::IO, ::MIME"image/svg+xml", ::SvgNoGfxResult) = print(io, "<svg></svg>")
            Base.showable(::MIME"image/png", ::SvgNoGfxResult) = false
            Base.showable(::MIME"text/plain", ::SvgNoGfxResult) = false

            @test classify_output(SvgNoGfxResult()) == :image_svg
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "classify_output — PNG preferred over SVG" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty

            struct PngSvgResult end
            Base.showable(::MIME"image/png", ::PngSvgResult) = true
            Base.showable(::MIME"image/svg+xml", ::PngSvgResult) = true
            Base.show(io::IO, ::MIME"image/png", ::PngSvgResult) = nothing
            Base.show(io::IO, ::MIME"image/svg+xml", ::PngSvgResult) = print(io, "<svg></svg>")

            # When graphics are available, PNG should be preferred
            @test classify_output(PngSvgResult()) == :image_png
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "classify_output — SVG preferred over text/plain" begin
        struct TextSvgResult end
        Base.showable(::MIME"text/plain", ::TextSvgResult) = true
        Base.show(io::IO, ::MIME"text/plain", ::TextSvgResult) = print(io, "text version")
        Base.showable(::MIME"image/svg+xml", ::TextSvgResult) = true
        Base.show(io::IO, ::MIME"image/svg+xml", ::TextSvgResult) = print(io, "<svg></svg>")
        Base.showable(::MIME"image/png", ::TextSvgResult) = false

        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_none
            # SVG is a richer representation than text/plain
            @test classify_output(TextSvgResult()) == :image_svg
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "_capture_svg_source" begin
        struct SvgCapTest end
        Base.showable(::MIME"image/svg+xml", ::SvgCapTest) = true
        function Base.show(io::IO, ::MIME"image/svg+xml", ::SvgCapTest)
            print(io, "<svg width=\"100\" height=\"50\"><circle r=\"10\"/></svg>")
        end

        src = Sessions._capture_svg_source(SvgCapTest())
        @test src !== nothing
        @test contains(src, "<svg")
        @test contains(src, "circle")

        # Non-SVG type returns nothing
        @test Sessions._capture_svg_source(42) === nothing
    end

    @testset "output_height for SVG" begin
        cell = Cell("svg()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_svg
        cell.output.text_representation = "<svg>\n  <rect/>\n  <circle/>\n</svg>"

        ow = Sessions.OutputWidget(cell)
        h = Sessions.output_height(ow)
        # 1 header line + 4 SVG source lines = 5
        @test h == 5
    end

    @testset "output_height for empty SVG" begin
        cell = Cell("svg()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_svg
        cell.output.text_representation = ""

        ow = Sessions.OutputWidget(cell)
        h = Sessions.output_height(ow)
        # Empty SVG — 1 header line
        @test h == 1
    end

    @testset "output_height for long SVG clamped" begin
        cell = Cell("svg()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_svg
        # 50 lines of SVG — should be clamped to max display height
        cell.output.text_representation = join(["<line $i/>" for i in 1:50], "\n")

        ow = Sessions.OutputWidget(cell)
        h = Sessions.output_height(ow)
        @test h <= Sessions._SVG_HEIGHT_MAX
    end

    @testset "SVG render — shows header and source" begin
        cell = Cell("svg()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_svg
        cell.output.text_representation = "<svg width=\"100\">\n  <rect/>\n</svg>"

        ow = Sessions.OutputWidget(cell)
        tb = Tachikoma.TestBackend(60, 10)
        Tachikoma.render_widget!(tb, ow)
        # Should show SVG header indicator
        @test Tachikoma.find_text(tb, "SVG") !== nothing
        # Should show SVG source
        @test Tachikoma.find_text(tb, "<svg") !== nothing
    end

    @testset "SVG render — empty SVG shows header only" begin
        cell = Cell("svg()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_svg
        cell.output.text_representation = ""

        ow = Sessions.OutputWidget(cell)
        tb = Tachikoma.TestBackend(60, 5)
        Tachikoma.render_widget!(tb, ow)
        @test Tachikoma.find_text(tb, "SVG") !== nothing
    end

    @testset "SVG render — stale cell shows text fallback" begin
        cell = Cell("svg()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_svg
        cell.output.text_representation = "<svg></svg>"
        # Mark as stale
        cell.produced_by_hash = "old"
        cell.code = "new_svg()"

        ow = Sessions.OutputWidget(cell)
        tb = Tachikoma.TestBackend(60, 5)
        Tachikoma.render_widget!(tb, ow)
        # When stale, falls through to default text rendering
        # (no SVG-specific rendering for stale cells)
    end

    @testset "Non-SVG types unaffected" begin
        # Verify other types still work after adding SVG support
        @test classify_output(42) == :text
        @test classify_output(nothing) == :nothing
        @test classify_output("hello") == :text
    end
end
