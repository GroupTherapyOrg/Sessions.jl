# DarkModeToggle.jl - Interactive dark/light mode toggle
#
# IMPORTANT: Therapy.jl has TWO event handler syntaxes:
#   - :on_click => () -> ... (for Wasm-compiled islands, SKIPPED in SSR)
#   - :onclick => "jsCode()" (for SSR HTML output, becomes onclick="jsCode()")
#
# Since Sessions.jl doesn't compile islands to Wasm yet, we use :onclick with
# JavaScript string for immediate functionality. The island definition below
# shows the future Wasm approach (will work once Sessions.jl integrates compile_component).

using Therapy

"""
Dark mode toggle component.

Returns a button that toggles the 'dark' class on document.documentElement.
Uses JavaScript onclick for immediate functionality (Layout.jl defines toggleDarkMode).

Future Wasm version:
- island(:DarkModeToggle) will compile to WebAssembly
- Signal-based state with automatic DOM binding
- No JavaScript needed once Therapy.jl island compilation is integrated
"""
function DarkModeToggle()
    # Simple button with JavaScript onclick
    # toggleDarkMode() is defined in Layout.jl's sessions_script()
    Button(
        :class => "p-2 rounded text-neutral-500 hover:text-neutral-700 dark:text-neutral-400 dark:hover:text-neutral-200 hover:bg-neutral-200 dark:hover:bg-neutral-800 transition-colors",
        :onclick => "toggleDarkMode()",
        :title => "Toggle dark mode",
        # Moon icon (shown in light mode - click to go dark)
        Svg(:class => "w-5 h-5 dark:hidden",
            :fill => "none",
            :viewBox => "0 0 24 24",
            :stroke => "currentColor",
            Symbol("stroke-width") => "2",
            Path(:d => "M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z")
        ),
        # Sun icon (shown in dark mode - click to go light)
        Svg(:class => "w-5 h-5 hidden dark:block",
            :fill => "none",
            :viewBox => "0 0 24 24",
            :stroke => "currentColor",
            Symbol("stroke-width") => "2",
            Path(:d => "M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z")
        )
    )
end

# Keep island definition for future Wasm compilation
# This will be used once Sessions.jl integrates Therapy.jl's compile_component
const _DarkModeToggleIsland = island(:DarkModeToggle) do
    dark, set_dark = create_signal(Int32(0))

    Div(:dark_mode => dark,
        Button(
            :class => "p-2 rounded text-neutral-500 hover:text-neutral-700 dark:text-neutral-400 dark:hover:text-neutral-200 hover:bg-neutral-200 dark:hover:bg-neutral-800 transition-colors",
            :on_click => () -> begin
                if dark() == Int32(0)
                    set_dark(Int32(1))
                else
                    set_dark(Int32(0))
                end
            end,
            :title => "Toggle dark mode",
            Svg(:class => "w-5 h-5",
                :fill => "none",
                :viewBox => "0 0 24 24",
                :stroke => "currentColor",
                :stroke_width => "2",
                Path(:d => "M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z")
            )
        )
    )
end
