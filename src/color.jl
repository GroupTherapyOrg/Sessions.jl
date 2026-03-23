# color.jl — Minimal RGB color type (replaces Tachikoma.ColorRGB)

"""24-bit RGB color."""
struct ColorRGB
    r::UInt8
    g::UInt8
    b::UInt8
end
