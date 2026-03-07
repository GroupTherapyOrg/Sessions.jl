using Test
using Sessions
import Tachikoma

@testset "JPEG Decoder — SESSIONS-9005" begin
    @testset "decode_jpeg_dimensions — valid JPEG header" begin
        # Minimal JPEG with SOF0 marker: FFD8 FF C0 ...
        # SOF0: length=11, precision=8, height=100, width=200, ncomp=3
        jpeg = UInt8[
            0xFF, 0xD8,                         # SOI
            0xFF, 0xC0,                         # SOF0
            0x00, 0x0B,                         # length = 11
            0x08,                               # precision = 8
            0x00, 0x64,                         # height = 100
            0x00, 0xC8,                         # width = 200
            0x03,                               # ncomp = 3
            0x01, 0x22, 0x00,                   # comp 1: h=2,v=2, qt=0
            0x02, 0x11, 0x01,                   # comp 2: h=1,v=1, qt=1
            0x03, 0x11, 0x01,                   # comp 3: h=1,v=1, qt=1
        ]
        dims = Sessions.decode_jpeg_dimensions(jpeg)
        @test dims !== nothing
        @test dims == (200, 100)
    end

    @testset "decode_jpeg_dimensions — JPEG with APP0 before SOF" begin
        # JFIF: SOI + APP0 + SOF0
        jpeg = UInt8[
            0xFF, 0xD8,                         # SOI
            0xFF, 0xE0,                         # APP0 (JFIF)
            0x00, 0x04, 0x00, 0x00,             # APP0 data (length=4, minimal)
            0xFF, 0xC0,                         # SOF0
            0x00, 0x0B,                         # length = 11
            0x08,                               # precision = 8
            0x01, 0xE0,                         # height = 480
            0x02, 0x80,                         # width = 640
            0x03,                               # ncomp = 3
            0x01, 0x22, 0x00,
            0x02, 0x11, 0x01,
            0x03, 0x11, 0x01,
        ]
        dims = Sessions.decode_jpeg_dimensions(jpeg)
        @test dims !== nothing
        @test dims == (640, 480)
    end

    @testset "decode_jpeg_dimensions — invalid data" begin
        @test Sessions.decode_jpeg_dimensions(UInt8[]) === nothing
        @test Sessions.decode_jpeg_dimensions(UInt8[0x00, 0x01]) === nothing
        @test Sessions.decode_jpeg_dimensions(UInt8[0xFF, 0xD8]) === nothing  # truncated
    end

    @testset "decode_jpeg_dimensions — PNG data returns nothing" begin
        png_sig = UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
        @test Sessions.decode_jpeg_dimensions(png_sig) === nothing
    end

    @testset "classify_output — JPEG MIME detection" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty

            # Create a type that supports image/jpeg
            struct JpegTestResult end
            Base.showable(::MIME"image/jpeg", ::JpegTestResult) = true
            Base.show(io::IO, ::MIME"image/jpeg", ::JpegTestResult) = write(io, UInt8[0xFF, 0xD8])
            Base.showable(::MIME"image/png", ::JpegTestResult) = false
            Base.showable(::MIME"text/plain", ::JpegTestResult) = false

            @test classify_output(JpegTestResult()) == :image_jpeg
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "classify_output — PNG preferred over JPEG" begin
        old_proto = Tachikoma.GRAPHICS_PROTOCOL[]
        try
            Tachikoma.GRAPHICS_PROTOCOL[] = Tachikoma.gfx_kitty

            # Type that supports both PNG and JPEG — PNG should win
            struct PngJpegResult end
            Base.showable(::MIME"image/png", ::PngJpegResult) = true
            Base.showable(::MIME"image/jpeg", ::PngJpegResult) = true
            Base.show(io::IO, ::MIME"image/png", ::PngJpegResult) = nothing
            Base.show(io::IO, ::MIME"image/jpeg", ::PngJpegResult) = nothing

            @test classify_output(PngJpegResult()) == :image_png  # PNG preferred
        finally
            Tachikoma.GRAPHICS_PROTOCOL[] = old_proto
        end
    end

    @testset "_capture_jpeg_bytes" begin
        struct JpegCapTest end
        Base.showable(::MIME"image/jpeg", ::JpegCapTest) = true
        function Base.show(io::IO, ::MIME"image/jpeg", ::JpegCapTest)
            write(io, UInt8[0xFF, 0xD8, 0xFF, 0xD9])
        end

        bytes = Sessions._capture_jpeg_bytes(JpegCapTest())
        @test bytes !== nothing
        @test bytes == UInt8[0xFF, 0xD8, 0xFF, 0xD9]

        # Non-JPEG type returns nothing
        @test Sessions._capture_jpeg_bytes(42) === nothing
    end

    @testset "output_height for JPEG image" begin
        cell = Cell("img()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_jpeg
        # Create JPEG header with known dimensions (200x100)
        cell.output.image_data = UInt8[
            0xFF, 0xD8,
            0xFF, 0xC0, 0x00, 0x0B, 0x08,
            0x00, 0x64, 0x00, 0xC8,  # 100h x 200w
            0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
        ]

        ow = Sessions.OutputWidget(cell)
        h = Sessions.output_height(ow)
        # 200x100 image: aspect = 100/200 = 0.5, rows = 0.5*80/2 = 20, clamped to 16
        @test h == 16
    end

    @testset "output_height falls back for corrupt JPEG" begin
        cell = Cell("img()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_jpeg
        cell.output.image_data = UInt8[0xFF, 0xD8, 0xFF]  # truncated

        ow = Sessions.OutputWidget(cell)
        h = Sessions.output_height(ow)
        @test h == Sessions._IMAGE_HEIGHT_DEFAULT
    end

    @testset "Huffman table construction" begin
        # Standard DC luminance table (partial)
        counts = Int[0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0]
        symbols = UInt8[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
        ht = Sessions._build_huffman_table(counts, symbols)
        @test length(ht.values) == 12
        @test ht.mincode[2] == 0  # first 2-bit code
        @test ht.maxcode[2] == 0  # only one 2-bit code
    end

    @testset "Bitstream reader" begin
        br = Sessions._JpegBitReader(UInt8[0b10110100, 0b01010101])
        @test Sessions._read_bits(br, 1) == 1
        @test Sessions._read_bits(br, 3) == 0b011
        @test Sessions._read_bits(br, 4) == 0b0100
    end

    @testset "SOS data extraction (byte-stuffing)" begin
        data = UInt8[0x01, 0xFF, 0x00, 0x02, 0xFF, 0xD9]  # FF00 = stuffed, FFD9 = marker
        result = Sessions._extract_sos_data(data, 1)
        @test result == UInt8[0x01, 0xFF, 0x02]
    end

    @testset "Receive and extend" begin
        br = Sessions._JpegBitReader(UInt8[0b10000000])
        @test Sessions._receive_extend(br, 1) == 1   # bit=1 → positive

        br2 = Sessions._JpegBitReader(UInt8[0b00000000])
        @test Sessions._receive_extend(br2, 1) == -1  # bit=0 → negative

        @test Sessions._receive_extend(Sessions._JpegBitReader(UInt8[]), 0) == 0
    end

    @testset "JPEG render path — corrupt data shows fallback" begin
        cell = Cell("img()")
        cell.state = Sessions.cell_done
        cell.output.output_type = :image_jpeg
        cell.output.image_data = UInt8[0xFF, 0xD8, 0x00, 0x01]  # invalid JPEG

        ow = Sessions.OutputWidget(cell)
        tb = Tachikoma.TestBackend(60, 14)
        Tachikoma.render_widget!(tb, ow)
        @test Tachikoma.find_text(tb, "unable to decode") !== nothing
    end
end
