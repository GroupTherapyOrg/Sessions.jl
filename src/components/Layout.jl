function Layout(children...; title="Sessions.jl")
    Fragment(
        RawHtml("""<script>
(function(){
  var t = localStorage.getItem('sessions-theme');
  if (!t) t = window.matchMedia('(prefers-color-scheme:dark)').matches ? 'dark' : 'light';
  if (t === 'dark') {
    document.documentElement.classList.add('dark', 'sl-theme-dark');
  } else {
    document.documentElement.classList.remove('dark', 'sl-theme-dark');
    document.documentElement.classList.add('sl-theme-light');
  }
})();
</script>"""),
        RawHtml("""<script>(function(){var l=document.createElement('link');l.rel='icon';l.type='image/svg+xml';l.href='/static/favicon.svg';document.head.appendChild(l)})();</script>"""),
        RawHtml("""<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,100..1000;1,9..40,100..1000&family=JetBrains+Mono:ital,wght@0,100..800;1,100..800&family=Fraunces:ital,opsz,wght@0,9..144,100..900;1,9..144,100..900&display=swap" rel="stylesheet">"""),
        RawHtml("""<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/themes/light.css" />
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/themes/dark.css" />
<script type="module" src="https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/shoelace-autoloader.js"></script>"""),
        RawHtml("""<script>window.MathJax={tex:{inlineMath:[['\$','\$'],['\\\\(','\\\\)']]},svg:{fontCache:'global'},options:{ignoreHtmlClass:'cm-editor|tex2jax_ignore',processHtmlClass:'tex2jax_process'}};</script>
<script id="MathJax-script" async src="https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/tex-svg-full.js"></script>"""),
        RawHtml("""<link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/styles/default.min.css" disabled>
<script src="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/highlight.min.js"></script>
<script src="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/languages/julia.min.js"></script>
<script>hljs.configure({cssSelector:'.md-prose pre code', ignoreUnescapedHTML:true});</script>"""),
        RawHtml("""<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/css/xterm.css" />
<script src="https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/lib/xterm.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/lib/addon-fit.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@xterm/addon-web-links@0.11.0/lib/addon-web-links.js"></script>"""),
        RawHtml("""<script src="/static/editor.js"></script>"""),
        RawHtml("<script>" * _notebook_island_js() * "</script>"),
        RawHtml("<script>" * Main.Sessions.SessionsUI.BOND_BRIDGE_JS * "</script>"),
        RawHtml("""<div id="app-root" class="font-sans">"""),
        children...,
        RawHtml("""</div>"""),
        RawHtml("""<script>
(function(){
  function _waitForWS() {
    if (window.TherapyWS && TherapyWS.send) {
      TherapyWS.sendMessage = function(channel, data) {
        TherapyWS.send(Object.assign({type:'channel_message', channel:channel}, data));
      };
    } else { setTimeout(_waitForWS, 100); }
  }
  _waitForWS();
  window.addEventListener('therapy:ws:message', function(e) {
    var msg = e.detail;
    if (msg && msg.channel) {
      window.dispatchEvent(new CustomEvent('therapy:channel:' + msg.channel, {detail: msg}));
    }
  });
})();
</script>"""),
        RawHtml("""<div id="undo-toast">Cell deleted &mdash; <kbd>Ctrl+Z</kbd> to undo</div>"""))
end
