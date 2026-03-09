# PageComponents.jl - Shared page helpers for Sessions.jl docs

"""
Render a page header with title and description.
"""
function PageHeader(title::String, description::String)
    Div(:class => "py-8 border-b border-warm-200 dark:border-warm-700 mb-10",
        H1(:class => "text-4xl font-serif font-semibold text-warm-800 dark:text-warm-300 mb-3", title),
        P(:class => "text-lg text-warm-600 dark:text-warm-300", description)
    )
end

"""
Render a section H2 heading.
"""
function SectionH2(text::String)
    H2(:class => "text-2xl font-serif font-semibold text-warm-800 dark:text-warm-300 mb-4", text)
end

"""
Render a section H3 heading.
"""
function SectionH3(text::String)
    H3(:class => "text-xl font-serif font-semibold text-warm-800 dark:text-warm-300 mb-3", text)
end

"""
Render a keyboard interactions table with title.
"""
function KeyboardTable(title::String, rows...)
    Div(:class => "mt-8 space-y-4",
        SectionH3(title),
        Div(:class => "overflow-x-auto",
            Main.Table(
                Main.TableHeader(Main.TableRow(
                    Main.TableHead("Key"),
                    Main.TableHead("Action"),
                )),
                Main.TableBody(rows...)
            )
        )
    )
end

"""
Render a keyboard shortcut row with Kbd component.
"""
function KeyRow(key, action)
    Main.TableRow(
        Main.TableCell(Main.Kbd(key)),
        Main.TableCell(action),
    )
end
