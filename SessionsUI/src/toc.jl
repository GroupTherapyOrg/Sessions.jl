# toc.jl — Table of Contents widget for notebook export
#
# Usage in notebooks:
#   using SessionsUI: TableOfContents
#   TableOfContents()
#
# Renders a floating navigation panel that scans markdown headings.
# For use in exported notebooks — the Sessions.jl live app has a
# built-in ToC toggle that doesn't require this widget.

"""
    TableOfContents(; title="Table of Contents", indent=true, depth=3)

A Table of Contents widget that auto-generates navigation from markdown headings.
Place in any cell — it scans the notebook for h1-h4 headings and creates a
clickable floating panel.

# Options
- `title`: Header text (default: "Table of Contents")
- `indent`: Indent entries by heading level (default: true)
- `depth`: Maximum heading level to include, 1-6 (default: 3)
"""
Base.@kwdef struct TableOfContents
    title::String = "Table of Contents"
    indent::Bool = true
    depth::Int = 3
end

function Base.show(io::IO, ::MIME"text/html", toc::TableOfContents)
    max_h = toc.depth
    selectors = join(["h$(i)" for i in 1:max_h], ", ")
    indent_cls = toc.indent ? " toc-indent" : ""

    print(io, """
    <nav class="sessions-toc$(indent_cls)" id="sessions-toc-widget">
    <div class="sessions-toc-title">$(toc.title)</div>
    <div class="sessions-toc-content"></div>
    <style>
    .sessions-toc{position:fixed;right:1rem;top:5rem;width:min(80vw,280px);max-height:calc(100vh - 7rem);overflow-y:auto;background:var(--panel-bg,#fff);border:1px solid var(--cell-border,#e5e5e5);border-radius:10px;padding:8px 0;z-index:40;font-family:'DM Sans',system-ui,sans-serif;box-shadow:0 4px 16px rgba(0,0,0,.08);}
    .sessions-toc-title{font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.5px;color:var(--text-3,#999);padding:6px 14px 8px;}
    .sessions-toc a{display:block;padding:3px 14px;font-size:12px;color:var(--text-2,#555);text-decoration:none;border-radius:4px;margin:0 4px;transition:background .12s;}
    .sessions-toc a:hover{background:rgba(128,128,128,.06);}
    .sessions-toc a.active{background:rgba(212,117,154,.08);color:#d4759a;}
    .sessions-toc.toc-indent a.H2{padding-left:24px;}
    .sessions-toc.toc-indent a.H3{padding-left:34px;font-size:11px;}
    .sessions-toc.toc-indent a.H4{padding-left:44px;font-size:11px;}
    </style>
    <script>
    (function(){
      var toc=document.querySelector('#sessions-toc-widget .sessions-toc-content');
      if(!toc)return;
      function build(){
        var hs=document.querySelectorAll('.md-prose $(selectors)');
        if(!hs.length){toc.innerHTML='<div style="color:#999;font-size:11px;font-style:italic;padding:8px 14px;">No headings</div>';return;}
        var h='';
        hs.forEach(function(el){
          var t=el.textContent.trim();if(!t)return;
          var id=el.id||(el.id='h-'+t.toLowerCase().replace(/[^a-z0-9]+/g,'-'));
          h+='<a class="'+el.tagName+'" href="#'+id+'">'+t.replace(/</g,'&lt;')+'</a>';
        });
        toc.innerHTML=h;
        toc.querySelectorAll('a').forEach(function(a){a.onclick=function(e){e.preventDefault();var el=document.getElementById(a.href.split('#')[1]);if(el)el.scrollIntoView({behavior:'smooth',block:'start'});};});
      }
      build();setTimeout(build,1000);setTimeout(build,5000);
      new MutationObserver(function(){setTimeout(build,300);}).observe(document.body,{childList:true,subtree:true});
    })();
    </script>
    </nav>
    """)
end
