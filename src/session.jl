# Layer 1: Companion file (.session.toml) — TOML-based execution state persistence

using TOML
using Dates

const SESSION_VERSION = 1
const MAX_TEXT_REPRESENTATION = 50_000  # characters
const MAX_STDOUT = 20_000              # characters
const TRUNCATION_MARKER = "\n... [output truncated for caching — re-execute to see full output]"

"""Return the companion file path for a notebook path (e.g. `foo.jl` → `foo.session.toml`)."""
session_path(notebook_path::String) = replace(notebook_path, r"\.jl$" => "") * ".session.toml"

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

"""Save notebook execution state to the companion .session.toml file.
Uses atomic write (write to .tmp, rename) to prevent partial reads."""
function save_session!(nb::Notebook)
    path = session_path(nb.path)
    tmp = path * ".tmp"
    try
        data = build_session_dict(nb)
        Base.open(tmp, "w") do io
            TOML.print(io, data)
        end
        mv(tmp, path; force=true)
        dlog("session", "saved"; path, cells=length(data["cells"]))
    catch e
        dlog("session", "save_session! FAILED"; path, err=sprint(showerror, e))
    end
    path
end

"""Load session data from a .session.toml file.
Returns the parsed Dict, or nothing if the file is missing, corrupt, or unsupported version."""
function load_session(path::String)
    isfile(path) || return nothing
    try
        data = TOML.parsefile(path)
        meta = get(data, "meta", Dict())
        version = get(meta, "version", 0)
        if version > SESSION_VERSION
            @warn "Unknown session file version $version, ignoring" path
            return nothing
        end
        return data
    catch e
        @warn "Failed to load session file" path exception=e
        return nothing
    end
end

"""Load a notebook and apply cached session data from the companion .session.toml file.
Returns the notebook with cached state populated (or plain notebook if no session file)."""
function load_notebook_with_session(path::String)
    nb = load_notebook(path)
    session_data = load_session(session_path(path))
    apply_session!(nb, session_data)
    nb
end

"""Apply cached session data to a notebook, populating cell outputs and state.
Matches cells by UUID. Cells not in session data are left unchanged."""
function apply_session!(nb::Notebook, session_data)
    session_data === nothing && return
    cells_data = get(session_data, "cells", Dict())

    for (id_str, cell_data) in cells_data
        id = UUID(id_str)
        cell = get(nb.cells, id, nothing)
        cell === nothing && continue  # cell no longer in notebook

        exec_hash = get(cell_data, "execution_hash", "")
        cell.produced_by_hash = exec_hash

        cell.output.output_type = Symbol(get(cell_data, "output_type", "nothing"))
        cell.output.text_representation = get(cell_data, "text_representation", "")
        cell.output.stdout = get(cell_data, "stdout", "")
        cell.output.runtime_ns = UInt64(get(cell_data, "runtime_ns", 0))

        # Determine cell state from hash comparison
        if exec_hash == ""
            cell.state = cell_idle
        elseif cell.output.output_type == :error
            cell.state = cell_errored
            err_msg = get(cell_data, "error_message", "")
            cell.output.error = CapturedException(ErrorException(err_msg), backtrace())
        else
            cell.state = cell_done
        end
    end
end
