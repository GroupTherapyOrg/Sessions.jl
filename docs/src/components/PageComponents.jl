# PageComponents.jl - Shared helpers and local components for Sessions.jl docs
#
# Local component library — replaces Suite.jl with Therapy.jl primitives + Tailwind CSS.
# No external UI framework dependency.

# <kbd> HTML element — not exported by Therapy.jl
const _KbdElement = Therapy.make_element(:kbd)

# =============================================================================
# Local Component Library
# =============================================================================

"""Styled code block with language badge and dark background."""
function CodeBlock(code::String=""; language::String="", class::String="", kwargs...)
    lang_class = isempty(language) ? "block" : "block language-$(language)"
    header = if !isempty(language)
        Div(:class => "flex items-center border-b border-warm-800 px-4 py-2",
            Span(:class => "text-[11px] font-mono uppercase tracking-wider text-warm-400 dark:text-warm-500 select-none", language))
    else
        nothing
    end
    Div(:class => "group relative overflow-hidden rounded-lg ring-1 ring-warm-200 dark:ring-warm-700 bg-warm-950 $(class)",
        Symbol("data-codeblock") => "", kwargs...,
        header,
        Pre(:class => "overflow-x-auto !m-0 !bg-transparent p-4 font-mono text-sm leading-6 text-warm-200",
            Code(:class => lang_class, code)))
end

"""Card container with border and rounded corners."""
function Card(children...; class::String="", kwargs...)
    Div(:class => "rounded-lg border border-warm-200 dark:border-warm-700 bg-warm-50 dark:bg-warm-900 $(class)", kwargs..., children...)
end

"""Card header section. Pass class to fully replace default padding."""
function CardHeader(children...; class::String="px-6 py-4", kwargs...)
    Div(:class => class, kwargs..., children...)
end

"""Card title. Pass class to replace default font size (text-lg)."""
function CardTitle(children...; class::String="text-lg", kwargs...)
    H3(:class => "font-semibold text-warm-800 dark:text-warm-300 $(class)", kwargs..., children...)
end

"""Card description text."""
function CardDescription(children...; kwargs...)
    P(:class => "text-sm text-warm-500 dark:text-warm-400 mt-1", kwargs..., children...)
end

"""Card content section. Pass class to fully replace default padding."""
function CardContent(children...; class::String="px-6 pb-4", kwargs...)
    Div(:class => class, kwargs..., children...)
end

"""Inline badge. variant: "default" (accent bg) or "outline" (border only)."""
function Badge(children...; variant::String="default", class::String="", kwargs...)
    base = "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium"
    vc = variant == "outline" ? "border border-warm-300 dark:border-warm-600 text-warm-700 dark:text-warm-300" :
        "bg-accent-100 dark:bg-accent-900 text-accent-700 dark:text-accent-300"
    Span(:class => "$(base) $(vc) $(class)", kwargs..., children...)
end

"""Styled <kbd> keyboard key element."""
function Kbd(children...; class::String="", kwargs...)
    _KbdElement(:class => "inline-flex items-center rounded border border-warm-300 dark:border-warm-600 bg-warm-100 dark:bg-warm-800 px-1.5 py-0.5 text-xs font-mono font-medium text-warm-700 dark:text-warm-300 $(class)", kwargs..., children...)
end

"""Horizontal separator."""
function Separator(; class::String="", kwargs...)
    Hr(:class => "border-warm-200 dark:border-warm-700 $(class)", kwargs...)
end

# TEMP: Plain JS theme toggle. The @island ThemeToggle compiles correctly
# (handler_0 exported, add_event_listener in hydrate) but the v2 cursor-based
# hydration doesn't attach the click handler — Therapy.jl framework bug.
# Switch back to @island once Therapy.jl hydration is fixed.
function ThemeToggle(; kwargs...)
    id = "theme-toggle-" * string(rand(UInt32), base=16)
    Div(:class => "inline-flex items-center", kwargs...,
        Button(:id => id,
            :class => "cursor-pointer p-2 rounded-md text-warm-600 dark:text-warm-400 hover:text-warm-800 dark:hover:text-warm-200 hover:bg-warm-200 dark:hover:bg-warm-800 transition-colors",
            :aria_label => "Toggle dark mode", :type => "button",
            RawHtml("""<svg class="h-5 w-5 hidden dark:block" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z"/></svg><svg class="h-5 w-5 block dark:hidden" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z"/></svg>""")),
        RawHtml("""<script>(function(){var b=document.getElementById('$(id)');if(!b)return;b.addEventListener('click',function(){var d=document.documentElement.classList.toggle('dark');try{var bp=document.documentElement.getAttribute('data-base-path')||'';var sk=bp?'therapy-theme:'+bp:'therapy-theme';localStorage.setItem(sk,d?'dark':'light')}catch(e){}})})();</script>"""))
end

"""Site footer with brand, links, and tagline."""
function SiteFooter()
    Footer(:class => "py-8 px-4 sm:px-6 lg:px-8 max-w-7xl mx-auto w-full",
        Div(:class => "flex flex-col sm:flex-row items-center justify-between gap-4",
            Span(:class => "text-sm font-medium text-warm-800 dark:text-warm-300", "GroupTherapyOrg"),
            Div(:class => "flex items-center gap-4 text-sm text-warm-500 dark:text-warm-400",
                A(:href => "https://github.com/GroupTherapyOrg/Therapy.jl", :class => "hover:text-accent-600 dark:hover:text-accent-400 transition-colors", :target => "_blank", "Therapy.jl"),
                A(:href => "https://github.com/GroupTherapyOrg/Suite.jl", :class => "hover:text-accent-600 dark:hover:text-accent-400 transition-colors", :target => "_blank", "Suite.jl"),
                A(:href => "https://github.com/GroupTherapyOrg/Sessions.jl", :class => "hover:text-accent-600 dark:hover:text-accent-400 transition-colors", :target => "_blank", "Sessions.jl")),
            Span(:class => "text-xs text-warm-400 dark:text-warm-500", "Built with Therapy.jl — A reactive web framework for Julia")))
end

# Table styling constants (used by route pages and NotebookRenderer)
const _TH_CLS = "px-4 py-3 text-left text-xs font-medium text-warm-500 dark:text-warm-400 uppercase tracking-wider"
const _TR_CLS = "border-b border-warm-200 dark:border-warm-700"
const _TD_CLS = "px-4 py-3 text-sm text-warm-700 dark:text-warm-300"
const _TD_LABEL_CLS = "px-4 py-3 text-sm font-medium text-warm-800 dark:text-warm-300"

# =============================================================================
# Page Layout Helpers
# =============================================================================

"""Render a page header with title and description."""
function PageHeader(title::String, description::String)
    Div(:class => "py-8 border-b border-warm-200 dark:border-warm-700 mb-10",
        H1(:class => "text-4xl font-serif font-semibold text-warm-800 dark:text-warm-300 mb-3", title),
        P(:class => "text-lg text-warm-600 dark:text-warm-300", description))
end

"""Render a section H2 heading."""
function SectionH2(text::String)
    H2(:class => "text-2xl font-serif font-semibold text-warm-800 dark:text-warm-300 mb-4", text)
end

"""Render a section H3 heading."""
function SectionH3(text::String)
    H3(:class => "text-xl font-serif font-semibold text-warm-800 dark:text-warm-300 mb-3", text)
end

"""Render a keyboard interactions table."""
function KeyboardTable(title::String, rows...)
    Div(:class => "mt-8 space-y-4",
        SectionH3(title),
        Div(:class => "overflow-x-auto",
            Table(:class => "w-full text-sm",
                Thead(Tr(
                    Th(:class => _TH_CLS, "Key"),
                    Th(:class => _TH_CLS, "Action"))),
                Tbody(rows...))))
end

"""Render a keyboard shortcut row."""
function KeyRow(key, action)
    Tr(:class => _TR_CLS,
        Td(:class => _TD_CLS, Kbd(key)),
        Td(:class => _TD_CLS, action))
end

# =============================================================================
# Notebooks Layout
# =============================================================================

# ── Extracted-notebook discovery ────────────────────────────────────
# The docs site auto-discovers Sessions-extracted notebooks living in
# docs/notebooks/extracted/<Name>.jl. Each file exposes a top-level
# Therapy component named after the file (PascalCase). docs/app.jl
# loads them into Main.TherapyApp at boot and registers a route per
# file at /notebooks/<slug>/. The sidebar + index gallery iterate
# `EXTRACTED_NOTEBOOKS` (set up in app.jl) — no more reaching at the
# old EXECUTED_NOTEBOOKS pipeline (which was removed when we shifted
# to the WASM-island publish target).

const _NOTEBOOK_PRIORITY_ORDER = ["welcome", "markdown", "interactive", "plots", "reactivity"]

"""Order extracted notebook slugs: preferred order first, then alphabetical remainder."""
function _ordered_notebook_slugs(slugs)
    ordered = String[]
    for s in _NOTEBOOK_PRIORITY_ORDER
        s in slugs && push!(ordered, s)
    end
    for s in sort(collect(slugs))
        s in ordered || push!(ordered, s)
    end
    ordered
end

"""Title-case a slug for the sidebar / cards (`welcome` → `Welcome`)."""
function _notebook_display_title(slug::AbstractString)
    titlecase(replace(String(slug), '-' => ' ', '_' => ' '))
end

"""Discovered extracted notebooks (slug → component fn). Set by docs/app.jl."""
function _extracted_notebooks()
    isdefined(Main, :EXTRACTED_NOTEBOOKS) ? Main.EXTRACTED_NOTEBOOKS : Dict{String, Any}()
end

"""Sidebar for notebooks section. The heading itself links to the
`/notebooks/` index (the gallery) — no separate "Overview" row, which
was a redundant click target on top of the already-clickable section
header + the "Notebooks" nav link in the top bar."""
function NotebooksSidebar()
    items = _ordered_notebook_slugs(keys(_extracted_notebooks()))

    Nav(:class => "py-4 px-2",
        # Clickable heading — same semantics the old "Overview" row
        # had, just collapsed into the section label so the sidebar
        # starts with one fewer line. Uses the same active-class
        # machinery as the per-notebook entries below so it highlights
        # on `/notebooks/` (exact match — otherwise every notebook
        # subpage would light it up too).
        NavLink("./notebooks/",
            Span(:class => "block px-3 mb-2 text-xs font-semibold tracking-wider uppercase",
                "Notebooks");
            class = "block transition-colors no-underline",
            active_class = "text-accent-700 dark:text-accent-400",
            inactive_class = "text-warm-600 dark:text-warm-400 hover:text-warm-800 dark:hover:text-warm-200",
            exact = true),
        Div(:class => "space-y-0.5 mb-2",
            map(items) do slug
                NavLink("./notebooks/$(slug)/", _notebook_display_title(slug);
                    class = "block px-3 py-1.5 text-sm rounded transition-colors",
                    active_class = "text-accent-700 dark:text-accent-400 bg-warm-100 dark:bg-warm-900 border-l-2 border-accent-600 -ml-0.5 pl-[calc(0.75rem+2px)]",
                    inactive_class = "text-warm-600 dark:text-warm-400 hover:text-warm-800 dark:hover:text-white hover:bg-warm-50 dark:hover:bg-warm-900",
                    exact = true)
            end...))
end

"""Layout wrapper for the notebooks INDEX page — sidebar column +
content column. Used only by `/notebooks/` (the gallery).

Uses the "stretched aside + sticky inner" pattern: the outer
`<aside>` stretches vertically inside a flex row so its background/
border fills the full column (from nav-bottom down to the end of
main content, i.e., just above the footer). The sticky inner div
pins the actual sidebar content at `top: 4rem` during scroll and
shrinks to viewport height with internal overflow. This gives us
three things at once:

1. Sidebar column visually extends to meet the footer — no gap.
2. Sidebar content is always visible while scrolling.
3. Sidebar never overlaps the footer (flex container ends at
   MainEl's bottom, which is directly above `<footer>`)."""
function NotebooksLayout(children...)
    Div(:class => "flex flex-1",
        Aside(:class => "hidden lg:block w-60 shrink-0 bg-warm-50 dark:bg-warm-900 border-r border-warm-200 dark:border-warm-700",
            Div(:class => "sticky top-16 max-h-[calc(100vh-4rem)] overflow-y-auto",
                NotebooksSidebar())),
        Div(:class => "flex-1 min-w-0",
            Div(:class => "max-w-4xl px-4 sm:px-6 lg:px-8 py-8",
                children...)))
end

# ── Single-notebook page layout (3 columns) ────────────────────────
#
# Individual `/notebooks/<slug>/` routes use this wrapper. Three
# columns on wide screens, collapses gracefully:
#
#   [ NotebooksSidebar ] [ notebook ] [ TOC ]
#
# Left sidebar is identical to the one on the /notebooks/ index page
# (auto-highlights the active slug via NavLink's route match). Middle
# column hosts the notebook's own `.nb-cell-list` chrome, which keeps
# the 900-px max-width + auto-margins it already has — nothing about
# the notebook's internal spacing changes. Right column is a sticky
# "On this page" TOC populated client-side by walking the notebook's
# h1/h2/h3 headings (same approach Therapy's docs use; the one
# difference is that notebook headings are dynamic per-notebook so we
# build the TOC at DOMContentLoaded instead of hard-coding the pairs
# at compile time).
#
# The JS lives in `_notebook_toc_script()` — marked `/* __therapy */`
# so the router re-executes it after SPA navigation.

"""Render the per-notebook page: left sidebar + notebook + right TOC.

`notebook_vnode` is the VNode/IslandVNode returned by calling the
extracted notebook's @island function. We wrap it so the layout
machinery can nest the notebook between the two sidebars without
touching the notebook component itself."""
function NotebookPageLayout(slug::AbstractString, notebook_vnode)
    Div(:class => "flex flex-1",
        # Left sidebar — aside stretches vertically to fill the flex
        # container (which ends right above the footer), so its bg +
        # border-right visually run the full column height. A sticky
        # inner <div> pins the actual nav content at `top: 4rem`
        # during scroll. This replaces the previous `position: fixed;
        # top: 4rem; bottom: 0` approach, which had two problems: it
        # overlapped the footer on scroll-to-bottom, and the hard
        # `bottom: 0` ignored page flow entirely.
        Aside(:class => "hidden lg:block w-60 shrink-0 bg-warm-50 dark:bg-warm-900 border-r border-warm-200 dark:border-warm-700",
            Div(:class => "sticky top-16 max-h-[calc(100vh-4rem)] overflow-y-auto",
                NotebooksSidebar())),

        # Middle column: the notebook. `flex-1 min-w-0` fills the
        # remaining space between the two fixed-width sidebars.
        # `<div>` (not `<main>`) because Layout.jl already wraps
        # page content in `<main id="page-content">`.
        Div(:id => "notebook-content",
            :class => "flex-1 min-w-0",
            notebook_vnode),

        # Right TOC column — same stretched-aside + sticky-inner
        # pattern. No bg/border so it reads as empty whitespace
        # when the viewport isn't wide enough, but the content sits
        # flush right at `xl:` breakpoint.
        Aside(:class => "hidden xl:block w-56 shrink-0",
            Div(:class => "sticky top-16 max-h-[calc(100vh-4rem)] overflow-y-auto py-10 px-6",
                H4(:class => "text-[11px] font-semibold tracking-wider uppercase text-warm-400 dark:text-warm-500 mb-3",
                    "On this page"),
                Div(:id => "notebook-toc",
                    :class => "space-y-1.5 border-l border-warm-200 dark:border-warm-800 pl-3"))),

        # Client-side TOC populator.
        RawHtml(_notebook_toc_script()))
end

"""JS that walks the notebook's headings and fills #notebook-toc.
`/* __therapy */` marker so Therapy's ClientRouter re-executes it
after each SPA navigation (the TOC has to rebuild when a different
notebook mounts)."""
function _notebook_toc_script()::String
    """
    <script>
    /* __therapy */
    (function () {
      function slugify(s) {
        return (s || '')
          .toLowerCase()
          .replace(/[^a-z0-9]+/g, '-')
          .replace(/^-+|-+\$/g, '') || 'h';
      }
      function build() {
        var toc = document.getElementById('notebook-toc');
        var content = document.getElementById('notebook-content');
        if (!toc || !content) return;
        toc.innerHTML = '';
        var heads = content.querySelectorAll('h1, h2, h3');
        if (!heads.length) { toc.parentNode.parentNode.style.display = 'none'; return; }
        var seen = {};
        heads.forEach(function (h) {
          var label = (h.textContent || '').trim();
          if (!label) return;
          if (!h.id) {
            var base = slugify(label);
            var id = base;
            var n = 1;
            while (seen[id]) id = base + '-' + (++n);
            seen[id] = true;
            h.id = id;
          } else {
            seen[h.id] = true;
          }
          var lvl = parseInt(h.tagName[1], 10) || 2;
          var a = document.createElement('a');
          a.href = '#' + h.id;
          a.textContent = label;
          a.className =
            'block text-[12px] leading-relaxed py-0.5 transition-colors ' +
            'hover:text-accent-500 dark:hover:text-accent-400 ' +
            (lvl === 1
               ? 'font-semibold text-warm-700 dark:text-warm-300'
               : lvl === 2
               ? 'text-warm-600 dark:text-warm-400'
               : 'text-warm-500 dark:text-warm-500 pl-3');
          toc.appendChild(a);
        });
      }
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', build);
      } else {
        build();
      }
    })();
    </script>
    """
end
