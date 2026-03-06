# Layer 1: Companion file (.jl.session) — TOML-based execution state persistence

using TOML
using Dates

const SESSION_VERSION = 1
const MAX_TEXT_REPRESENTATION = 50_000  # characters
const MAX_STDOUT = 20_000              # characters
const TRUNCATION_MARKER = "\n... [output truncated for caching — re-execute to see full output]"

"""Return the companion file path for a notebook path."""
session_path(notebook_path::String) = notebook_path * ".session"

"""Truncate a string if it exceeds max_len, appending a truncation marker."""
function _truncate(s::String, max_len::Int)
    length(s) <= max_len && return s
    s[1:max_len] * TRUNCATION_MARKER
end

"""Extract a cacheable error message from a CellOutput."""
function _cached_error_message(output::CellOutput)
    output.error === nothing && return ""
    output.text_representation
end

"""Build a TOML-compatible Dict from notebook execution state."""
function build_session_dict(nb::Notebook)
    cells_dict = Dict{String, Any}()
    for id in nb.cell_order
        cell = nb.cells[id]
        cell.produced_by_hash == "" && continue  # skip never-executed

        cells_dict[string(id)] = Dict{String, Any}(
            "execution_hash" => cell.produced_by_hash,
            "output_type" => string(cell.output.output_type),
            "runtime_ns" => Int64(cell.output.runtime_ns),
            "executed_at" => Dates.format(now(), dateformat"yyyy-mm-ddTHH:MM:SS"),
            "stdout" => _truncate(cell.output.stdout, MAX_STDOUT),
            "error_message" => _cached_error_message(cell.output),
            "text_representation" => _truncate(cell.output.text_representation, MAX_TEXT_REPRESENTATION),
        )
    end

    Dict{String, Any}(
        "meta" => Dict{String, Any}(
            "version" => SESSION_VERSION,
            "sessions_version" => string(pkgversion(Sessions)),
            "notebook_path" => basename(nb.path),
            "created_at" => Dates.format(now(), dateformat"yyyy-mm-ddTHH:MM:SS"),
        ),
        "cells" => cells_dict,
    )
end

"""Save notebook execution state to the companion .jl.session file.
Uses atomic write (write to .tmp, rename) to prevent partial reads."""
function save_session!(nb::Notebook)
    path = session_path(nb.path)
    tmp = path * ".tmp"
    data = build_session_dict(nb)
    Base.open(tmp, "w") do io
        TOML.print(io, data)
    end
    mv(tmp, path; force=true)
    path
end
