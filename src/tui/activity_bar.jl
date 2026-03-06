# TUI: Activity Bar — VS Code-style icon button strip (far left island)
# Thin vertical panel with icon buttons, rounded border, floating on black bg

struct ActivityButton
    icon::String
    id::Symbol
end

const ACTIVITY_BUTTONS = [
    ActivityButton("⊟", :explorer),
    ActivityButton("⊞", :open_folder),
    ActivityButton("⊳", :terminal),
]

mutable struct ActivityBar
    active::Set{Symbol}     # which buttons are active (multiple can be active)
    hovered::Symbol         # which button mouse is hovering
    viewport::Tachikoma.Rect
end

ActivityBar() = ActivityBar(Set{Symbol}([:explorer]), :none, Tachikoma.Rect())

"""Toggle a button — add or remove from active set."""
function toggle!(ab::ActivityBar, id::Symbol)
    if id in ab.active
        delete!(ab.active, id)
    else
        push!(ab.active, id)
    end
end

"""Check if a button is active."""
is_active(ab::ActivityBar, id::Symbol) = id in ab.active

"""Map screen y to a button id, or nothing."""
function button_at_y(ab::ActivityBar, y::Int)
    vp = ab.viewport
    vp.width == 0 && return nothing
    # Buttons start inside border: v_inset + border(1), spaced 2 rows apart
    vi = Theme.CELL_V_INSET
    for (i, btn) in enumerate(ACTIVITY_BUTTONS)
        btn_y = vp.y + vi + 1 + (i - 1) * 2
        y == btn_y && return btn.id
    end
    nothing
end

function Tachikoma.render(ab::ActivityBar, rect::Tachikoma.Rect, buf::Tachikoma.Buffer)
    ab.viewport = rect
    rect.width < 3 && return
    rect.height < 3 && return

    hi = Theme.CELL_H_INSET
    vi = Theme.CELL_V_INSET
    border_style = Tachikoma.Style(; fg=Theme.ACTIVITY_BORDER_FG, bg=Theme.ACTIVITY_BG)
    bg_style = Tachikoma.Style(; bg=Theme.ACTIVITY_BG)

    # Fill entire rect with activity bg (overflow visible around border)
    for fy in rect.y:(rect.y + rect.height - 1)
        Tachikoma.set_string!(buf, rect.x, fy, " " ^ rect.width, bg_style)
    end

    # Border drawn inset from fill edges
    bx = rect.x + hi
    by = rect.y + vi
    bw = max(rect.width - 2 * hi, 3)
    bh = max(rect.height - 2 * vi, 3)

    # Rounded border
    Tachikoma.set_char!(buf, bx, by, '╭', border_style)
    Tachikoma.set_char!(buf, bx + bw - 1, by, '╮', border_style)
    Tachikoma.set_char!(buf, bx, by + bh - 1, '╰', border_style)
    Tachikoma.set_char!(buf, bx + bw - 1, by + bh - 1, '╯', border_style)

    for cx in (bx + 1):(bx + bw - 2)
        Tachikoma.set_char!(buf, cx, by, '─', border_style)
        Tachikoma.set_char!(buf, cx, by + bh - 1, '─', border_style)
    end

    for fy in (by + 1):(by + bh - 2)
        Tachikoma.set_char!(buf, bx, fy, '│', border_style)
        Tachikoma.set_char!(buf, bx + bw - 1, fy, '│', border_style)
    end

    # Render buttons
    inner_w = bw - 2
    for (i, btn) in enumerate(ACTIVITY_BUTTONS)
        btn_y = by + 1 + (i - 1) * 2
        btn_y > by + bh - 2 && break

        is_active = btn.id in ab.active
        is_hovered = (btn.id == ab.hovered)

        # Active indicator — accent bar on left edge (green for terminal, blue for others)
        if is_active
            indicator_fg = btn.id == :terminal ? Theme.REPL_INDICATOR : Theme.ACTIVITY_INDICATOR
            Tachikoma.set_char!(buf, bx, btn_y,
                '▎', Tachikoma.Style(; fg=indicator_fg, bg=Theme.ACTIVITY_BG))
        end

        # Icon — glow on hover, bright when active
        icon_fg = if is_active
            Theme.ACTIVITY_ICON_ACTIVE_FG
        elseif is_hovered
            Theme.ACCENT_GLOW
        else
            Theme.ACTIVITY_ICON_FG
        end
        icon_x = bx + 1 + div(inner_w - 1, 2)  # center icon
        Tachikoma.set_string!(buf, icon_x, btn_y, btn.icon,
            Tachikoma.Style(; fg=icon_fg, bg=Theme.ACTIVITY_BG))
    end
end
