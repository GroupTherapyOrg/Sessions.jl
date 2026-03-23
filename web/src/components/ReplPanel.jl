# ReplPanel.jl — xterm.js terminal panel with multi-tab support
#
# Renders the terminal container with tab bar and xterm.js initialization.
# Each tab gets its own PTY process on the server. Communication is via
# the "terminal" WebSocket channel with base64-encoded byte streams.

"""
    ReplPanel()

Render the terminal panel with xterm.js. Includes tab bar (add/close tabs),
terminal container, and all client-side JS for PTY ↔ xterm.js bridging.
"""
function ReplPanel()
    Div(:id => "repl",
        :class => "flex flex-col overflow-hidden shrink-0",
        :style => "height:220px; background:#0a0e14; border:1px solid #1c2736; border-radius:0.75rem; box-shadow:0 10px 15px -3px rgba(0,0,0,.25);",

        # Tab bar
        Div(:id => "term-tab-bar",
            :class => "flex items-center shrink-0",
            :style => "padding:0 4px; border-bottom:1px solid #1c2736; height:30px; gap:0;",

            # Tabs go here (populated by JS)
            Div(:id => "term-tabs", :class => "flex items-center gap-0 flex-1 overflow-x-auto",
                :style => "scrollbar-width:none;"),

            # Add terminal button
            Button(:id => "term-add-btn",
                :class => "shrink-0",
                :style => "background:none;border:none;cursor:pointer;color:#3d5068;padding:4px 8px;font-size:14px;font-family:ui-monospace,monospace;transition:color .12s;",
                :title => "New Terminal",
                RawHtml("""<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M8 3v10M3 8h10"/></svg>"""))),

        # xterm.js container
        Div(:id => "term-container",
            :class => "flex-1 min-h-0",
            :style => "padding:4px 4px 0;"),

        # Client-side JS
        RawHtml(string("<script>", _terminal_js(), "</script>")))
end

function _terminal_js()
"""
(function() {
  if (window._terminalInit) return;
  window._terminalInit = true;

  // Wait for xterm.js to load
  if (typeof window.Terminal === 'undefined') {
    setTimeout(function() { window._terminalInit = false; eval(document.querySelector('#repl script').textContent); }, 200);
    return;
  }

  var container = document.getElementById('term-container');
  var tabBar = document.getElementById('term-tabs');
  var addBtn = document.getElementById('term-add-btn');
  if (!container || !tabBar) return;

  // Theme matching Sessions.jl palette
  var termTheme = {
    background: '#0a0e14',
    foreground: '#d4dce8',
    cursor: '#56d4a0',
    cursorAccent: '#0a0e14',
    selectionBackground: 'rgba(86,212,160,.2)',
    selectionForeground: '#d4dce8',
    black: '#0a0e14',
    red: '#e06b65',
    green: '#56d4a0',
    yellow: '#d4a056',
    blue: '#7bb8e8',
    magenta: '#b08fd8',
    cyan: '#56d4a0',
    white: '#d4dce8',
    brightBlack: '#3d5068',
    brightRed: '#e06b65',
    brightGreen: '#56d4a0',
    brightYellow: '#d4a056',
    brightBlue: '#7bb8e8',
    brightMagenta: '#b08fd8',
    brightCyan: '#7bb8e8',
    brightWhite: '#ffffff'
  };

  // Terminal instances per tab: { tabId: { term, fitAddon } }
  var terminals = {};
  var activeTabId = null;

  // ── Create a new xterm.js instance for a tab ──
  function createTerminal(tabId) {
    var term = new Terminal({
      fontSize: 12,
      fontFamily: \"'JetBrains Mono', 'SF Mono', monospace\",
      cursorBlink: true,
      cursorStyle: 'bar',
      scrollback: 5000,
      theme: termTheme,
      allowProposedApi: true
    });

    var fitAddon = new FitAddon.FitAddon();
    term.loadAddon(fitAddon);

    if (typeof WebLinksAddon !== 'undefined') {
      term.loadAddon(new WebLinksAddon.WebLinksAddon());
    }

    // Send input to server
    term.onData(function(data) {
      if (window.TherapyWS) {
        // Base64 encode the input
        var bytes = new TextEncoder().encode(data);
        var b64 = btoa(String.fromCharCode.apply(null, bytes));
        TherapyWS.sendMessage('terminal', {action: 'input', tab_id: tabId, data: b64});
      }
    });

    // Send resize to server (debounced)
    var resizeTimer = null;
    term.onResize(function(evt) {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(function() {
        if (window.TherapyWS) {
          TherapyWS.sendMessage('terminal', {action: 'resize', tab_id: tabId, rows: evt.rows, cols: evt.cols});
        }
      }, 100);
    });

    terminals[tabId] = { term: term, fitAddon: fitAddon };
    return { term: term, fitAddon: fitAddon };
  }

  // ── Show a specific tab's terminal ──
  function showTab(tabId) {
    // Hide all terminals
    for (var id in terminals) {
      var el = document.getElementById('term-' + id);
      if (el) el.style.display = 'none';
    }
    // Show active
    var el = document.getElementById('term-' + tabId);
    if (el) {
      el.style.display = '';
      terminals[tabId].term.focus();
      setTimeout(function() {
        terminals[tabId].fitAddon.fit();
      }, 10);
    }
    activeTabId = tabId;
    // Update tab bar styling
    tabBar.querySelectorAll('.term-tab').forEach(function(t) {
      t.classList.toggle('active', t.dataset.tabId === tabId);
    });
  }

  // ── Render tab bar from tabs array ──
  function renderTabs(tabs) {
    tabBar.innerHTML = '';
    tabs.forEach(function(t) {
      var tab = document.createElement('div');
      tab.className = 'term-tab' + (t.active ? ' active' : '');
      tab.dataset.tabId = t.id;
      tab.innerHTML = '<span>' + t.label + '</span><span class=\"close-x\" title=\"Close\">&times;</span>';

      tab.addEventListener('click', function(e) {
        if (e.target.classList.contains('close-x')) {
          if (window.TherapyWS) {
            TherapyWS.sendMessage('terminal', {action: 'close_tab', tab_id: t.id});
          }
          return;
        }
        if (window.TherapyWS) {
          TherapyWS.sendMessage('terminal', {action: 'switch_tab', tab_id: t.id});
        }
        showTab(t.id);
      });

      tabBar.appendChild(tab);
    });
  }

  // ── Add terminal button ──
  addBtn.addEventListener('click', function() {
    // Get container dimensions for initial size
    var dims = {rows: 24, cols: 80};
    if (activeTabId && terminals[activeTabId]) {
      var t = terminals[activeTabId].term;
      dims.rows = t.rows;
      dims.cols = t.cols;
    }
    if (window.TherapyWS) {
      TherapyWS.sendMessage('terminal', {action: 'spawn', rows: dims.rows, cols: dims.cols});
    }
  });

  // ── Handle panel visibility: fit on show ──
  var replPanel = document.getElementById('repl-panel');
  if (replPanel) {
    var observer = new MutationObserver(function() {
      if (replPanel.style.display !== 'none' && activeTabId && terminals[activeTabId]) {
        setTimeout(function() {
          terminals[activeTabId].fitAddon.fit();
        }, 50);
      }
    });
    observer.observe(replPanel, {attributes: true, attributeFilter: ['style']});
  }

  // ── Resize on window resize ──
  window.addEventListener('resize', function() {
    if (activeTabId && terminals[activeTabId]) {
      terminals[activeTabId].fitAddon.fit();
    }
  });

  // ── WebSocket handler for terminal channel ──
  window.addEventListener('therapy:channel:terminal', function(e) {
    var data = e.detail;
    if (!data || !data.event) return;

    if (data.event === 'output') {
      var t = terminals[data.tab_id];
      if (t) {
        // Decode base64 output and write to xterm
        var raw = atob(data.data);
        var bytes = new Uint8Array(raw.length);
        for (var i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
        t.term.write(bytes);
      }
    }

    else if (data.event === 'tab_opened') {
      // Create xterm instance and DOM element
      var info = createTerminal(data.tab_id);
      var div = document.createElement('div');
      div.id = 'term-' + data.tab_id;
      div.style.cssText = 'height:100%;';
      container.appendChild(div);
      info.term.open(div);

      // Render tabs and show this one
      if (data.tabs) renderTabs(data.tabs);
      showTab(data.tab_id);

      // Fit after DOM settles
      setTimeout(function() { info.fitAddon.fit(); }, 50);
    }

    else if (data.event === 'tab_closed') {
      var t = terminals[data.tab_id];
      if (t) {
        t.term.dispose();
        delete terminals[data.tab_id];
        var el = document.getElementById('term-' + data.tab_id);
        if (el) el.remove();
      }
      if (data.tabs) renderTabs(data.tabs);
      if (data.active_tab_id) showTab(data.active_tab_id);
    }

    else if (data.event === 'tab_switched') {
      if (data.tabs) renderTabs(data.tabs);
      showTab(data.tab_id);
    }

    else if (data.event === 'terminal_list') {
      var serverIds = new Set((data.tabs || []).map(function(t){ return t.id; }));

      // Remove client terminals that no longer exist on server
      for (var id in terminals) {
        if (!serverIds.has(id)) {
          terminals[id].term.dispose();
          delete terminals[id];
          var el = document.getElementById('term-' + id);
          if (el) el.remove();
        }
      }

      if (data.tabs && data.tabs.length > 0) {
        // Create xterm instances for server tabs we don't have yet
        data.tabs.forEach(function(t) {
          if (!terminals[t.id]) {
            var info = createTerminal(t.id);
            var div = document.createElement('div');
            div.id = 'term-' + t.id;
            div.style.cssText = 'height:100%;';
            container.appendChild(div);
            info.term.open(div);
            info.term.writeln('\x1b[90m[reconnected]\x1b[0m');
            setTimeout(function() { info.fitAddon.fit(); }, 50);
          }
        });
        renderTabs(data.tabs);
        var activeId = data.active_tab_id || data.tabs[data.tabs.length - 1].id;
        showTab(activeId);
      } else {
        // No terminals on server — spawn one
        if (window.TherapyWS && TherapyWS.sendMessage) {
          TherapyWS.sendMessage('terminal', {action: 'spawn', rows: 24, cols: 80});
        }
      }
    }

    else if (data.event === 'tab_exited') {
      var t = terminals[data.tab_id];
      if (t) {
        t.term.writeln('\\r\\n\\x1b[90m[Process exited]\\x1b[0m');
      }
    }
  });

  // ── Request terminal list whenever panel is visible ──
  function requestList() {
    if (window.TherapyWS && TherapyWS.sendMessage) {
      TherapyWS.sendMessage('terminal', {action: 'list'});
    }
  }

  // If panel is already visible (restored from localStorage), request list
  setTimeout(function() {
    if (replPanel && replPanel.style.display !== 'none') {
      requestList();
    }
  }, 500);

  // When panel becomes visible via toggle
  if (replPanel) {
    var spawnObserver = new MutationObserver(function() {
      if (replPanel.style.display !== 'none') {
        requestList();
      }
    });
    spawnObserver.observe(replPanel, {attributes: true, attributeFilter: ['style']});
  }
})();
"""
end
