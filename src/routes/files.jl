# files.jl - File browser route for testing SESSIONS-2102
#
# This route displays the file browser with context menus.
#
# Route: /files

using Therapy

"""
    FilesRoute(params::Dict{Symbol, String})

Render the file browser page for testing context menus.
"""
function FilesRoute(params::Dict{Symbol, String}=Dict{Symbol, String}())
    # Get workspace directory (current working directory)
    workspace = pwd()

    # List directory contents
    entries = Sessions.list_directory(workspace)

    # Build page content with file browser
    Div(:class => "flex h-[calc(100vh-12rem)]",
        # Sidebar with file browser
        Div(:class => "w-64 flex-shrink-0",
            Sessions.FileBrowser(
                root_path = workspace,
                current_path = workspace,
                entries = entries
            )
        ),

        # Main content area
        Div(:class => "flex-1 p-8",
            H1(:class => "text-2xl font-serif font-medium text-stone-700 dark:text-stone-200 mb-4",
                "File Browser Test"
            ),
            P(:class => "text-stone-600 dark:text-stone-400 mb-4",
                "Test the file browser context menu by:"
            ),
            Ul(:class => "list-disc list-inside text-stone-600 dark:text-stone-400 space-y-2",
                Li("Right-clicking on a file or folder"),
                Li("Clicking the ⋮ (ellipsis) button on hover"),
                Li("Using the toolbar buttons to create files/folders")
            ),
            P(:class => "text-sm text-stone-400 dark:text-stone-500 mt-6",
                "Current workspace: ", Code(:class => "bg-stone-200 dark:bg-neutral-700 px-2 py-0.5 rounded", workspace)
            )
        )
    )
end

# Export the route function
FilesRoute
