# IDE/NotebookTabs.jl - Notebook tab bar (Suite.jl rewrite)
#
# Matches the SVG design exactly:
#   ┌──────────────────┬───────────────┬──────────┬───┬─────────────┐
#   │ ● signals.jl  ×  │ effects.jl  × │ memo.jl × │ + │  ● ▶ Run All│
#   └──────────────────┴───────────────┴──────────┴───┴─────────────┘
#
# - 28px height, warm-100 background
# - Active tab: warm-50 bg, rounded-t, bottom border removed
# - Inactive tabs: transparent bg, muted text
# - '+' button for new notebook
# - Run All: right-aligned green accent pill with running indicator
#
# SESSIONS-3402: NotebookTabs component rewrite

import Suite

# =============================================================================
# Individual Tab
# =============================================================================

"""
    IDETab(; id, title, is_active, is_modified)

Single notebook tab matching SVG design.
Active tab has warm-50 bg with rounded top corners and bottom border removal.
"""
function IDETab(;
    id::UUID,
    title::String,
    is_active::Bool=false,
    is_modified::Bool=false
)
    id_str = string(id)

    Div(:class => join(filter(!isempty, [
            "notebook-tab group relative flex items-center gap-1.5 px-3 h-[26px] cursor-pointer transition-colors",
            is_active ?
                "sessions-tab-active bg-warm-50 dark:bg-warm-950 rounded-t-[5px] text-warm-800 dark:text-warm-100" :
                "sessions-tab-inactive text-warm-400 dark:text-warm-500 hover:text-warm-600 dark:hover:text-warm-400"
        ]), " "),
        Symbol("data-tab-id") => id_str,
        Symbol("data-active") => is_active ? "true" : "false",
        :onclick => "switchTab('$(id_str)')",

        # Modified indicator (amber dot, before title)
        is_modified ? Span(:class => "w-1.5 h-1.5 rounded-full bg-amber-500 dark:bg-amber-400 flex-shrink-0",
            :title => "Unsaved changes"
        ) : nothing,

        # Filename in mono
        Span(:class => "text-[10px] font-mono truncate max-w-[120px]",
            title
        ),

        # Close button (×)
        Button(:class => join(filter(!isempty, [
                "p-0 leading-none text-[8px] font-mono flex-shrink-0 transition-opacity",
                is_active ?
                    "text-warm-400 dark:text-warm-500 hover:text-warm-700 dark:hover:text-warm-300" :
                    "text-warm-400 dark:text-warm-500 opacity-0 group-hover:opacity-100"
            ]), " "),
            :onclick => "event.stopPropagation(); closeTab('$(id_str)')",
            :title => "Close",
            "×"
        )
    )
end

# =============================================================================
# Run All Button
# =============================================================================

"""
    RunAllButton(; is_running)

Green accent pill button matching SVG design.
Shows a green dot indicator when cells are executing.
"""
function RunAllButton(; is_running::Bool=false)
    Div(:class => "flex items-center gap-1.5 flex-shrink-0",
        # Running indicator (green dot) — updated by run_controls_script()
        Span(:id => "run-all-indicator",
            :class => "w-2 h-2 rounded-full bg-accent-500 animate-pulse $(is_running ? "" : "hidden")",
            :title => "Cells executing"
        ),

        # Run All pill
        Button(:class => "flex items-center gap-1 px-3 h-[22px] rounded bg-accent-500/10 text-accent-600 dark:text-accent-400 text-[9px] font-mono hover:bg-accent-500/20 transition-colors",
            :onclick => "runAll()",
            :title => "Run all cells",
            Span("▶"),
            Span("Run All")
        )
    )
end

# =============================================================================
# NotebookTabs (Main Component)
# =============================================================================

"""
    IDENotebookTabs(notebooks; active_id=nothing, is_running=false)

Tab bar for managing multiple open notebooks, matching SVG design.

# Design
- 28px height, warm-100 bg with bottom border
- Active tab: warm-50 bg, rounded top, bottom border removed (blends into content)
- Tabs scroll horizontally on overflow
- '+' button after last tab
- Run All pill right-aligned

# Arguments
- `notebooks::Vector`: List of notebook info dicts with keys: id, title, modified
- `active_id`: Currently active notebook ID (UUID or String)
- `is_running::Bool`: Whether cells are currently executing
"""
function IDENotebookTabs(notebooks::Vector; active_id=nothing, is_running::Bool=false)
    # Normalize active_id to UUID
    resolved_active = if active_id isa UUID
        active_id
    elseif active_id isa String && !isempty(active_id)
        UUID(active_id)
    elseif !isempty(notebooks)
        nb_id_from_dict(notebooks[1])
    else
        nothing
    end

    Div(:class => "flex items-center h-7 bg-warm-100 dark:bg-warm-900 border-b border-warm-200 dark:border-[#252422] flex-shrink-0 relative",

        # Tab strip (horizontal scrollable)
        Div(:class => "flex-1 flex items-end gap-0 overflow-x-auto px-1 h-full",
            :style => "scrollbar-width: none; -ms-overflow-style: none;",

            # Render tabs
            [
                begin
                    nb_id = nb_id_from_dict(nb)
                    is_active = nb_id == resolved_active

                    # Wrap active tab in a container that masks the bottom border
                    if is_active
                        Div(:class => "relative",
                            IDETab(
                                id=nb_id,
                                title=get(nb, "title", "Untitled"),
                                is_active=true,
                                is_modified=get(nb, "modified", false)
                            ),
                            # Bottom border mask — 2px white/dark strip to "remove" the border
                            Div(:class => "absolute bottom-[-1px] left-0 right-0 h-[2px] bg-warm-50 dark:bg-warm-950")
                        )
                    else
                        IDETab(
                            id=nb_id,
                            title=get(nb, "title", "Untitled"),
                            is_active=false,
                            is_modified=get(nb, "modified", false)
                        )
                    end
                end
                for nb in notebooks
            ]...,

            # '+' new tab button
            Button(:class => "flex items-center justify-center w-6 h-6 text-warm-400 dark:text-warm-500 hover:text-warm-600 dark:hover:text-warm-400 text-sm font-mono transition-colors flex-shrink-0",
                :onclick => "createNewNotebook()",
                :title => "New notebook",
                "+"
            )
        ),

        # Run All button (right side)
        Div(:class => "flex items-center px-2 flex-shrink-0",
            RunAllButton(is_running=is_running)
        )
    )
end

# =============================================================================
# Empty State
# =============================================================================

"""
    IDEEmptyTabs()

Shown when no notebooks are open. Provides a quick way to create or open one.
"""
function IDEEmptyTabs()
    Div(:class => "flex items-center h-7 bg-warm-100 dark:bg-warm-900 border-b border-warm-200 dark:border-[#252422] flex-shrink-0",
        Div(:class => "flex items-center px-3",
            Button(:class => "flex items-center gap-1.5 text-[10px] font-mono text-warm-400 dark:text-warm-500 hover:text-warm-600 dark:hover:text-warm-400 transition-colors",
                :onclick => "createNewNotebook()",
                Span(:class => "text-sm", "+"),
                Span("New notebook")
            )
        )
    )
end
