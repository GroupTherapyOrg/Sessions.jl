using Test
using Sessions
import Tachikoma

@testset "PNG Decoder — SESSIONS-8030" begin
    # Helper to build a valid PNG from raw pixel data
    function _build_test_png(width, height, color_type, raw_pixels; filter_type=0x00)
        io = IOBuffer()
        # PNG signature
        write(io, UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

        # IHDR
        ihdr = IOBuffer()
        write(ihdr, hton(UInt32(width)))
        write(ihdr, hton(UInt32(height)))
        write(ihdr, UInt8(8))           # bit depth
        write(ihdr, UInt8(color_type))  # 2=RGB, 6=RGBA
        write(ihdr, UInt8(0))           # compression
        write(ihdr, UInt8(0))           # filter method
        write(ihdr, UInt8(0))           # interlace: none
        _write_png_chunk(io, b"IHDR", take!(ihdr))

        # IDAT: add filter byte per row, then zlib compress
        channels = color_type == 6 ? 4 : 3
        stride = width * channels
        raw = IOBuffer()
        for row in 0:height-1
            write(raw, UInt8(filter_type))
            write(raw, raw_pixels[row*stride+1 : (row+1)*stride])
        end
        raw_data = take!(raw)
        # Use zlib compress via CodecZlib (loaded by Tachikoma)
        codec_zlib = Base.loaded_modules[Base.PkgId(Base.UUID("944b1d66-785c-5afd-91f1-9de20f533193"), "CodecZlib")]
        compressed = Base.invokelatest(codec_zlib.transcode, codec_zlib.ZlibCompressor, raw_data)
        _write_png_chunk(io, b"IDAT", compressed)

        # IEND
        _write_png_chunk(io, b"IEND", UInt8[])
        take!(io)
    end

    function _write_png_chunk(io, chunk_type, data)
        write(io, hton(UInt32(length(data))))
        write(io, chunk_type)
        write(io, data)
        crc_data = vcat(Vector{UInt8}(chunk_type), data)
        write(io, hton(UInt32(_crc32(crc_data))))
    end

    function _crc32(data::Vector{UInt8})
        c = UInt32(0xffffffff)
        for b in data
            c = xor(c, UInt32(b))
            for _ in 1:8
                c = (c & 1) != 0 ? xor(c >> 1, UInt32(0xedb88320)) : c >> 1
            end
        end
        xor(c, UInt32(0xffffffff))
    end

    @testset "decode 1x1 RGB PNG" begin
        pixels_rgb = UInt8[0xff, 0x00, 0x00]  # red
        png = _build_test_png(1, 1, 2, pixels_rgb)
        result = Sessions.decode_png(png)
        @test result !== nothing
        @test size(result) == (1, 1)
        @test result[1, 1] == Tachikoma.ColorRGB(0xff, 0x00, 0x00)
    end

    @testset "decode 2x2 RGB PNG" begin
        pixels_rgb = UInt8[
            0xff, 0x00, 0x00,  0x00, 0xff, 0x00,  # row 1: red, green
            0x00, 0x00, 0xff,  0xff, 0xff, 0xff,  # row 2: blue, white
        ]
        png = _build_test_png(2, 2, 2, pixels_rgb)
        result = Sessions.decode_png(png)
        @test result !== nothing
        @test size(result) == (2, 2)
        @test result[1, 1] == Tachikoma.ColorRGB(0xff, 0x00, 0x00)  # red
        @test result[1, 2] == Tachikoma.ColorRGB(0x00, 0xff, 0x00)  # green
        @test result[2, 1] == Tachikoma.ColorRGB(0x00, 0x00, 0xff)  # blue
        @test result[2, 2] == Tachikoma.ColorRGB(0xff, 0xff, 0xff)  # white
    end

    @testset "decode 1x1 RGBA PNG" begin
        pixels_rgba = UInt8[0xff, 0x00, 0x00, 0xff]  # red, full alpha
        png = _build_test_png(1, 1, 6, pixels_rgba)
        result = Sessions.decode_png(png)
        @test result !== nothing
        @test size(result) == (1, 1)
        @test result[1, 1] == Tachikoma.ColorRGB(0xff, 0x00, 0x00)
    end

    @testset "decode 2x2 RGBA PNG — alpha compositing on black" begin
        # Semi-transparent red (alpha=128) on black background → dark red
        pixels_rgba = UInt8[
            0xff, 0x00, 0x00, 0x80,  # semi-transparent red
            0x00, 0xff, 0x00, 0xff,  # opaque green
            0x00, 0x00, 0xff, 0x00,  # fully transparent blue → black
            0xff, 0xff, 0xff, 0xff,  # opaque white
        ]
        png = _build_test_png(2, 2, 6, pixels_rgba)
        result = Sessions.decode_png(png)
        @test result !== nothing
        @test size(result) == (2, 2)
        # Semi-transparent red on black: r=255*128/255≈128, g=0, b=0
        r1 = result[1, 1]
        @test r1.r > 0x60 && r1.r < 0x90  # approximately 128
        @test r1.g == 0x00
        @test r1.b == 0x00
        # Opaque green
        @test result[1, 2] == Tachikoma.ColorRGB(0x00, 0xff, 0x00)
        # Fully transparent → black
        @test result[2, 1] == Tachikoma.ColorRGB(0x00, 0x00, 0x00)
        # Opaque white
        @test result[2, 2] == Tachikoma.ColorRGB(0xff, 0xff, 0xff)
    end

    @testset "decode with Sub filter (type 1)" begin
        # Sub filter: each byte = raw - left byte
        # For 2x1 RGB: [R1,G1,B1, R2-R1, G2-G1, B2-B1]
        # Pixel 1: (0x80, 0x40, 0x20), Pixel 2: (0xa0, 0x60, 0x30)
        # Sub-filtered: [0x80, 0x40, 0x20, 0x20, 0x20, 0x10]
        # (0xa0-0x80=0x20, 0x60-0x40=0x20, 0x30-0x20=0x10)
        raw_filtered = UInt8[0x80, 0x40, 0x20, 0x20, 0x20, 0x10]

        # Build PNG with filter type 1 (Sub) — need to compress the filter byte + filtered data
        io = IOBuffer()
        write(io, UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        ihdr = IOBuffer()
        write(ihdr, hton(UInt32(2)))  # width
        write(ihdr, hton(UInt32(1)))  # height
        write(ihdr, UInt8(8), UInt8(2), UInt8(0), UInt8(0), UInt8(0))
        _write_png_chunk(io, b"IHDR", take!(ihdr))

        # IDAT with filter type 1 prefix
        idat_raw = vcat(UInt8[0x01], raw_filtered)  # filter type 1 + filtered data
        codec_zlib = Base.loaded_modules[Base.PkgId(Base.UUID("944b1d66-785c-5afd-91f1-9de20f533193"), "CodecZlib")]
        compressed = Base.invokelatest(codec_zlib.transcode, codec_zlib.ZlibCompressor, idat_raw)
        _write_png_chunk(io, b"IDAT", compressed)
        _write_png_chunk(io, b"IEND", UInt8[])

        png = take!(io)
        result = Sessions.decode_png(png)
        @test result !== nothing
        @test size(result) == (1, 2)
        @test result[1, 1] == Tachikoma.ColorRGB(0x80, 0x40, 0x20)
        @test result[1, 2] == Tachikoma.ColorRGB(0xa0, 0x60, 0x30)
    end

    @testset "invalid/corrupt PNG" begin
        # Empty bytes
        @test Sessions.decode_png(UInt8[]) === nothing

        # Too short
        @test Sessions.decode_png(UInt8[0x89, 0x50]) === nothing

        # Wrong signature
        @test Sessions.decode_png(UInt8[0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) === nothing

        # Just signature, no chunks
        sig = UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
        @test Sessions.decode_png(sig) === nothing
    end

    @testset "unsupported PNG formats" begin
        # Paletted (color type 3) — not supported
        io = IOBuffer()
        write(io, UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        ihdr = IOBuffer()
        write(ihdr, hton(UInt32(1)), hton(UInt32(1)))
        write(ihdr, UInt8(8), UInt8(3), UInt8(0), UInt8(0), UInt8(0))  # color type 3
        _write_png_chunk(io, b"IHDR", take!(ihdr))
        _write_png_chunk(io, b"IEND", UInt8[])
        @test Sessions.decode_png(take!(io)) === nothing

        # 16-bit depth — not supported
        io = IOBuffer()
        write(io, UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        ihdr = IOBuffer()
        write(ihdr, hton(UInt32(1)), hton(UInt32(1)))
        write(ihdr, UInt8(16), UInt8(2), UInt8(0), UInt8(0), UInt8(0))  # 16-bit
        _write_png_chunk(io, b"IHDR", take!(ihdr))
        _write_png_chunk(io, b"IEND", UInt8[])
        @test Sessions.decode_png(take!(io)) === nothing

        # Interlaced — not supported
        io = IOBuffer()
        write(io, UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        ihdr = IOBuffer()
        write(ihdr, hton(UInt32(1)), hton(UInt32(1)))
        write(ihdr, UInt8(8), UInt8(2), UInt8(0), UInt8(0), UInt8(1))  # interlaced
        _write_png_chunk(io, b"IHDR", take!(ihdr))
        _write_png_chunk(io, b"IEND", UInt8[])
        @test Sessions.decode_png(take!(io)) === nothing
    end
end
