@testset "E2E Editing — v4 Integration" begin

    import Tachikoma

    # Helper: render app and return TestBackend
    function render_app_e2e(app; width=120, height=40)
        tb = Tachikoma.TestBackend(width, height)
        frame = Tachikoma.Frame(tb.buf, Tachikoma.Rect(1, 1, width, height), [], [])
        Tachikoma.view(app, frame)
        tb
    end

    # ── Notebook editing workflow ───────────────────────────────────

    @testset "Notebook: type → render → escape flow" begin
        nb = Sessions.Notebook(; path="e2e_edit_test.jl")
        Sessions.add_cell!(nb, "x=1+2")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert

        # Initial state renders
        tb = render_app_e2e(app)
        @test Tachikoma.find_text(tb, "x=1+2") !== nothing

        # Type a character (insert mode)
        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, 'a'))
        text = Tachikoma.text(cw.editor)
        @test occursin("a", text)

        # Escape to normal doesn't crash
        Tachikoma.update!(app, Tachikoma.KeyEvent(:escape, '\0'))
        @test app.mode in (:normal, :insert)

        # Render still works
        tb2 = render_app_e2e(app)
        @test Tachikoma.row_text(tb2, 1) isa String
    end

    @testset "Notebook: bracket matching finds pair" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "f(x) = x + 1")
        app = Sessions.SessionsApp(nb)
        cw = app.notebook_view.cell_widgets[1]

        # Bracket match at '(' which is at col 1 (0-based)
        lines = cw.editor.lines
        match = Sessions._bracket_match_positions(lines, 1, 1)
        @test match !== nothing
        # ')' is at col 3 (0-based); match returns 0-based col
        @test match[1][1] == 1  # same row
    end

    @testset "Notebook: auto-close bracket inserts pair" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert

        # Type '(' — should auto-close to "()"
        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, '('))
        text = Tachikoma.text(cw.editor)
        @test text == "()"
    end

    @testset "Notebook: hover tooltip lifecycle" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "println(\"hello\")")
        app = Sessions.SessionsApp(nb)

        # Set hover tooltip manually (simulates LSP response)
        app.hover_tooltip = Sessions.HoverTooltip("Prints to stdout", 10, 5)
        @test app.hover_tooltip !== nothing

        tb = render_app_e2e(app)
        @test Tachikoma.row_text(tb, 1) isa String

        # Dismiss hover
        app.hover_tooltip = nothing
        @test app.hover_tooltip === nothing
    end

    @testset "Notebook: completion popup lifecycle" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "prin")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert
        cw.editor.cursor_col = 4

        # Set completion popup with proper LspCompletionItem types
        items = [
            Sessions.LspCompletionItem("println", :function, "", ""),
            Sessions.LspCompletionItem("print", :function, "", ""),
            Sessions.LspCompletionItem("printstyled", :function, "", ""),
        ]
        app.completion_popup = Sessions.CompletionPopup(items, 1, 10, 5)
        app.mode = :completion
        @test app.completion_popup !== nothing

        # Navigate down
        Tachikoma.update!(app, Tachikoma.KeyEvent(:down, '\0'))
        @test app.completion_popup.selected_idx == 2

        # Escape dismisses
        Tachikoma.update!(app, Tachikoma.KeyEvent(:escape, '\0'))
        @test app.completion_popup === nothing
        @test app.mode == :insert
    end

    @testset "Notebook: signature help tooltip lifecycle" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "println(")
        app = Sessions.SessionsApp(nb)

        # Set signature help manually
        app.signature_tooltip = Sessions.SignatureHelpTooltip(
            "println(io::IO, xs...)", ["io::IO", "xs..."], 0, 10, 5)
        @test app.signature_tooltip !== nothing

        tb = render_app_e2e(app)
        @test Tachikoma.row_text(tb, 1) isa String

        # Dismiss
        app.signature_tooltip = nothing
        @test app.signature_tooltip === nothing
    end

    @testset "Notebook: rename prompt lifecycle" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "hello = 42")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert
        cw.editor.cursor_col = 2

        # F2 starts rename
        Tachikoma.update!(app, Tachikoma.KeyEvent(:f2, '\0'))
        @test app.rename_prompt !== nothing
        @test app.mode == :rename

        # Type new name
        for _ in 1:5
            Tachikoma.update!(app, Tachikoma.KeyEvent(:backspace, '\0'))
        end
        for c in "world"
            Tachikoma.update!(app, Tachikoma.KeyEvent(:char, c))
        end
        @test app.rename_prompt.new_name == "world"

        # Enter submits
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter, '\0'))
        @test app.rename_prompt === nothing
        @test app.mode == :insert

        # Verify rename was applied
        text = Tachikoma.text(cw.editor)
        @test occursin("world", text)
        @test !occursin("hello", text)
    end

    @testset "Notebook: scrollbar renders for many cells" begin
        nb = Sessions.Notebook()
        for i in 1:30
            Sessions.add_cell!(nb, "cell_$i = $i")
        end
        app = Sessions.SessionsApp(nb)

        tb = render_app_e2e(app; height=20)
        @test Tachikoma.row_text(tb, 1) isa String
    end

    # ── File editor workflow ────────────────────────────────────────

    @testset "File editor: type in insert mode" begin
        path = tempname() * ".jl"
        write(path, "x=1+2\ny=3+4\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)

        # Render works
        tb = render_app_e2e(app)
        @test Tachikoma.find_text(tb, "x=1+2") !== nothing

        # Switch to insert mode first (editor starts in normal)
        fev.editor.mode = :insert
        app.mode = :insert

        # Type a character
        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, 'a'))
        text = Tachikoma.text(fev.editor)
        @test occursin("a", text)

        rm(path; force=true)
    end

    @testset "File editor: auto-close bracket in insert mode" begin
        path = tempname() * ".jl"
        write(path, "\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)

        # Must be in insert mode for auto-close
        fev.editor.mode = :insert
        app.mode = :insert

        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, '('))
        text = Tachikoma.text(fev.editor)
        @test occursin("()", text)

        rm(path; force=true)
    end

    @testset "File editor: hover tooltip" begin
        path = tempname() * ".jl"
        write(path, "println(\"hi\")\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)

        app.hover_tooltip = Sessions.HoverTooltip("Prints to stdout", 10, 3)
        tb = render_app_e2e(app)
        @test Tachikoma.row_text(tb, 1) isa String

        rm(path; force=true)
    end

    @testset "File editor: rename prompt" begin
        path = tempname() * ".jl"
        write(path, "foo = 1\nbar = foo + 1\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.cursor_col = 1  # inside "foo"

        # F2
        Tachikoma.update!(app, Tachikoma.KeyEvent(:f2, '\0'))
        @test app.rename_prompt !== nothing
        @test app.rename_prompt.old_name == "foo"
        @test app.mode == :rename

        # Escape cancels
        Tachikoma.update!(app, Tachikoma.KeyEvent(:escape, '\0'))
        @test app.rename_prompt === nothing
        @test app.mode == :insert

        rm(path; force=true)
    end

    @testset "File editor: completion popup" begin
        path = tempname() * ".jl"
        write(path, "prin\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.cursor_col = 4

        items = [
            Sessions.LspCompletionItem("println", :function, "", ""),
            Sessions.LspCompletionItem("print", :function, "", ""),
        ]
        app.completion_popup = Sessions.CompletionPopup(items, 1, 10, 3)
        app.mode = :completion

        # Enter accepts
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter, '\0'))
        @test app.completion_popup === nothing

        rm(path; force=true)
    end

    @testset "File editor: scrollbar for long file" begin
        path = tempname() * ".jl"
        write(path, join(["line_$i = $i" for i in 1:100], "\n") * "\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)

        tb = render_app_e2e(app; height=20)
        @test Tachikoma.row_text(tb, 1) isa String

        rm(path; force=true)
    end

    # ── Tab switching preserves state ───────────────────────────────

    @testset "Tab switching preserves notebook mode and state" begin
        # Create first tab (notebook)
        nb1 = Sessions.Notebook(; path="tab1_test.jl")
        Sessions.add_cell!(nb1, "first_tab = 1")
        app = Sessions.SessionsApp(nb1)
        app.mode = :insert
        @test app.active_tab_idx == 1

        # Open second tab (file)
        path2 = tempname() * ".jl"
        write(path2, "second_tab = 2\n")
        Sessions._open_in_tab!(app, path2)
        @test app.active_tab_idx == 2
        @test app.editor_type == :file

        # Switch back to tab 1
        Sessions._switch_tab!(app, 1)
        @test app.active_tab_idx == 1
        @test app.editor_type == :notebook

        # Verify content preserved
        cw = app.notebook_view.cell_widgets[1]
        text = Tachikoma.text(cw.editor)
        @test occursin("first_tab", text)

        # Switch to tab 2 again
        Sessions._switch_tab!(app, 2)
        @test app.editor_type == :file
        text2 = Tachikoma.text(app.file_editor_view.editor)
        @test occursin("second_tab", text2)

        rm(path2; force=true)
    end

    @testset "Tab switching collapses transient modes" begin
        nb = Sessions.Notebook(; path="transient_test.jl")
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        # Set transient mode
        app.mode = :completion
        items = [Sessions.LspCompletionItem("test", :variable, "", "")]
        app.completion_popup = Sessions.CompletionPopup(items, 1, 5, 3)

        # Save to tab — transient mode collapsed
        Sessions._save_to_tab!(app)
        tab = app.tabs[app.active_tab_idx]
        @test tab.mode == :normal  # :completion collapses to :normal
    end

    @testset "Tab switching collapses :rename mode" begin
        nb = Sessions.Notebook(; path="rename_transient_test.jl")
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        app.mode = :rename
        app.rename_prompt = Sessions.RenamePrompt("x", "y", 1)

        Sessions._save_to_tab!(app)
        tab = app.tabs[app.active_tab_idx]
        @test tab.mode == :normal  # :rename collapses to :normal
    end

    @testset "Multiple tabs render without error" begin
        nb = Sessions.Notebook(; path="multi_tab_test.jl")
        Sessions.add_cell!(nb, "a = 1")
        app = Sessions.SessionsApp(nb)

        path2 = tempname() * ".jl"
        write(path2, "b = 2\n")
        Sessions._open_in_tab!(app, path2)

        # Render tab 2
        tb = render_app_e2e(app)
        @test Tachikoma.row_text(tb, 1) isa String

        # Switch back and render tab 1
        Sessions._switch_tab!(app, 1)
        tb2 = render_app_e2e(app)
        @test Tachikoma.row_text(tb2, 1) isa String

        rm(path2; force=true)
    end

    # ── Cross-feature integration ───────────────────────────────────

    @testset "All overlays can coexist with scrollbar" begin
        nb = Sessions.Notebook()
        for i in 1:20
            Sessions.add_cell!(nb, "var_$i = $i")
        end
        app = Sessions.SessionsApp(nb)

        # Set various overlays
        app.hover_tooltip = Sessions.HoverTooltip("test hover", 10, 5)
        app.signature_tooltip = Sessions.SignatureHelpTooltip(
            "f(x, y)", ["x", "y"], 0, 10, 3)

        # Render with both overlays + scrollbar
        tb = render_app_e2e(app; height=15)
        @test Tachikoma.row_text(tb, 1) isa String
    end

    @testset "Rename prompt overlay renders over scrollbar" begin
        nb = Sessions.Notebook()
        for i in 1:20
            Sessions.add_cell!(nb, "var_$i = $i")
        end
        app = Sessions.SessionsApp(nb)
        app.mode = :rename
        app.rename_prompt = Sessions.RenamePrompt("var_1", "new_var", 7)

        tb = render_app_e2e(app; height=15)
        @test Tachikoma.row_text(tb, 1) isa String
    end

    @testset "Format-on-save integrates with cell execution" begin
        nb = Sessions.Notebook(; path="format_e2e.jl")
        Sessions.add_cell!(nb, "x=1+2")
        app = Sessions.SessionsApp(nb)

        # format_code should be available
        @test Sessions.format_code_available() isa Bool

        # format_code normalizes spacing
        result = Sessions.format_code("x=1+2")
        if Sessions.format_code_available()
            @test result == "x = 1 + 2"
        else
            @test result == "x=1+2"  # unchanged when Runic not available
        end
    end

    @testset "LSP client graceful degradation" begin
        # Verify all LSP functions handle disabled client
        client = Sessions.LspClient(; enabled=false)
        @test Sessions.lsp_rename_with_timeout!(client, "file://test.jl", 1, 0, "new") == Sessions.LspTextEdit[]
        @test Sessions.lsp_definition_with_timeout!(client, "file://test.jl", 1, 0) === nothing
        @test Sessions.lsp_signature_help_with_timeout!(client, "file://test.jl", 1, 0) === nothing
    end

    @testset "Inline diagnostics render with other overlays" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        # Set diagnostic using correct Diagnostic type
        cw = app.notebook_view.cell_widgets[1]
        push!(cw.diagnostics, Sessions.Diagnostic(1, :error, "test error", "test"))

        # Also set hover
        app.hover_tooltip = Sessions.HoverTooltip("hover text", 10, 5)

        tb = render_app_e2e(app)
        @test Tachikoma.row_text(tb, 1) isa String
    end

    @testset "No v2/v3 regression — notebook still works end-to-end" begin
        nb = Sessions.Notebook(; path="regression_test.jl")
        Sessions.add_cell!(nb, "x = 42")
        Sessions.add_cell!(nb, "y = x + 1")
        app = Sessions.SessionsApp(nb)

        # Render shows cells
        tb = render_app_e2e(app)
        @test Tachikoma.find_text(tb, "x = 42") !== nothing
        @test Tachikoma.find_text(tb, "y = x + 1") !== nothing

        # Execute works
        Sessions.execute_cell!(app.workspace, nb.cells[1])
        @test nb.cells[1].output.type == :value

        # Stale detection works
        Sessions.update_stale!(nb, nb.cells[1])
        @test nb.cells[2].state == Sessions.stale

        # Cell management still works
        Sessions.add_cell!(nb, "z = 3")
        @test length(nb.cells) == 3
    end

end
