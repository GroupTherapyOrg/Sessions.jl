# SessionsApp.jl — Top-level IDE layout (SSR shell)
#
# Places all @island components in the floating panel layout.
# No signals, no interactivity — just structural HTML.
# All interactivity lives in the island components.

function SessionsApp(children...)
    cell_count_init = if isdefined(Main, :WEB_STATE) && Main.WEB_STATE[] !== nothing
        try
            length(Main.Sessions.ordered_cells(Main.Sessions.active_nb(Main.WEB_STATE[])))
        catch
            0
        end
    else
        0
    end

    Fragment(
        # Main layout
        Div(:id => "sessions-root",

            # Workspace: floating panels with gaps
            Div(:id => "workspace",

                # Activity Bar (@island — panel toggles)
                ActivityBar(),

                # File Explorer (@island — Shoelace tree)
                # Wrapped in a container that Show(sidebar_open) will control
                Div(:id => "fpanel",
                    :class => "rounded-xl flex flex-col overflow-hidden shrink-0",
                    :style => "width:234px;max-height:100%;display:none;background:var(--panel-bg);border:1px solid var(--cell-border);",
                    Div(:class => "flex items-center justify-between px-3 shrink-0",
                        :style => "height:38px;border-bottom:1px solid var(--divider);",
                        Span(:style => "font-size:10px;font-weight:600;text-transform:uppercase;letter-spacing:.5px;color:var(--text-3);", "Explorer"),
                        Span(:style => "font-size:9px;color:var(--text-3);font-family:'JetBrains Mono',monospace;", "\u2318B")),
                    Div(:class => "explorer-loading", :id => "explorer-loading",
                        Span(:class => "dot-pulse"), Span(:class => "dot-pulse"), Span(:class => "dot-pulse")),
                    FileExplorer()),

                # Editor Area (notebook/file + terminal)
                Div(:id => "editor-area",
                    :style => "flex:1 1 0%;display:flex;flex-direction:column;min-width:0;min-height:0;overflow:hidden;gap:12px;",
                    children...,
                    # Terminal (@island — xterm.js)
                    Div(:id => "repl-panel",
                        :style => "display:none;flex-shrink:0;",
                        ReplPanel()))),

            # Status Bar (@island — theme toggle, connection, cell count)
            StatusBar(initial_cells=cell_count_init)),

        # Panel visibility restore script (bridges shared signals to existing panels)
        # This will be replaced when FileExplorer and Terminal become proper Show()-based islands
        RawHtml("""<script>
(function() {
    var fp = document.getElementById('fpanel');
    var repl = document.getElementById('repl-panel');
    var sb = localStorage.getItem('sessions-sidebar');
    var rp = localStorage.getItem('sessions-repl');
    if (fp && sb === '1') fp.style.display = '';
    if (repl && rp === '1') repl.style.display = '';
    customElements.whenDefined('sl-tree').then(function() {
        var loader = document.getElementById('explorer-loading');
        if (loader) loader.style.display = 'none';
    });

    // ── Restore saved panel sizes ──
    var savedW = localStorage.getItem('sessions-explorer-w');
    if (fp && savedW) fp.style.width = savedW + 'px';
    var savedH = localStorage.getItem('sessions-terminal-h');
    if (repl && savedH) { var r = repl.querySelector('#repl'); if (r) r.style.height = savedH + 'px'; }

    // ── Resize logic (uses ::after/::before pseudo-elements on panels) ──
    function setupEdgeResize(panel, target, prop, lsKey, min, max, axis) {
      if (!panel || !target) return;
      panel.addEventListener('mousedown', function(e) {
        var rect = panel.getBoundingClientRect();
        // Only activate if click is in the resize zone (near the edge)
        if (axis === 'x' && e.clientX < rect.right - 4) return;
        if (axis === 'y' && e.clientY > rect.top + 4) return;
        e.preventDefault();
        document.body.classList.add(axis === 'x' ? 'resizing-x' : 'resizing-y');
        var start = axis === 'x' ? e.clientX : e.clientY;
        var startSize = target.getBoundingClientRect()[axis === 'x' ? 'width' : 'height'];
        var onMove = function(e2) {
          var delta = (axis === 'x' ? e2.clientX : e2.clientY) - start;
          var newSize = Math.round(Math.max(min, Math.min(max, startSize + (axis === 'y' ? -delta : delta))));
          target.style[prop] = newSize + 'px';
          if (axis === 'y') window.dispatchEvent(new Event('resize'));
        };
        var onUp = function() {
          document.body.classList.remove('resizing-x', 'resizing-y');
          document.removeEventListener('mousemove', onMove);
          document.removeEventListener('mouseup', onUp);
          localStorage.setItem(lsKey, Math.round(target.getBoundingClientRect()[axis === 'x' ? 'width' : 'height']));
        };
        document.addEventListener('mousemove', onMove);
        document.addEventListener('mouseup', onUp);
      });
    }

    setupEdgeResize(fp, fp, 'width', 'sessions-explorer-w', 160, 500, 'x');
    var termEl = repl ? repl.querySelector('#repl') : null;
    setupEdgeResize(termEl, termEl, 'height', 'sessions-terminal-h', 80, 600, 'y');
})();
</script>"""))
end
