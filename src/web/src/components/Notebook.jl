# Notebook.jl — NotebookIsland @island
#
# SSR Children + Signal Hydration approach:
# 1. render_cell() produces rich VNodes (markdown, outputs, CM hosts, etc.)
# 2. NotebookPanel passes them as children to NotebookIsland
# 3. SSR preserves full HTML inside <therapy-island>
# 4. on_mount hydrates: CM editors, WS bridge, fold observers
#
# Signals track state (cell_order, is_executing, stale_count)
# but DOM is the source of truth for cell positions.

@island function NotebookIsland(children...)
    # State tracking signals
    cell_order, set_cell_order = create_signal(Vector{String}())
    is_executing, set_executing = create_signal(0)
    stale_count, set_stale_count = create_signal(0)

    # Hydrate: wire CM editors + WS bridge to existing SSR'd DOM
    on_mount(() -> begin
        # Init CM editors on existing .cm-cell elements
        js("if(window._initAllCM) _initAllCM()")

        # Setup WS bridge with signal setters for structural changes
        js("if(window._setupWSBridge) _setupWSBridge(\$1, \$2, \$3)",
            set_cell_order, set_executing, set_stale_count)

        # Init fold observers on existing .cell-island elements
        js("""
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
        """)

        # Build initial cell_order from DOM
        js("""
            var ids = [];
            document.querySelectorAll('.cell-wrap[data-cell-id]').forEach(function(el) {
                ids.push(el.dataset.cellId);
            });
            \$1(ids);
        """, set_cell_order)
    end)

    # SSR'd children (render_cell output) rendered directly — no For(), no skeletons
    return Div(:id => "nb", :class => "flex-1 overflow-y-auto px-5 pt-3 pb-8",
        Div(:style => "max-width:900px;margin:0 auto;padding-left:28px;",
            children...))
end
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

    var accentColor = '#d4759a';
    function _makeEdTheme() {
      var isDark = document.documentElement.classList.contains('dark');
      return C.EditorView.theme({
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
    }
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
    // Basic save — works for file tabs without WS bridge. WS bridge overrides with optimistic version.
    window._sessionsSave = function() { if (!TherapyWS||!TherapyWS.sendMessage) return; var fe=window._fileEditorView; if(fe){TherapyWS.sendMessage('notebook',{action:'save',content:fe.state.doc.toString()});return;} TherapyWS.sendMessage('notebook',{action:'save',codes:_collectCodes()}); };

    var _syncTimers = {};
    if (!window._sessSuppressSync) window._sessSuppressSync = {};
    function syncCodeToServer(cellId) { if(window._sessSuppressSync[cellId]){delete window._sessSuppressSync[cellId];return;} if(window._sessionsMarkUnsaved)window._sessionsMarkUnsaved(); if(_syncTimers[cellId])clearTimeout(_syncTimers[cellId]); _syncTimers[cellId]=setTimeout(function(){var ev=editors[cellId];if(!ev)return;var code=ev.state.doc.toString();if(TherapyWS&&TherapyWS.sendMessage)TherapyWS.sendMessage('notebook',{action:'update_code',cell_id:cellId,code:code});},400); }
    function editSyncExtension(cellId) { return C.EditorView.updateListener.of(function(update){if(update.docChanged)syncCodeToServer(cellId);}); }
    function shiftEnterKeymap(cellId) { return C.EditorView.domEventHandlers({keydown:function(event){if(event.key==='Enter'&&event.shiftKey&&!event.ctrlKey&&!event.metaKey){event.preventDefault();window._sessionsRunCell(cellId);return true;}}}); }

    window._initAllCM = function() {
      // Rebuild theme fresh each time (picks up current dark/light mode)
      var currentEdTheme = _makeEdTheme();
      document.querySelectorAll('.cm-cell').forEach(function(host) {
        if (host.querySelector('.cm-editor')) return;
        var src = host.dataset.src || '';
        var cellId = host.dataset.cellId || '';
        var isFileEditor = host.classList.contains('cm-file-editor');
        var cellKeymaps = (!isFileEditor && cellId) ? [shiftEnterKeymap(cellId)] : [];
        var exts = [...cellKeymaps, C.lineNumbers(),C.highlightActiveLineGutter(),C.highlightSpecialChars(),C.history(),C.drawSelection(),C.EditorState.allowMultipleSelections.of(true),C.indentOnInput(),C.bracketMatching(),C.closeBrackets(),C.rectangularSelection(),C.highlightActiveLine(),C.highlightSelectionMatches(),C.keymap.of([...C.closeBracketsKeymap,...C.defaultKeymap,...C.searchKeymap,...C.historyKeymap,...C.completionKeymap,C.indentWithTab]),C.julia(),C.syntaxHighlighting(hlTheme),currentEdTheme];
        if (isFileEditor) { exts.push(C.EditorView.theme({'&':{height:'100%'},'.cm-scroller':{overflow:'auto'}})); }
        else if (cellId) { exts.push(editSyncExtension(cellId)); }
        var view = new C.EditorView({doc:src,extensions:exts,parent:host});
        if (isFileEditor) { window._fileEditorView = view; } else if (cellId) { editors[cellId] = view; }
      });
      // Fade out loading overlay once editors are ready
      var lo = document.getElementById('nb-loading');
      if (lo) { lo.classList.add('loaded'); setTimeout(function(){ lo.remove(); }, 400); }
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
  // ══════════════════════════════════════════════════════════════
  // MutationManager — optimistic UI with server reconciliation
  // Pattern: client applies immediately → server confirms/rejects
  // ══════════════════════════════════════════════════════════════
  var _mutations = new Map();  // mutation_id → { rollback, timeout_id }
  var _mutSeq = 0;

  function mutate(channel, payload, rollbackFn) {
    var mid = 'm_' + (++_mutSeq);
    payload.mutation_id = mid;
    _mutations.set(mid, {
      rollback: rollbackFn,
      timeout_id: setTimeout(function() {
        if (_mutations.has(mid)) {
          console.warn('[Sessions] Mutation timed out:', mid, payload.action);
          _mutations.get(mid).rollback();
          _mutations.delete(mid);
        }
      }, 10000)
    });
    if (window.TherapyWS && TherapyWS.sendMessage) {
      TherapyWS.sendMessage(channel, payload);
    }
    return mid;
  }

  function reconcile(data) {
    var mid = data.ack_mutation;
    if (!mid || !_mutations.has(mid)) return false;
    var m = _mutations.get(mid);
    clearTimeout(m.timeout_id);
    if (data.event === 'mutation_error') {
      console.warn('[Sessions] Mutation rejected:', mid, data.reason);
      m.rollback();
    }
    _mutations.delete(mid);
    return true;
  }

  // ══════════════════════════════════════════════════════════════
  // WS Bridge — sets up event listener + exposes optimistic APIs
  // ══════════════════════════════════════════════════════════════
  window._setupWSBridge = function(setCellOrder, setExecuting, setStaleCount) {
    console.log('[Sessions WS] Bridge initialized');

    // ── Save state ──
    window._sessionsUnsaved = false;
    function markUnsaved() { if(window._sessionsUnsaved)return; window._sessionsUnsaved=true; var btn=document.getElementById('save-indicator'); if(btn){btn.textContent='\\u25CF Save';btn.style.color='var(--status-running)';} }
    function markSaved() { window._sessionsUnsaved=false; var btn=document.getElementById('save-indicator'); if(btn){btn.textContent='Saved';btn.style.color='';setTimeout(function(){if(!window._sessionsUnsaved)btn.textContent='Save';},2000);} }
    window._sessionsMarkUnsaved = markUnsaved;

    // ── DOM helpers ──
    function cellEls(cellId) { var wrap=document.querySelector('.cell-wrap[data-cell-id="'+cellId+'"]'); if(!wrap)return null; return {wrap:wrap,code:wrap.querySelector('.code-cell'),out:wrap.querySelector('.cell-out'),ctrls:wrap.querySelector('.cell-ctrls')}; }
    function nbContainer() { return document.querySelector('#nb > div'); }
    function fmtRuntime(ns) { var ms=ns/1e6; return ms<1?(ns/1e3).toFixed(1)+'\\u00b5s':ms<1000?ms.toFixed(1)+'ms':(ms/1000).toFixed(2)+'s'; }
    function fmtSeconds(s) { return s<1?s.toFixed(2)+'s':s<60?s.toFixed(1)+'s':(s/60).toFixed(1)+'min'; }

    // ── Cell execution timer ──
    var _cellTimers = {};
    function startCellTimer(cellId, el) { stopCellTimer(cellId); if(!el||!el.ctrls)return; var t0=performance.now(); var badge=el.ctrls.querySelector('.rt-badge'); if(!badge){badge=document.createElement('span');badge.className='rt-badge';el.ctrls.insertBefore(badge,el.ctrls.firstChild);} badge.style.cssText='font-size:10px;font-family:ui-monospace,monospace;padding:1px 7px;border-radius:9999px;color:#7bb8e8;opacity:.9;background:rgba(123,184,232,.08);border:1px solid rgba(123,184,232,.15);'; badge.textContent='0.0s'; var iv=setInterval(function(){badge.textContent=fmtSeconds((performance.now()-t0)/1000);},100); _cellTimers[cellId]={interval:iv}; }
    function stopCellTimer(cellId) { var t=_cellTimers[cellId]; if(t){clearInterval(t.interval);delete _cellTimers[cellId];} }
    function setCellState(el,state,cellId) {
      if(!el)return;
      // Apply state to code-cell (visible when code shown)
      if(el.code){el.code.classList.remove('idle','stale','executing');if(state==='cell_queued'||state==='cell_running'){el.code.style.borderColor=state==='cell_queued'?'var(--status-running)':'#7bb8e8';el.code.classList.add('executing');if(state==='cell_running'&&cellId)startCellTimer(cellId,el);}else{if(cellId)stopCellTimer(cellId);el.code.style.borderColor=state==='cell_errored'?'var(--status-error)':'';}}
      // Also apply state to cell-wrap (visible even when code is hidden/folded)
      if(el.wrap){el.wrap.classList.remove('wrap-queued','wrap-running','wrap-done','wrap-errored');if(state==='cell_queued')el.wrap.classList.add('wrap-queued');else if(state==='cell_running')el.wrap.classList.add('wrap-running');else if(state==='cell_errored')el.wrap.classList.add('wrap-errored');}
    }

    // ── Find gap after a cell (or first gap if null) ──
    function gapAfter(cellId) {
      if (cellId) {
        var wrap = document.querySelector('.cell-wrap[data-cell-id="'+cellId+'"]');
        if (!wrap) return null;
        var sib = wrap.nextElementSibling;
        while (sib && !sib.classList.contains('cdiv')) sib = sib.nextElementSibling;
        return sib;
      }
      var c = nbContainer();
      return c ? c.querySelector('.cdiv') : null;
    }

    // ── Insert HTML after a gap element ──
    function insertHtmlAfterGap(gap, html) {
      var tmp = document.createElement('div');
      tmp.innerHTML = html;
      var nodes = Array.from(tmp.children);
      var ref = gap.nextSibling;
      var parent = gap.parentNode;
      nodes.forEach(function(n) { parent.insertBefore(n, ref); });
      setTimeout(function() {
        if (window._initAllCM) _initAllCM();
        if (window.__hydrateTherapyIslands) { var nb=document.getElementById('nb'); if(nb) __hydrateTherapyIslands(nb); }
      }, 30);
    }

    // ── Remove cell + its following gap from DOM, return rollback data ──
    function removeCellDOM(cellId) {
      var wrap = document.querySelector('.cell-wrap[data-cell-id="'+cellId+'"]');
      if (!wrap) return null;
      var nextGap = wrap.nextElementSibling;
      while (nextGap && !nextGap.classList.contains('cdiv')) nextGap = nextGap.nextElementSibling;
      var parent = wrap.parentNode;
      var refNode = wrap.previousElementSibling; // gap before this cell
      var wrapHTML = wrap.outerHTML;
      var gapHTML = nextGap ? nextGap.outerHTML : '';
      if (nextGap) nextGap.remove();
      wrap.remove();
      return { html: wrapHTML + gapHTML, parent: parent, refNode: refNode };
    }

    // ══════════════════════════════════════════════════════════════
    // Optimistic APIs — called by UI handlers, send + apply at once
    // ══════════════════════════════════════════════════════════════

    // Optimistic add: insert placeholder → server confirms with real HTML
    window._sessionsAddCell = function(afterCellId) {
      markUnsaved();
      var tempId = 'temp_' + Date.now() + '_' + Math.random().toString(36).slice(2,6);
      var gap = gapAfter(afterCellId);
      mutate('notebook',
        { action:'add_cell', after_cell_id:afterCellId||'', temp_id:tempId },
        function() {
          // Rollback: remove the temp cell if it exists
          var el = document.querySelector('.cell-wrap[data-cell-id="'+tempId+'"]');
          if (el) { var ng=el.nextElementSibling; if(ng&&ng.classList.contains('cdiv'))ng.remove(); el.remove(); }
        }
      );
      // No immediate DOM insertion — server sends cell_html quickly
      // This is "pessimistic-for-add" since we need server-rendered HTML
    };

    // Optimistic delete: remove DOM immediately → server confirms
    window._sessionsDeleteCell = function(cellId) {
      markUnsaved();
      var eds = window._sessionsEditors||{};
      if (eds[cellId]) delete eds[cellId];
      // Capture for undo toast
      var wrap = document.querySelector('.cell-wrap[data-cell-id="'+cellId+'"]');
      var prevWrap = null;
      if (wrap) {
        var prev = wrap.previousElementSibling;
        while (prev && !prev.classList.contains('cell-wrap')) prev = prev.previousElementSibling;
        prevWrap = prev;
      }
      var prevId = prevWrap ? prevWrap.dataset.cellId : '';
      // Capture DOM for rollback BEFORE removing
      var removed = removeCellDOM(cellId);
      if (!removed) return;
      mutate('notebook',
        { action:'delete_cell', cell_id:cellId },
        function() {
          // Rollback: re-insert the cell
          if (removed.refNode && removed.parent) {
            var tmp = document.createElement('div');
            tmp.innerHTML = removed.html;
            var nodes = Array.from(tmp.children);
            var ref = removed.refNode.nextSibling;
            nodes.forEach(function(n) { removed.parent.insertBefore(n, ref); });
            if (window._initAllCM) _initAllCM();
            if (window.__hydrateTherapyIslands) { var nb=document.getElementById('nb'); if(nb) __hydrateTherapyIslands(nb); }
          }
        }
      );
      // Show undo toast
      window._recentlyDeleted = {cell_id:cellId,prev_cell_id:prevId};
      var toast=document.getElementById('undo-toast');
      if(toast){toast.classList.add('show');if(window._undoToastTimer)clearTimeout(window._undoToastTimer);window._undoToastTimer=setTimeout(function(){toast.classList.remove('show');window._recentlyDeleted=null;},8000);}
    };

    // Optimistic move: swap DOM elements immediately → server confirms
    window._sessionsMoveCell = function(cellId, direction) {
      markUnsaved();
      var wrap = document.querySelector('.cell-wrap[data-cell-id="'+cellId+'"]');
      if (!wrap) return;
      var parent = wrap.parentNode;
      var nextGap = wrap.nextElementSibling;
      while (nextGap && !nextGap.classList.contains('cdiv')) nextGap = nextGap.nextElementSibling;

      // Capture original position for rollback
      var origNextSibling = wrap.nextSibling;

      if (direction === 'up') {
        // Find the cell-wrap above (skip past the gap before us)
        var prevGap = wrap.previousElementSibling;
        while (prevGap && !prevGap.classList.contains('cdiv')) prevGap = prevGap.previousElementSibling;
        if (!prevGap) return; // already at top
        var target = prevGap.previousElementSibling;
        while (target && !target.classList.contains('cell-wrap')) target = target.previousElementSibling;
        if (!target) return;
        // Move: insert wrap before target (with gap following)
        parent.insertBefore(wrap, target);
        if (nextGap) parent.insertBefore(nextGap, target);
      } else if (direction === 'down') {
        if (!nextGap) return;
        var nextCell = nextGap.nextElementSibling;
        while (nextCell && !nextCell.classList.contains('cell-wrap')) nextCell = nextCell.nextElementSibling;
        if (!nextCell) return; // already at bottom
        var nextCellGap = nextCell.nextElementSibling;
        while (nextCellGap && !nextCellGap.classList.contains('cdiv')) nextCellGap = nextCellGap.nextElementSibling;
        // Move: insert wrap after nextCell's gap
        var insertRef = nextCellGap ? nextCellGap.nextSibling : null;
        parent.insertBefore(wrap, insertRef);
        if (nextGap) parent.insertBefore(nextGap, insertRef);
      }
      wrap.scrollIntoView({behavior:'smooth',block:'nearest'});

      mutate('notebook',
        { action:'move_cell', cell_id:cellId, direction:direction },
        function() {
          // Rollback: move back to original position
          parent.insertBefore(wrap, origNextSibling);
          if (nextGap) parent.insertBefore(nextGap, wrap.nextSibling);
        }
      );
    };

    // Optimistic save: show "Saved" immediately → rollback on error
    window._sessionsSave = function() {
      if (!TherapyWS||!TherapyWS.sendMessage) return;
      var fe=window._fileEditorView;
      markSaved(); // optimistic
      if(fe) {
        mutate('notebook', {action:'save',content:fe.state.doc.toString()}, function(){ markUnsaved(); });
      } else {
        var codes={}; var eds=window._sessionsEditors||{}; for(var cid in eds)codes[cid]=eds[cid].state.doc.toString();
        mutate('notebook', {action:'save',codes:codes}, function(){ markUnsaved(); });
      }
    };

    // ══════════════════════════════════════════════════════════════
    // WS Event Handler — processes server events, reconciles mutations
    // ══════════════════════════════════════════════════════════════
    window.addEventListener('therapy:channel:notebook', function(e) {
      var data = e.detail;
      if (!data || !data.event) return;

      // Reconcile: if this event acknowledges a pending mutation, handle it
      if (data.ack_mutation) {
        var wasPending = reconcile(data);
        if (data.event === 'mutation_error') return; // rollback already done
        // For confirmed mutations, we still process the event to handle
        // server-provided data (e.g. real cell_id replacing temp_id)
      }

      // ── Cell state (queued/running/idle/errored) ──
      if (data.event === 'cell_state') {
        setCellState(cellEls(data.cell_id), data.state, data.cell_id);
      }

      // ── Cell output (pessimistic — server computes, client displays) ──
      else if (data.event === 'cell_output') {
        var el = cellEls(data.cell_id);
        if (!el) return;
        if (el.out) {
          var html = data.output_html || '';
          if (html) {
            el.out.innerHTML=html; el.out.style.display=''; el.out.style.padding='6px 0 10px';
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
      }

      // ── Cell added (server confirms with rendered HTML) ──
      else if (data.event === 'cell_added') {
        markUnsaved();
        // If we had a temp placeholder, replace it. Otherwise insert fresh.
        if (data.temp_id) {
          var tempEl = document.querySelector('.cell-wrap[data-cell-id="'+data.temp_id+'"]');
          if (tempEl) { tempEl.remove(); } // remove placeholder
        }
        if (data.cell_html) {
          var gap = gapAfter(data.after_cell_id);
          if (gap) insertHtmlAfterGap(gap, data.cell_html);
        }
      }

      // ── Cell deleted (already removed optimistically, just confirm) ──
      else if (data.event === 'cell_deleted') {
        // If NOT our mutation (e.g. from another client), remove from DOM
        if (!data.ack_mutation) {
          removeCellDOM(data.cell_id);
        }
        if(window._sessionsEditors)delete window._sessionsEditors[data.cell_id];
        // Undo info (for non-optimistic path)
        if (!data.ack_mutation) {
          window._recentlyDeleted = {cell_id:data.cell_id,code:data.code||'',prev_cell_id:data.prev_cell_id||''};
          var toast=document.getElementById('undo-toast');
          if(toast){toast.classList.add('show');if(window._undoToastTimer)clearTimeout(window._undoToastTimer);window._undoToastTimer=setTimeout(function(){toast.classList.remove('show');window._recentlyDeleted=null;},8000);}
        }
      }

      // ── Cell moved (already moved optimistically, just confirm) ──
      else if (data.event === 'cell_moved') {
        // If NOT our mutation, apply the move to DOM
        if (!data.ack_mutation) {
          // Other client moved a cell — reload for simplicity
          setTimeout(function(){window.location.reload();},200);
        }
      }

      // ── Code updated (format, external edit) ──
      else if (data.event === 'cell_formatted' || data.event === 'cell_code_updated') {
        if (data.event === 'cell_formatted') markUnsaved();
        // File editor update (format_file result)
        if (data.cell_id === '__file__' && window._fileEditorView && data.code !== undefined) {
          var fe = window._fileEditorView;
          var cur = fe.state.doc.toString();
          if (data.code !== cur) fe.dispatch({changes:{from:0,to:cur.length,insert:data.code}});
        } else {
          var eds=window._sessionsEditors||{}; var ev=eds[data.cell_id];
          if(ev&&data.code!==undefined){var cur=ev.state.doc.toString();if(data.code!==cur){window._sessSuppressSync[data.cell_id]=true;ev.dispatch({changes:{from:0,to:cur.length,insert:data.code}});}}
        }
      }

      // ── Stale cells update ──
      else if (data.event === 'stale_update') {
        setStaleCount(data.count || 0);
        var btn=document.getElementById('run-stale-btn');var label=document.getElementById('run-stale-label');
        if(btn){if(data.count>0&&!window._sessionsExecuting){btn.classList.remove('tb-disabled');if(label)label.textContent=' Run Stale ('+data.count+')';}else{btn.classList.add('tb-disabled');if(label)label.textContent=' Run Stale';}}
        var staleSet=new Set(data.stale_ids||[]);
        document.querySelectorAll('.code-cell').forEach(function(el){var wrap=el.closest('.cell-wrap');var cid=wrap?wrap.dataset.cellId:null;if(cid&&staleSet.has(cid)){el.classList.add('stale');}else{el.classList.remove('stale');}});
      }

      // ── Run progress ──
      else if (data.event === 'run_progress') {
        var isRunning=data.running_index>0&&data.total>0;
        window._sessionsExecuting=isRunning;
        window._sessionsRunningCellId=isRunning&&data.cell_id?data.cell_id:null;
        setExecuting(isRunning ? 1 : 0);
        var el=document.getElementById('run-progress');if(el){if(isRunning){el.textContent='Running '+data.running_index+'/'+data.total+'...';}else{el.textContent='';}}
        var jumpBtn=document.getElementById('jump-running-btn');
        if(jumpBtn){if(isRunning){jumpBtn.classList.remove('tb-disabled');}else{jumpBtn.classList.add('tb-disabled');}}
        var runAllBtn=document.getElementById('run-all-btn');var stopBtn=document.getElementById('stop-btn');var runStaleBtn=document.getElementById('run-stale-btn');
        if(runAllBtn&&stopBtn){if(isRunning){runAllBtn.classList.add('tb-disabled');stopBtn.classList.remove('tb-disabled');if(runStaleBtn)runStaleBtn.classList.add('tb-disabled');}else{runAllBtn.classList.remove('tb-disabled');stopBtn.classList.add('tb-disabled');}}
      }

      // ── Format progress ──
      else if (data.event === 'format_started') { document.querySelectorAll('[data-format-btn]').forEach(function(btn){btn.textContent='Formatting...';btn.classList.add('tb-disabled');}); }
      else if (data.event === 'format_done') { document.querySelectorAll('[data-format-btn]').forEach(function(btn){btn.textContent='Format';btn.classList.remove('tb-disabled');}); }

      // ── Save confirmed ──
      else if (data.event === 'saved') { if(!data.ack_mutation) markSaved(); }

      // ── Interrupted ──
      else if (data.event === 'interrupted') {
        window._sessionsExecuting=false; setExecuting(0);
        var el=document.getElementById('run-progress');if(el){el.textContent='Interrupted';el.style.color='var(--status-error)';setTimeout(function(){el.textContent='';el.style.color='';},2000);}
        var runAllBtn=document.getElementById('run-all-btn');var stopBtn=document.getElementById('stop-btn');if(runAllBtn&&stopBtn){runAllBtn.classList.remove('tb-disabled');stopBtn.classList.add('tb-disabled');}
      }

      // ── Full state (SSR already rendered, skip) ──
      else if (data.event === 'full_state') {
        // Restore cell execution states from server (important after reconnect/reload)
        if (data.cells) {
          data.cells.forEach(function(cell) {
            var el = cellEls(cell.cell_id);
            if (el && cell.state && cell.state !== 'cell_idle') {
              setCellState(el, cell.state, cell.cell_id);
            }
          });
        }
        // Restore execution progress indicators
        if (data.executing) {
          window._sessionsExecuting = true;
          setExecuting(1);
          var runAllBtn=document.getElementById('run-all-btn');var stopBtn=document.getElementById('stop-btn');var runStaleBtn=document.getElementById('run-stale-btn');
          if(runAllBtn)runAllBtn.classList.add('tb-disabled');
          if(stopBtn)stopBtn.classList.remove('tb-disabled');
          if(runStaleBtn)runStaleBtn.classList.add('tb-disabled');
          // Count running/queued cells for progress text + find running cell
          var running=0,queued=0,total=0,runningCid=null;
          if(data.cells){data.cells.forEach(function(c){if(c.state==='cell_running'){running++;total++;runningCid=c.cell_id;}else if(c.state==='cell_queued'){queued++;total++;}});}
          window._sessionsRunningCellId=runningCid;
          var el=document.getElementById('run-progress');
          if(el&&total>0){el.textContent='Running '+(running>0?1:0)+'/'+(total)+'...';}
          var jumpBtn=document.getElementById('jump-running-btn');
          if(jumpBtn)jumpBtn.classList.remove('tb-disabled');
        }
      }

      // ── Notebook replaced (tab switch, etc.) ──
      else if (data.event === 'nb_replaced') {
        window._fileEditorView = null;
        if (data.nb_html) {
          var nbIsland=document.getElementById('nb-island');
          if(nbIsland){nbIsland.outerHTML=data.nb_html;if(window._initAllCM)_initAllCM();if(window.__hydrateTherapyIslands){var newNb=document.getElementById('nb-island');if(newNb)window.__hydrateTherapyIslands(newNb);}}
        }
        var lo=document.getElementById('nb-loading');if(lo){lo.classList.add('loaded');setTimeout(function(){lo.remove();},400);}
      }
    });
  };
"""
end

# Combined notebook JS for global injection by Layout.jl
# No _populateCells — SSR provides all cell HTML
function _notebook_island_js()
"""
(function() {
  // ── Cell menu + toggle fold + hover + keyboard shortcuts ──
  window._toggleFold = function(cellId) {
    var wrap = document.querySelector('.cell-wrap[data-cell-id="' + cellId + '"]');
    if (!wrap) return;
    var code = wrap.querySelector('.code-cell');
    if (code) code.style.display = code.style.display === 'none' ? '' : 'none';
    if (window.TherapyWS && TherapyWS.sendMessage) {
      TherapyWS.sendMessage('notebook', {action:'toggle_fold', cell_id:cellId, folded:code && code.style.display==='none'});
    }
  };

  var _cellMenu = null;
  window._sessionsShowCellMenu = function(btn, cellId) {
    if (_cellMenu) { _cellMenu.remove(); _cellMenu = null; return; }
    var rect = btn.getBoundingClientRect();
    _cellMenu = document.createElement('div');
    _cellMenu.style.cssText = 'position:fixed;z-index:9999;background:var(--panel-bg);border:1px solid var(--cell-border-hov,var(--cell-border));border-radius:8px;min-width:140px;box-shadow:0 8px 24px rgba(0,0,0,.3);overflow:hidden;padding:4px 0;top:'+(rect.bottom+4)+'px;right:'+(window.innerWidth-rect.right)+'px;';
    var actions = [
      {label:'Move Up', icon:'\\u2191', action:function(){ window._sessionsMoveCell && _sessionsMoveCell(cellId,'up'); }},
      {label:'Move Down', icon:'\\u2193', action:function(){ window._sessionsMoveCell && _sessionsMoveCell(cellId,'down'); }},
      {label:'Format', icon:'\\u2728', action:function(){TherapyWS.sendMessage('notebook',{action:'format_cell',cell_id:cellId})}},
      {sep:true},
      {label:'Delete', icon:'\\u2715', danger:true, action:function(){ window._sessionsDeleteCell && _sessionsDeleteCell(cellId); }}
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
    if (_cellMenu && !_cellMenu.contains(e.target) && !e.target.closest('.menu-btn')) { _cellMenu.remove(); _cellMenu = null; }
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

  // ── Jump to currently running cell ──
  window._sessionsJumpToRunning = function() {
    var cid = window._sessionsRunningCellId;
    if (!cid) {
      // Fallback: find any cell with executing class
      var ex = document.querySelector('.code-cell.executing');
      if (ex) { var wrap = ex.closest('.cell-wrap'); if (wrap) cid = wrap.dataset.cellId; }
    }
    if (!cid) return;
    var wrap = document.querySelector('.cell-wrap[data-cell-id="'+cid+'"]');
    if (wrap) {
      wrap.scrollIntoView({behavior:'smooth',block:'start'});
    }
  };

  // ── Theme switch: rebuild CM editors in-place, preserve scroll + content ──
  window._sessionsThemeSwitch = function() {
    // 1. Save notebook scroll position
    var nb = document.getElementById('nb');
    var scrollTop = nb ? nb.scrollTop : 0;

    // 2. Save each editor's current doc content (may differ from data-src)
    var editorDocs = {};
    if (window._sessionsEditors) {
      for (var cid in _sessionsEditors) {
        editorDocs[cid] = _sessionsEditors[cid].state.doc.toString();
      }
    }
    var fileDoc = window._fileEditorView ? _fileEditorView.state.doc.toString() : null;

    // 3. Destroy all CM editors
    document.querySelectorAll('.cm-cell .cm-editor').forEach(function(ed) { ed.remove(); });
    if (window._sessionsEditors) {
      for (var cid in _sessionsEditors) delete _sessionsEditors[cid];
    }
    window._fileEditorView = null;

    // 4. Update CM theme (new dark flag) — uses the factory function
    if (typeof _makeEdTheme === 'function') {
      // _makeEdTheme reads isDark from DOM, returns fresh theme
      // But it's scoped inside the CM IIFE, so we use _initAllCM which
      // rebuilds editors with the current theme. We just need to update
      // data-src on each host so the new editor gets the current content.
    }

    // 5. Update data-src attributes with current content
    for (var cid in editorDocs) {
      var host = document.querySelector('.cm-cell[data-cell-id="'+cid+'"]');
      if (host) host.dataset.src = editorDocs[cid];
    }
    if (fileDoc !== null) {
      var fh = document.querySelector('.cm-file-editor');
      if (fh) fh.dataset.src = fileDoc;
    }

    // 6. Reinit all CM editors (picks up new dark/light theme)
    if (window._initAllCM) _initAllCM();

    // 7. Restore scroll position
    if (nb) nb.scrollTop = scrollTop;

    // 8. Update terminal theme
    if (window._sessionsUpdateTermTheme) _sessionsUpdateTermTheme();
  };

  // ── Auto-init CM editors (file editors outside NotebookIsland) ──
  setTimeout(function() { if (window._initAllCM) _initAllCM(); }, 100);

  // ── Hydrate nested Therapy islands (CellToggle etc.) after DOM replacement ──
  window.__hydrateTherapyIslands = function(root) {
    if (!window.TherapyHydrate) return;
    for (var name in TherapyHydrate) {
      TherapyHydrate[name]();
    }
  };

  // ── Show loading overlay on notebook panel (called before server responds) ──
  window._sessionsShowLoading = function() {
    var panel = document.getElementById('nb-island');
    if (!panel) return;
    // Remove old loading overlay if exists
    var old = document.getElementById('nb-loading');
    if (old) old.remove();
    // Ensure panel has position:relative for the overlay
    if (!panel.style.position) panel.style.position = 'relative';
    // Create and insert loading overlay (within nb-island, not replacing it)
    var lo = document.createElement('div');
    lo.id = 'nb-loading';
    lo.className = 'nb-loading';
    lo.innerHTML = '<span class="dot-pulse"></span><span class="dot-pulse"></span><span class="dot-pulse"></span>';
    panel.appendChild(lo);
  };

  // ── Global event handler (works for file tabs without WS bridge) ──
  window._sessionsMarkUnsaved = window._sessionsMarkUnsaved || function() { var btn=document.getElementById('save-indicator'); if(btn){btn.textContent='\\u25CF Save';btn.style.color='var(--status-running)';} };
  window.addEventListener('therapy:channel:notebook', function(e) {
    var d = e.detail;
    if (!d) return;
    if (d.event === 'saved') { var btn=document.getElementById('save-indicator'); if(btn){btn.textContent='Saved';btn.style.color='';setTimeout(function(){btn.textContent='Save';},2000);} }
    if (d.event === 'format_started') { document.querySelectorAll('[data-format-btn]').forEach(function(b){b.dataset.origText=b.textContent;b.textContent='Formatting...';b.style.opacity='0.6';b.style.pointerEvents='none';}); }
    if (d.event === 'format_done') { document.querySelectorAll('[data-format-btn]').forEach(function(b){b.textContent=b.dataset.origText||'Format';b.style.opacity='';b.style.pointerEvents='';}); }
    // File editor format result
    if (d.event === 'cell_code_updated' && d.cell_id === '__file__' && window._fileEditorView && d.code !== undefined) {
      var fe = window._fileEditorView; var cur = fe.state.doc.toString();
      if (d.code !== cur) fe.dispatch({changes:{from:0,to:cur.length,insert:d.code}});
    }
    // nb_replaced fallback (for when WS bridge wasn't initialized)
    if (d.event === 'nb_replaced') {
      window._fileEditorView = null;
      if (d.nb_html) {
        var nbIsland = document.getElementById('nb-island');
        if (nbIsland) {
          nbIsland.outerHTML = d.nb_html;
          setTimeout(function() {
            if (window._initAllCM) _initAllCM();
            if (window.__hydrateTherapyIslands) { var nb = document.getElementById('nb-island'); if (nb) __hydrateTherapyIslands(nb); }
          }, 50);
        }
      }
      // Remove loading overlay if present
      var lo = document.getElementById('nb-loading');
      if (lo) { lo.classList.add('loaded'); setTimeout(function(){ lo.remove(); }, 400); }
    }
  });

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
        // Undo uses direct WS call (not optimistic — we need server to render the cell)
        if (window.TherapyWS && TherapyWS.sendMessage) {
          TherapyWS.sendMessage('notebook', {action: 'add_cell', after_cell_id: del.prev_cell_id, code: del.code});
        }
      }
    }
  });
})();
"""
end
