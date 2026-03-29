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
    var sb = localStorage.getItem('sessions-sidebar');
    var rp = localStorage.getItem('sessions-repl');
    var fp = document.getElementById('fpanel');
    var repl = document.getElementById('repl-panel');
    if (fp && sb === '1') fp.style.display = '';
    if (repl && rp === '1') repl.style.display = '';
    customElements.whenDefined('sl-tree').then(function() {
        var loader = document.getElementById('explorer-loading');
        if (loader) loader.style.display = 'none';
    });
})();
</script>"""))
end
