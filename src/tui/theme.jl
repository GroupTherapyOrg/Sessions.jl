# TUI: Islands Dark Theme — single source of truth for all visual styling
# Inspired by bwya77/vscode-dark-islands
#
# ALL colors, styles, layout constants, and component-specific styling live here.
# Widget code MUST reference Theme.* — never create ad-hoc styles inline.

module Theme

using Tachikoma: ColorRGB, Color256, Style, NoColor, BOX_ROUNDED

# ╭──────────────────────────────────────────────────────────────────╮
# │  Colors                                                         │
# ╰──────────────────────────────────────────────────────────────────╯

# Background — pure black so every island floats
const BG              = ColorRGB(0x00, 0x00, 0x00)   # #000000 — true black backdrop

# Canvas & Surface — island backgrounds
const CANVAS_BG     = ColorRGB(0x12, 0x12, 0x16)   # #121216 — notebook pane bg
const SURFACE_BG    = ColorRGB(0x1a, 0x1b, 0x1e)   # #1a1b1e — cell island background
const ELEVATED_BG   = ColorRGB(0x22, 0x23, 0x2a)   # #22232a — focused cell / hover

# Text hierarchy
const FG            = ColorRGB(0xbc, 0xbe, 0xc4)   # #bcbec4 — primary text
const FG_DIM        = ColorRGB(0x7a, 0x7e, 0x85)   # #7a7e85 — comments, secondary
const FG_MUTED      = ColorRGB(0x4e, 0x51, 0x57)   # #4e5157 — line numbers, inactive
const FG_FAINT      = ColorRGB(0x35, 0x38, 0x3d)   # #35383d — very dim (status bar idle)

# Accent
const ACCENT        = ColorRGB(0x54, 0x8a, 0xf7)   # #548af7 — primary accent blue
const ACCENT_DIM    = ColorRGB(0x3d, 0x6b, 0xc7)   # dimmer accent for unfocused
const ACCENT_GLOW   = ColorRGB(0x6e, 0xa2, 0xff)   # brighter accent for glow effects

# Semantic
const GREEN         = ColorRGB(0x6a, 0xab, 0x73)   # #6aab73 — success, string
const GREEN_BRIGHT  = ColorRGB(0x8c, 0xd4, 0x96)   # brighter green for glow
const ORANGE        = ColorRGB(0xcf, 0x8e, 0x6d)   # #cf8e6d — warning, keyword
const RED           = ColorRGB(0xf7, 0x54, 0x64)   # #f75464 — error
const PURPLE        = ColorRGB(0xc7, 0x7d, 0xbb)   # #c77dbb — type, special
const CYAN          = ColorRGB(0x2a, 0xac, 0xb8)   # #2aacb8 — number, info

# Borders
const BORDER_BRIGHT = ColorRGB(0x3c, 0x3f, 0x44)   # glass highlight
const BORDER_DIM    = ColorRGB(0x2b, 0x2d, 0x30)   # glass shadow
const BORDER_FOCUS  = ACCENT                         # focused cell border

# Selection
const SELECTION_BG  = ColorRGB(0x37, 0x3b, 0x39)   # #373b39

# ╭──────────────────────────────────────────────────────────────────╮
# │  Animation                                                      │
# ╰──────────────────────────────────────────────────────────────────╯

const TICK = Ref(0)
tick() = TICK[]
advance_tick!() = (TICK[] += 1)

# ╭──────────────────────────────────────────────────────────────────╮
# │  Global box style — ALL bordered elements use rounded            │
# ╰──────────────────────────────────────────────────────────────────╯

const BOX = BOX_ROUNDED

# ╭──────────────────────────────────────────────────────────────────╮
# │  Layout constants                                                │
# ╰──────────────────────────────────────────────────────────────────╯

const ISLAND_GAP        = 2       # gap between floating islands (rows & cols)
const ACTIVITY_BAR_W    = 7       # activity bar width (wider for comfort)
const SIDEBAR_PCT       = 22      # sidebar takes 22% of remaining width
const CELL_PAD_FRACTION = 0.06    # 6% each side — narrower pane needs less padding
const MARGIN_CTRL_WIDTH = 3       # left margin width for +/eye controls
const CELL_GAP          = 2       # rows between cells
const TOP_MARGIN        = 1       # padding above first cell

# Background style — pure black fills entire screen
const S_BG = Style(; bg=BG)

# ╭──────────────────────────────────────────────────────────────────╮
# │  Prebuilt text styles                                            │
# ╰──────────────────────────────────────────────────────────────────╯

const S_FG          = Style(; fg=FG)
const S_DIM         = Style(; fg=FG_DIM)
const S_MUTED       = Style(; fg=FG_MUTED)
const S_FAINT       = Style(; fg=FG_FAINT)
const S_ACCENT      = Style(; fg=ACCENT)
const S_GREEN       = Style(; fg=GREEN)
const S_ORANGE      = Style(; fg=ORANGE)
const S_RED         = Style(; fg=RED)
const S_PURPLE      = Style(; fg=PURPLE)
const S_CYAN        = Style(; fg=CYAN)

# Border styles
const S_BORDER      = Style(; fg=BORDER_BRIGHT)
const S_BORDER_DIM  = Style(; fg=BORDER_DIM)
const S_BORDER_FOCUS = Style(; fg=BORDER_FOCUS)
const S_BORDER_SELECT = Style(; fg=CYAN)

# Status indicators
const S_RUNNING     = Style(; fg=ACCENT)
const S_QUEUED      = Style(; fg=ORANGE)
const S_ERRORED     = Style(; fg=RED)
const S_STALE       = Style(; fg=ORANGE)
const S_NEVER_RUN   = Style(; fg=FG_MUTED)
const S_DONE        = Style(; fg=GREEN)
const S_DISABLED    = Style(; fg=FG_MUTED)

# ╭──────────────────────────────────────────────────────────────────╮
# │  Component: Progress Bar (top border of notebook pane)           │
# ╰──────────────────────────────────────────────────────────────────╯

const PROGRESS_FG       = ACCENT_GLOW    # blue glow while running
const PROGRESS_DONE_FG  = GREEN_BRIGHT   # green flash on completion
const PROGRESS_HOLD     = 30             # frames to hold green bar (~1s at 30fps)

# ╭──────────────────────────────────────────────────────────────────╮
# │  Component: Cell                                                 │
# ╰──────────────────────────────────────────────────────────────────╯

cell_surface(focused::Bool) = focused ? ELEVATED_BG : SURFACE_BG

# Border bg = CANVAS_BG so rounded corners blend with notebook pane bg
cell_border_focused(bg=CANVAS_BG)  = Style(; fg=ACCENT, bg)
cell_border_hovered(bg=CANVAS_BG)  = Style(; fg=BORDER_BRIGHT, bg)
cell_border_disabled(bg=CANVAS_BG) = Style(; fg=FG_MUTED, bg)
cell_border_selected(bg=CANVAS_BG) = Style(; fg=CYAN, bg)
cell_border_default(bg=CANVAS_BG)  = Style(; fg=BORDER_DIM, bg)

const SHIMMER_INTENSITY = 0.25
const CELL_H_INSET     = 1       # horizontal padding between fill edge and border (cols)
const CELL_V_INSET     = 0       # vertical padding between fill edge and border (rows)
const CELL_H_PAD       = 1       # extra horizontal padding inside border (each side)

# Canvas fill (used to clear notebook viewport and gaps)
const S_CANVAS = Style(; bg=CANVAS_BG)

# Folded cell accent bar
const FOLD_BAR_FG = BORDER_BRIGHT

# ╭──────────────────────────────────────────────────────────────────╮
# │  Component: Ellipsis (⋯) button                                 │
# ╰──────────────────────────────────────────────────────────────────╯

const BTN_BG        = ELEVATED_BG     # pill background
const BTN_FG        = FG_MUTED        # ⋯ character color
const BTN_BRACKET   = BORDER_BRIGHT   # ( ) bracket color
const BTN_CHAR      = '⋯'

# ╭──────────────────────────────────────────────────────────────────╮
# │  Component: Dropdown menu                                        │
# ╰──────────────────────────────────────────────────────────────────╯

const DROPDOWN_BG        = SURFACE_BG
const DROPDOWN_HOVER_BG  = ELEVATED_BG
const DROPDOWN_BORDER_FG = BORDER_BRIGHT
const DROPDOWN_ITEM_FG   = FG_DIM
const DROPDOWN_HOVER_FG  = FG
const DROPDOWN_ICON_FG   = FG_MUTED
const DROPDOWN_HOVER_ICON = RED           # destructive actions highlight red

# ╭──────────────────────────────────────────────────────────────────╮
# │  Component: Margin controls (+, eye)                             │
# ╰──────────────────────────────────────────────────────────────────╯

const MARGIN_FG    = FG_MUTED
const MARGIN_BG    = CANVAS_BG
margin_style()     = Style(; fg=MARGIN_FG, bg=MARGIN_BG)

# Eye button
eye_fg(folded::Bool) = folded ? FG_FAINT : FG_MUTED
eye_char(folded::Bool) = folded ? "◌" : "⊙"

# ╭──────────────────────────────────────────────────────────────────╮
# │  Component: Run button (▶) in gap                               │
# ╰──────────────────────────────────────────────────────────────────╯

const RUN_BG         = CANVAS_BG
const RUN_DEFAULT_FG = FG_DIM
const RUN_DONE_FG    = GREEN
const RUN_ERROR_FG   = RED

# ╭──────────────────────────────────────────────────────────────────╮
# │  Component: Output                                               │
# ╰──────────────────────────────────────────────────────────────────╯

# Output text on canvas
output_text_style(errored::Bool, stale::Bool) =
    if errored
        Style(; fg=RED, bg=CANVAS_BG)
    elseif stale
        Style(; fg=FG_MUTED, bg=CANVAS_BG, italic=true)
    else
        Style(; fg=FG_DIM, bg=CANVAS_BG)
    end

# Output left accent bar color
output_bar_color(errored::Bool, stale::Bool) =
    errored ? RED : stale ? ORANGE : BORDER_DIM

# ╭──────────────────────────────────────────────────────────────────╮
# │  Component: Activity Bar (icon button strip)                    │
# ╰──────────────────────────────────────────────────────────────────╯

const ACTIVITY_BG         = ColorRGB(0x0c, 0x0c, 0x0e)  # very dark, close to black
const ACTIVITY_ICON_FG    = FG_MUTED
const ACTIVITY_ICON_ACTIVE_FG = FG
const ACTIVITY_INDICATOR  = ACCENT       # left accent bar for active button
const ACTIVITY_BORDER_FG  = BORDER_DIM

# ╭──────────────────────────────────────────────────────────────────╮
# │  Component: File Panel (sidebar explorer)                       │
# ╰──────────────────────────────────────────────────────────────────╯

const SIDEBAR_BG        = ColorRGB(0x10, 0x10, 0x14)   # very dark, slightly above black
const SIDEBAR_HEADER_FG = FG_DIM
const SIDEBAR_BORDER_FG = BORDER_DIM
const S_SIDEBAR         = Style(; fg=FG_DIM, bg=SIDEBAR_BG)
const S_SIDEBAR_HEADER  = Style(; fg=FG, bg=SIDEBAR_BG, bold=true)

end # module Theme
