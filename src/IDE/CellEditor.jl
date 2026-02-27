# IDE/CellEditor.jl - CodeMirror 6 integration for cell editing
#
# Therapy.jl provides CodeMirror 6 via register_codemirror_pluto():
# - Initialization on [data-codemirror] elements
# - Julia syntax highlighting (Pluto's julia_andrey / pluto_syntax_colors)
# - Line numbers, bracket matching, fold gutter, dirty tracking
# - Shift+Enter / Cmd+Enter keybindings to execute cells
#
# This file provides the Sessions.jl-specific CodeMirror theme overlay
# that maps the editor colors to the warm neutral + Julia accent palette.
#
# SESSIONS-3501: CodeMirror 6 island for cell editing

"""
    codemirror_sessions_theme()

CSS theme overlay for CodeMirror 6 editors in Sessions.jl.

Colors match the SVG design and Julia's official syntax colors:
- Purple (#9558b2): keywords (function, struct, if, end, etc.)
- Blue (#4063d8): types, modules
- Red/crimson (#cb3c33): strings
- Green (#389826): output text, comments
- Warm neutrals for editor chrome (gutters, selections, cursors)

Returns a <style> tag string to inject into head_extra.
"""
function codemirror_sessions_theme()
    """
    <style>
    /* Sessions.jl CodeMirror Theme — Warm neutrals + Julia colors */

    /* Editor container */
    .cm-editor {
        font-family: var(--font-mono, 'JetBrains Mono', 'SF Mono', 'Fira Code', monospace);
        font-size: 12.5px;
        line-height: 1.6;
        background: transparent !important;
    }

    .cm-editor .cm-scroller {
        padding: 0.75rem 1rem;
        overflow-x: auto;
    }

    .cm-editor .cm-content {
        caret-color: var(--color-accent-500);
    }

    /* Gutters (line numbers) */
    .cm-editor .cm-gutters {
        background: transparent;
        border-right: none;
        padding-right: 0.5rem;
    }

    .cm-editor .cm-lineNumbers .cm-gutterElement {
        font-size: 10px;
        min-width: 2rem;
        padding: 0 0.25rem 0 0;
        text-align: right;
    }

    /* Light mode gutter/selection */
    :root:not(.dark) .cm-editor .cm-lineNumbers .cm-gutterElement {
        color: var(--color-warm-300);
    }
    :root:not(.dark) .cm-editor .cm-activeLine {
        background: color-mix(in srgb, var(--color-accent-500) 4%, transparent);
    }
    :root:not(.dark) .cm-editor .cm-selectionBackground,
    :root:not(.dark) .cm-editor .cm-content ::selection {
        background: color-mix(in srgb, var(--color-accent-500) 15%, transparent) !important;
    }
    :root:not(.dark) .cm-editor .cm-matchingBracket {
        background: color-mix(in srgb, var(--color-accent-500) 20%, transparent);
        outline: 1px solid color-mix(in srgb, var(--color-accent-500) 30%, transparent);
    }
    :root:not(.dark) .cm-editor .cm-cursor {
        border-left-color: var(--color-accent-500);
    }
    :root:not(.dark) .cm-editor .cm-activeLineGutter {
        background: transparent;
        color: var(--color-warm-500);
    }

    /* Dark mode gutter/selection */
    .dark .cm-editor .cm-lineNumbers .cm-gutterElement {
        color: var(--color-warm-700);
    }
    .dark .cm-editor .cm-activeLine {
        background: color-mix(in srgb, var(--color-accent-500) 6%, transparent);
    }
    .dark .cm-editor .cm-selectionBackground,
    .dark .cm-editor .cm-content ::selection {
        background: color-mix(in srgb, var(--color-accent-500) 20%, transparent) !important;
    }
    .dark .cm-editor .cm-matchingBracket {
        background: color-mix(in srgb, var(--color-accent-500) 25%, transparent);
        outline: 1px solid color-mix(in srgb, var(--color-accent-500) 35%, transparent);
    }
    .dark .cm-editor .cm-cursor {
        border-left-color: var(--color-accent-500);
    }
    .dark .cm-editor .cm-activeLineGutter {
        background: transparent;
        color: var(--color-warm-500);
    }

    /* Focus ring */
    .cm-editor.cm-focused {
        outline: none;
    }
    .cm-editor.cm-focused .cm-scroller {
        /* Subtle left accent glow on focus */
    }

    /* Julia syntax colors — override Pluto defaults to match Sessions.jl palette */

    /* Light mode syntax */
    :root:not(.dark) .cm-editor {
        color: var(--color-warm-800);
    }
    :root:not(.dark) .cm-editor .tok-keyword,
    :root:not(.dark) .cm-editor .cm-keyword { color: #9558b2; }

    :root:not(.dark) .cm-editor .tok-typeName,
    :root:not(.dark) .cm-editor .tok-className,
    :root:not(.dark) .cm-editor .cm-type { color: var(--color-accent-secondary-500); }

    :root:not(.dark) .cm-editor .tok-string,
    :root:not(.dark) .cm-editor .tok-string2,
    :root:not(.dark) .cm-editor .cm-string { color: #cb3c33; }

    :root:not(.dark) .cm-editor .tok-number,
    :root:not(.dark) .cm-editor .cm-number { color: var(--color-warm-800); }

    :root:not(.dark) .cm-editor .tok-comment,
    :root:not(.dark) .cm-editor .cm-comment { color: var(--color-warm-400); }

    :root:not(.dark) .cm-editor .tok-operator,
    :root:not(.dark) .cm-editor .cm-operator { color: var(--color-warm-600); }

    :root:not(.dark) .cm-editor .tok-function,
    :root:not(.dark) .cm-editor .cm-function { color: var(--color-accent-secondary-500); opacity: 0.85; }

    :root:not(.dark) .cm-editor .tok-bool,
    :root:not(.dark) .cm-editor .cm-bool { color: #9558b2; }

    :root:not(.dark) .cm-editor .tok-macroName,
    :root:not(.dark) .cm-editor .cm-macroName { color: var(--color-accent-500); }

    /* Dark mode syntax */
    .dark .cm-editor {
        color: var(--color-warm-300);
    }
    .dark .cm-editor .tok-keyword,
    .dark .cm-editor .cm-keyword { color: #c9a0dc; }

    .dark .cm-editor .tok-typeName,
    .dark .cm-editor .tok-className,
    .dark .cm-editor .cm-type { color: var(--color-accent-secondary-400); }

    .dark .cm-editor .tok-string,
    .dark .cm-editor .tok-string2,
    .dark .cm-editor .cm-string { color: #e8a0a0; }

    .dark .cm-editor .tok-number,
    .dark .cm-editor .cm-number { color: var(--color-warm-300); }

    .dark .cm-editor .tok-comment,
    .dark .cm-editor .cm-comment { color: var(--color-warm-700); }

    .dark .cm-editor .tok-operator,
    .dark .cm-editor .cm-operator { color: var(--color-warm-500); }

    .dark .cm-editor .tok-function,
    .dark .cm-editor .cm-function { color: var(--color-accent-secondary-400); }

    .dark .cm-editor .tok-bool,
    .dark .cm-editor .cm-bool { color: #c9a0dc; }

    .dark .cm-editor .tok-macroName,
    .dark .cm-editor .cm-macroName { color: var(--color-accent-400); }

    /* Fold gutter */
    .cm-editor .cm-foldGutter .cm-gutterElement {
        font-size: 10px;
        padding: 0 2px;
        cursor: pointer;
    }
    :root:not(.dark) .cm-editor .cm-foldGutter .cm-gutterElement { color: var(--color-warm-300); }
    .dark .cm-editor .cm-foldGutter .cm-gutterElement { color: var(--color-warm-700); }

    /* Placeholder */
    .cm-editor .cm-placeholder {
        font-style: italic;
    }
    :root:not(.dark) .cm-editor .cm-placeholder { color: var(--color-warm-300); }
    .dark .cm-editor .cm-placeholder { color: var(--color-warm-700); }

    /* Tooltip (autocomplete, hover info) */
    .cm-tooltip {
        border-radius: 6px;
        font-size: 12px;
        box-shadow: 0 4px 12px rgba(0,0,0,0.1);
    }
    :root:not(.dark) .cm-tooltip {
        background: var(--color-warm-50);
        border: 1px solid var(--color-warm-200);
        color: var(--color-warm-800);
    }
    .dark .cm-tooltip {
        background: var(--color-warm-900);
        border: 1px solid var(--color-warm-800);
        color: var(--color-warm-300);
    }

    /* Autocomplete list */
    .cm-tooltip-autocomplete ul li[aria-selected] {
        border-radius: 4px;
    }
    :root:not(.dark) .cm-tooltip-autocomplete ul li[aria-selected] {
        background: color-mix(in srgb, var(--color-accent-500) 10%, transparent);
        color: var(--color-warm-800);
    }
    .dark .cm-tooltip-autocomplete ul li[aria-selected] {
        background: color-mix(in srgb, var(--color-accent-500) 15%, transparent);
        color: var(--color-warm-300);
    }

    /* Dirty indicator styling */
    .cell .dirty-indicator {
        transition: opacity 0.2s;
    }
    .cell .dirty-indicator.hidden {
        display: none;
    }

    /* Hide the SSR fallback <pre> when CodeMirror initializes */
    [data-codemirror] .cm-editor ~ pre.cell-code {
        display: none;
    }
    </style>
    """
end
