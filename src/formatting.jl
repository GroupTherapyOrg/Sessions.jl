# Layer 1: Code Formatting — Runic.jl runtime-loaded formatter
# Runic.jl is NOT a hard dependency. It is loaded at runtime via Base.require.
# If Runic is not installed, format_code() returns the original code unchanged.

const _RUNIC_MOD = Ref{Union{Module, Nothing}}(nothing)
const _RUNIC_LOADED = Ref(false)

"""Try to load Runic.jl at runtime. Returns the module or nothing."""
function _load_runic()
    _RUNIC_LOADED[] && return _RUNIC_MOD[]
    _RUNIC_LOADED[] = true
    try
        _RUNIC_MOD[] = Base.require(Base.PkgId(Base.UUID("62bfec6d-59d7-401d-8490-b29ee721c001"), "Runic"))
    catch
        _RUNIC_MOD[] = nothing
    end
    _RUNIC_MOD[]
end

"""Check if Runic.jl is available for formatting."""
function format_code_available()::Bool
    _load_runic() !== nothing
end

"""Format Julia source code using Runic.jl.

Returns formatted code if Runic is available and the code is valid Julia.
Returns the original code unchanged if:
- Runic.jl is not installed
- The code has syntax errors that prevent formatting
- Any other error occurs during formatting
"""
function format_code(code::String)::String
    isempty(code) && return code
    runic = _load_runic()
    runic === nothing && return code
    try
        fmt_fn = getfield(runic, :format_string)
        formatted = Base.invokelatest(fmt_fn, code)
        return formatted
    catch
        return code
    end
end
