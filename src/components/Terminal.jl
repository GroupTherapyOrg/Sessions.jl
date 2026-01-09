# Terminal.jl - Julia REPL terminal panel for Sessions.jl

using Therapy

"""
    Terminal()

Bottom panel with Julia REPL terminal.
Communication happens via WebSocket.
"""
function Terminal()
    Div(:id => "terminal-panel", :class => "h-48 bg-gray-800 border-t border-gray-700 flex flex-col",
        # Terminal header
        Div(:class => "h-8 bg-gray-900 border-b border-gray-700 flex items-center px-3 text-sm",
            Span(:class => "text-gray-400", "Terminal"),
            Div(:class => "flex-1"),
            Button(:id => "btn-toggle-terminal",
                   :class => "text-gray-500 hover:text-white",
                   "×")
        ),

        # Terminal output
        Div(:id => "terminal-output",
            :class => "flex-1 overflow-auto p-2 font-mono text-sm text-green-400 bg-gray-900"),

        # Terminal input
        Div(:class => "flex items-center px-2 py-1 bg-gray-900 border-t border-gray-700",
            Span(:class => "text-blue-400 mr-2 font-mono", "julia>"),
            Input(:type => "text",
                  :id => "terminal-input",
                  :class => "flex-1 bg-transparent outline-none font-mono text-green-400",
                  :placeholder => "Enter command...")
        )
    )
end
