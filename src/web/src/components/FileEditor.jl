# FileEditor.jl — @island: CodeMirror editor for non-notebook files
#
# Full-height CM editor for .toml, .md, .py, etc.
# Save via Ctrl+S → WS send. No cell execution, no reactivity.

@island function FileEditor(; file_path::String = "", file_content::String = "")
    on_mount(() -> begin
        # Initialize CodeMirror for the file editor
        js("""
            (function(){
                var host = island.querySelector('.cm-file-editor');
                if (!host || host.querySelector('.cm-editor')) return;
                if (typeof C === 'undefined' || !C.EditorView) return;
                var src = host.dataset.src || '';
                var view = new C.EditorView({
                    doc: src,
                    extensions: [
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
                        C.EditorView.theme({
                            '&': { height: '100%', backgroundColor: 'transparent', color: 'var(--text-1)' },
                            '.cm-scroller': { overflow: 'auto', fontFamily: "'JetBrains Mono',monospace" },
                            '.cm-gutters': { backgroundColor: 'transparent', color: 'var(--text-3)', border: 'none' },
                            '.cm-content': { fontFamily: "'JetBrains Mono',monospace", fontSize: '13px', lineHeight: '1.65' },
                            '&.cm-focused .cm-cursor': { borderLeftColor: 'var(--accent)' },
                        }, {dark: document.documentElement.classList.contains('dark')}),
                    ],
                    parent: host
                });
                window._fileEditorView = view;
            })();
        """)
    end)

    return Div(:class => "file-editor-wrap", :style => "height:100%;",
        Div(:class => "cm-cell cm-file-editor",
            :data_file_path => file_path,
            :data_src => file_content,
            :style => "height:100%;overflow:auto;"))
end
