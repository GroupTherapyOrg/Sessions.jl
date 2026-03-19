# Layout.jl — HTML shell for Sessions.jl Web UI
#
# Minimal wrapper: dark mode detection, font loading, body container.
# Includes client-side JS for handling notebook channel messages.
# No navigation header — the full-screen IDE layout is handled by SessionsApp.

function Layout(children...; title="Sessions.jl")
    Div(:class => "h-screen overflow-hidden bg-warm-50 dark:bg-warm-950 text-warm-800 dark:text-warm-300",
        # FOUC prevention — apply saved theme before paint
        RawHtml("""<script>(function(){var t=localStorage.getItem('theme');if(t==='dark'||(!t&&window.matchMedia('(prefers-color-scheme: dark)').matches)){document.documentElement.classList.add('dark')}})();</script>"""),
        # Main content — full viewport, no scroll (panels handle their own scroll)
        Div(:id => "page-content", :class => "h-full",
            children...),
        # Notebook channel message handler
        _notebook_channel_script())
end

"""Client-side JavaScript for handling notebook WebSocket channel messages."""
function _notebook_channel_script()
    RawHtml("""<script>
(function() {
  if (window._sessionsNotebookHandler) return;
  window._sessionsNotebookHandler = true;

  // State class mapping
  var stateClasses = {
    'cell_idle': 'cell-state-idle',
    'cell_queued': 'cell-state-queued',
    'cell_running': 'cell-state-running',
    'cell_done': 'cell-state-done',
    'cell_errored': 'cell-state-errored'
  };

  // Listen for notebook channel messages
  window.addEventListener('therapy:channel:notebook', function(e) {
    var data = e.detail;
    if (!data || !data.event) return;

    if (data.event === 'cell_state') {
      // Update cell state badge
      var badge = document.querySelector('[data-cell-state][data-cell-id="' + data.cell_id + '"]');
      if (badge) {
        badge.className = stateClasses[data.state] || 'cell-state-idle';
        badge.dataset.cellState = data.state;
      }
    }

    else if (data.event === 'cell_output') {
      // Update cell output HTML
      var output = document.querySelector('.cell-output[data-cell-id="' + data.cell_id + '"]');
      if (output) {
        output.innerHTML = data.output_html || '';
      }
      // Update state badge
      var badge = document.querySelector('[data-cell-state][data-cell-id="' + data.cell_id + '"]');
      if (badge && data.state) {
        badge.className = stateClasses[data.state] || 'cell-state-done';
        badge.dataset.cellState = data.state;
      }
      // Update stdout
      if (data.stdout) {
        var cell = document.querySelector('.cell-container[data-cell-id="' + data.cell_id + '"]');
        if (cell) {
          var existing = cell.querySelector('pre.font-mono.text-warm-500');
          if (existing) {
            existing.textContent = data.stdout;
          }
        }
      }
    }

    else if (data.event === 'cell_added' || data.event === 'cell_deleted' || data.event === 'cell_order') {
      // For structural changes, reload the page to get fresh SSR
      // TODO: In-place DOM updates for smoother UX
      window.location.reload();
    }

    else if (data.event === 'saved') {
      console.log('[Sessions] Notebook saved:', data.notebook_path);
    }

    else if (data.event === 'full_state') {
      console.log('[Sessions] Full state received:', data.cells ? data.cells.length : 0, 'cells');
      // On initial connect, update all cell states and outputs
      if (data.cells) {
        data.cells.forEach(function(cell) {
          // Update state badge
          var badge = document.querySelector('[data-cell-state][data-cell-id="' + cell.cell_id + '"]');
          if (badge) {
            badge.className = stateClasses[cell.state] || 'cell-state-idle';
            badge.dataset.cellState = cell.state;
          }
          // Update output
          if (cell.output_html) {
            var output = document.querySelector('.cell-output[data-cell-id="' + cell.cell_id + '"]');
            if (output && output.innerHTML === '') {
              output.innerHTML = cell.output_html;
            }
          }
        });
      }
    }
  });

  // Keyboard shortcuts
  document.addEventListener('keydown', function(e) {
    // Ctrl+S / Cmd+S → Save
    if ((e.ctrlKey || e.metaKey) && e.key === 's') {
      e.preventDefault();
      if (window.TherapyWS && TherapyWS.sendMessage) {
        TherapyWS.sendMessage('notebook', {action: 'save'});
      }
    }
  });
})();
</script>""")
end
