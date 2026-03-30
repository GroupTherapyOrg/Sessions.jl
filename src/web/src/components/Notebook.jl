# Notebook.jl — Notebook cell rendering + client-side behavior
#
# Phase A (current): SSR rendering via render_cell() + client-side JS
# Phase B (future): @island with For(cell_order), signals, optimistic updates
#
# All notebook-specific JS lives here (extracted from Layout.jl):
# - CM initialization + syntax highlighting
# - Cell execution (Shift+Enter, Run All, Run Stale, Save)
# - Debounced code sync to server
# - Fold observer (eye toggle → server persistence)
# - WS channel handler (cell_state, cell_output, add/delete/move, stale, progress)
# - Cell action menu + keyboard shortcuts (Ctrl+S, Ctrl+Z)

"""
    NotebookContent(state) -> VNode

Render the notebook content area: cell list with gaps + all client-side JS.
"""
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
        # CM initialization + cell execution + fold observer
        RawHtml(string("<script>", _notebook_cm_script(), "</script>")),
        # WS channel handler + cell menu + keyboard shortcuts
        # _notebook_channel_script() returns RawHtml with <script> tags included
        _notebook_channel_script()
    )
end

# ═══════════════════════════════════════════════════════════════
# CM Initialization + Cell Execution
# ═══════════════════════════════════════════════════════════════

function _notebook_cm_script()
"""
(function() {
  if (typeof C === 'undefined' || !C.EditorView) return;

  if (!window._sessionsEditors) window._sessionsEditors = {};
  var editors = window._sessionsEditors;

  // ── Syntax highlight theme ──
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

  // ── Editor theme (uses CSS vars for light/dark adaptability) ──
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

  // ── Run cell ──
  window._sessionsRunCell = function(cellId) {
    var code = '';
    var ev = editors[cellId];
    if (ev) code = ev.state.doc.toString();
    if (!code) {
      var host = document.querySelector('.cm-cell[data-cell-id="' + cellId + '"]');
      if (host) code = host.dataset.src || '';
    }
    if (window.TherapyWS && TherapyWS.sendMessage) {
      TherapyWS.sendMessage('notebook', {action: 'execute', cell_id: cellId, code: code});
    }
  };

  // ── Collect all codes ──
  function _collectCodes() {
    var codes = {};
    for (var cid in editors) {
      codes[cid] = editors[cid].state.doc.toString();
    }
    return codes;
  }

  // ── Run All ──
  window._sessionsRunAll = function() {
    var codes = _collectCodes();
    for (var cid in codes) {
      if (window.TherapyWS && TherapyWS.sendMessage) {
        TherapyWS.sendMessage('notebook', {action: 'update_code', cell_id: cid, code: codes[cid]});
      }
    }
    if (window.TherapyWS && TherapyWS.sendMessage) {
      TherapyWS.sendMessage('notebook', {action: 'run_all'});
    }
  };

  // ── Run Stale ──
  window._sessionsRunStale = function() {
    if (window.TherapyWS && TherapyWS.sendMessage) {
      TherapyWS.sendMessage('notebook', {action: 'run_stale', codes: _collectCodes()});
    }
  };

  // ── Save ──
  window._sessionsSave = function() {
    if (!window.TherapyWS || !TherapyWS.sendMessage) return;
    var fileEditor = window._fileEditorView;
    if (fileEditor) {
      TherapyWS.sendMessage('notebook', {action: 'save', content: fileEditor.state.doc.toString()});
      return;
    }
    TherapyWS.sendMessage('notebook', {action: 'save', codes: _collectCodes()});
  };

  // ── Debounced code sync ──
  var _syncTimers = {};
  if (!window._sessSuppressSync) window._sessSuppressSync = {};
  function syncCodeToServer(cellId) {
    if (window._sessSuppressSync[cellId]) { delete window._sessSuppressSync[cellId]; return; }
    if (window._sessionsMarkUnsaved) window._sessionsMarkUnsaved();
    if (_syncTimers[cellId]) clearTimeout(_syncTimers[cellId]);
    _syncTimers[cellId] = setTimeout(function() {
      var ev = editors[cellId];
      if (!ev) return;
      var code = ev.state.doc.toString();
      if (window.TherapyWS && TherapyWS.sendMessage) {
        TherapyWS.sendMessage('notebook', {action: 'update_code', cell_id: cellId, code: code});
      }
    }, 400);
  }

  function editSyncExtension(cellId) {
    return C.EditorView.updateListener.of(function(update) {
      if (update.docChanged) syncCodeToServer(cellId);
    });
  }

  // ── Shift+Enter ──
  function shiftEnterKeymap(cellId) {
    return C.EditorView.domEventHandlers({
      keydown: function(event) {
        if (event.key === 'Enter' && event.shiftKey && !event.ctrlKey && !event.metaKey) {
          event.preventDefault();
          window._sessionsRunCell(cellId);
          return true;
        }
      }
    });
  }

  // ── Initialize CM editors ──
  function initCMEditors() {
    document.querySelectorAll('.cm-cell').forEach(function(host) {
      if (host.querySelector('.cm-editor')) return;
      var src = host.dataset.src || '';
      var cellId = host.dataset.cellId || '';
      var isFileEditor = host.classList.contains('cm-file-editor');

      var cellKeymaps = (!isFileEditor && cellId) ? [shiftEnterKeymap(cellId)] : [];
      var exts = [
        ...cellKeymaps,
        C.lineNumbers(), C.highlightActiveLineGutter(), C.highlightSpecialChars(),
        C.history(), C.drawSelection(),
        C.EditorState.allowMultipleSelections.of(true),
        C.indentOnInput(), C.bracketMatching(), C.closeBrackets(),
        C.rectangularSelection(), C.highlightActiveLine(), C.highlightSelectionMatches(),
        C.keymap.of([
          ...C.closeBracketsKeymap, ...C.defaultKeymap, ...C.searchKeymap,
          ...C.historyKeymap, ...C.completionKeymap, C.indentWithTab,
        ]),
        C.julia(),
        C.syntaxHighlighting(hlTheme),
        edTheme,
      ];

      if (isFileEditor) {
        exts.push(C.EditorView.theme({
          '&': { height: '100%' },
          '.cm-scroller': { overflow: 'auto' }
        }));
      } else if (cellId) {
        exts.push(editSyncExtension(cellId));
      }

      var view = new C.EditorView({ doc: src, extensions: exts, parent: host });

      if (isFileEditor) {
        window._fileEditorView = view;
      } else if (cellId) {
        editors[cellId] = view;
      }
    });
  }
  initCMEditors();
  window._sessionsInitNewCells = initCMEditors;

  // ── Fold observer ──
  document.querySelectorAll('.cell-island').forEach(function(island) {
    var cellWrap = island.closest('.cell-wrap');
    var cellId = cellWrap ? cellWrap.dataset.cellId : '';
    if (!cellId) return;
    var lastFolded = null;
    var observer = new MutationObserver(function() {
      var codeCell = island.querySelector('.code-cell');
      var folded = !codeCell || codeCell.offsetParent === null;
      if (folded !== lastFolded) {
        lastFolded = folded;
        if (window.TherapyWS && TherapyWS.sendMessage) {
          TherapyWS.sendMessage('notebook', {action: 'toggle_fold', cell_id: cellId, folded: folded});
        }
      }
    });
    observer.observe(island, {childList: true, subtree: true, attributes: true, attributeFilter: ['style']});
  });
})();
"""
end

# ═══════════════════════════════════════════════════════════════
# WS Channel Handler + Cell Menu + Keyboard Shortcuts
# (moved from Layout.jl _notebook_channel_script)
# ═══════════════════════════════════════════════════════════════

"""Client-side JavaScript for handling notebook WebSocket channel messages."""
function _notebook_channel_script()
    RawHtml("""<script>
(function() {
  if (window._sessionsNotebookHandler) return;
  window._sessionsNotebookHandler = true;

  // ── Unsaved changes indicator ──
  window._sessionsUnsaved = false;
  function markUnsaved() {
    if (window._sessionsUnsaved) return;
    window._sessionsUnsaved = true;
    var btn = document.getElementById('save-indicator');
    if (btn) {
      btn.textContent = '\u25CF Save';
      btn.style.color = '#d4a056';
      btn.style.borderColor = '#d4a056';
    }
  }
  function markSaved() {
    window._sessionsUnsaved = false;
    var btn = document.getElementById('save-indicator');
    if (btn) {
      btn.textContent = 'Saved';
      btn.style.color = '';
      btn.style.borderColor = '';
      setTimeout(function(){ if (!window._sessionsUnsaved) btn.textContent = 'Save'; }, 2000);
    }
  }
  window._sessionsMarkUnsaved = markUnsaved;

  // ── Helper: find cell elements by ID ──
  function cellEls(cellId) {
    var wrap = document.querySelector('.cell-wrap[data-cell-id="' + cellId + '"]');
    if (!wrap) return null;
    return {
      wrap: wrap,
      code: wrap.querySelector('.code-cell'),
      out: wrap.querySelector('.cell-out'),
      ctrls: wrap.querySelector('.cell-ctrls')
    };
  }

  // ── Helper: format runtime ──
  function fmtRuntime(ns) {
    var ms = ns / 1e6;
    return ms < 1 ? (ns / 1e3).toFixed(1) + '\u00b5s' : ms < 1000 ? ms.toFixed(1) + 'ms' : (ms / 1000).toFixed(2) + 's';
  }
  function fmtSeconds(s) {
    return s < 1 ? s.toFixed(2) + 's' : s < 60 ? s.toFixed(1) + 's' : (s / 60).toFixed(1) + 'min';
  }

  // ── Live stopwatch for running cells ──
  var _cellTimers = {};  // cellId → {interval, startTime}

  function startCellTimer(cellId, el) {
    stopCellTimer(cellId);
    if (!el || !el.ctrls) return;
    var startTime = performance.now();
    // Create or reuse the badge
    var badge = el.ctrls.querySelector('.rt-badge');
    if (!badge) {
      badge = document.createElement('span');
      badge.className = 'rt-badge';
      el.ctrls.insertBefore(badge, el.ctrls.firstChild);
    }
    badge.style.cssText = 'font-size:10px;font-family:ui-monospace,monospace;padding:1px 7px;border-radius:9999px;color:#7bb8e8;opacity:.9;background:rgba(123,184,232,.08);border:1px solid rgba(123,184,232,.15);';
    badge.textContent = '0.0s';
    var interval = setInterval(function() {
      var elapsed = (performance.now() - startTime) / 1000;
      badge.textContent = fmtSeconds(elapsed);
    }, 100);
    _cellTimers[cellId] = {interval: interval, startTime: startTime};
  }

  function stopCellTimer(cellId) {
    var timer = _cellTimers[cellId];
    if (timer) {
      clearInterval(timer.interval);
      delete _cellTimers[cellId];
    }
  }

  // ── Helper: update cell CSS state (accent bar color) ──
  function setCellState(el, state, cellId) {
    if (!el) return;
    var cc = el.code;
    if (!cc) return;
    cc.classList.remove('idle', 'stale', 'executing');
    // Queued/running: colored border + hide the green/orange side accent bar
    if (state === 'cell_queued' || state === 'cell_running') {
      cc.style.borderColor = state === 'cell_queued' ? '#d4a056' : '#7bb8e8';
      cc.classList.add('executing');
      // Start live stopwatch when cell begins running
      if (state === 'cell_running' && cellId) {
        startCellTimer(cellId, el);
      }
    } else {
      if (cellId) stopCellTimer(cellId);
      if (state === 'cell_errored') {
        cc.style.borderColor = '#e06b65';
      } else {
        cc.style.borderColor = '';  // revert to CSS default
      }
    }
  }

  window.addEventListener('therapy:channel:notebook', function(e) {
    var data = e.detail;
    if (!data || !data.event) return;

    if (data.event === 'cell_state') {
      var el = cellEls(data.cell_id);
      setCellState(el, data.state, data.cell_id);
    }

    else if (data.event === 'format_started') {
      // Show spinner on all Format buttons
      document.querySelectorAll('[data-format-btn]').forEach(function(btn) {
        btn.dataset.origText = btn.textContent;
        btn.textContent = 'Formatting...';
        btn.style.opacity = '0.6';
        btn.style.pointerEvents = 'none';
      });
    }

    else if (data.event === 'format_done') {
      // Restore Format buttons
      document.querySelectorAll('[data-format-btn]').forEach(function(btn) {
        btn.textContent = btn.dataset.origText || 'Format';
        btn.style.opacity = '';
        btn.style.pointerEvents = '';
      });
    }

    else if (data.event === 'cell_formatted') {
      markUnsaved();
      // Update CodeMirror editor with formatted code
      var eds = window._sessionsEditors || {};
      var ev = eds[data.cell_id];
      if (ev && data.code !== undefined) {
        var currentCode = ev.state.doc.toString();
        if (data.code !== currentCode) {
          window._sessSuppressSync[data.cell_id] = true;  // don't echo back to server
          ev.dispatch({
            changes: {from: 0, to: currentCode.length, insert: data.code}
          });
        }
      }
    }

    else if (data.event === 'cell_code_updated') {
      // External edit (agent, git, IDE) changed cell code on the server.
      // Push the new code into the CM editor so Run Stale sends the right content.
      var eds = window._sessionsEditors || {};
      var ev = eds[data.cell_id];
      if (ev && data.code !== undefined) {
        var currentCode = ev.state.doc.toString();
        if (data.code !== currentCode) {
          window._sessSuppressSync[data.cell_id] = true;  // don't echo back to server
          ev.dispatch({
            changes: {from: 0, to: currentCode.length, insert: data.code}
          });
        }
      }
    }

    else if (data.event === 'cell_output') {
      var el = cellEls(data.cell_id);
      if (!el) return;

      // Update output HTML
      if (el.out) {
        var html = data.output_html || '';
        if (html) {
          el.out.innerHTML = html;
          el.out.style.display = '';
          el.out.style.padding = '6px 0 10px';

          // innerHTML doesn't execute <script> tags — re-create them so they run.
          // This is needed for the WebSlider JS bridge (set_bond on input).
          el.out.querySelectorAll('script').forEach(function(oldScript) {
            var newScript = document.createElement('script');
            newScript.textContent = oldScript.textContent;
            oldScript.parentNode.replaceChild(newScript, oldScript);
          });

          // Re-hydrate any @island components in the new output
          // (WebSlider WASM signal needs to be initialized)
          if (window.__hydrateTherapyIslands) {
            window.__hydrateTherapyIslands(el.out);
          }
        } else {
          el.out.innerHTML = '';
          el.out.style.display = 'none';
        }
      }

      // Update cell state (done/errored) — stops live timer
      setCellState(el, data.state, data.cell_id);

      // Update runtime badge with final server-measured time
      if (el.ctrls && data.runtime_ns && data.runtime_ns > 0) {
        var old = el.ctrls.querySelector('.rt-badge');
        if (old) old.remove();
        var badge = document.createElement('span');
        badge.className = 'rt-badge';
        var isErr = data.state === 'cell_errored';
        var c = isErr ? '#e06b65' : '#56d4a0';
        badge.style.cssText = 'font-size:10px;font-family:ui-monospace,monospace;padding:1px 7px;border-radius:9999px;opacity:.8;color:'+c+';background:rgba('+(isErr?'224,107,101':'86,212,160')+',.08);border:1px solid rgba('+(isErr?'224,107,101':'86,212,160')+',.12);';
        badge.textContent = fmtRuntime(data.runtime_ns);
        el.ctrls.insertBefore(badge, el.ctrls.firstChild);
      }
    }

    else if (data.event === 'cell_added') {
      markUnsaved();
      // Server renders the cell HTML — just insert it and init CM
      var html = data.cell_html || '';
      if (!html) return;

      var nb = document.getElementById('nb');
      if (!nb) return;
      var container = nb.firstElementChild; // max-width wrapper

      // Create a temp container to parse the HTML
      var tmp = document.createElement('div');
      tmp.innerHTML = html;

      // Find insertion point
      var afterId = data.after_cell_id;
      if (afterId) {
        var afterWrap = container.querySelector('.cell-wrap[data-cell-id="' + afterId + '"]');
        if (afterWrap) {
          // Insert after the divider that follows the target cell
          var ref = afterWrap.nextElementSibling;
          if (ref && ref.classList.contains('cdiv')) ref = ref.nextElementSibling;
          while (tmp.firstChild) {
            if (ref) container.insertBefore(tmp.firstChild, ref);
            else container.appendChild(tmp.firstChild);
          }
        } else {
          while (tmp.firstChild) container.appendChild(tmp.firstChild);
        }
      } else {
        // Insert at beginning
        var first = container.firstElementChild;
        if (first) first = first.nextElementSibling; // skip initial divider
        while (tmp.firstChild) {
          if (first) container.insertBefore(tmp.firstChild, first);
          else container.appendChild(tmp.firstChild);
        }
      }

      // Initialize CM editors + hydrate WASM islands in the new HTML
      window._sessionsInitNewCells && window._sessionsInitNewCells();
      if (window.__hydrateTherapyIslands) {
        var container = document.querySelector('#nb > div');
        if (container) window.__hydrateTherapyIslands(container);
      }
    }

    else if (data.event === 'cell_deleted') {
      markUnsaved();
      // Save deleted cell info for undo
      window._recentlyDeleted = {
        cell_id: data.cell_id,
        code: data.code || '',
        prev_cell_id: data.prev_cell_id || ''
      };
      // Show undo toast
      var toast = document.getElementById('undo-toast');
      if (toast) {
        toast.classList.add('show');
        if (window._undoToastTimer) clearTimeout(window._undoToastTimer);
        window._undoToastTimer = setTimeout(function() {
          toast.classList.remove('show');
          window._recentlyDeleted = null;
        }, 8000);
      }
      // Remove cell from DOM in-place (no page reload)
      var wrap = document.querySelector('.cell-wrap[data-cell-id="' + data.cell_id + '"]');
      if (wrap) {
        // Also remove the divider after this cell
        var next = wrap.nextElementSibling;
        if (next && next.classList.contains('cdiv')) next.remove();
        wrap.remove();
      }
      // Clean up editor reference
      delete editors[data.cell_id];
    }

    else if (data.event === 'cell_moved') {
      markUnsaved();
      // Swap cell DOM nodes in-place (no reload)
      var container = document.querySelector('#nb > div'); // max-width wrapper
      if (!container) return;
      var cellWrap = container.querySelector('.cell-wrap[data-cell-id="' + data.cell_id + '"]');
      if (!cellWrap) return;

      // Each cell has: cell-wrap + following cdiv (divider)
      var divider = cellWrap.nextElementSibling;
      if (data.direction === 'up') {
        // Find the previous cell-wrap (skip its divider)
        var prevDiv = cellWrap.previousElementSibling; // divider before this cell
        if (!prevDiv) return;
        var prevCell = prevDiv.previousElementSibling; // cell-wrap above
        if (!prevCell || !prevCell.classList.contains('cell-wrap')) return;
        // Move this cell+divider before the previous cell
        container.insertBefore(cellWrap, prevCell);
        if (divider && divider.classList.contains('cdiv')) container.insertBefore(divider, prevCell);
      } else if (data.direction === 'down') {
        // Find the next cell-wrap (after our divider)
        if (!divider || !divider.classList.contains('cdiv')) return;
        var nextCell = divider.nextElementSibling;
        if (!nextCell || !nextCell.classList.contains('cell-wrap')) return;
        var nextDiv = nextCell.nextElementSibling;
        // Move next cell+divider before this cell
        container.insertBefore(nextCell, cellWrap);
        if (nextDiv && nextDiv.classList.contains('cdiv')) container.insertBefore(nextDiv, cellWrap);
      }
      // Smooth scroll to keep moved cell visible
      cellWrap.scrollIntoView({behavior: 'smooth', block: 'nearest'});
    }

    else if (data.event === 'nb_replaced') {
      // Server rendered the full notebook panel — swap in-place
      var nbIsland = document.getElementById('nb-island');
      window._fileEditorView = null;  // Clear file editor ref on tab switch
      if (nbIsland && data.nb_html) {
        nbIsland.outerHTML = data.nb_html;
        // Re-init CM editors (handles both cell and file editors)
        window._sessionsInitNewCells && window._sessionsInitNewCells();
        // Re-hydrate WASM islands (CellToggle eye toggles, etc.)
        if (window.__hydrateTherapyIslands) {
          var newNb = document.getElementById('nb-island');
          if (newNb) window.__hydrateTherapyIslands(newNb);
        }
      } else if (!data.nb_html) {
        setTimeout(function(){ window.location.reload(); }, 200);
      }
    }

    else if (data.event === 'tabs_changed') {
      // Legacy fallback — reload
      setTimeout(function(){ window.location.reload(); }, 200);
    }

    else if (data.event === 'saved') {
      markSaved();
    }

    else if (data.event === 'stale_update') {
      // Show/hide Run Stale button (but keep hidden during execution)
      var btn = document.getElementById('run-stale-btn');
      var label = document.getElementById('run-stale-label');
      if (btn) {
        if (data.count > 0 && !window._sessionsExecuting) {
          btn.style.display = '';
          if (label) label.textContent = ' Run Stale (' + data.count + ')';
        } else {
          btn.style.display = 'none';
        }
      }
      // Toggle stale class on cell accent bars
      var staleSet = new Set(data.stale_ids || []);
      document.querySelectorAll('.code-cell').forEach(function(el) {
        var wrap = el.closest('.cell-wrap');
        var cid = wrap ? wrap.dataset.cellId : null;
        if (cid && staleSet.has(cid)) {
          el.classList.add('stale');
        } else {
          el.classList.remove('stale');
        }
      });
    }

    else if (data.event === 'run_progress') {
      var isRunning = data.running_index > 0 && data.total > 0;
      window._sessionsExecuting = isRunning;
      var el = document.getElementById('run-progress');
      if (el) {
        if (isRunning) {
          el.textContent = 'Running ' + data.running_index + '/' + data.total + '...';
          el.style.display = '';
        } else {
          el.textContent = '';
          el.style.display = 'none';
        }
      }
      // Toggle Run All / Stop / Run Stale button visibility
      var runAllBtn = document.getElementById('run-all-btn');
      var stopBtn = document.getElementById('stop-btn');
      var runStaleBtn = document.getElementById('run-stale-btn');
      if (runAllBtn && stopBtn) {
        if (isRunning) {
          runAllBtn.style.display = 'none';
          stopBtn.style.display = '';
          if (runStaleBtn) runStaleBtn.style.display = 'none';
        } else {
          runAllBtn.style.display = '';
          stopBtn.style.display = 'none';
          // Run Stale restored by the stale_update event that follows
        }
      }
    }

    else if (data.event === 'interrupted') {
      window._sessionsExecuting = false;
      var el = document.getElementById('run-progress');
      if (el) {
        el.textContent = 'Interrupted';
        el.style.display = '';
        el.style.color = '#e06b65';
        setTimeout(function() {
          el.textContent = '';
          el.style.display = 'none';
          el.style.color = '#56d4a0';
        }, 2000);
      }
      // Restore Run All + Run Stale buttons
      var runAllBtn = document.getElementById('run-all-btn');
      var stopBtn = document.getElementById('stop-btn');
      if (runAllBtn && stopBtn) {
        runAllBtn.style.display = '';
        stopBtn.style.display = 'none';
      }
    }

    else if (data.event === 'full_state') {
      console.log('[Sessions] Full state:', data.cells ? data.cells.length : 0, 'cells');
      var needsHydration = false;
      if (data.cells) {
        data.cells.forEach(function(cell) {
          var el = cellEls(cell.cell_id);
          if (!el) return;
          setCellState(el, cell.state, cell.cell_id);
          if (cell.output_html && el.out && !el.out.innerHTML) {
            el.out.innerHTML = cell.output_html;
            el.out.style.display = '';
            el.out.style.padding = '6px 0 10px';
            // Execute inline scripts (JS bridge for WebSlider etc.)
            el.out.querySelectorAll('script').forEach(function(oldScript) {
              var newScript = document.createElement('script');
              newScript.textContent = oldScript.textContent;
              oldScript.parentNode.replaceChild(newScript, oldScript);
            });
            if (el.out.querySelector('therapy-island')) needsHydration = true;
          }
        });
      }
      // Re-hydrate any @island components inserted via full_state
      if (needsHydration && window.__hydrateTherapyIslands) {
        var nb = document.getElementById('nb');
        if (nb) window.__hydrateTherapyIslands(nb);
      }
    }
  });

  document.addEventListener('keydown', function(e) {
    if ((e.ctrlKey || e.metaKey) && e.key === 's') {
      e.preventDefault();
      window._sessionsSave && window._sessionsSave();
    }
    // Ctrl+Z undo deleted cell (only when not focused in an editor)
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

  // ── Shared cell action dropdown (fixed position, escapes all overflow) ──
  var _cellMenu = document.createElement('div');
  _cellMenu.style.cssText = 'display:none;position:fixed;z-index:9999;background:#1a2332;border:1px solid #2a3a4f;border-radius:8px;min-width:130px;box-shadow:0 8px 24px rgba(0,0,0,.5);overflow:hidden;';
  var _menuItemStyle = 'display:flex;align-items:center;gap:8px;padding:6px 12px;font-size:12px;cursor:pointer;color:#9baabd;transition:background .1s,color .1s;';
  _cellMenu.innerHTML =
    '<div class="cell-menu-up" style="' + _menuItemStyle + '"><svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M8 3v10M4 7l4-4 4 4"/></svg>Move up</div>' +
    '<div class="cell-menu-down" style="' + _menuItemStyle + '"><svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M8 13V3M4 9l4 4 4-4"/></svg>Move down</div>' +
    '<div style="height:1px;background:#2a3a4f;margin:2px 8px;"></div>' +
    '<div class="cell-menu-format" style="' + _menuItemStyle + '"><svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"><path d="M2 3h12M2 6h8M2 9h10M2 12h6"/></svg>Format cell</div>' +
    '<div style="height:1px;background:#2a3a4f;margin:2px 8px;"></div>' +
    '<div class="cell-menu-delete" style="' + _menuItemStyle + '"><svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M2 4h12M5 4V3a1 1 0 011-1h4a1 1 0 011 1v1M6 7v5M10 7v5"/><path d="M3 4l1 9a1 1 0 001 1h6a1 1 0 001-1l1-9"/></svg>Delete cell</div>';
  document.body.appendChild(_cellMenu);
  var _menuCellId = '';

  // Hover effects for all menu items
  _cellMenu.querySelectorAll('[class^="cell-menu-"]').forEach(function(item) {
    var isDelete = item.classList.contains('cell-menu-delete');
    item.addEventListener('mouseenter', function(){
      this.style.background = isDelete ? 'rgba(224,107,101,.12)' : 'rgba(86,212,160,.08)';
      this.style.color = isDelete ? '#e06b65' : '#d4dce8';
    });
    item.addEventListener('mouseleave', function(){ this.style.background=''; this.style.color='#9baabd'; });
  });

  // Move up action
  _cellMenu.querySelector('.cell-menu-up').addEventListener('click', function(){
    _cellMenu.style.display = 'none';
    if (_menuCellId) TherapyWS.sendMessage('notebook', {action: 'move_cell', cell_id: _menuCellId, direction: 'up'});
  });

  // Move down action
  _cellMenu.querySelector('.cell-menu-down').addEventListener('click', function(){
    _cellMenu.style.display = 'none';
    if (_menuCellId) TherapyWS.sendMessage('notebook', {action: 'move_cell', cell_id: _menuCellId, direction: 'down'});
  });

  // Format cell action
  _cellMenu.querySelector('.cell-menu-format').addEventListener('click', function(){
    _cellMenu.style.display = 'none';
    if (_menuCellId) TherapyWS.sendMessage('notebook', {action: 'format_cell', cell_id: _menuCellId});
  });

  // Delete action (no confirm — undo available via Ctrl+Z)
  _cellMenu.querySelector('.cell-menu-delete').addEventListener('click', function(){
    _cellMenu.style.display = 'none';
    if (_menuCellId) {
      TherapyWS.sendMessage('notebook', {action: 'delete_cell', cell_id: _menuCellId});
    }
  });

  // Show dropdown next to a menu button (flip above if near bottom of viewport)
  window._sessionsShowCellMenu = function(btn, cellId) {
    _menuCellId = cellId;
    var r = btn.getBoundingClientRect();
    _cellMenu.style.display = 'block';
    var menuH = _cellMenu.offsetHeight || 150;
    if (window.innerHeight - r.bottom < menuH + 8) {
      _cellMenu.style.top = (r.top - menuH - 4) + 'px';
    } else {
      _cellMenu.style.top = (r.bottom + 4) + 'px';
    }
    _cellMenu.style.left = (r.right - 130) + 'px';
  };

  // Close on click outside
  document.addEventListener('click', function(e) {
    if (!e.target.closest('.menu-btn') && _cellMenu.style.display !== 'none') {
      _cellMenu.style.display = 'none';
    }
  });
})();
</script>""")
end
