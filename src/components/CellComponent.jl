# CellComponent.jl - Server-side cell rendering with Therapy.jl
#
# Cells are rendered entirely on the server. The client receives HTML.
# Only CodeMirror initialization requires JS (external library).

using Therapy

"""
    CellComponent(cell::Cell)

Render a cell as Therapy.jl VNodes. This is called server-side
and the HTML is sent to the client via WebSocket.
"""
function CellComponent(cell::Cell)
    status_class = get_status_class(cell.status)
    status_name = lowercase(string(cell.status))

    Div(:class => "cell bg-gray-800 rounded-lg mb-4",
        Symbol("data-id") => string(cell.id),
        Symbol("data-status") => status_name,

        # Cell header with status and controls
        Div(:class => "flex items-center h-10 px-3 bg-gray-700 rounded-t-lg",
            # Execution count
            Span(:class => "text-xs text-gray-500 mr-2",
                "[$(cell.execution_count)]"),

            # Spacer
            Div(:class => "flex-1"),

            # Run button
            Button(:class => "run-btn px-3 py-1 text-xs text-gray-300 hover:bg-gray-600 rounded",
                "Run"),

            # Delete button
            Button(:class => "delete-btn px-2 py-1 text-xs text-gray-400 hover:text-red-400 rounded ml-1",
                "×")
        ),

        # Editor container - CodeMirror will be mounted here by JS
        Div(:class => "editor-container",
            Symbol("data-id") => string(cell.id),
            Symbol("data-code") => cell.code),

        # Output area
        CellOutput(cell)
    )
end

"""
    CellOutput(cell::Cell)

Render cell output (stdout, result, errors).
"""
function CellOutput(cell::Cell)
    Div(:class => "output px-3 pb-3",
        # Stdout
        if !isempty(cell.stdout)
            Pre(:class => "bg-gray-900 rounded p-2 text-sm text-gray-300 whitespace-pre-wrap",
                cell.stdout)
        else
            nothing
        end,

        # Result (for completed cells with output)
        if cell.status == COMPLETED && cell.output !== nothing
            output_str = repr(cell.output)
            if output_str != "nothing"
                Pre(:class => "bg-gray-900 rounded p-2 text-sm text-blue-400 mt-2",
                    output_str)
            else
                nothing
            end
        else
            nothing
        end,

        # Error message
        if cell.status == ERRORED && !isempty(cell.error_msg)
            Pre(:class => "bg-red-900/30 rounded p-2 text-sm text-red-400 mt-2 whitespace-pre-wrap",
                cell.error_msg)
        else
            nothing
        end
    )
end

"""
    CellsContainer(cells::Vector{Cell})

Render all cells in order.
"""
function CellsContainer(cells::Vector{Cell})
    Div(:id => "cells-content",
        [CellComponent(cell) for cell in cells]...
    )
end

"""
    get_status_class(status::CellStatus)

Get CSS class for cell status indicator.
"""
function get_status_class(status::CellStatus)
    if status == IDLE
        "border-l-gray-500"
    elseif status == QUEUED
        "border-l-yellow-500"
    elseif status == RUNNING
        "border-l-yellow-500 animate-pulse"
    elseif status == COMPLETED
        "border-l-green-500"
    elseif status == ERRORED
        "border-l-red-500"
    else
        "border-l-gray-500"
    end
end
