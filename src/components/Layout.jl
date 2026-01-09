# Layout.jl - Main page layout for Sessions.jl
#
# Provides the overall IDE structure:
# - Top bar with controls
# - Content area passed as children

using Therapy

"""
    Layout(children...)

Main layout component for Sessions.jl pages.
Provides the IDE chrome (top bar, structure) and renders children in the main area.
"""
function Layout(children...)
    Div(:id => "app", :class => "h-screen flex flex-col bg-gray-900 text-gray-200",
        # Top Bar
        TopBar(),

        # Main Content (passed as children)
        children...
    )
end

"""
    TopBar()

Top navigation bar with session controls.
"""
function TopBar()
    Div(:class => "h-10 bg-gray-800 border-b border-gray-700 flex items-center px-4",
        Span(:class => "font-bold text-lg", "Sessions.jl"),

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
