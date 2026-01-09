# Main notebook page route
#
# This is the home page showing the full notebook IDE interface.
# Following Therapy.jl file-based routing convention.

using Therapy

function Index()
    Layout(
        # Main IDE content - will be hydrated by WebSocket client
        Div(:class => "flex-1 flex overflow-hidden",
            # Sidebar
            Sidebar(),

            # Main Editor Area
            Div(:class => "flex-1 flex flex-col overflow-hidden",
                # Notebook cells container (populated via WebSocket)
                Div(:id => "cells", :class => "flex-1 overflow-auto p-4 space-y-4"),

                # Terminal panel
                Terminal()
            )
        )
    )
end

# Export the page component
Index
