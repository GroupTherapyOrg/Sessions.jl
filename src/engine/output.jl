# Layer 1: Minimal PNG decoder — PNG bytes → Matrix{ColorRGB}
#
# Handles only the subset that plotting libraries produce:
# - 8-bit RGB (color type 2)
# - 8-bit RGBA (color type 6)
# - Non-interlaced
# - All 5 filter types (None, Sub, Up, Average, Paeth)
#
# Returns nothing on unsupported or corrupt PNGs.
# Uses CodecZlib for zlib decompression.

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

# Locate CodecZlib from loaded modules
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
    decode_png(bytes::Vector{UInt8}) → Union{Matrix{ColorRGB}, Nothing}

Decode PNG bytes to a pixel matrix. Returns `nothing` on error or unsupported format.
Only supports 8-bit RGB (color type 2) and RGBA (color type 6), non-interlaced.
RGBA pixels are alpha-composited onto black background.
"""
function decode_png(bytes::Vector{UInt8})::Union{Matrix{ColorRGB}, Nothing}
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
    pixels = Matrix{ColorRGB}(undef, height, width)
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
            pixels[y, x] = ColorRGB(r, g, b)
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

# Layer 1: Minimal JPEG decoder — JPEG bytes → Matrix{ColorRGB}
#
# Handles only baseline sequential (SOF0):
# - 8-bit, 3-component YCbCr
# - 4:4:4 and 4:2:0 chroma subsampling
# - Custom or standard Huffman tables
#
# Returns nothing on unsupported or corrupt JPEGs.

const _JPEG_SOI = UInt8[0xFF, 0xD8]  # Start of Image

"""
    decode_jpeg_dimensions(bytes::Vector{UInt8}) → Union{Tuple{Int,Int}, Nothing}

Read JPEG SOF marker to extract (width, height). Does NOT decode image data.
"""
function decode_jpeg_dimensions(bytes::Vector{UInt8})::Union{Tuple{Int,Int}, Nothing}
    length(bytes) < 4 && return nothing
    bytes[1:2] != _JPEG_SOI && return nothing

    pos = 3
    while pos + 1 <= length(bytes)
        bytes[pos] != 0xFF && return nothing
        # Skip padding FF bytes
        while pos <= length(bytes) && bytes[pos] == 0xFF
            pos += 1
        end
        pos > length(bytes) && return nothing
        marker = bytes[pos]
        pos += 1

        # SOF0 (baseline) or SOF2 (progressive) — both have same header format
        if marker == 0xC0 || marker == 0xC2
            pos + 7 > length(bytes) && return nothing
            # pos+0,+1 = length, pos+2 = precision, pos+3,+4 = height, pos+5,+6 = width
            height = Int(UInt16(bytes[pos+3]) << 8 | bytes[pos+4])
            width = Int(UInt16(bytes[pos+5]) << 8 | bytes[pos+6])
            (width <= 0 || height <= 0) && return nothing
            return (width, height)
        end

        # Skip other markers (read length and advance)
        if marker == 0xD9  # EOI
            return nothing
        elseif marker == 0xD8 || (0xD0 <= marker <= 0xD7)
            # Standalone markers (no length)
            continue
        end
        pos + 1 > length(bytes) && return nothing
        seg_len = Int(UInt16(bytes[pos]) << 8 | bytes[pos+1])
        pos += seg_len
    end
    nothing
end

"""
    decode_jpeg(bytes::Vector{UInt8}) → Union{Matrix{ColorRGB}, Nothing}

Decode baseline JPEG (SOF0) to a pixel matrix.
Returns `nothing` on error, progressive, or unsupported format.
Only supports 8-bit YCbCr with 4:4:4 or 4:2:0 subsampling.
"""
function decode_jpeg(bytes::Vector{UInt8})::Union{Matrix{ColorRGB}, Nothing}
    length(bytes) < 4 && return nothing
    bytes[1:2] != _JPEG_SOI && return nothing

    # Parse all markers
    width, height = 0, 0
    ncomp = 0
    comp_h_samp = Int[0, 0, 0]  # horizontal sampling factors
    comp_v_samp = Int[0, 0, 0]  # vertical sampling factors
    comp_qt_id = Int[0, 0, 0]   # quantization table ID per component
    comp_dc_id = Int[0, 0, 0]   # DC Huffman table ID per component
    comp_ac_id = Int[0, 0, 0]   # AC Huffman table ID per component
    qt_tables = Dict{Int, Vector{Int}}()     # quantization tables (zigzag order)
    dc_tables = Dict{Int, _JpegHuffTable}()  # DC Huffman tables
    ac_tables = Dict{Int, _JpegHuffTable}()  # AC Huffman tables
    sos_data = UInt8[]
    found_sof = false

    pos = 3
    while pos + 1 <= length(bytes)
        bytes[pos] != 0xFF && break
        while pos <= length(bytes) && bytes[pos] == 0xFF; pos += 1; end
        pos > length(bytes) && break
        marker = bytes[pos]; pos += 1

        if marker == 0xC0  # SOF0 — baseline sequential
            pos + 1 > length(bytes) && return nothing
            seg_len = Int(UInt16(bytes[pos]) << 8 | bytes[pos+1])
            pos + seg_len > length(bytes) + 1 && return nothing
            precision = bytes[pos+2]
            precision != 8 && return nothing  # only 8-bit
            height = Int(UInt16(bytes[pos+3]) << 8 | bytes[pos+4])
            width = Int(UInt16(bytes[pos+5]) << 8 | bytes[pos+6])
            ncomp = Int(bytes[pos+7])
            ncomp != 3 && return nothing  # only 3-component (YCbCr)
            for i in 1:3
                base = pos + 8 + (i-1)*3
                base + 2 > length(bytes) && return nothing
                # component ID (ignored), sampling factors, QT table
                samp = bytes[base+1]
                comp_h_samp[i] = Int(samp >> 4)
                comp_v_samp[i] = Int(samp & 0x0F)
                comp_qt_id[i] = Int(bytes[base+2])
            end
            found_sof = true
            pos += seg_len

        elseif marker == 0xC2  # SOF2 — progressive (not supported)
            return nothing

        elseif marker == 0xC4  # DHT — Huffman table
            pos + 1 > length(bytes) && return nothing
            seg_len = Int(UInt16(bytes[pos]) << 8 | bytes[pos+1])
            seg_end = pos + seg_len
            p = pos + 2
            while p < seg_end
                p > length(bytes) && return nothing
                tc_th = bytes[p]; p += 1
                tc = Int(tc_th >> 4)  # 0=DC, 1=AC
                th = Int(tc_th & 0x0F)  # table ID
                p + 15 > length(bytes) && return nothing
                counts = Int[bytes[p+i] for i in 0:15]; p += 16
                total = sum(counts)
                p + total - 1 > length(bytes) && return nothing
                symbols = UInt8[bytes[p+i] for i in 0:total-1]; p += total
                ht = _build_huffman_table(counts, symbols)
                if tc == 0
                    dc_tables[th] = ht
                else
                    ac_tables[th] = ht
                end
            end
            pos = seg_end

        elseif marker == 0xDB  # DQT — quantization table
            pos + 1 > length(bytes) && return nothing
            seg_len = Int(UInt16(bytes[pos]) << 8 | bytes[pos+1])
            seg_end = pos + seg_len
            p = pos + 2
            while p < seg_end
                p > length(bytes) && return nothing
                pq_tq = bytes[p]; p += 1
                pq = Int(pq_tq >> 4)  # precision (0=8-bit, 1=16-bit)
                tq = Int(pq_tq & 0x0F)  # table ID
                if pq == 0
                    p + 63 > length(bytes) && return nothing
                    qt_tables[tq] = Int[bytes[p+i] for i in 0:63]; p += 64
                else
                    p + 127 > length(bytes) && return nothing
                    qt_tables[tq] = Int[Int(UInt16(bytes[p+2i]) << 8 | bytes[p+2i+1]) for i in 0:63]
                    p += 128
                end
            end
            pos = seg_end

        elseif marker == 0xDA  # SOS — start of scan
            pos + 1 > length(bytes) && return nothing
            seg_len = Int(UInt16(bytes[pos]) << 8 | bytes[pos+1])
            # Read component table selectors
            p = pos + 2
            ns = Int(bytes[p]); p += 1
            for i in 1:ns
                p + 1 > length(bytes) && return nothing
                # component selector, DC/AC table IDs
                dc_ac = bytes[p+1]; p += 2
                comp_dc_id[i] = Int(dc_ac >> 4)
                comp_ac_id[i] = Int(dc_ac & 0x0F)
            end
            pos += seg_len
            # Rest is entropy-coded data until next marker
            sos_data = _extract_sos_data(bytes, pos)
            break

        elseif marker == 0xD9  # EOI
            break
        elseif marker == 0xD8 || (0xD0 <= marker <= 0xD7)
            continue  # standalone markers
        else
            # Skip unknown marker
            pos + 1 > length(bytes) && break
            seg_len = Int(UInt16(bytes[pos]) << 8 | bytes[pos+1])
            pos += seg_len
        end
    end

    !found_sof && return nothing
    (width <= 0 || height <= 0) && return nothing
    isempty(sos_data) && return nothing
    isempty(qt_tables) && return nothing
    isempty(dc_tables) && return nothing
    isempty(ac_tables) && return nothing

    # Determine subsampling
    max_h = maximum(comp_h_samp)
    max_v = maximum(comp_v_samp)

    # Decode MCU blocks
    try
        return _decode_jpeg_data(sos_data, width, height, ncomp,
                                 comp_h_samp, comp_v_samp, max_h, max_v,
                                 comp_qt_id, comp_dc_id, comp_ac_id,
                                 qt_tables, dc_tables, ac_tables)
    catch
        return nothing
    end
end

# --- Huffman table ---

struct _JpegHuffTable
    mincode::Vector{Int}   # first code value for each bit length (1-16)
    maxcode::Vector{Int}   # max code value for each bit length (1-16), -1 if none
    valptr::Vector{Int}    # index into values for first symbol at each bit length
    values::Vector{UInt8}  # decoded symbol values
end

function _build_huffman_table(counts::Vector{Int}, symbols::Vector{UInt8})
    mincode = fill(0, 16)
    maxcode = fill(-1, 16)
    valptr = fill(0, 16)
    code = 0
    si = 1
    for bits in 1:16
        if counts[bits] > 0
            valptr[bits] = si
            mincode[bits] = code
            maxcode[bits] = code + counts[bits] - 1
            si += counts[bits]
        end
        code = (code + counts[bits]) << 1
    end
    _JpegHuffTable(mincode, maxcode, valptr, symbols)
end

# --- Bitstream reader ---

mutable struct _JpegBitReader
    data::Vector{UInt8}
    pos::Int
    bit_buf::UInt32
    bits_left::Int
end

_JpegBitReader(data::Vector{UInt8}) = _JpegBitReader(data, 1, UInt32(0), 0)

function _read_bits(br::_JpegBitReader, n::Int)::Int
    while br.bits_left < n
        if br.pos > length(br.data)
            br.bit_buf = (br.bit_buf << 8)
            br.bits_left += 8
            continue
        end
        b = br.data[br.pos]; br.pos += 1
        br.bit_buf = (br.bit_buf << 8) | UInt32(b)
        br.bits_left += 8
    end
    br.bits_left -= n
    Int((br.bit_buf >> br.bits_left) & ((UInt32(1) << n) - 1))
end

function _decode_huffman(br::_JpegBitReader, ht::_JpegHuffTable)::UInt8
    code = 0
    for bits in 1:16
        code = (code << 1) | _read_bits(br, 1)
        if ht.maxcode[bits] >= 0 && code <= ht.maxcode[bits]
            return ht.values[ht.valptr[bits] + code - ht.mincode[bits]]
        end
    end
    UInt8(0)
end

function _receive_extend(br::_JpegBitReader, nbits::Int)::Int
    nbits == 0 && return 0
    val = _read_bits(br, nbits)
    if val < (1 << (nbits - 1))
        val -= (1 << nbits) - 1
    end
    val
end

# --- Extract entropy data (byte-stuffing removed) ---

function _extract_sos_data(bytes::Vector{UInt8}, start::Int)::Vector{UInt8}
    result = UInt8[]
    i = start
    while i <= length(bytes)
        b = bytes[i]
        if b == 0xFF
            i + 1 > length(bytes) && break
            next = bytes[i+1]
            if next == 0x00
                push!(result, 0xFF)  # byte-stuffed FF
                i += 2
            elseif 0xD0 <= next <= 0xD7
                # RST marker — skip
                i += 2
            else
                break  # next marker found
            end
        else
            push!(result, b)
            i += 1
        end
    end
    result
end

# --- Zigzag order ---

const _ZIGZAG_ORDER = Int[
     1,  2,  6,  7, 15, 16, 28, 29,
     3,  5,  8, 14, 17, 27, 30, 43,
     4,  9, 13, 18, 26, 31, 42, 44,
    10, 12, 19, 25, 32, 41, 45, 54,
    11, 20, 24, 33, 40, 46, 53, 55,
    21, 23, 34, 39, 47, 52, 56, 61,
    22, 35, 38, 48, 51, 57, 60, 62,
    36, 37, 49, 50, 58, 59, 63, 64
]

# --- Inverse DCT (8x8) ---

function _idct_8x8!(block::Vector{Float64})
    # Apply 1D IDCT on rows then columns
    tmp = Vector{Float64}(undef, 8)
    # Rows
    for row in 0:7
        _idct_1d!(block, row*8+1, tmp)
    end
    # Transpose and columns (work on columns of original)
    col_buf = Vector{Float64}(undef, 64)
    for c in 1:8
        for r in 0:7
            tmp[r+1] = block[r*8+c]
        end
        _idct_1d!(tmp, 1, col_buf)
        for r in 0:7
            block[r*8+c] = col_buf[r+1]
        end
    end
end

const _COS_TABLE = Float64[cos((2k+1)*n*π/16) for k in 0:7, n in 0:7]

function _idct_1d!(data::Vector{Float64}, offset::Int, tmp::Vector{Float64})
    for i in 0:7
        sum = 0.0
        for j in 0:7
            c = j == 0 ? 1.0/sqrt(2.0) : 1.0
            sum += c * data[offset+j] * _COS_TABLE[i+1, j+1]
        end
        tmp[i+1] = sum / 2.0
    end
    for i in 0:7
        data[offset+i] = tmp[i+1]
    end
end

# --- Main decode pipeline ---

function _decode_jpeg_data(sos_data, width, height, ncomp,
                           h_samp, v_samp, max_h, max_v,
                           qt_id, dc_id, ac_id,
                           qt_tables, dc_tables, ac_tables)
    # MCU dimensions
    mcu_w = max_h * 8
    mcu_h = max_v * 8
    mcus_x = cld(width, mcu_w)
    mcus_y = cld(height, mcu_h)

    # Component data buffers (full image, padded to MCU grid)
    pw = mcus_x * mcu_w
    ph = mcus_y * mcu_h
    comp_data = [zeros(Float64, ph ÷ (max_v ÷ v_samp[c]) , pw ÷ (max_h ÷ h_samp[c])) for c in 1:3]

    br = _JpegBitReader(sos_data)
    dc_pred = Int[0, 0, 0]

    for mcu_y in 0:mcus_y-1
        for mcu_x in 0:mcus_x-1
            for c in 1:3
                for vy in 0:v_samp[c]-1
                    for hx in 0:h_samp[c]-1
                        block = zeros(Float64, 64)

                        # Decode DC coefficient
                        dc_ht = get(dc_tables, dc_id[c], nothing)
                        dc_ht === nothing && return nothing
                        dc_cat = Int(_decode_huffman(br, dc_ht))
                        dc_diff = _receive_extend(br, dc_cat)
                        dc_pred[c] += dc_diff
                        block[1] = Float64(dc_pred[c])

                        # Decode AC coefficients
                        ac_ht = get(ac_tables, ac_id[c], nothing)
                        ac_ht === nothing && return nothing
                        k = 2
                        while k <= 64
                            rs = Int(_decode_huffman(br, ac_ht))
                            r = rs >> 4    # run of zeros
                            s = rs & 0x0F  # category
                            if s == 0
                                r == 0 && break   # EOB
                                r == 15 && (k += 16; continue)  # ZRL
                                break
                            end
                            k += r
                            k > 64 && break
                            block[_ZIGZAG_ORDER[k]] = Float64(_receive_extend(br, s))
                            k += 1
                        end

                        # Dequantize
                        qt = get(qt_tables, qt_id[c], nothing)
                        qt === nothing && return nothing
                        for i in 1:64
                            block[i] *= qt[i]
                        end

                        # Inverse DCT
                        _idct_8x8!(block)

                        # Store in component buffer
                        bx = mcu_x * h_samp[c] * 8 + hx * 8
                        by = mcu_y * v_samp[c] * 8 + vy * 8
                        cd = comp_data[c]
                        for py in 0:7
                            for px in 0:7
                                cy = by + py + 1
                                cx = bx + px + 1
                                if cy <= size(cd, 1) && cx <= size(cd, 2)
                                    cd[cy, cx] = block[py*8+px+1] + 128.0
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    # YCbCr → RGB conversion with chroma upsampling
    pixels = Matrix{ColorRGB}(undef, height, width)
    y_data = comp_data[1]
    cb_data = comp_data[2]
    cr_data = comp_data[3]

    cb_scale_x = max_h ÷ h_samp[2]
    cb_scale_y = max_v ÷ v_samp[2]
    cr_scale_x = max_h ÷ h_samp[3]
    cr_scale_y = max_v ÷ v_samp[3]

    for py in 1:height
        for px in 1:width
            y_val = y_data[py, px]
            cb_val = cb_data[cld(py, cb_scale_y), cld(px, cb_scale_x)]
            cr_val = cr_data[cld(py, cr_scale_y), cld(px, cr_scale_x)]

            r = y_val + 1.402 * (cr_val - 128.0)
            g = y_val - 0.344136 * (cb_val - 128.0) - 0.714136 * (cr_val - 128.0)
            b = y_val + 1.772 * (cb_val - 128.0)

            pixels[py, px] = ColorRGB(
                UInt8(clamp(round(Int, r), 0, 255)),
                UInt8(clamp(round(Int, g), 0, 255)),
                UInt8(clamp(round(Int, b), 0, 255))
            )
        end
    end

    pixels
end
