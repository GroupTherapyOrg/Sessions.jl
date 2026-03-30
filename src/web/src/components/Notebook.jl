# Notebook.jl — Notebook @island component
#
# True @island with For(cell_order) signal driving cell list.
# SSR renders cells initially, @island hydrates with:
# - cell_order signal for structural changes (add/delete/move)
# - on_mount for CM init + WS bridge
# - Per-cell state managed in JS cell store (DOM patches, not signals)
#
# Works in both modes:
# - Live IDE: WS bridge receives cell_state, cell_output, etc.
# - Published (future): @bind signals → JST-compiled dependent cells

# ═══════════════════════════════════════════════════════════════
# NotebookIsland @island — the publishable unit
# ═══════════════════════════════════════════════════════════════

@island function NotebookIsland(; mode::String = "live")
    # Structural signal: drives For() — add/delete/move trigger re-render
    cell_order, set_cell_order = create_signal(Vector{String}())

    # Toolbar state signals
    is_executing, set_executing = create_signal(0)
    stale_count, set_stale_count = create_signal(0)

    # on_mount: read initial data, build cell store, init CM, setup WS
    on_mount(() -> begin
        # 1. Read serialized cell data from <script> tag
        js("""
            var dataEl = document.getElementById('nb-cells-data');
            var cells = dataEl ? JSON.parse(dataEl.textContent) : [];
            var ids = cells.map(function(c){ return c.cell_id; });
            \$1(ids);
        """, set_cell_order)

        # 2. Build JS cell store + populate skeletons
        js("""
            window._cellStore = new Map();
            var cells = document.getElementById('nb-cells-data') ?
                JSON.parse(document.getElementById('nb-cells-data').textContent) : [];
            cells.forEach(function(c) {
                _cellStore.set(c.cell_id, {
                    state: c.state || 'cell_idle',
                    output_html: c.output_html || '',
                    runtime_ns: c.runtime_ns || 0,
                    code: c.code || '',
                    folded: c.folded || false,
                    stale: c.stale || false,
                    stdout: c.stdout || ''
                });
            });
            // Populate cell skeletons after For() renders them
            setTimeout(function() { _populateCells(); _initAllCM(); }, 50);
        """)

        # 3. Setup WS bridge (live mode)
        js("""
            if ('""" * mode * """' === 'live') {
                _setupWSBridge(\$1, \$2, \$3);
            }
        """, set_cell_order, set_executing, set_stale_count)
    end)

    # Render: For() over cell_order signal
    return Div(:class => "flex-1 overflow-y-auto px-5 pt-3 pb-8", :id => "nb",
        Div(:style => "max-width:900px;margin:0 auto;padding-left:28px;",
            For(cell_order) do cell_id
                # Cell skeleton with full static structure.
                # onclick handlers wired by _populateCells (For items can't compile closures).
                # Dynamic data (output HTML, code, state) injected by _populateCells from _cellStore.
                Fragment(
                    Div(:class => "cell-wrap relative", :data_cell_id => cell_id,
                        # Output above code (Pluto style) — innerHTML set by _populateCells
                        Div(:class => "cell-out", :data_cell_id => cell_id,
                            :style => "display:none;overflow-x:auto;"),
                        # Code cell
                        Div(:class => "code-cell relative overflow-hidden",
                            :style => "background:var(--cell-bg);border:1px solid var(--cell-border);border-radius:8px;transition:border-color .2s;",
                            # Controls (hover visible) — onclick wired by _populateCells
                            Div(:class => "cell-ctrls absolute top-1 right-1.5 flex items-center gap-1.5 z-10",
                                :style => "opacity:0;transform:translateY(-3px);transition:opacity .15s,transform .15s;pointer-events:none;",
                                # Runtime badge slot (inserted dynamically)
                                # Run button
                                Button(:class => "run-btn",
                                    :style => "width:22px;height:22px;display:flex;align-items:center;justify-content:center;border-radius:50%;border:0;cursor:pointer;color:var(--status-done);background:rgba(86,212,160,.1);",
                                    :title => "Run cell (Shift+Enter)",
                                    RawHtml("""<svg width="10" height="10" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2.5v11l10-5.5z"/></svg>""")),
                                # Menu button
                                Button(:class => "menu-btn",
                                    :style => "width:22px;height:22px;display:flex;align-items:center;justify-content:center;border-radius:50%;border:0;cursor:pointer;color:var(--text-3);background:rgba(128,128,128,.06);",
                                    :title => "Cell actions",
                                    RawHtml("""<svg width="11" height="11" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="8" cy="3" r="1.2"/><circle cx="8" cy="8" r="1.2"/><circle cx="8" cy="13" r="1.2"/></svg>"""))),
                            # Eye toggle (left gutter) — onclick wired by _populateCells
                            Div(:class => "cell-eye",
                                :style => "position:absolute;left:-28px;top:0;bottom:0;width:24px;display:flex;align-items:center;justify-content:center;opacity:0;transition:opacity .15s;cursor:pointer;z-index:5;color:var(--text-3);",
                                RawHtml("""<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>""")),
                            # CM editor host — code injected by _populateCells
                            Div(:class => "cm-cell", :data_cell_id => cell_id, :data_src => ""))),
                    # Cell gap
                    Div(:class => "cdiv h-[26px] flex items-center justify-center my-[2px]",
                        Div(:class => "cdiv-inner flex items-center gap-1 opacity-0 transition-opacity",
                            Div(:class => "h-px w-14", :style => "background:var(--divider);"),
                            Button(:class => "flex items-center gap-1 rounded-full text-[10px] font-sans px-2.5 py-px cursor-pointer",
                                :style => "border:1px solid var(--divider);background:transparent;color:var(--text-3);",
                                RawHtml("""<svg width="8" height="8" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M8 2v12M2 8h12"/></svg>"""),
                                "Code"),
                            Div(:class => "h-px w-14", :style => "background:var(--divider);"))))
            end),
        # Inject the notebook JS (CM init + WS handler)
        RawHtml(string("<script>", _notebook_island_js(), "</script>"))
    )
end

# ═══════════════════════════════════════════════════════════════
# SSR Fallback (used when NotebookIsland hasn't been switched on yet)
# ═══════════════════════════════════════════════════════════════

"""SSR cell rendering fallback — used during transition."""
function NotebookContent(state)
    _Sess = Main.Sessions
    nb = _Sess.active_nb(state)
    cells = _Sess.ordered_cells(nb)

    rendered = Any[]
    cell_index = 0
    push!(rendered, _Sess.CellGap(after_cell_id=""))
    for cell in cells
        cell_index += 1
        view = _Sess.render_cell(cell; mode=:live, index=cell_index)
        view === nothing && continue
        push!(rendered, view)
        push!(rendered, _Sess.CellGap(after_cell_id=string(cell.id)))
    end

    Fragment(
        Div(:class => "flex-1 overflow-y-auto px-5 pt-3 pb-8", :id => "nb",
            Div(:style => "max-width:900px;margin:0 auto;padding-left:28px;",
                rendered...)),
        RawHtml(string("<script>", _notebook_cm_script(), "</script>")),
        _notebook_channel_script()
    )
end

# ═══════════════════════════════════════════════════════════════
# Notebook Island JS — populates skeletons, inits CM, WS bridge
# Combines CM init + WS handler + cell population into one script
# ═══════════════════════════════════════════════════════════════

function _notebook_island_js()
"""
(function() {
  // ── Populate cell skeletons from _cellStore ──
  window._populateCells = function() {
    if (!window._cellStore) return;
    _cellStore.forEach(function(cell, cellId) {
      var wrap = document.querySelector('.cell-wrap[data-cell-id="' + cellId + '"]');
      if (!wrap) return;

      // Output HTML
      var out = wrap.querySelector('.cell-out');
      if (out && cell.output_html) {
        out.innerHTML = cell.output_html;
        out.style.display = '';
        out.style.padding = '6px 0 10px';
        // Re-execute inline scripts
        out.querySelectorAll('script').forEach(function(old) {
          var s = document.createElement('script');
          s.textContent = old.textContent;
          old.parentNode.replaceChild(s, old);
        });
      }

      // Code source for CM
      var cm = wrap.querySelector('.cm-cell');
      if (cm) cm.dataset.src = cell.code || '';

      // Cell state CSS
      var code = wrap.querySelector('.code-cell');
      if (code) {
        code.classList.remove('idle', 'stale', 'executing');
        if (cell.stale) code.classList.add('stale');
        else if (cell.state === 'cell_idle') code.classList.add('idle');
      }

      // Folded state
      if (cell.folded && code) {
        code.style.display = 'none';
      }

      // Runtime badge
      if (cell.runtime_ns > 0) {
        var ctrls = wrap.querySelector('.cell-ctrls');
        if (ctrls) {
          var ms = cell.runtime_ns / 1e6;
          var rt = ms < 1 ? (cell.runtime_ns / 1e3).toFixed(1) + '\\u00b5s' :
                   ms < 1000 ? ms.toFixed(1) + 'ms' : (ms / 1000).toFixed(2) + 's';
          var badge = document.createElement('span');
          badge.className = 'rt-badge';
          var isErr = cell.state === 'cell_errored';
          var c = isErr ? 'var(--status-error)' : 'var(--status-done)';
          badge.style.cssText = 'font-size:10px;font-family:ui-monospace,monospace;padding:1px 7px;border-radius:9999px;opacity:.8;color:'+c+';';
          badge.textContent = rt;
          ctrls.insertBefore(badge, ctrls.firstChild);
        }
      }

      // Stdout (separate from output_html)
      if (cell.stdout && cell.stdout.length > 0) {
        var out = wrap.querySelector('.cell-out');
        if (out) {
          var stdoutDiv = document.createElement('div');
          stdoutDiv.className = 'font-mono text-xs whitespace-pre overflow-x-auto';
          stdoutDiv.style.cssText = 'padding:4px 0 6px;line-height:1.5;color:var(--output-text);';
          stdoutDiv.textContent = cell.stdout;
          out.parentNode.insertBefore(stdoutDiv, out);
          stdoutDiv.style.display = '';
        }
      }

      // Wire onclick handlers (buttons are in VNode skeleton, but For items
      // can't compile closures that capture cell_id — so we wire here)
      var eye = wrap.querySelector('.cell-eye');
      if (eye) eye.onclick = function() { _toggleFold(cellId); };

      var runBtn = wrap.querySelector('.run-btn');
      if (runBtn) runBtn.onclick = function() { window._sessionsRunCell(cellId); };

      var menuBtn = wrap.querySelector('.menu-btn');
      if (menuBtn) menuBtn.onclick = function(e) { e.stopPropagation(); _showCellMenu(menuBtn, cellId); };

      // Wire CellGap "+ Code" button (VNode button, onclick needs cell_id)
      var gap = wrap.nextElementSibling;
      if (gap && gap.classList.contains('cdiv')) {
        var gapBtn = gap.querySelector('button');
        if (gapBtn) gapBtn.onclick = function() {
          if (TherapyWS && TherapyWS.sendMessage) TherapyWS.sendMessage('notebook', {action:'add_cell', after_cell_id: cellId});
        };
      }
    });
  };

  // ── Toggle fold ──
  window._toggleFold = function(cellId) {
    if (!window._cellStore) return;
    var s = _cellStore.get(cellId);
    if (!s) return;
    s.folded = !s.folded;
    var wrap = document.querySelector('.cell-wrap[data-cell-id="' + cellId + '"]');
    if (!wrap) return;
    var code = wrap.querySelector('.code-cell');
    if (code) code.style.display = s.folded ? 'none' : '';
    if (window.TherapyWS && TherapyWS.sendMessage) {
      TherapyWS.sendMessage('notebook', {action:'toggle_fold', cell_id:cellId, folded:s.folded});
    }
  };

  // ── Cell action menu (move up/down, format, delete) ──
  var _cellMenu = null;
  window._showCellMenu = function(btn, cellId) {
    if (_cellMenu) { _cellMenu.remove(); _cellMenu = null; return; }
    var rect = btn.getBoundingClientRect();
    _cellMenu = document.createElement('div');
    _cellMenu.style.cssText = 'position:fixed;z-index:9999;background:var(--panel-bg);border:1px solid var(--cell-border-hov,var(--cell-border));border-radius:8px;min-width:140px;box-shadow:0 8px 24px rgba(0,0,0,.3);overflow:hidden;padding:4px 0;top:'+(rect.bottom+4)+'px;right:'+(window.innerWidth-rect.right)+'px;';
    var actions = [
      {label:'Move Up', icon:'\\u2191', action:function(){TherapyWS.sendMessage('notebook',{action:'move_cell',cell_id:cellId,direction:'up'})}},
      {label:'Move Down', icon:'\\u2193', action:function(){TherapyWS.sendMessage('notebook',{action:'move_cell',cell_id:cellId,direction:'down'})}},
      {label:'Format', icon:'\\u2728', action:function(){TherapyWS.sendMessage('notebook',{action:'format_cell',cell_id:cellId})}},
      {sep:true},
      {label:'Delete', icon:'\\u2715', danger:true, action:function(){TherapyWS.sendMessage('notebook',{action:'delete_cell',cell_id:cellId})}}
    ];
    actions.forEach(function(a) {
      if (a.sep) { var sep=document.createElement('div');sep.style.cssText='height:1px;background:var(--divider);margin:4px 8px;';_cellMenu.appendChild(sep);return; }
      var item = document.createElement('div');
      item.style.cssText = 'display:flex;align-items:center;gap:8px;padding:6px 12px;font-size:12px;cursor:pointer;color:var(--text-2);font-family:ui-monospace,monospace;transition:background .1s,color .1s;';
      item.innerHTML = '<span style="width:14px;text-align:center;">'+a.icon+'</span>'+a.label;
      item.addEventListener('mouseenter', function(){item.style.background=a.danger?'rgba(220,53,69,.1)':'rgba(128,128,128,.08)';item.style.color=a.danger?'var(--status-error)':'var(--text-1)';});
      item.addEventListener('mouseleave', function(){item.style.background='';item.style.color='var(--text-2)';});
      item.onclick = function(){a.action();_cellMenu.remove();_cellMenu=null;};
      _cellMenu.appendChild(item);
    });
    document.body.appendChild(_cellMenu);
  };
  document.addEventListener('click', function(e) {
    if (_cellMenu && !_cellMenu.contains(e.target) && !e.target.closest('.menu-btn')) {
      _cellMenu.remove(); _cellMenu = null;
    }
  });

  // ── Hover visibility for cell controls ──
  document.addEventListener('mouseover', function(e) {
    var wrap = e.target.closest('.cell-wrap');
    if (wrap) {
      var eye = wrap.querySelector('.cell-eye');
      var ctrls = wrap.querySelector('.cell-ctrls');
      if (eye) eye.style.opacity = '1';
      if (ctrls) { ctrls.style.opacity = '1'; ctrls.style.transform = 'translateY(0)'; ctrls.style.pointerEvents = 'auto'; }
    }
  });
  document.addEventListener('mouseout', function(e) {
    var wrap = e.target.closest('.cell-wrap');
    if (wrap && !wrap.contains(e.relatedTarget)) {
      var eye = wrap.querySelector('.cell-eye');
      var ctrls = wrap.querySelector('.cell-ctrls');
      if (eye) eye.style.opacity = '0';
      if (ctrls) { ctrls.style.opacity = '0'; ctrls.style.transform = 'translateY(-3px)'; ctrls.style.pointerEvents = 'none'; }
    }
  });

  // ── CellGap hover ──
  document.addEventListener('mouseover', function(e) {
    var gap = e.target.closest('.cdiv');
    if (gap) { var inner = gap.querySelector('.cdiv-inner'); if (inner) inner.style.opacity = '1'; }
  });
  document.addEventListener('mouseout', function(e) {
    var gap = e.target.closest('.cdiv');
    if (gap && !gap.contains(e.relatedTarget)) { var inner = gap.querySelector('.cdiv-inner'); if (inner) inner.style.opacity = '0'; }
  });

""" * _notebook_cm_script_body() * """

""" * _notebook_ws_bridge_body() * """

  // ── Keyboard shortcuts ──
  document.addEventListener('keydown', function(e) {
    if ((e.ctrlKey || e.metaKey) && e.key === 's') {
      e.preventDefault();
      window._sessionsSave && window._sessionsSave();
    }
    if ((e.ctrlKey || e.metaKey) && e.key === 'z' && window._recentlyDeleted) {
      var active = document.activeElement;
      var inEditor = active && (active.closest('.cm-editor') || active.tagName === 'INPUT' || active.tagName === 'TEXTAREA');
      if (!inEditor) {
        e.preventDefault();
        var del = window._recentlyDeleted;
        window._recentlyDeleted = null;
        var toast = document.getElementById('undo-toast');
        if (toast) toast.classList.remove('show');
        if (window._undoToastTimer) clearTimeout(window._undoToastTimer);
        if (window.TherapyWS && TherapyWS.sendMessage) {
          TherapyWS.sendMessage('notebook', {action: 'add_cell', after_cell_id: del.prev_cell_id, code: del.code});
        }
      }
    }
  });
})();
"""
end

# ═══════════════════════════════════════════════════════════════
# CM Init Script Body (no wrapper — inlined into _notebook_island_js)
# ═══════════════════════════════════════════════════════════════

function _notebook_cm_script_body()
"""
  // ── CM Init ──
  if (typeof C !== 'undefined' && C.EditorView) {
    if (!window._sessionsEditors) window._sessionsEditors = {};
    var editors = window._sessionsEditors;

    var hlTheme = C.HighlightStyle.define([
      {tag:C.t.keyword,color:"#e06b65"},{tag:C.t.controlKeyword,color:"#e06b65"},
      {tag:C.t.operatorKeyword,color:"#e06b65"},{tag:C.t.definitionKeyword,color:"#e06b65"},
      {tag:C.t.moduleKeyword,color:"#e06b65"},
      {tag:C.t.string,color:"#56d4a0"},{tag:C.t.character,color:"#56d4a0"},
      {tag:C.t.comment,color:"#4a6178",fontStyle:"italic"},
      {tag:C.t.lineComment,color:"#4a6178",fontStyle:"italic"},
      {tag:C.t.number,color:"#d4a056"},{tag:C.t.integer,color:"#d4a056"},
      {tag:C.t.float,color:"#d4a056"},{tag:C.t.bool,color:"#d4a056"},
      {tag:C.t.function(C.t.variableName),color:"#7bb8e8"},
      {tag:C.t.definition(C.t.variableName),color:"#7bb8e8"},
      {tag:C.t.typeName,color:"#b08fd8"},{tag:C.t.className,color:"#b08fd8"},
      {tag:C.t.variableName,color:"var(--text-1)"},
      {tag:C.t.punctuation,color:"var(--text-3)"},{tag:C.t.paren,color:"var(--text-3)"},
      {tag:C.t.squareBracket,color:"var(--text-3)"},{tag:C.t.brace,color:"var(--text-3)"},
      {tag:C.t.operator,color:"var(--text-1)"},{tag:C.t.special(C.t.string),color:"#7bb8e8"},
      {tag:C.t.macroName,color:"#d4a056"},
    ]);

    var isDark = document.documentElement.classList.contains('dark');
    var accentColor = getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() || '#d4759a';
    var edTheme = C.EditorView.theme({
      "&":{backgroundColor:"transparent",color:"var(--text-1)"},
      ".cm-gutters":{backgroundColor:"transparent",color:"var(--text-3)",border:"none",minWidth:"38px"},
      ".cm-activeLine":{backgroundColor:"transparent"},
      "&.cm-focused .cm-activeLine":{backgroundColor:"rgba(128,128,128,.04)"},
      ".cm-activeLineGutter":{backgroundColor:"transparent",color:"var(--text-3)"},
      "&.cm-focused .cm-activeLineGutter":{backgroundColor:"transparent",color:"var(--text-2)"},
      "&.cm-focused .cm-cursor":{borderLeftColor:accentColor},
      "&.cm-focused .cm-selectionBackground, .cm-selectionBackground":{backgroundColor:"var(--selection-bg) !important"},
      ".cm-content":{caretColor:accentColor,fontFamily:"'JetBrains Mono',monospace",fontSize:"13px",lineHeight:"1.65",padding:"8px 0"},
      ".cm-scroller":{fontFamily:"'JetBrains Mono',monospace"},
      ".cm-matchingBracket":{color:accentColor+" !important",backgroundColor:"rgba(212,117,154,.1)",outline:"1px solid rgba(212,117,154,.2)"},
      ".cm-line":{paddingLeft:"4px"},
    },{dark:isDark});

    window._sessionsRunCell = function(cellId) {
      var code = '';
      var ev = editors[cellId];
      if (ev) code = ev.state.doc.toString();
      if (!code) { var host = document.querySelector('.cm-cell[data-cell-id="'+cellId+'"]'); if (host) code = host.dataset.src || ''; }
      if (window.TherapyWS && TherapyWS.sendMessage) { TherapyWS.sendMessage('notebook', {action:'execute', cell_id:cellId, code:code}); }
    };

    function _collectCodes() { var codes = {}; for (var cid in editors) { codes[cid] = editors[cid].state.doc.toString(); } return codes; }
    window._sessionsRunAll = function() { var codes = _collectCodes(); for (var cid in codes) { if (TherapyWS&&TherapyWS.sendMessage) TherapyWS.sendMessage('notebook',{action:'update_code',cell_id:cid,code:codes[cid]}); } if (TherapyWS&&TherapyWS.sendMessage) TherapyWS.sendMessage('notebook',{action:'run_all'}); };
    window._sessionsRunStale = function() { if (TherapyWS&&TherapyWS.sendMessage) TherapyWS.sendMessage('notebook',{action:'run_stale',codes:_collectCodes()}); };
    window._sessionsSave = function() { if (!TherapyWS||!TherapyWS.sendMessage) return; var fe=window._fileEditorView; if(fe){TherapyWS.sendMessage('notebook',{action:'save',content:fe.state.doc.toString()});return;} TherapyWS.sendMessage('notebook',{action:'save',codes:_collectCodes()}); };

    var _syncTimers = {};
    if (!window._sessSuppressSync) window._sessSuppressSync = {};
    function syncCodeToServer(cellId) { if(window._sessSuppressSync[cellId]){delete window._sessSuppressSync[cellId];return;} if(window._sessionsMarkUnsaved)window._sessionsMarkUnsaved(); if(_syncTimers[cellId])clearTimeout(_syncTimers[cellId]); _syncTimers[cellId]=setTimeout(function(){var ev=editors[cellId];if(!ev)return;var code=ev.state.doc.toString();if(TherapyWS&&TherapyWS.sendMessage)TherapyWS.sendMessage('notebook',{action:'update_code',cell_id:cellId,code:code});},400); }
    function editSyncExtension(cellId) { return C.EditorView.updateListener.of(function(update){if(update.docChanged)syncCodeToServer(cellId);}); }
    function shiftEnterKeymap(cellId) { return C.EditorView.domEventHandlers({keydown:function(event){if(event.key==='Enter'&&event.shiftKey&&!event.ctrlKey&&!event.metaKey){event.preventDefault();window._sessionsRunCell(cellId);return true;}}}); }

    window._initAllCM = function() {
      document.querySelectorAll('.cm-cell').forEach(function(host) {
        if (host.querySelector('.cm-editor')) return;
        var src = host.dataset.src || '';
        var cellId = host.dataset.cellId || '';
        var isFileEditor = host.classList.contains('cm-file-editor');
        var cellKeymaps = (!isFileEditor && cellId) ? [shiftEnterKeymap(cellId)] : [];
        var exts = [...cellKeymaps, C.lineNumbers(),C.highlightActiveLineGutter(),C.highlightSpecialChars(),C.history(),C.drawSelection(),C.EditorState.allowMultipleSelections.of(true),C.indentOnInput(),C.bracketMatching(),C.closeBrackets(),C.rectangularSelection(),C.highlightActiveLine(),C.highlightSelectionMatches(),C.keymap.of([...C.closeBracketsKeymap,...C.defaultKeymap,...C.searchKeymap,...C.historyKeymap,...C.completionKeymap,C.indentWithTab]),C.julia(),C.syntaxHighlighting(hlTheme),edTheme];
        if (isFileEditor) { exts.push(C.EditorView.theme({'&':{height:'100%'},'.cm-scroller':{overflow:'auto'}})); }
        else if (cellId) { exts.push(editSyncExtension(cellId)); }
        var view = new C.EditorView({doc:src,extensions:exts,parent:host});
        if (isFileEditor) { window._fileEditorView = view; } else if (cellId) { editors[cellId] = view; }
      });
    };
    window._sessionsInitNewCells = window._initAllCM;
  }
"""
end

# ═══════════════════════════════════════════════════════════════
# WS Bridge Body (no wrapper — inlined into _notebook_island_js)
# ═══════════════════════════════════════════════════════════════

function _notebook_ws_bridge_body()
"""
  // ── WS Bridge ──
  window._setupWSBridge = function(setCellOrder, setExecuting, setStaleCount) {
    window._sessionsUnsaved = false;
    function markUnsaved() { if(window._sessionsUnsaved)return; window._sessionsUnsaved=true; var btn=document.getElementById('save-indicator'); if(btn){btn.textContent='\\u25CF Save';btn.style.color='var(--status-running)';} }
    function markSaved() { window._sessionsUnsaved=false; var btn=document.getElementById('save-indicator'); if(btn){btn.textContent='Saved';btn.style.color='';setTimeout(function(){if(!window._sessionsUnsaved)btn.textContent='Save';},2000);} }
    window._sessionsMarkUnsaved = markUnsaved;

    function cellEls(cellId) { var wrap=document.querySelector('.cell-wrap[data-cell-id="'+cellId+'"]'); if(!wrap)return null; return {wrap:wrap,code:wrap.querySelector('.code-cell'),out:wrap.querySelector('.cell-out'),ctrls:wrap.querySelector('.cell-ctrls')}; }
    function fmtRuntime(ns) { var ms=ns/1e6; return ms<1?(ns/1e3).toFixed(1)+'\\u00b5s':ms<1000?ms.toFixed(1)+'ms':(ms/1000).toFixed(2)+'s'; }
    function fmtSeconds(s) { return s<1?s.toFixed(2)+'s':s<60?s.toFixed(1)+'s':(s/60).toFixed(1)+'min'; }

    var _cellTimers = {};
    function startCellTimer(cellId, el) { stopCellTimer(cellId); if(!el||!el.ctrls)return; var startTime=performance.now(); var badge=el.ctrls.querySelector('.rt-badge'); if(!badge){badge=document.createElement('span');badge.className='rt-badge';el.ctrls.insertBefore(badge,el.ctrls.firstChild);} badge.style.cssText='font-size:10px;font-family:ui-monospace,monospace;padding:1px 7px;border-radius:9999px;color:#7bb8e8;opacity:.9;background:rgba(123,184,232,.08);border:1px solid rgba(123,184,232,.15);'; badge.textContent='0.0s'; var interval=setInterval(function(){var elapsed=(performance.now()-startTime)/1000;badge.textContent=fmtSeconds(elapsed);},100); _cellTimers[cellId]={interval:interval,startTime:startTime}; }
    function stopCellTimer(cellId) { var timer=_cellTimers[cellId]; if(timer){clearInterval(timer.interval);delete _cellTimers[cellId];} }
    function setCellState(el,state,cellId) { if(!el)return; var cc=el.code; if(!cc)return; cc.classList.remove('idle','stale','executing'); if(state==='cell_queued'||state==='cell_running'){cc.style.borderColor=state==='cell_queued'?'var(--status-running)':'#7bb8e8';cc.classList.add('executing');if(state==='cell_running'&&cellId)startCellTimer(cellId,el);}else{if(cellId)stopCellTimer(cellId);if(state==='cell_errored'){cc.style.borderColor='var(--status-error)';}else{cc.style.borderColor='';}} }

    window.addEventListener('therapy:channel:notebook', function(e) {
      var data = e.detail;
      if (!data || !data.event) return;

      if (data.event === 'cell_state') {
        var el = cellEls(data.cell_id);
        setCellState(el, data.state, data.cell_id);
        if (window._cellStore) { var s = _cellStore.get(data.cell_id); if (s) s.state = data.state; }
      }

      else if (data.event === 'cell_output') {
        var el = cellEls(data.cell_id);
        if (!el) return;
        if (el.out) {
          var html = data.output_html || '';
          if (html) { el.out.innerHTML=html; el.out.style.display=''; el.out.style.padding='6px 0 10px';
            el.out.querySelectorAll('script').forEach(function(old){var s=document.createElement('script');s.textContent=old.textContent;old.parentNode.replaceChild(s,old);});
            if(window.__hydrateTherapyIslands)window.__hydrateTherapyIslands(el.out);
          } else { el.out.innerHTML=''; el.out.style.display='none'; }
        }
        setCellState(el, data.state, data.cell_id);
        if (el.ctrls && data.runtime_ns && data.runtime_ns > 0) {
          var old = el.ctrls.querySelector('.rt-badge'); if(old)old.remove();
          var badge=document.createElement('span'); badge.className='rt-badge';
          var isErr=data.state==='cell_errored'; var c=isErr?'var(--status-error)':'var(--status-done)';
          badge.style.cssText='font-size:10px;font-family:ui-monospace,monospace;padding:1px 7px;border-radius:9999px;opacity:.8;color:'+c+';';
          badge.textContent=fmtRuntime(data.runtime_ns); el.ctrls.insertBefore(badge,el.ctrls.firstChild);
        }
        if (window._cellStore) { var s=_cellStore.get(data.cell_id); if(s){s.state=data.state;s.output_html=data.output_html||'';s.runtime_ns=data.runtime_ns||0;} }
      }

      else if (data.event === 'cell_added') {
        markUnsaved();
        if (window._cellStore) {
          _cellStore.set(data.cell_id, {state:'cell_idle',output_html:'',runtime_ns:0,code:data.code||'',folded:false,stale:false,stdout:''});
        }
        // Update cell_order signal — insert after the target cell
        var currentOrder = setCellOrder._getter ? setCellOrder._getter() : [];
        if (typeof currentOrder === 'function') currentOrder = currentOrder();
        var newOrder = currentOrder.slice ? currentOrder.slice() : Array.from(currentOrder);
        var afterIdx = data.after_cell_id ? newOrder.indexOf(data.after_cell_id) : -1;
        newOrder.splice(afterIdx + 1, 0, data.cell_id);
        setCellOrder(newOrder);
        // Populate + init CM after For re-renders
        setTimeout(function(){ _populateCells(); _initAllCM(); }, 100);
      }

      else if (data.event === 'cell_deleted') {
        markUnsaved();
        window._recentlyDeleted = {cell_id:data.cell_id,code:data.code||'',prev_cell_id:data.prev_cell_id||''};
        var toast=document.getElementById('undo-toast'); if(toast){toast.classList.add('show');if(window._undoToastTimer)clearTimeout(window._undoToastTimer);window._undoToastTimer=setTimeout(function(){toast.classList.remove('show');window._recentlyDeleted=null;},8000);}
        if(window._sessionsEditors)delete window._sessionsEditors[data.cell_id];
        if(window._cellStore)_cellStore.delete(data.cell_id);
        // Update cell_order signal — remove the deleted cell
        var currentOrder = setCellOrder._getter ? setCellOrder._getter() : [];
        if (typeof currentOrder === 'function') currentOrder = currentOrder();
        var newOrder = (currentOrder.slice ? currentOrder.slice() : Array.from(currentOrder)).filter(function(id){return id!==data.cell_id;});
        setCellOrder(newOrder);
      }

      else if (data.event === 'cell_moved') {
        markUnsaved();
        // Update cell_order signal with new order
        if (data.cell_order) { setCellOrder(data.cell_order); }
      }

      else if (data.event === 'cell_formatted' || data.event === 'cell_code_updated') {
        if (data.event === 'cell_formatted') markUnsaved();
        var eds=window._sessionsEditors||{}; var ev=eds[data.cell_id];
        if(ev&&data.code!==undefined){var cur=ev.state.doc.toString();if(data.code!==cur){window._sessSuppressSync[data.cell_id]=true;ev.dispatch({changes:{from:0,to:cur.length,insert:data.code}});}}
      }

      else if (data.event === 'stale_update') {
        setStaleCount(data.count || 0);
        var btn=document.getElementById('run-stale-btn');var label=document.getElementById('run-stale-label');
        if(btn){if(data.count>0&&!window._sessionsExecuting){btn.style.display='';if(label)label.textContent=' Run Stale ('+data.count+')';}else{btn.style.display='none';}}
        var staleSet=new Set(data.stale_ids||[]);
        document.querySelectorAll('.code-cell').forEach(function(el){var wrap=el.closest('.cell-wrap');var cid=wrap?wrap.dataset.cellId:null;if(cid&&staleSet.has(cid)){el.classList.add('stale');}else{el.classList.remove('stale');}});
      }

      else if (data.event === 'run_progress') {
        var isRunning=data.running_index>0&&data.total>0;
        window._sessionsExecuting=isRunning;
        setExecuting(isRunning ? 1 : 0);
        var el=document.getElementById('run-progress');if(el){if(isRunning){el.textContent='Running '+data.running_index+'/'+data.total+'...';el.style.display='';}else{el.textContent='';el.style.display='none';}}
        var runAllBtn=document.getElementById('run-all-btn');var stopBtn=document.getElementById('stop-btn');var runStaleBtn=document.getElementById('run-stale-btn');
        if(runAllBtn&&stopBtn){if(isRunning){runAllBtn.style.display='none';stopBtn.style.display='';if(runStaleBtn)runStaleBtn.style.display='none';}else{runAllBtn.style.display='';stopBtn.style.display='none';}}
      }

      else if (data.event === 'format_started') { document.querySelectorAll('[data-format-btn]').forEach(function(btn){btn.dataset.origText=btn.textContent;btn.textContent='Formatting...';btn.style.opacity='0.6';btn.style.pointerEvents='none';}); }
      else if (data.event === 'format_done') { document.querySelectorAll('[data-format-btn]').forEach(function(btn){btn.textContent=btn.dataset.origText||'Format';btn.style.opacity='';btn.style.pointerEvents='';}); }
      else if (data.event === 'saved') { markSaved(); }
      else if (data.event === 'interrupted') {
        window._sessionsExecuting=false; setExecuting(0);
        var el=document.getElementById('run-progress');if(el){el.textContent='Interrupted';el.style.display='';el.style.color='var(--status-error)';setTimeout(function(){el.textContent='';el.style.display='';el.style.color='';},2000);}
        var runAllBtn=document.getElementById('run-all-btn');var stopBtn=document.getElementById('stop-btn');if(runAllBtn&&stopBtn){runAllBtn.style.display='';stopBtn.style.display='none';}
      }
      else if (data.event === 'full_state') {
        console.log('[Sessions] Full state:', data.cells ? data.cells.length : 0, 'cells');
        if (data.cells && window._cellStore) {
          data.cells.forEach(function(cell) {
            _cellStore.set(cell.cell_id, {state:cell.state,output_html:cell.output_html||'',runtime_ns:cell.runtime_ns||0,code:cell.code||'',folded:cell.folded||false,stale:cell.stale||false,stdout:cell.stdout||''});
          });
          _populateCells();
          if(window.__hydrateTherapyIslands){var nb=document.getElementById('nb');if(nb)window.__hydrateTherapyIslands(nb);}
        }
      }
      else if (data.event === 'nb_replaced') {
        window._fileEditorView = null;
        if (data.nb_html) {
          var nbIsland=document.getElementById('nb-island');
          if(nbIsland){nbIsland.outerHTML=data.nb_html;window._sessionsInitNewCells&&window._sessionsInitNewCells();if(window.__hydrateTherapyIslands){var newNb=document.getElementById('nb-island');if(newNb)window.__hydrateTherapyIslands(newNb);}}
        } else { setTimeout(function(){window.location.reload();},200); }
      }
    });
  };
"""
end

# Keep the old functions for backward compatibility during transition
function _notebook_cm_script()
    _notebook_cm_script_body()
end

function _notebook_channel_script()
    RawHtml(string("<script>(function(){", _notebook_ws_bridge_body(), "if(window.TherapyWS)_setupWSBridge(function(){},function(){},function(){});})();</script>"))
end
