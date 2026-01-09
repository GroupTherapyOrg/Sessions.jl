# Sidebar.jl - File explorer sidebar for Sessions.jl

using Therapy

"""
    Sidebar()

Left sidebar with file explorer.
The file tree is populated dynamically via WebSocket.
"""
function Sidebar()
    Div(:id => "sidebar", :class => "w-64 bg-gray-800 border-r border-gray-700 flex flex-col",
        # Header
        Div(:class => "p-2 border-b border-gray-700 flex items-center justify-between",
            Span(:class => "text-xs text-gray-500 uppercase", "Explorer"),
            Button(:id => "btn-refresh-files",
                   :class => "text-gray-500 hover:text-white text-sm",
                   "↻")
        ),

        # File tree container (populated via WebSocket)
        Div(:id => "file-tree", :class => "flex-1 overflow-auto p-2 text-sm")
    )
end
