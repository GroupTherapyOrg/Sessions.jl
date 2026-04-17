# SessionsApp.jl — Top-level IDE layout (SSR shell)
#
# Places all @island components in the floating panel layout.
# No signals, no interactivity — just structural HTML.
# All interactivity lives in the island components.

function SessionsApp(children...)
    # Initial cell count is set on the shared cellcount_signal at module
    # load (see SharedSignals.jl) and updated by the WS bridge.
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
                    Div(:class => "flex items-center shrink-0",
                        :style => "height:42px;padding:0 14px;border-bottom:1px solid var(--divider);",
                        Span(:style => "font-size:10px;font-weight:600;text-transform:uppercase;letter-spacing:.6px;color:var(--text-3);", "Explorer")),
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
            StatusBar()),

        # Panel visibility restore script (bridges shared signals to existing panels)
        # This will be replaced when FileExplorer and Terminal become proper Show()-based islands
        RawHtml("""<script>
(function() {
    var fp = document.getElementById('fpanel');
    var repl = document.getElementById('repl-panel');
    var sb = localStorage.getItem('sessions-sidebar');
    var rp = localStorage.getItem('sessions-repl');
    var ws = document.getElementById('workspace');
    if (fp && sb === '1') fp.style.display = '';
    if (repl && rp === '1') repl.style.display = '';

    // ── Seed ActivityBar @island kwargs from localStorage before hydration.
    // Therapy's compiled hydration reads props.initial_sidebar / initial_terminal
    // and writes them to signal_0/signal_1 via `ex.signal_N.value = BigInt(...)`
    // BEFORE the initial _rt_flush. That way the first effect fire sees the
    // restored values and sets the DOM + localStorage to match. Must run
    // before requestIdleCallback wakes hydrate_activitybar.
    var ab = document.querySelector('[data-component="activitybar"]');
    if (ab) {
        var props = {};
        try { props = JSON.parse(ab.dataset.props || '{}'); } catch (e) {}
        props.initial_sidebar  = sb === '1' ? 1 : 0;
        props.initial_terminal = rp === '1' ? 1 : 0;
        ab.dataset.props = JSON.stringify(props);
    }

    // ── Restore saved panel sizes ──
    var savedW = localStorage.getItem('sessions-explorer-w');
    if (fp && savedW) fp.style.width = savedW + 'px';
    var savedH = localStorage.getItem('sessions-terminal-h');
    if (repl && savedH) { var r = repl.querySelector('#repl'); if (r) r.style.height = savedH + 'px'; }

    // ── Restore terminal orientation ──
    var orient = localStorage.getItem('sessions-terminal-orient');
    if (orient === 'v' && repl && ws) {
        ws.appendChild(repl);
        ws.classList.add('terminal-right');
        var r = repl.querySelector('#repl');
        if (r) {
            r.style.height = '';
            r.style.width = (localStorage.getItem('sessions-terminal-w') || '350') + 'px';
        }
        var btn = document.getElementById('term-orient-btn');
        if (btn) {
            btn.title = 'Terminal to bottom';
            btn.innerHTML = '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M8 3v10M5 10l3 3 3-3"/></svg>';
        }
    }

    // ── Toggle terminal orientation ──
    window._sessionsToggleTerminalOrientation = function() {
        var ea = document.getElementById('editor-area');
        var rp = document.getElementById('repl-panel');
        var r = document.getElementById('repl');
        if (!ws || !ea || !rp || !r) return;
        var isVert = ws.classList.contains('terminal-right');
        if (isVert) {
            // → horizontal (bottom)
            ea.appendChild(rp);
            ws.classList.remove('terminal-right');
            r.style.width = '';
            r.style.height = (localStorage.getItem('sessions-terminal-h') || '220') + 'px';
            localStorage.setItem('sessions-terminal-orient', 'h');
        } else {
            // → vertical (right)
            ws.appendChild(rp);
            ws.classList.add('terminal-right');
            r.style.height = '';
            r.style.width = (localStorage.getItem('sessions-terminal-w') || '350') + 'px';
            localStorage.setItem('sessions-terminal-orient', 'v');
        }
        // Re-fit all xterm instances
        setTimeout(function(){ window.dispatchEvent(new Event('resize')); }, 100);
        // Update toggle button icon + title
        var btn = document.getElementById('term-orient-btn');
        if (btn) {
            btn.title = ws.classList.contains('terminal-right') ? 'Terminal to bottom' : 'Terminal to right';
            btn.innerHTML = ws.classList.contains('terminal-right')
                ? '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M8 3v10M5 10l3 3 3-3"/></svg>'
                : '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M3 8h10M10 5l3 3-3 3"/></svg>';
        }
    };

    // ── Resize logic (uses ::after/::before pseudo-elements on panels) ──
    function setupEdgeResize(panel, target, prop, lsKey, min, max, axis) {
      if (!panel || !target) return;
      panel.addEventListener('mousedown', function(e) {
        var rect = panel.getBoundingClientRect();
        // Only activate if click is in the resize zone (near the edge)
        // For vertical terminal: resize zone is on the LEFT edge
        var isTermVert = ws.classList.contains('terminal-right') && panel.id === 'repl';
        if (isTermVert) {
            if (e.clientX > rect.left + 8) return;
        } else if (axis === 'x' && e.clientX < rect.right - 4) return;
        else if (axis === 'y' && e.clientY > rect.top + 4) return;

        e.preventDefault();
        var actualAxis = isTermVert ? 'x' : axis;
        document.body.classList.add(actualAxis === 'x' ? 'resizing-x' : 'resizing-y');
        var start = actualAxis === 'x' ? e.clientX : e.clientY;
        var startSize = target.getBoundingClientRect()[actualAxis === 'x' ? 'width' : 'height'];
        var onMove = function(e2) {
          var delta = (actualAxis === 'x' ? e2.clientX : e2.clientY) - start;
          var newSize = Math.round(Math.max(min, Math.min(max, startSize + (actualAxis === 'y' ? -delta : isTermVert ? -delta : delta))));
          target.style[actualAxis === 'x' ? 'width' : 'height'] = newSize + 'px';
          window.dispatchEvent(new Event('resize'));
        };
        var onUp = function() {
          document.body.classList.remove('resizing-x', 'resizing-y');
          document.removeEventListener('mousemove', onMove);
          document.removeEventListener('mouseup', onUp);
          var sz = Math.round(target.getBoundingClientRect()[actualAxis === 'x' ? 'width' : 'height']);
          localStorage.setItem(isTermVert ? 'sessions-terminal-w' : lsKey, sz);
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
