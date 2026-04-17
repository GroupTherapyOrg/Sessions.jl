# Types.jl — shared types for the extract pipeline.
# Defined early so all stage modules (CellGraph / StaticRender / Emit /
# Extractor) can reference each other without ordering pain.

"""
    CellClass

Per-cell classification result. `bond_name` is the symbol the user
bound (e.g. `:n` from `@bind n BoundSlider(...)`) for `:bond` cells,
otherwise `nothing`. `upstream_bonds` is the set of bond names this
cell transitively depends on (only populated for `:reactive` cells).
"""
struct CellClass
    cell::Cell
    kind::Symbol                            # :bond | :reactive | :static
    bond_name::Union{Symbol, Nothing}
    upstream_bonds::Set{Symbol}
end

"""
    ExtractionPlan

Computed bundle of everything the emitter needs.
"""
struct ExtractionPlan
    notebook_path::String
    component_name::String
    out_path::String
    cells::Vector{CellClass}
    outputs::Dict{Any, String}           # cell.id → rendered HTML
    imports::Vector{String}
    runtime_imports::Vector{String}
end
