# Layout.jl — HTML shell for Sessions.jl Web UI
#
# Always-dark IDE layout. Uses inline styles for the structural colors so the
# layout looks correct even when Tailwind falls back to CDN (which strips
# custom @theme tokens like warm-*/accent-*).

# Color constants matching the TUI theme
const _BG_BASE      = "#121216"  # warm-950
const _BG_SURFACE   = "#181a1d"  # warm-900
const _BG_ELEVATED  = "#1e1f23"  # between warm-900 and warm-800
const _BG_CELL      = "#0e0e12"  # darker than base for code blocks
const _BORDER       = "#2b2d30"  # warm-800
const _BORDER_LIGHT = "#3a3d42"  # warm-700ish
const _TEXT_PRIMARY  = "#bcbec4"  # warm-300
const _TEXT_SECONDARY= "#7a7e85"  # warm-500
const _TEXT_DIM      = "#4e5157"  # warm-700
const _ACCENT        = "#389826"  # Julia green
const _ACCENT_LIGHT  = "#4ad64a"  # accent-400
const _RED           = "#cb3c33"  # Julia red
const _BLUE          = "#4063d8"  # Julia blue
const _PURPLE        = "#9558b2"  # Julia purple

function Layout(children...; title="Sessions.jl")
    Fragment(
        # Force dark mode + base styles
        RawHtml("""<style>
html, body { margin: 0; padding: 0; height: 100%; overflow: hidden; }
html { background: $(_BG_BASE); color: $(_TEXT_PRIMARY); }
* { box-sizing: border-box; }
/* Syntax highlighting */
.hl-keyword  { color: #c792ea; }
.hl-string   { color: #c3e88d; }
.hl-comment  { color: #6b6560; font-style: italic; }
.hl-number   { color: #f78c6c; }
.hl-funcall  { color: #82aaff; }
.hl-type     { color: #ffcb6b; }
.hl-symbol   { color: #ff5370; }
.hl-macro    { color: #c792ea; font-weight: 600; }
.hl-operator { color: #89ddff; }
/* Scrollbar */
::-webkit-scrollbar { width: 8px; height: 8px; }
::-webkit-scrollbar-track { background: $(_BG_BASE); }
::-webkit-scrollbar-thumb { background: $(_BORDER); border-radius: 4px; }
::-webkit-scrollbar-thumb:hover { background: $(_BORDER_LIGHT); }
/* Notebook prose */
.nb-prose h1 { font-size: 1.875rem; font-weight: 600; color: $(_TEXT_PRIMARY); margin: 0.5rem 0 1rem; }
.nb-prose h2 { font-size: 1.5rem; font-weight: 600; color: $(_TEXT_PRIMARY); margin: 1.5rem 0 0.75rem; border-bottom: 1px solid $(_BORDER); padding-bottom: 0.5rem; }
.nb-prose h3 { font-size: 1.25rem; font-weight: 600; color: $(_TEXT_PRIMARY); margin: 1rem 0 0.5rem; }
.nb-prose p { color: $(_TEXT_SECONDARY); line-height: 1.7; margin-bottom: 1rem; }
.nb-prose ul, .nb-prose ol { color: $(_TEXT_SECONDARY); margin-bottom: 1rem; padding-left: 1.5rem; }
.nb-prose li { margin-bottom: 0.25rem; }
.nb-prose blockquote { border-left: 3px solid $(_ACCENT); padding-left: 1rem; color: $(_TEXT_SECONDARY); font-style: italic; }
.nb-prose code { font-family: 'JuliaMono', 'Fira Code', monospace; font-size: 0.875rem; background: $(_BG_ELEVATED); padding: 0.125rem 0.375rem; border-radius: 3px; }
.nb-prose a { color: $(_ACCENT_LIGHT); text-decoration: none; }
.nb-prose a:hover { text-decoration: underline; }
.nb-prose strong { color: $(_TEXT_PRIMARY); font-weight: 600; }
</style>"""),
        # App container
        Div(:style => "height: 100vh; overflow: hidden; background: $(_BG_BASE); color: $(_TEXT_PRIMARY); font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;",
            Div(:id => "page-content", :style => "height: 100%;",
                children...)),
        _notebook_channel_script())
end

"""Client-side JavaScript for handling notebook WebSocket channel messages."""
function _notebook_channel_script()
    RawHtml("""<script>
(function() {
  if (window._sessionsNotebookHandler) return;
  window._sessionsNotebookHandler = true;

  var stateColors = {
    'cell_idle':    '$(_TEXT_DIM)',
    'cell_queued':  '#eab308',
    'cell_running': '$(_BLUE)',
    'cell_done':    '$(_ACCENT)',
    'cell_errored': '$(_RED)'
  };

  window.addEventListener('therapy:channel:notebook', function(e) {
    var data = e.detail;
    if (!data || !data.event) return;

    if (data.event === 'cell_state') {
      var badge = document.querySelector('[data-cell-state][data-cell-id="' + data.cell_id + '"]');
      if (badge) {
        badge.style.background = stateColors[data.state] || stateColors['cell_idle'];
        badge.dataset.cellState = data.state;
        badge.style.animation = (data.state === 'cell_queued' || data.state === 'cell_running') ? 'pulse 1.5s infinite' : 'none';
      }
    }

    else if (data.event === 'cell_output') {
      var output = document.querySelector('.cell-output[data-cell-id="' + data.cell_id + '"]');
      if (output) output.innerHTML = data.output_html || '';
      var badge = document.querySelector('[data-cell-state][data-cell-id="' + data.cell_id + '"]');
      if (badge && data.state) {
        badge.style.background = stateColors[data.state] || '$(_ACCENT)';
        badge.dataset.cellState = data.state;
        badge.style.animation = 'none';
      }
    }

    else if (data.event === 'cell_added' || data.event === 'cell_deleted' || data.event === 'cell_order') {
      window.location.reload();
    }

    else if (data.event === 'saved') {
      var ind = document.getElementById('save-indicator');
      if (ind) { ind.textContent = 'Saved'; setTimeout(function(){ ind.textContent = 'Save'; }, 2000); }
    }

    else if (data.event === 'full_state') {
      console.log('[Sessions] Full state:', data.cells ? data.cells.length : 0, 'cells');
      if (data.cells) {
        data.cells.forEach(function(cell) {
          var badge = document.querySelector('[data-cell-state][data-cell-id="' + cell.cell_id + '"]');
          if (badge) {
            badge.style.background = stateColors[cell.state] || stateColors['cell_idle'];
            badge.dataset.cellState = cell.state;
          }
          if (cell.output_html) {
            var output = document.querySelector('.cell-output[data-cell-id="' + cell.cell_id + '"]');
            if (output && output.innerHTML === '') output.innerHTML = cell.output_html;
          }
        });
      }
    }
  });

  document.addEventListener('keydown', function(e) {
    if ((e.ctrlKey || e.metaKey) && e.key === 's') {
      e.preventDefault();
      if (window.TherapyWS && TherapyWS.sendMessage) TherapyWS.sendMessage('notebook', {action: 'save'});
    }
  });
})();
</script>
<style>@keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.4; } }</style>""")
end
