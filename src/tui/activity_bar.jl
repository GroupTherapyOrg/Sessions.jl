# TUI: Activity Bar — VS Code-style icon button strip (far left island)
# Thin vertical panel with icon buttons, rounded border, floating on black bg

struct ActivityButton
    icon::String
    id::Symbol
end

const ACTIVITY_BUTTONS = [
    ActivityButton("⊟", :explorer),
]

mutable struct ActivityBar
    active::Symbol          # which button is active (:explorer, :none)
    hovered::Symbol         # which button mouse is hovering
    viewport::Tachikoma.Rect
end

ActivityBar() = ActivityBar(:explorer, :none, Tachikoma.Rect())

"""Toggle a button — if already active, deactivate it."""
function toggle!(ab::ActivityBar, id::Symbol)
    ab.active = ab.active == id ? :none : id
end

"""Map screen y to a button id, or nothing."""
function button_at_y(ab::ActivityBar, y::Int)
    vp = ab.viewport
    vp.width == 0 && return nothing
    # Buttons start at row vp.y + 1 (inside top border), spaced 2 rows apart
    for (i, btn) in enumerate(ACTIVITY_BUTTONS)
        btn_y = vp.y + 1 + (i - 1) * 2
        y == btn_y && return btn.id
    end
    nothing
end

function Tachikoma.render(ab::ActivityBar, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    ab.viewport = rect
    rect.width < 3 && return
    rect.height < 3 && return

    border_style = Tachikoma.Style(; fg=Theme.ACTIVITY_BORDER_FG, bg=Theme.BG)
    bg_style = Tachikoma.Style(; bg=Theme.ACTIVITY_BG)

    # Fill with activity bg
    for fy in rect.y:(rect.y + rect.height - 1)
        Tachikoma.set_string!(buf, rect.x, fy, " " ^ rect.width, bg_style)
    end

    # Rounded border
    Tachikoma.set_char!(buf, rect.x, rect.y, '╭', border_style)
    Tachikoma.set_char!(buf, rect.x + rect.width - 1, rect.y, '╮', border_style)
    Tachikoma.set_char!(buf, rect.x, rect.y + rect.height - 1, '╰', border_style)
    Tachikoma.set_char!(buf, rect.x + rect.width - 1, rect.y + rect.height - 1, '╯', border_style)

    for cx in (rect.x + 1):(rect.x + rect.width - 2)
        Tachikoma.set_char!(buf, cx, rect.y, '─', border_style)
        Tachikoma.set_char!(buf, cx, rect.y + rect.height - 1, '─', border_style)
    end

    for fy in (rect.y + 1):(rect.y + rect.height - 2)
        Tachikoma.set_char!(buf, rect.x, fy, '│', border_style)
        Tachikoma.set_char!(buf, rect.x + rect.width - 1, fy, '│', border_style)
    end

    # Render buttons
    inner_w = rect.width - 2
    for (i, btn) in enumerate(ACTIVITY_BUTTONS)
        btn_y = rect.y + 1 + (i - 1) * 2
        btn_y > rect.y + rect.height - 2 && break

        is_active = (btn.id == ab.active)
        is_hovered = (btn.id == ab.hovered)

        # Active indicator — accent bar on left edge
        if is_active
            Tachikoma.set_char!(buf, rect.x, btn_y,
                '▎', Tachikoma.Style(; fg=Theme.ACTIVITY_INDICATOR, bg=Theme.ACTIVITY_BG))
        end

        # Icon
        icon_fg = if is_active
            Theme.ACTIVITY_ICON_ACTIVE_FG
        elseif is_hovered
            Theme.FG_DIM
        else
            Theme.ACTIVITY_ICON_FG
        end
        icon_x = rect.x + 1 + div(inner_w - 1, 2)  # center icon
        Tachikoma.set_string!(buf, icon_x, btn_y, btn.icon,
            Tachikoma.Style(; fg=icon_fg, bg=Theme.ACTIVITY_BG))
    end
end
