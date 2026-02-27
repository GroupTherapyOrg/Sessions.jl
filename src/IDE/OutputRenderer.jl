# IDE/OutputRenderer.jl - Output rendering styles and components
#
# Styles for different output types matching the SVG design:
# - Plain text: green (#389826) monospace, opacity 0.55
# - HTML: rendered inline (DataFrames, custom show)
# - Images: responsive sizing with warm border
# - Errors: Suite.Alert destructive (handled in CellState.jl)
# - Logs: stdout/stderr with distinct styling
# - Large output: truncation with "Show more" button
#
# SESSIONS-3504: Output rendering (HTML, MIME, plots, errors)

import Suite

# =============================================================================
# Output Styles CSS
# =============================================================================

"""
    output_styles()

CSS for cell output rendering matching the SVG design.
"""
function output_styles()
    """
    <style>
    /* ============================================================
       Cell Output Styles — Sessions.jl
       ============================================================ */

    /* Output container */
    .cell-output {
        font-family: var(--font-mono, 'JetBrains Mono', 'SF Mono', 'Fira Code', monospace);
    }

    /* Plain text output — accent monospace matching SVG */
    .cell-output .output-text,
    .cell-output pre:not(.stacktrace):not(.cell-code) {
        font-size: 11.5px;
        line-height: 1.6;
        white-space: pre-wrap;
        word-break: break-word;
    }
    :root:not(.dark) .cell-output .output-text,
    :root:not(.dark) .cell-output .output-value > pre {
        color: var(--color-accent-500);
        opacity: 0.55;
    }
    .dark .cell-output .output-text,
    .dark .cell-output .output-value > pre {
        color: var(--color-accent-500);
        opacity: 0.55;
    }

    /* Function signatures (generic function output) */
    .cell-output .output-value {
        font-size: 11.5px;
        line-height: 1.6;
    }
    :root:not(.dark) .cell-output .output-value {
        color: var(--color-accent-500);
        opacity: 0.55;
    }
    .dark .cell-output .output-value {
        color: var(--color-accent-500);
        opacity: 0.55;
    }

    /* HTML output (DataFrames, custom show methods) */
    .cell-output .output-value table {
        width: 100%;
        border-collapse: collapse;
        font-size: 11px;
        opacity: 1;
        color: inherit;
    }
    :root:not(.dark) .cell-output .output-value table {
        color: var(--color-warm-800);
    }
    .dark .cell-output .output-value table {
        color: var(--color-warm-300);
    }
    .cell-output .output-value table th {
        font-weight: 500;
        text-align: left;
        padding: 0.3rem 0.6rem;
    }
    :root:not(.dark) .cell-output .output-value table th {
        border-bottom: 2px solid var(--color-warm-200);
        color: var(--color-warm-800);
    }
    .dark .cell-output .output-value table th {
        border-bottom: 2px solid var(--color-warm-800);
        color: var(--color-warm-300);
    }
    .cell-output .output-value table td {
        padding: 0.25rem 0.6rem;
    }
    :root:not(.dark) .cell-output .output-value table td {
        border-bottom: 1px solid var(--color-warm-200);
        color: var(--color-warm-600);
    }
    .dark .cell-output .output-value table td {
        border-bottom: 1px solid var(--color-warm-800);
        color: var(--color-warm-500);
    }

    /* Image output */
    .cell-output img {
        max-width: 100%;
        height: auto;
        border-radius: 6px;
        margin: 0.25rem 0;
    }
    :root:not(.dark) .cell-output img {
        border: 1px solid var(--color-warm-200);
    }
    .dark .cell-output img {
        border: 1px solid var(--color-warm-800);
    }

    /* SVG output */
    .cell-output svg {
        max-width: 100%;
        height: auto;
    }

    /* Stdout logs */
    .cell-output .stdout {
        font-size: 10.5px;
        line-height: 1.5;
        margin-bottom: 0.25rem;
    }
    :root:not(.dark) .cell-output .stdout { color: var(--color-warm-400); }
    .dark .cell-output .stdout { color: var(--color-warm-700); }

    .cell-output .stdout .log-line {
        padding: 0 0.25rem;
    }

    /* Stderr logs */
    .cell-output .stderr {
        font-size: 10.5px;
        line-height: 1.5;
        margin-bottom: 0.25rem;
    }
    :root:not(.dark) .cell-output .stderr {
        color: var(--color-rose-600, #cb3c33);
        opacity: 0.6;
    }
    .dark .cell-output .stderr {
        color: var(--color-rose-400, #e8a0a0);
        opacity: 0.6;
    }

    .cell-output .stderr .log-line {
        padding: 0 0.25rem;
    }

    /* Error output (inline, not Suite.Alert — for signal-based updates) */
    .cell-output .cell-error {
        padding: 0.75rem 1rem;
        border-radius: 6px;
        font-size: 11px;
    }
    :root:not(.dark) .cell-output .cell-error {
        background: color-mix(in srgb, var(--color-rose-600, #cb3c33) 6%, transparent);
        border: 1px solid color-mix(in srgb, var(--color-rose-600, #cb3c33) 15%, transparent);
    }
    .dark .cell-output .cell-error {
        background: color-mix(in srgb, var(--color-rose-600, #cb3c33) 8%, transparent);
        border: 1px solid color-mix(in srgb, var(--color-rose-600, #cb3c33) 15%, transparent);
    }

    .cell-output .cell-error .error-header {
        font-weight: 600;
        margin-bottom: 0.25rem;
    }
    :root:not(.dark) .cell-output .cell-error .error-header { color: var(--color-rose-600, #cb3c33); }
    .dark .cell-output .cell-error .error-header { color: var(--color-rose-400, #e8a0a0); }

    .cell-output .cell-error .error-message {
        margin-bottom: 0.25rem;
    }
    :root:not(.dark) .cell-output .cell-error .error-message { color: var(--color-rose-800, #8b2e27); }
    .dark .cell-output .cell-error .error-message { color: var(--color-rose-400, #e8a0a0); }

    .cell-output .cell-error .stacktrace {
        font-size: 10px;
        line-height: 1.5;
        max-height: 200px;
        overflow-y: auto;
        padding: 0.5rem;
        border-radius: 4px;
        white-space: pre-wrap;
    }
    :root:not(.dark) .cell-output .cell-error .stacktrace {
        background: color-mix(in srgb, var(--color-rose-600, #cb3c33) 4%, transparent);
        color: var(--color-warm-600);
    }
    .dark .cell-output .cell-error .stacktrace {
        background: color-mix(in srgb, var(--color-rose-600, #cb3c33) 6%, transparent);
        color: var(--color-warm-500);
    }

    /* Large output truncation */
    .cell-output .output-truncated {
        position: relative;
        max-height: 300px;
        overflow: hidden;
    }
    .cell-output .output-truncated::after {
        content: '';
        position: absolute;
        bottom: 0;
        left: 0;
        right: 0;
        height: 60px;
        pointer-events: none;
    }
    :root:not(.dark) .cell-output .output-truncated::after {
        background: linear-gradient(transparent, color-mix(in srgb, var(--color-warm-50) 90%, transparent));
    }
    .dark .cell-output .output-truncated::after {
        background: linear-gradient(transparent, color-mix(in srgb, var(--color-warm-950) 90%, transparent));
    }

    .cell-output .output-show-more {
        display: flex;
        justify-content: center;
        padding: 0.25rem 0;
    }
    .cell-output .output-show-more button {
        font-size: 10px;
        font-family: var(--font-mono, monospace);
        padding: 0.2rem 0.75rem;
        border-radius: 9999px;
        cursor: pointer;
        transition: all 0.15s;
    }
    :root:not(.dark) .cell-output .output-show-more button {
        color: var(--color-warm-400);
        background: var(--color-warm-100);
        border: 1px solid var(--color-warm-200);
    }
    :root:not(.dark) .cell-output .output-show-more button:hover {
        color: var(--color-warm-600);
        border-color: var(--color-warm-300);
    }
    .dark .cell-output .output-show-more button {
        color: var(--color-warm-700);
        background: var(--color-warm-900);
        border: 1px solid var(--color-warm-800);
    }
    .dark .cell-output .output-show-more button:hover {
        color: var(--color-warm-500);
        border-color: var(--color-warm-700);
    }

    /* Number/numeric output — slightly brighter green */
    .cell-output .output-value > pre:only-child {
        margin: 0;
        padding: 0;
        background: transparent;
        border: none;
    }
    </style>
    """
end

# =============================================================================
# Output Truncation Script
# =============================================================================

"""
    output_truncation_script()

JavaScript for "Show more" button on large outputs.
"""
function output_truncation_script()
    """
    // Output truncation — Show more / Show less
    window.toggleOutputTruncation = function(cellId) {
        var output = document.querySelector('[data-cell-id="' + cellId + '"] .cell-output');
        if (!output) return;
        var truncated = output.querySelector('.output-truncated');
        if (!truncated) return;

        var isExpanded = truncated.style.maxHeight === 'none';
        if (isExpanded) {
            truncated.style.maxHeight = '300px';
            truncated.style.overflow = 'hidden';
            var btn = output.querySelector('.output-show-more button');
            if (btn) btn.textContent = 'Show more';
        } else {
            truncated.style.maxHeight = 'none';
            truncated.style.overflow = 'visible';
            var btn = output.querySelector('.output-show-more button');
            if (btn) btn.textContent = 'Show less';
        }
    };
    """
end
