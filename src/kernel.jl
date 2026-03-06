# Layer 1: Kernel — Cell execution with workspace isolation and output capture

using Markdown: Markdown

"""
Classify a cell's return value into an output type for TUI rendering.
Returns a Symbol: :nothing, :error, :markdown, :dataframe, :image_png, or :text.
"""
function classify_output(value)::Symbol
    value === nothing && return :nothing
    value isa Markdown.MD && return :markdown
    # Check for Tables.jl-compatible tabular data (duck typing)
    try
        mod = parentmodule(typeof(value))
        if isdefined(mod, :Tables) || _has_table_interface(value)
            return :dataframe
        end
    catch; end
    # Check for image/png MIME support (plots)
    if hasmethod(show, Tuple{IO, MIME"image/png", typeof(value)})
        return :image_png
    end
    return :text
end

"""Check if a value looks like tabular data (duck typing without Tables.jl dependency)."""
function _has_table_interface(value)
    # Common table-like types: Vector{<:NamedTuple}, Matrix, etc.
    value isa AbstractVector{<:NamedTuple} && return true
    # Check if Tables module is loaded and value is a table
    tables_mod = get(Base.loaded_modules, Base.PkgId(Base.UUID("bd369af6-aec1-5ad0-b16a-f7cc5008161c"), "Tables"), nothing)
    if tables_mod !== nothing
        try
            return tables_mod.istable(value)
        catch; end
    end
    false
end

"""Generate a text representation of any value for fallback display."""
function text_representation(value)::String
    value === nothing && return ""
    try
        sprint(show, MIME"text/plain"(), value; context=:limit => true)
    catch
        try
            sprint(show, value)
        catch
            repr(value)
        end
    end
end

"""
The Workspace holds all cell-evaluated state in a dedicated module.
Each notebook gets its own workspace module so variables don't leak.
"""
mutable struct Workspace
    mod::Module
    ns::Symbol
end

let workspace_counter = Ref(0)
    global function Workspace()
        workspace_counter[] += 1
        ns = Symbol("SessionsWorkspace_", workspace_counter[])
        mod = Module(ns)
        # Pre-populate the workspace with Base
        Core.eval(mod, :(using Base))
        Workspace(mod, ns)
    end
end

"""Execute a single cell in the workspace, capturing output and timing."""
function execute_cell!(workspace::Workspace, cell::Cell)
    cell.state = cell_running
    cell.output = CellOutput()

    result = nothing
    err = nothing
    captured_stdout = ""
    t_start = time_ns()

    try
        expr = Meta.parse("begin\n$(cell.code)\nend")
        # Use a Pipe for stdout capture (IOBuffer doesn't work with redirect_stdout)
        old_stdout = stdout
        rd, wr = redirect_stdout()
        try
            result = Base.eval(workspace.mod, expr)
        finally
            redirect_stdout(old_stdout)
            close(wr)
        end
        captured_stdout = String(read(rd))
    catch e
        err = CapturedException(e, catch_backtrace())
    end

    t_end = time_ns()

    cell.output.result = err === nothing ? result : nothing
    cell.output.stdout = captured_stdout
    cell.output.error = err
    cell.output.runtime_ns = t_end - t_start

    if err === nothing
        cell.output.output_type = classify_output(result)
        cell.output.text_representation = text_representation(result)
        cell.state = cell_done
        mark_executed!(cell)
    else
        cell.output.output_type = :error
        cell.output.text_representation = sprint(showerror, err.ex)
        cell.state = cell_errored
    end
    cell.output
end

"""
Execute a notebook reactively: analyze dependencies, sort topologically, run in order.
Returns the notebook with all cells updated.
"""
function execute_notebook!(nb::Notebook; workspace::Workspace=Workspace())
    order = execution_order(nb)

    # Mark errable cells
    for (cell, err) in order.errable
        cell.state = cell_errored
        cell.output = CellOutput()
        cell.output.error = CapturedException(
            ErrorException("Reactivity error: $(typeof(err))"),
            backtrace()
        )
    end

    # Execute runnable cells in topological order
    for cell in order.runnable
        execute_cell!(workspace, cell)
    end

    nb
end

"""
Re-execute only the cells affected by changes to `changed_cells`.
"""
function execute_changed!(nb::Notebook, changed_cells::Vector{Cell}; workspace::Workspace=Workspace())
    order = execution_order(nb, changed_cells)

    for (cell, err) in order.errable
        cell.state = cell_errored
        cell.output = CellOutput()
        cell.output.error = CapturedException(
            ErrorException("Reactivity error: $(typeof(err))"),
            backtrace()
        )
    end

    for cell in order.runnable
        execute_cell!(workspace, cell)
    end

    nb
end
