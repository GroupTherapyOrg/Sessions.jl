# Workspace.jl - Module-based isolation for cell evaluation
#
# Each notebook gets its own isolated Julia module where cells execute.
# This provides:
# - Variable isolation between notebooks
# - Clean "restart" via module recreation
# - Variable cleanup without process restart
#
# Reference: architecture.md Section 3.3

using UUIDs

"""
Isolated Julia workspace for notebook evaluation.

Each workspace is a dynamically-created module (`gensym(:sessions_workspace)`).
Code evaluated in the workspace is isolated from other workspaces and Main.

# Fields
- `module_name::Symbol`: The name of the workspace module
- `defined_names::Set{Symbol}`: Names currently defined in the workspace
- `previous_modules::Vector{Symbol}`: Old modules to be GC'd
"""
mutable struct Workspace
    # The module where cells execute
    module_name::Symbol

    # Track what's defined
    defined_names::Set{Symbol}

    # For cleanup
    previous_modules::Vector{Symbol}   # GC'd after bump
end

"""
    create_workspace() -> Workspace

Create a fresh isolated workspace.

The workspace is a new module created under Main. Variables defined
in this workspace will not affect other workspaces or Main.

# Example
```julia
ws = create_workspace()
run_cell!(ws, "x = 1")
run_cell!(ws, "y = x + 1")  # y = 2
```
"""
function create_workspace()::Workspace
    mod_name = gensym(:sessions_workspace)
    Core.eval(Main, :(module $mod_name end))
    Workspace(mod_name, Set{Symbol}(), Symbol[])
end

"""
    get_workspace_module(ws::Workspace) -> Module

Get the actual module object for the workspace.
"""
function get_workspace_module(ws::Workspace)::Module
    getfield(Main, ws.module_name)
end

"""
    run_cell!(ws::Workspace, code::String) -> Tuple{Any, Float64}

Execute code in the workspace, returning (result, runtime_ms).

Uses `include_string` to handle multiple expressions natively
(returns the value of the last expression, like Pluto).

# Arguments
- `ws`: The workspace to evaluate in
- `code`: Julia code to evaluate

# Returns
- Tuple of (result, runtime_ms) where result may be an Exception if evaluation failed

# Example
```julia
ws = create_workspace()
result, time_ms = run_cell!(ws, "x = 42")
# result = 42, time_ms = ~0.1
```
"""
function run_cell!(ws::Workspace, code::String)::Tuple{Any, Float64}
    mod = get_workspace_module(ws)

    start_time = time_ns()
    result = try
        # Use include_string for multi-expression support
        include_string(mod, code)
    catch e
        e
    end
    runtime_ms = (time_ns() - start_time) / 1e6

    # Track defined names (heuristic: parse and look for assignments)
    try
        # Use parseall for multi-expression support
        exprs = Base.Meta.parseall(code)
        track_definitions!(ws, exprs)
    catch err
        # Parsing failed, skip tracking
        # This is normal for syntax errors - they'll be caught in execution
    end

    return (result, runtime_ms)
end

"""
    track_definitions!(ws::Workspace, expr)

Track variable definitions from an expression.
"""
function track_definitions!(ws::Workspace, expr)
    if expr isa Expr
        if expr.head == :(=) && length(expr.args) >= 1
            lhs = expr.args[1]
            if lhs isa Symbol
                push!(ws.defined_names, lhs)
            elseif lhs isa Expr && lhs.head == :tuple
                # Handle tuple unpacking: a, b = 1, 2
                for arg in lhs.args
                    if arg isa Symbol
                        push!(ws.defined_names, arg)
                    end
                end
            end
        elseif expr.head == :function || expr.head == :macro
            # function foo() or macro bar()
            if length(expr.args) >= 1
                call = expr.args[1]
                if call isa Expr && call.head == :call && length(call.args) >= 1
                    push!(ws.defined_names, call.args[1])
                elseif call isa Symbol
                    push!(ws.defined_names, call)
                end
            end
        elseif expr.head == :const
            # const x = ...
            if length(expr.args) >= 1
                inner = expr.args[1]
                if inner isa Expr && inner.head == :(=) && inner.args[1] isa Symbol
                    push!(ws.defined_names, inner.args[1])
                end
            end
        elseif expr.head == :struct
            # struct Foo ... end -> args = [mutable::Bool, name, body]
            if length(expr.args) >= 2
                name = expr.args[2]  # Second arg is the name
                if name isa Symbol
                    push!(ws.defined_names, name)
                elseif name isa Expr && name.head == :(<:) && length(name.args) >= 1 && name.args[1] isa Symbol
                    push!(ws.defined_names, name.args[1])
                end
            end
        elseif expr.head == :abstract
            # abstract type Bar end
            if length(expr.args) >= 1
                name = expr.args[1]
                if name isa Symbol
                    push!(ws.defined_names, name)
                elseif name isa Expr && name.head == :(<:) && length(name.args) >= 1 && name.args[1] isa Symbol
                    push!(ws.defined_names, name.args[1])
                end
            end
        elseif expr.head == :block || expr.head == :toplevel
            # Recurse into blocks and toplevel
            for arg in expr.args
                if arg isa Expr
                    track_definitions!(ws, arg)
                end
            end
        end
    end
end

"""
    cleanup_variables!(ws::Workspace, to_delete::Set{Symbol})

Remove variables by creating a new module and copying survivors.

This is useful when a cell is deleted and its definitions should be removed
from the workspace without affecting other variables.

# Arguments
- `ws`: The workspace to clean up
- `to_delete`: Set of variable names to remove

# Example
```julia
ws = create_workspace()
run_cell!(ws, "x = 1")
run_cell!(ws, "y = 2")
cleanup_variables!(ws, Set([:x]))
# x is now undefined, y still exists
```
"""
function cleanup_variables!(ws::Workspace, to_delete::Set{Symbol})
    old_mod = get_workspace_module(ws)
    new_mod_name = gensym(:sessions_workspace)
    Core.eval(Main, :(module $new_mod_name end))
    new_mod = getfield(Main, new_mod_name)

    # Copy only needed variables
    for name in ws.defined_names
        if name ∉ to_delete && isdefined(old_mod, name)
            val = getfield(old_mod, name)
            try
                Core.eval(new_mod, :($name = $val))
            catch
                # Some values can't be copied (e.g., types, functions with closures)
                # Skip them - they'll be recreated on re-execution
            end
        end
    end

    # Track for GC
    push!(ws.previous_modules, ws.module_name)
    ws.module_name = new_mod_name
    setdiff!(ws.defined_names, to_delete)
end

"""
    reset_workspace!(ws::Workspace)

Reset the workspace to a fresh state, clearing all variables.

This is equivalent to "Restart Kernel" in notebook UIs.

# Example
```julia
ws = create_workspace()
run_cell!(ws, "x = 1")
reset_workspace!(ws)
# x is now undefined
```
"""
function reset_workspace!(ws::Workspace)
    # Track old module for GC
    push!(ws.previous_modules, ws.module_name)

    # Create fresh module
    ws.module_name = gensym(:sessions_workspace)
    Core.eval(Main, :(module $(ws.module_name) end))
    empty!(ws.defined_names)
end

"""
    get_variable(ws::Workspace, name::Symbol) -> Any

Get the value of a variable in the workspace.

Returns `nothing` if the variable is not defined.
"""
function get_variable(ws::Workspace, name::Symbol)
    mod = get_workspace_module(ws)
    if isdefined(mod, name)
        getfield(mod, name)
    else
        nothing
    end
end

"""
    set_variable!(ws::Workspace, name::Symbol, value)

Set a variable in the workspace.

Used for @bind to inject values without executing code.
"""
function set_variable!(ws::Workspace, name::Symbol, value)
    mod = get_workspace_module(ws)
    Core.eval(mod, :($name = $value))
    push!(ws.defined_names, name)
end

"""
    is_defined(ws::Workspace, name::Symbol) -> Bool

Check if a variable is defined in the workspace.
"""
function is_defined(ws::Workspace, name::Symbol)::Bool
    mod = get_workspace_module(ws)
    isdefined(mod, name)
end

"""
    list_defined(ws::Workspace) -> Set{Symbol}

Get the set of variable names defined in the workspace.
"""
function list_defined(ws::Workspace)::Set{Symbol}
    copy(ws.defined_names)
end
