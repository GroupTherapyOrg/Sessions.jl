# SessionsApp.jl — Top-level IDE layout
#
# Structure (top to bottom in viewport):
#   1. Workspace row: [Activity Bar] [File Explorer?] [Editor Area]
#   2. Terminal panel (toggle, starts hidden)
#   3. Status bar (always visible, fixed bottom)
#
# Panel toggles: JS onclick → display toggle + localStorage + button state
# Status bar: live-updated via JS (cell count, connection status)

const _JULIA_LOGO_SVG = """<svg width="16" height="14" viewBox="0 0 40 34" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="20" cy="6" r="5.5" fill="#56d4a0"/><circle cx="10" cy="28" r="5.5" fill="#e06b65"/><circle cx="30" cy="28" r="5.5" fill="#b08fd8"/></svg>"""

const _AB_BTN_STYLE = "width:32px;height:32px;display:flex;align-items:center;justify-content:center;border-radius:6px;border:none;background:none;cursor:pointer;color:#3d5068;transition:all .15s;"

function SessionsApp(children...)
    cell_count = if isdefined(Main, :WEB_STATE) && Main.WEB_STATE[] !== nothing
        length(Main.Sessions.ordered_cells(Main.Sessions.active_nb(Main.WEB_STATE[])))
    else
        0
    end

    Fragment(
        # ── Panel toggle JS (must be early so onclick handlers work) ──
        _panel_toggle_script(),

        # ── Main layout (CSS in Layout.jl handles flex-col + height) ──
        Div(:id => "sessions-root",

            # Row 1: Workspace (activity bar + sidebar + editor)
            Div(:id => "workspace",

                # Activity Bar
                _activity_bar(),

                # File Explorer (starts hidden)
                _file_explorer_panel(),

                # Editor Area (notebook + terminal)
                Div(:id => "editor-area",
                    :style => "flex:1 1 0%;display:flex;flex-direction:column;min-width:0;min-height:0;overflow:hidden;",
                    children...,
                    # Terminal (inside editor area so it matches notebook width)
                    Div(:id => "repl-panel",
                        :style => "display:none;flex-shrink:0;margin-top:10px;",
                        ReplPanel()))),

            # Row 3: Status bar (always visible, fixed height)
            _status_bar(cell_count)),

        # ── Restore panels from localStorage ──
        _panel_restore_script(),

        # ── Status bar live update ──
        _status_bar_script())
end

# ═══════════════════════════════════════════════════════════════
# Sub-components (clean separation)
# ═══════════════════════════════════════════════════════════════

function _activity_bar()
    Div(:class => "flex flex-col items-center gap-1 py-2 w-[42px] shrink-0 self-start rounded-xl bg-surf border border-b1 shadow-lg shadow-black/25",
        Div(:class => "flex items-center justify-center w-8 h-8 mb-2",
            RawHtml(_JULIA_LOGO_SVG)),

        # File explorer toggle
        Button(:class => "ab-btn",
            :style => _AB_BTN_STYLE,
            :title => "Toggle Explorer (Ctrl+B)",
            Symbol("data-state") => "off",
            :on_click => "_togglePanel('fpanel','sessions-sidebar',this)",
            RawHtml("""<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"/></svg>""")),

        # JET diagnostics (disabled — JETLS integration coming soon)
        Button(:class => "ab-btn",
            :style => _AB_BTN_STYLE * "opacity:0.3;cursor:default;",
            :title => "JETLS diagnostics — coming soon",
            :disabled => "true",
            RawHtml("""<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"/></svg>""")),

        # Terminal toggle
        Button(:class => "ab-btn",
            :style => _AB_BTN_STYLE,
            :title => "Toggle Terminal (Ctrl+`)",
            Symbol("data-state") => "off",
            :on_click => "_togglePanel('repl-panel','sessions-repl',this)",
            RawHtml("""<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>""")))
end

function _file_explorer_panel()
    Div(:id => "fpanel",
        :class => "rounded-xl bg-surf border border-b1 flex flex-col overflow-hidden shrink-0 shadow-lg shadow-black/25",
        :style => "width:234px;max-height:100%;display:none;",
        Div(:class => "flex items-center justify-between px-3 py-2.5 border-b border-b1 shrink-0",
            Span(:class => "text-[10px] font-semibold uppercase tracking-wider text-t3", "Explorer"),
            Span(:class => "text-[9px] text-t4 font-mono", "\u2318B")),
        FileExplorer())
end

function _status_bar(cell_count::Int)
    Div(:id => "status-bar",
        :style => "height:26px;flex-shrink:0;display:flex;align-items:center;padding:0 16px;gap:16px;font-size:10px;font-family:'JetBrains Mono',monospace;color:#3d5068;background:transparent;border-top:1px solid #1c2736;",
        Span(:style => "display:flex;align-items:center;gap:6px;",
            RawHtml(_JULIA_LOGO_SVG),
            "Sessions.jl"),
        Span(:id => "status-cells", "$(cell_count) cells"),
        Span(:style => "flex:1;"),
        Span(:id => "status-connection", :style => "color:#56d4a0;", "\u25CF connected"),
        # Theme picker
        Span(:id => "theme-picker",
            :style => "position:relative;cursor:pointer;padding:2px 6px;border-radius:4px;transition:background .12s;",
            :title => "Switch IDE theme",
            RawHtml("""<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="8" cy="8" r="5"/><path d="M8 3a5 5 0 000 10"/></svg>"""),
            Span(:id => "theme-picker-label", :style => "margin-left:4px;", "Dark+")))
end

# ═══════════════════════════════════════════════════════════════
# Scripts (separated for clarity)
# ═══════════════════════════════════════════════════════════════

function _panel_toggle_script()
    RawHtml("""<script>
window._togglePanel = function(panelId, storageKey, btn) {
    var panel = document.getElementById(panelId);
    if (!panel) return;
    var isOpen = panel.style.display !== 'none';
    panel.style.display = isOpen ? 'none' : '';
    btn.setAttribute('data-state', isOpen ? 'off' : 'on');
    localStorage.setItem(storageKey, isOpen ? '0' : '1');
};
</script>""")
end

function _panel_restore_script()
    RawHtml("""<script>
(function() {
    var sb = localStorage.getItem('sessions-sidebar');
    var rp = localStorage.getItem('sessions-repl');

    var fp = document.getElementById('fpanel');
    var repl = document.getElementById('repl-panel');
    var btns = document.querySelectorAll('.ab-btn');

    if (fp) {
        var showSidebar = sb === '1';
        fp.style.display = showSidebar ? '' : 'none';
        if (btns[0]) btns[0].setAttribute('data-state', showSidebar ? 'on' : 'off');
    }
    if (repl) {
        var showRepl = rp === '1';
        repl.style.display = showRepl ? '' : 'none';
        if (btns[2]) btns[2].setAttribute('data-state', showRepl ? 'on' : 'off');
    }
})();
</script>""")
end

function _status_bar_script()
    RawHtml("""<script>
(function(){
  if(window._statusBarInit) return;
  window._statusBarInit=true;

  var cellsEl = document.getElementById('status-cells');
  var connEl = document.getElementById('status-connection');

  function updateCells(count){
    if(cellsEl) cellsEl.textContent = count + ' cells';
  }

  function setConnected(ok){
    if(!connEl) return;
    connEl.style.color = ok ? '#56d4a0' : '#e06b65';
    connEl.textContent = ok ? '\u25CF connected' : '\u25CF disconnected';
  }

  // Listen for notebook events that change cell count
  window.addEventListener('therapy:channel:notebook', function(e){
    var d = e.detail;
    if(!d || !d.event) return;
    if(d.total_cells) {
      updateCells(d.total_cells);
    } else if(d.event==='cell_added' || d.event==='cell_deleted') {
      setTimeout(function(){ updateCells(document.querySelectorAll('.cell-wrap').length); }, 50);
    } else if(d.event==='nb_replaced' || d.event==='full_state') {
      setTimeout(function(){ updateCells(document.querySelectorAll('.cell-wrap').length); }, 200);
    }
  });

  // Connection status polling
  setInterval(function(){
    if(window.TherapyWS && TherapyWS._ws){
      setConnected(TherapyWS._ws.readyState === 1);
    }
  }, 2000);

  window.addEventListener('therapy:ws:open', function(){ setConnected(true); });
  window.addEventListener('therapy:ws:close', function(){ setConnected(false); });

  // ── Theme picker ──
  var _themes = [
    {id:'dark+', label:'Dark+'},
    {id:'dark', label:'Dark'}
  ];
  var _picker = document.getElementById('theme-picker');
  var _pickerLabel = document.getElementById('theme-picker-label');
  var _popup = null;

  // Restore saved theme
  var saved = localStorage.getItem('sessions-ide-theme') || 'dark+';
  _applyTheme(saved);

  function _applyTheme(id) {
    var root = document.getElementById('sessions-root');
    if (root) {
      if (id === 'dark+') root.removeAttribute('data-ide-theme');
      else root.setAttribute('data-ide-theme', id);
    }
    if (_pickerLabel) _pickerLabel.textContent = _themes.find(function(t){return t.id===id;}).label;
    localStorage.setItem('sessions-ide-theme', id);
  }

  if (_picker) {
    _picker.addEventListener('mouseenter', function(){ _picker.style.background='rgba(255,255,255,.06)'; });
    _picker.addEventListener('mouseleave', function(){ _picker.style.background=''; });
    _picker.addEventListener('click', function(e) {
      e.stopPropagation();
      if (_popup) { _popup.remove(); _popup = null; return; }
      var r = _picker.getBoundingClientRect();
      _popup = document.createElement('div');
      _popup.style.cssText = 'position:fixed;z-index:9999;background:#1a2332;border:1px solid #2a3a4f;border-radius:6px;min-width:100px;box-shadow:0 8px 24px rgba(0,0,0,.5);overflow:hidden;padding:3px 0;bottom:'+(window.innerHeight-r.top+4)+'px;right:'+(window.innerWidth-r.right)+'px;';
      _themes.forEach(function(t) {
        var item = document.createElement('div');
        item.textContent = t.label;
        item.style.cssText = 'padding:5px 12px;font-size:11px;cursor:pointer;color:#9baabd;transition:background .1s,color .1s;';
        item.addEventListener('mouseenter', function(){ item.style.background='rgba(86,212,160,.08)'; item.style.color='#d4dce8'; });
        item.addEventListener('mouseleave', function(){ item.style.background=''; item.style.color='#9baabd'; });
        item.addEventListener('click', function(){ _applyTheme(t.id); _popup.remove(); _popup = null; });
        _popup.appendChild(item);
      });
      document.body.appendChild(_popup);
    });
    document.addEventListener('click', function(){ if(_popup){ _popup.remove(); _popup=null; } });
  }
})();
</script>""")
end
