# Layout.jl - Main page layout for Sessions.jl
#
# Provides the overall IDE structure:
# - Top bar with controls
# - Content area passed as children

using Therapy

"""
    Layout(children...; island_html="")

Main layout component for Sessions.jl pages.
Provides the IDE chrome (top bar, structure) and renders children in the main area.
"""
function Layout(children...; island_html::String="")
    Div(:id => "app", :class => "h-screen flex flex-col bg-gray-900 text-gray-200",
        # Top Bar with optional island
        TopBar(; island_html=island_html),

        # Main Content (passed as children)
        children...
    )
end

"""
    TopBar(; island_html="")

Top navigation bar with session controls.
Optionally includes compiled island HTML for reactive cell count.
"""
function TopBar(; island_html::String="")
    Div(:class => "h-10 bg-gray-800 border-b border-gray-700 flex items-center px-4",
        Span(:class => "font-bold text-lg", "Sessions.jl"),

        # Island container for notebook controls (cell count, etc.)
        Div(:id => "notebook-controls-container",
            :class => "ml-4",
            RawHtml(island_html)),

        # Spacer
        Div(:class => "flex-1"),

        # Action buttons
        Button(:id => "btn-run-all",
               :class => "px-3 py-1 bg-green-600 hover:bg-green-500 rounded text-sm mr-2",
               "Run All"),
        Button(:id => "btn-restart",
               :class => "px-3 py-1 bg-gray-700 hover:bg-gray-600 rounded text-sm mr-2",
               "Restart"),
        Button(:id => "btn-add-cell",
               :class => "px-3 py-1 bg-blue-600 hover:bg-blue-500 rounded text-sm",
               "+ Cell")
    )
end
