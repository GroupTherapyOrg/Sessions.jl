# Layer 1: Minimal PNG decoder — PNG bytes → Matrix{Tachikoma.ColorRGB}
#
# Handles only the subset that plotting libraries produce:
# - 8-bit RGB (color type 2)
# - 8-bit RGBA (color type 6)
# - Non-interlaced
# - All 5 filter types (None, Sub, Up, Average, Paeth)
#
# Returns nothing on unsupported or corrupt PNGs.
# Uses CodecZlib (transitive dep via Tachikoma) for zlib decompression.

const _PNG_SIGNATURE = UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]

"""
    decode_png_dimensions(bytes::Vector{UInt8}) → Union{Tuple{Int,Int}, Nothing}

Lightweight header-only parser: reads PNG IHDR to extract (width, height).
Returns `nothing` on invalid/truncated data. Does NOT decompress IDAT.
"""
function decode_png_dimensions(bytes::Vector{UInt8})::Union{Tuple{Int,Int}, Nothing}
    length(bytes) < 24 && return nothing  # sig(8) + IHDR length(4) + type(4) + data(8 min)
    bytes[1:8] != _PNG_SIGNATURE && return nothing
    # IHDR must be the first chunk after signature
    chunk_type = String(bytes[13:16])
    chunk_type == "IHDR" || return nothing
    length(bytes) < 24 && return nothing
    width = Int(ntoh(reinterpret(UInt32, bytes[17:20])[1]))
    height = Int(ntoh(reinterpret(UInt32, bytes[21:24])[1]))
    (width <= 0 || height <= 0) && return nothing
    (width, height)
end

# Locate CodecZlib from loaded modules (guaranteed available via Tachikoma dep)
const _CODECZLIB_PKGID = Base.PkgId(Base.UUID("944b1d66-785c-5afd-91f1-9de20f533193"), "CodecZlib")

function _zlib_decompress(data::Vector{UInt8})::Union{Vector{UInt8}, Nothing}
    zlib = get(Base.loaded_modules, _CODECZLIB_PKGID, nothing)
    zlib === nothing && return nothing
    try
        Base.invokelatest(zlib.transcode, zlib.ZlibDecompressor, data)
    catch
        nothing
    end
end

"""
    decode_png(bytes::Vector{UInt8}) → Union{Matrix{Tachikoma.ColorRGB}, Nothing}

Decode PNG bytes to a pixel matrix. Returns `nothing` on error or unsupported format.
Only supports 8-bit RGB (color type 2) and RGBA (color type 6), non-interlaced.
RGBA pixels are alpha-composited onto black background.
"""
function decode_png(bytes::Vector{UInt8})::Union{Matrix{Tachikoma.ColorRGB}, Nothing}
    length(bytes) < 8 && return nothing
    bytes[1:8] != _PNG_SIGNATURE && return nothing

    # Parse chunks
    width, height, color_type = 0, 0, 0
    idat_data = UInt8[]
    pos = 9  # after signature

    while pos + 7 <= length(bytes)
        chunk_len = Int(ntoh(reinterpret(UInt32, bytes[pos:pos+3])[1]))
        pos + 11 + chunk_len > length(bytes) + 1 && break
        chunk_type = String(bytes[pos+4:pos+7])
        chunk_data = bytes[pos+8:pos+7+chunk_len]
        pos += 12 + chunk_len  # length(4) + type(4) + data + crc(4)

        if chunk_type == "IHDR"
            length(chunk_data) < 13 && return nothing
            width = Int(ntoh(reinterpret(UInt32, chunk_data[1:4])[1]))
            height = Int(ntoh(reinterpret(UInt32, chunk_data[5:8])[1]))
            bit_depth = chunk_data[9]
            color_type = chunk_data[10]
            interlace = chunk_data[13]
            # Only support 8-bit RGB (2) or RGBA (6), non-interlaced
            bit_depth != 8 && return nothing
            color_type != 2 && color_type != 6 && return nothing
            interlace != 0 && return nothing
        elseif chunk_type == "IDAT"
            append!(idat_data, chunk_data)
        elseif chunk_type == "IEND"
            break
        end
    end

    (width <= 0 || height <= 0 || isempty(idat_data)) && return nothing

    # Decompress IDAT
    raw = _zlib_decompress(idat_data)
    raw === nothing && return nothing

    channels = color_type == 6 ? 4 : 3
    stride = width * channels
    expected_len = height * (1 + stride)  # filter byte + pixel data per row
    length(raw) < expected_len && return nothing

    # Unfilter rows
    pixels = Matrix{Tachikoma.ColorRGB}(undef, height, width)
    prev_row = zeros(UInt8, stride)
    curr_row = Vector{UInt8}(undef, stride)

    for y in 1:height
        row_start = (y - 1) * (1 + stride) + 1
        filter_type = raw[row_start]
        row_data = @view raw[row_start+1:row_start+stride]

        # Apply filter reconstruction
        if filter_type == 0x00  # None
            copyto!(curr_row, row_data)
        elseif filter_type == 0x01  # Sub
            _unfilter_sub!(curr_row, row_data, channels)
        elseif filter_type == 0x02  # Up
            _unfilter_up!(curr_row, row_data, prev_row)
        elseif filter_type == 0x03  # Average
            _unfilter_average!(curr_row, row_data, prev_row, channels)
        elseif filter_type == 0x04  # Paeth
            _unfilter_paeth!(curr_row, row_data, prev_row, channels)
        else
            return nothing  # Unknown filter type
        end

        # Extract pixels from unfiltered row
        for x in 1:width
            base = (x - 1) * channels
            r = curr_row[base + 1]
            g = curr_row[base + 2]
            b = curr_row[base + 3]
            if channels == 4
                a = curr_row[base + 4]
                # Alpha-composite onto black background
                r = UInt8(div(Int(r) * Int(a), 255))
                g = UInt8(div(Int(g) * Int(a), 255))
                b = UInt8(div(Int(b) * Int(a), 255))
            end
            pixels[y, x] = Tachikoma.ColorRGB(r, g, b)
        end

        # Current row becomes previous row for next iteration
        copyto!(prev_row, curr_row)
    end

    pixels
end

# --- PNG row unfilter functions ---

function _unfilter_sub!(curr::Vector{UInt8}, raw::AbstractVector{UInt8}, channels::Int)
    @inbounds for i in 1:length(raw)
        a = i <= channels ? UInt8(0) : curr[i - channels]
        curr[i] = raw[i] + a
    end
end

function _unfilter_up!(curr::Vector{UInt8}, raw::AbstractVector{UInt8}, prev::Vector{UInt8})
    @inbounds for i in 1:length(raw)
        curr[i] = raw[i] + prev[i]
    end
end

function _unfilter_average!(curr::Vector{UInt8}, raw::AbstractVector{UInt8}, prev::Vector{UInt8}, channels::Int)
    @inbounds for i in 1:length(raw)
        a = i <= channels ? UInt8(0) : curr[i - channels]
        b = prev[i]
        curr[i] = raw[i] + UInt8(div(Int(a) + Int(b), 2))
    end
end

function _unfilter_paeth!(curr::Vector{UInt8}, raw::AbstractVector{UInt8}, prev::Vector{UInt8}, channels::Int)
    @inbounds for i in 1:length(raw)
        a = i <= channels ? Int(0) : Int(curr[i - channels])
        b = Int(prev[i])
        c = i <= channels ? Int(0) : Int(prev[i - channels])
        curr[i] = raw[i] + UInt8(_paeth_predictor(a, b, c))
    end
end

@inline function _paeth_predictor(a::Int, b::Int, c::Int)
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    pa <= pb && pa <= pc ? a : pb <= pc ? b : c
end
