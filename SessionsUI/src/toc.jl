# toc.jl — Table of Contents widget
#
# Single source of truth for the ToC sidebar — same HTML / CSS / JS the
# Sessions.jl IDE renders as built-in chrome. The IDE imports this widget
# and calls it; users get the IDENTICAL look in standalone exports
# (Pluto, file:// HTML dumps, WASM publish) by writing in a cell:
#
#     using SessionsUI: TableOfContents
#     TableOfContents()
#
# # Behaviour
# - Auto-scans every `h1`–`h<depth>` under the notebook content area
#   on every DOM change (MutationObserver).
# - Highlights the heading currently in the upper half of the viewport
#   (twin IntersectionObserver pattern, ported 1-1 from Pluto's
#   PlutoUI.TableOfContents).
# - Click an entry → smooth scroll the heading to top.
# - Singleton: if more than one ToC ends up in the DOM (e.g. the IDE
#   already injected one and the user also added a `TableOfContents()`
#   cell), every duplicate after the first removes itself on hydrate.
#   So users in the IDE who explicitly add the widget get one ToC, not
#   two; users in standalone exports get exactly the one they declared.

"""
    TableOfContents(; title="Table of Contents", indent=true, depth=3)

A floating Table-of-Contents sidebar that auto-generates from the
markdown headings in the notebook output.

# Options
- `title`:  Header text shown above the link list.
- `indent`: Indent entries by heading level (default `true`).
- `depth`:  Maximum heading level to include, 1–6 (default `3`).
"""
Base.@kwdef struct TableOfContents
    title::String = "Contents"
    indent::Bool  = true
    depth::Int    = 3
end

function Base.show(io::IO, ::MIME"text/html", toc::TableOfContents)
    indent_cls = toc.indent ? " indent" : ""
    depth = clamp(toc.depth, 1, 6)
    title = replace(toc.title, "<" => "&lt;")
    selectors = join(["h$(i)" for i in 1:depth], ", ")

    print(io, """
<nav class="sessions-toc aside$(indent_cls) hide" id="toc-panel" data-su-toc="1">
  <header>
    <span class="toc-toggle open-toc"></span>
    <span class="toc-toggle closed-toc"></span>
    $(title)
  </header>
  <section id="toc-content"></section>
</nav>
<style>
.sessions-toc{font-family:'DM Sans',-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,system-ui,sans-serif;--toc-bg:var(--warm-50,#fafafa);--toc-color:var(--warm-600,#666);--toc-color-h:var(--warm-800,#222);--toc-active-bg:rgb(235,235,235);--toc-icon-filter:unset;}
.dark .sessions-toc,html[data-theme="dark"] .sessions-toc{--toc-bg:#1a2332;--toc-color:var(--text-2,#aaa);--toc-color-h:var(--text-1,#fff);--toc-active-bg:rgb(60,65,75);--toc-icon-filter:invert(1);}
.sessions-toc.aside{color:var(--toc-color);position:fixed;right:0.5rem;top:3rem;width:min(80vw,280px);padding:0.5rem;padding-top:0;border-radius:10px;max-height:calc(100vh - 4rem);overflow:auto;z-index:100;background:var(--toc-bg);transition:transform 300ms cubic-bezier(0.18,0.89,0.45,1.12);box-shadow:0 0 11px 0px rgba(0,0,0,.06);}
.sessions-toc.aside.hide{transform:translateX(calc(100% - 28px));color:transparent;box-shadow:none;}
.sessions-toc.aside.hide section{display:none;}
.sessions-toc.aside.hide header{margin-bottom:0;padding-bottom:0;border-bottom:none;}
.sessions-toc.aside.hide .open-toc,.sessions-toc.aside:not(.hide) .closed-toc{display:none;}
.toc-toggle{cursor:pointer;padding:1em;margin:-1em;margin-right:-0.7em;line-height:1em;display:flex;}
.toc-toggle::before{content:'';display:inline-block;height:1em;width:1em;background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 512 512'%3E%3Cpath d='M160 144h288M160 256h288M160 368h288' fill='none' stroke='%23000' stroke-linecap='round' stroke-linejoin='round' stroke-width='48'/%3E%3Ccircle cx='80' cy='144' r='16' fill='none' stroke='%23000' stroke-linecap='round' stroke-linejoin='round' stroke-width='32'/%3E%3Ccircle cx='80' cy='256' r='16' fill='none' stroke='%23000' stroke-linecap='round' stroke-linejoin='round' stroke-width='32'/%3E%3Ccircle cx='80' cy='368' r='16' fill='none' stroke='%23000' stroke-linecap='round' stroke-linejoin='round' stroke-width='32'/%3E%3C/svg%3E");background-size:1em;filter:var(--toc-icon-filter);}
.sessions-toc header{display:flex;align-items:center;gap:.3em;font-size:1.5em;margin-bottom:0.4em;padding:0.5rem 0;font-weight:bold;position:sticky;top:0;background:var(--toc-bg);z-index:41;}
.sessions-toc section .toc-row{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;padding:.1em;border-radius:.2em;}
.sessions-toc section .toc-row.H1{margin-top:1em;}
.sessions-toc.aside section .toc-row.in-view{background:var(--toc-active-bg);}
.sessions-toc section a{text-decoration:none;font-weight:normal;color:var(--toc-color);display:block;}
.sessions-toc section a:hover{color:var(--toc-color-h);}
.sessions-toc.indent section a.H1{font-weight:700;line-height:1em;padding-left:0;}
.sessions-toc.indent section a.H2{padding-left:10px;}
.sessions-toc.indent section a.H3{padding-left:20px;}
.sessions-toc.indent section a.H4{padding-left:30px;}
.sessions-toc.indent section a.H5{padding-left:40px;}
.sessions-toc.indent section a.H6{padding-left:50px;}
.sessions-toc .toc-empty{color:#999;font-size:11px;font-style:italic;padding:8px 14px;}
</style>
<script>
(function(){
  // Singleton dedup: if the IDE (or another cell) already mounted a ToC,
  // remove THIS instance. We check for >1 #toc-panel and remove all but
  // the first that owned the build script.
  var all = document.querySelectorAll('#toc-panel');
  if (all.length > 1) {
    var me = document.currentScript ? document.currentScript.previousElementSibling : null;
    while (me && me.id !== 'toc-panel') me = me.previousElementSibling;
    if (me && me !== all[0]) { me.remove(); return; }
  }

  var tocNav = document.getElementById('toc-panel');
  if (!tocNav) return;
  var tocSection = tocNav.querySelector('#toc-content');
  var headerMap = new Map();
  var inViewSet = new Set();
  var obs1, obs2;

  // Toggle (clicking the hamburger icon flips .hide).
  tocNav.addEventListener('click', function(e){
    var t = e.target.closest('.toc-toggle');
    if (!t) return;
    e.stopPropagation();
    tocNav.classList.toggle('hide');
    if (!tocNav.classList.contains('hide')) buildToc();
  });

  function getHeaders(){
    // Universal scan: any heading in the page, but skip ones inside the
    // ToC itself. Works in Sessions IDE (.cell-out), Pluto (pluto-cell),
    // and plain HTML exports (any structure).
    return Array.from(document.querySelectorAll('$(selectors)'))
      .filter(function(h){ return !h.closest('.sessions-toc'); });
  }

  function buildToc(){
    var headers = getHeaders();
    if (!headers.length){ tocSection.innerHTML = '<div class="toc-empty">No headings</div>'; return; }
    if (obs1) obs1.disconnect();
    if (obs2) obs2.disconnect();
    headerMap.clear();
    inViewSet.clear();

    var frag = document.createDocumentFragment();
    headers.forEach(function(h){
      var cls = h.tagName;
      var text = h.textContent.trim();
      if (!text) return;
      if (!h.id) h.id = 'h-' + text.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+\$/g,'');
      var row = document.createElement('div');
      row.className = 'toc-row ' + cls;
      var a = document.createElement('a');
      a.className = cls;
      a.href = '#' + h.id;
      a.title = text;
      a.textContent = text;
      a.onclick = function(e){ e.preventDefault(); h.scrollIntoView({behavior:'smooth',block:'start'}); };
      row.appendChild(a);
      frag.appendChild(row);
      headerMap.set(h, row);
    });
    tocSection.innerHTML = '';
    tocSection.appendChild(frag);

    // Twin IntersectionObserver — Pluto's pattern. Highlights the
    // heading in the top half of the viewport.
    var ixCallback = function(entries){
      entries.forEach(function(ix){
        if (ix.intersectionRatio > 0 && ix.intersectionRect.y < ix.rootBounds.height / 2) {
          inViewSet.forEach(function(r){ r.classList.remove('in-view'); });
          inViewSet.clear();
          var row = headerMap.get(ix.target);
          if (row) { row.classList.add('in-view'); inViewSet.add(row); }
        }
      });
    };
    obs1 = new IntersectionObserver(ixCallback, {root:null, threshold:1, rootMargin:'-15px'});
    obs2 = new IntersectionObserver(ixCallback, {root:null, threshold:1, rootMargin:'15px'});
    headers.forEach(function(h){ obs1.observe(h); obs2.observe(h); });
  }

  // Auto-rebuild on DOM mutation (cells added / output changed).
  var _t = null;
  function debouncedBuild(){
    if (_t) clearTimeout(_t);
    _t = setTimeout(function(){ if (!tocNav.classList.contains('hide')) buildToc(); }, 300);
  }
  // Expose a global rebuild hook so external code (e.g. tab-switch handlers
  // in the Sessions IDE) can request a rebuild without inventing its own.
  window._sessionsBuildToc = debouncedBuild;

  // Scope the observer to the notebook container so the ToC's own
  // innerHTML rewrites (during buildToc) don't trigger themselves —
  // that's the classic MutationObserver feedback-loop bug.
  // Sessions IDE: #nb exists, ToC is a sibling → safe.
  // Pluto / standalone HTML: fall back to document.body but skip
  // any mutation originating inside the ToC itself.
  var observerTarget = document.getElementById('nb') || document.body;
  new MutationObserver(function(mutations){
    // If every mutation is inside the ToC, it's our own write — ignore.
    var allFromToc = true;
    for (var i = 0; i < mutations.length; i++) {
      if (!tocNav.contains(mutations[i].target)) { allFromToc = false; break; }
    }
    if (allFromToc) return;
    debouncedBuild();
  }).observe(observerTarget, {childList:true, subtree:true});

  // First build (in case it boots already-open).
  if (!tocNav.classList.contains('hide')) buildToc();
})();
</script>
""")
end
