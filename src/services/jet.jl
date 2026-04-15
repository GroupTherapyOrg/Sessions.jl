# Layer 1: JET.jl integration — static analysis for notebook cells
# Uses JET.report_text() to catch type errors, undefined variables, etc.
# JET is an optional dependency — all functions gracefully no-op if JET is not installed.

"""A single diagnostic from JET analysis."""
struct Diagnostic
    line::Int               # line number within the cell (1-based)
    severity::Symbol        # :error, :warning, :info
    message::String         # human-readable error description
    source::String          # analyzer name ("JET" or "JET-opt")
end

"""Result of analyzing a cell with JET."""
struct CellDiagnostics
    cell_id::UUID
    diagnostics::Vector{Diagnostic}
    analysis_time_ns::UInt64
    analyzer::Symbol        # :error or :opt
end

CellDiagnostics(id::UUID) = CellDiagnostics(id, Diagnostic[], UInt64(0), :error)

"""Check if JET.jl is available in the current environment."""
function _jet_available()::Bool
    jet_id = Base.PkgId(Base.UUID("c3a54625-cd67-489e-a8e7-0a5a0ff4e31b"), "JET")
    return haskey(Base.loaded_modules, jet_id)
end

"""Get the JET module if loaded, otherwise try to load it."""
function _get_jet_module()
    jet_id = Base.PkgId(Base.UUID("c3a54625-cd67-489e-a8e7-0a5a0ff4e31b"), "JET")
    jet = get(Base.loaded_modules, jet_id, nothing)
    if jet !== nothing
        return jet
    end
    # Try loading JET
    try
        return Base.require(jet_id)
    catch
        return nothing
    end
end

"""
    analyze_cell_jet(cell::Cell; mode=:error) -> CellDiagnostics

Run JET static analysis on a single cell's code.
`mode` can be :error (type errors) or :opt (type instabilities).
Returns empty diagnostics if JET is not available.
"""
function analyze_cell_jet(cell::Cell; mode::Symbol=:error)::CellDiagnostics
    jet = _get_jet_module()
    jet === nothing && return CellDiagnostics(cell.id)

    code = strip(cell.code)
    isempty(code) && return CellDiagnostics(cell.id)

    t_start = time_ns()
    diagnostics = Diagnostic[]

    try
        if mode == :opt
            result = Base.invokelatest(jet.report_text, code; analyzer=Base.invokelatest(getproperty, jet, :OptAnalyzer))
            reports = Base.invokelatest(jet.get_reports, result)
            for r in reports
                d = _report_to_diagnostic(jet, r, :warning, "JET-opt")
                d !== nothing && push!(diagnostics, d)
            end
        else
            result = Base.invokelatest(jet.report_text, code)
            reports = Base.invokelatest(jet.get_reports, result)
            for r in reports
                d = _report_to_diagnostic(jet, r, :error, "JET")
                d !== nothing && push!(diagnostics, d)
            end
        end
    catch e
        # JET itself errored — report as a single diagnostic
        push!(diagnostics, Diagnostic(1, :info, "JET analysis failed: $(sprint(showerror, e))", "JET"))
    end

    t_end = time_ns()
    CellDiagnostics(cell.id, diagnostics, t_end - t_start, mode)
end

"""Convert a JET report into our Diagnostic struct."""
function _report_to_diagnostic(jet, report, default_severity::Symbol, source::String)
    try
        # Get the error location from the virtual stack trace
        vst = getproperty(report, :vst)
        if !isempty(vst)
            frame = last(vst)
            line = Int(getproperty(frame, :line))
        else
            line = 1
        end

        # Get the error message
        msg = sprint() do io
            Base.invokelatest(jet.print_report_message, io, report)
        end

        # Determine severity based on report type
        severity = default_severity
        report_type = string(typeof(report))
        if contains(report_type, "Undef")
            severity = :error
        elseif contains(report_type, "MethodError")
            severity = :error
        elseif contains(report_type, "RuntimeDispatch")
            severity = :warning
        elseif contains(report_type, "Captured")
            severity = :warning
        end

        return Diagnostic(max(line, 1), severity, strip(msg), source)
    catch
        return nothing
    end
end

"""
    analyze_notebook_jet(nb::Notebook; mode=:error) -> Dict{UUID, CellDiagnostics}

Run JET analysis on all cells in a notebook.
Returns a dictionary mapping cell IDs to their diagnostics.
"""
function analyze_notebook_jet(nb::Notebook; mode::Symbol=:error)::Dict{UUID, CellDiagnostics}
    results = Dict{UUID, CellDiagnostics}()
    for id in nb.cell_order
        cell = get(nb.cells, id, nothing)
        cell === nothing && continue
        cell.disabled && continue
        isempty(strip(cell.code)) && continue
        results[id] = analyze_cell_jet(cell; mode)
    end
    results
end

"""Count total diagnostics across all cells."""
function total_diagnostics(diags::Dict{UUID, CellDiagnostics})
    n_errors = 0
    n_warnings = 0
    n_info = 0
    for cd in values(diags)
        for d in cd.diagnostics
            if d.severity == :error
                n_errors += 1
            elseif d.severity == :warning
                n_warnings += 1
            else
                n_info += 1
            end
        end
    end
    (errors=n_errors, warnings=n_warnings, info=n_info)
end

"""Get diagnostics for a specific cell, or empty if none."""
function cell_diagnostics(diags::Dict{UUID, CellDiagnostics}, cell_id::UUID)::Vector{Diagnostic}
    cd = get(diags, cell_id, nothing)
    cd === nothing && return Diagnostic[]
    cd.diagnostics
end
