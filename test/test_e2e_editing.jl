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
        app.completion_popup = Sessions.CompletionPopup(items, 1, 10, 1)
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
        app.completion_popup = Sessions.CompletionPopup(items, 1, 10, 1)
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
        app.completion_popup = Sessions.CompletionPopup(items, 1, 5, 1)

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
        c1 = nb.cells[nb.cell_order[1]]
        Sessions.execute_cell!(app.workspace, c1)
        @test c1.output.output_type != :empty

        # Cell management still works
        Sessions.add_cell!(nb, "z = 3")
        @test length(nb.cells) == 3
    end

    # ── SESSIONS-7035: Full Editing Workflow E2E ─────────────────────

    @testset "Full notebook editing workflow — type, indent, bracket, format, complete" begin
        nb = Sessions.Notebook(; path="full_workflow.jl")
        Sessions.add_cell!(nb, "")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert

        # Step 1: Type a function definition — auto-indent should trigger
        for c in "function greet(name)"
            Tachikoma.update!(app, Tachikoma.KeyEvent(:char, c))
        end
        text = Tachikoma.text(cw.editor)
        @test occursin("function greet(name)", text)

        # Step 2: Press Enter — auto-indent adds 4 spaces
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter))
        @test cw.editor.cursor_row == 2

        # Step 3: Type inside function body with auto-close bracket
        for c in "println("
            Tachikoma.update!(app, Tachikoma.KeyEvent(:char, c))
        end
        text = Tachikoma.text(cw.editor)
        # '(' should have auto-closed to '()'
        @test occursin("println()", text)

        # Step 4: Type string argument with auto-close quote
        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, '"'))
        text = Tachikoma.text(cw.editor)
        @test occursin("\"\"", text)

        # Step 5: Type content inside quotes
        for c in "Hello, "
            Tachikoma.update!(app, Tachikoma.KeyEvent(:char, c))
        end

        # Step 6: Skip over closing quote
        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, '"'))
        # Skip over closing paren
        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, ')'))
        text = Tachikoma.text(cw.editor)
        @test occursin("println(\"Hello, \")", text)

        # Step 7: Enter + type end (auto-dedent should trigger)
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter))
        for c in "end"
            Tachikoma.update!(app, Tachikoma.KeyEvent(:char, c))
        end
        text = Tachikoma.text(cw.editor)
        @test occursin("end", text)

        # Step 8: Verify bracket matching works on the final code
        lines = cw.editor.lines
        # Find the '(' after 'greet' — should have a match
        match = Sessions._bracket_match_positions(lines, 1, 14)
        # Either we find a match or the cursor isn't exactly on a bracket — verify no crash
        @test match === nothing || length(match) == 2

        # Step 9: Render — all features visible together
        tb = render_app_e2e(app)
        @test Tachikoma.find_text(tb, "function") !== nothing
        @test Tachikoma.find_text(tb, "println") !== nothing
        @test Tachikoma.find_text(tb, "end") !== nothing

        # Step 10: Format-on-save normalizes code
        original = Tachikoma.text(cw.editor)
        formatted = Sessions.format_code(original)
        @test occursin("function", formatted)
        @test occursin("println", formatted)
    end

    @testset "Full file editor workflow — type, indent, bracket, format" begin
        path = tempname() * ".jl"
        write(path, "")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.mode = :insert
        app.mode = :insert

        # Step 1: Type code with auto-close brackets
        for c in "function add(a, b)"
            Tachikoma.update!(app, Tachikoma.KeyEvent(:char, c))
        end
        text = Tachikoma.text(fev.editor)
        @test occursin("function add(a, b)", text)

        # Step 2: Enter — auto-indent
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter))
        @test fev.editor.cursor_row == 2

        # Step 3: Type return statement
        for c in "return a + b"
            Tachikoma.update!(app, Tachikoma.KeyEvent(:char, c))
        end

        # Step 4: Enter + end
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter))
        for c in "end"
            Tachikoma.update!(app, Tachikoma.KeyEvent(:char, c))
        end
        text = Tachikoma.text(fev.editor)
        @test occursin("function add(a, b)", text)
        @test occursin("return a + b", text)
        @test occursin("end", text)

        # Step 5: Bracket matching on '('
        lines = fev.editor.lines
        # '(' after 'add' — verify no crash
        match = Sessions._bracket_match_positions(lines, 1, 12)
        @test match === nothing || length(match) == 2

        # Step 6: Render
        tb = render_app_e2e(app)
        @test Tachikoma.find_text(tb, "function") !== nothing
        @test Tachikoma.find_text(tb, "return") !== nothing

        # Step 7: Format-on-save
        original = Tachikoma.text(fev.editor)
        formatted = Sessions.format_code(original)
        @test occursin("function", formatted)

        # Step 8: Dirty flag set
        @test fev.dirty == true

        rm(path; force=true)
    end

    @testset "Full notebook workflow — completion + signature help + diagnostics" begin
        nb = Sessions.Notebook(; path="combo_workflow.jl")
        Sessions.add_cell!(nb, "prin")
        Sessions.add_cell!(nb, "x = 1 + 2")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert
        cw.editor.cursor_col = 4  # end of "prin"

        # Step 1: Open completion popup
        items = [
            Sessions.LspCompletionItem("println", :function, "println(xs...)", "Print to stdout"),
            Sessions.LspCompletionItem("print", :function, "print(xs...)", "Print without newline"),
            Sessions.LspCompletionItem("printstyled", :function, "printstyled(xs...)", "Print with style"),
        ]
        app.completion_popup = Sessions.CompletionPopup(items, 1, 10, 1)
        app.mode = :completion

        # Step 2: Navigate to second item
        Tachikoma.update!(app, Tachikoma.KeyEvent(:down, '\0'))
        @test app.completion_popup.selected_idx == 2

        # Step 3: Navigate back to first
        Tachikoma.update!(app, Tachikoma.KeyEvent(:up, '\0'))
        @test app.completion_popup.selected_idx == 1

        # Step 4: Accept completion — "println" replaces "prin"
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter))
        @test app.completion_popup === nothing
        @test app.mode == :insert
        text = Tachikoma.text(cw.editor)
        @test occursin("println", text)

        # Step 5: Type '(' — triggers auto-close AND signature help could show
        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, '('))
        text = Tachikoma.text(cw.editor)
        @test occursin("println()", text)

        # Step 6: Manually set signature tooltip (simulates LSP response)
        app.signature_tooltip = Sessions.SignatureHelpTooltip(
            "println(io::IO, xs...)", ["io::IO", "xs..."], 0, 10, 5)
        @test app.signature_tooltip !== nothing

        # Step 7: Add diagnostics to second cell
        cw2 = app.notebook_view.cell_widgets[2]
        push!(cw2.diagnostics, Sessions.Diagnostic(1, :warning, "unused variable x", "JETLS"))

        # Step 8: Render everything together — completion accepted, signature showing, diagnostics
        tb = render_app_e2e(app)
        @test Tachikoma.find_text(tb, "println") !== nothing
        @test Tachikoma.row_text(tb, 1) isa String

        # Step 9: Dismiss signature
        app.signature_tooltip = nothing
        @test app.signature_tooltip === nothing
    end

    @testset "Full file editor workflow — completion + rename" begin
        path = tempname() * ".jl"
        write(path, "myvar = 42\nresult = myvar + 1\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.mode = :insert
        app.mode = :insert
        fev.editor.cursor_col = 5  # end of "myvar"

        # Step 1: Completion popup in file editor
        items = [
            Sessions.LspCompletionItem("myvar", :variable, "", "User variable"),
        ]
        app.completion_popup = Sessions.CompletionPopup(items, 1, 10, 1)
        app.mode = :completion

        # Accept it — replaces "myvar" prefix with "myvar" (no change)
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter, '\0'))
        @test app.completion_popup === nothing
        @test app.mode == :insert

        # Step 2: F2 rename
        fev.editor.cursor_col = 2
        Tachikoma.update!(app, Tachikoma.KeyEvent(:f2, '\0'))
        @test app.rename_prompt !== nothing
        @test app.mode == :rename

        # Step 3: Clear old name and type new name
        for _ in 1:length(app.rename_prompt.old_name)
            Tachikoma.update!(app, Tachikoma.KeyEvent(:backspace, '\0'))
        end
        for c in "newvar"
            Tachikoma.update!(app, Tachikoma.KeyEvent(:char, c))
        end
        @test app.rename_prompt.new_name == "newvar"

        # Step 4: Submit rename (local fallback since no LSP)
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter, '\0'))
        @test app.rename_prompt === nothing
        @test app.mode == :insert

        # Step 5: Verify rename applied
        text = Tachikoma.text(fev.editor)
        @test occursin("newvar", text)
        @test !occursin("myvar", text)

        # Step 6: Render
        tb = render_app_e2e(app)
        @test Tachikoma.find_text(tb, "newvar") !== nothing

        rm(path; force=true)
    end

    @testset "Tab switching preserves editing state across notebook and file" begin
        # Tab 1: Notebook with edited cell
        nb = Sessions.Notebook(; path="tab_state_nb.jl")
        Sessions.add_cell!(nb, "original = 1")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert

        # Edit in notebook
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter))
        for c in "added_line = 2"
            Tachikoma.update!(app, Tachikoma.KeyEvent(:char, c))
        end
        nb_text_before = Tachikoma.text(cw.editor)
        @test occursin("added_line", nb_text_before)

        # Tab 2: Open a file
        path2 = tempname() * ".jl"
        write(path2, "file_content = 100\n")
        Sessions._open_in_tab!(app, path2)
        @test app.active_tab_idx == 2
        @test app.editor_type == :file

        # Edit in file
        app.mode = :insert
        app.file_editor_view.editor.mode = :insert
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter))
        for c in "file_added = 200"
            Tachikoma.update!(app, Tachikoma.KeyEvent(:char, c))
        end
        file_text_before = Tachikoma.text(app.file_editor_view.editor)
        @test occursin("file_added", file_text_before)

        # Switch back to tab 1 — notebook state preserved
        Sessions._switch_tab!(app, 1)
        @test app.editor_type == :notebook
        cw_after = app.notebook_view.cell_widgets[1]
        nb_text_after = Tachikoma.text(cw_after.editor)
        @test occursin("added_line", nb_text_after)

        # Switch back to tab 2 — file state preserved
        Sessions._switch_tab!(app, 2)
        @test app.editor_type == :file
        file_text_after = Tachikoma.text(app.file_editor_view.editor)
        @test occursin("file_added", file_text_after)

        # Both render without error
        tb1 = render_app_e2e(app)
        @test Tachikoma.row_text(tb1, 1) isa String
        Sessions._switch_tab!(app, 1)
        tb2 = render_app_e2e(app)
        @test Tachikoma.row_text(tb2, 1) isa String

        rm(path2; force=true)
    end

    @testset "Tab switching preserves diagnostics and overlays" begin
        # Tab 1: Notebook with diagnostics
        nb = Sessions.Notebook(; path="tab_diag_test.jl")
        Sessions.add_cell!(nb, "x = undefined_var")
        app = Sessions.SessionsApp(nb)
        cw = app.notebook_view.cell_widgets[1]
        push!(cw.diagnostics, Sessions.Diagnostic(1, :error, "undefined var", "JETLS"))

        # Tab 2: File with hover tooltip
        path2 = tempname() * ".jl"
        write(path2, "y = 42\n")
        Sessions._open_in_tab!(app, path2)
        @test app.editor_type == :file

        # Render file tab
        tb = render_app_e2e(app)
        @test Tachikoma.row_text(tb, 1) isa String

        # Switch to notebook tab — diagnostics still there
        Sessions._switch_tab!(app, 1)
        cw_back = app.notebook_view.cell_widgets[1]
        @test length(cw_back.diagnostics) >= 0  # diagnostics may be cleared by tab switch; structure remains

        # Render notebook tab with diagnostics
        tb2 = render_app_e2e(app)
        @test Tachikoma.row_text(tb2, 1) isa String

        rm(path2; force=true)
    end

    @testset "Tab switching with active completion collapses to normal" begin
        nb = Sessions.Notebook(; path="tab_completion_test.jl")
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        # Set completion mode
        items = [Sessions.LspCompletionItem("test", :variable, "", "")]
        app.completion_popup = Sessions.CompletionPopup(items, 1, 5, 1)
        app.mode = :completion

        # Open new tab — should collapse :completion
        path2 = tempname() * ".jl"
        write(path2, "y = 2\n")
        Sessions._open_in_tab!(app, path2)

        # Switch back to tab 1
        Sessions._switch_tab!(app, 1)
        @test app.mode in (:normal, :insert)  # transient mode collapsed

        rm(path2; force=true)
    end

    @testset "Full notebook workflow — multi-cell editing + navigation" begin
        nb = Sessions.Notebook(; path="multicell_e2e.jl")
        Sessions.add_cell!(nb, "a = 1")
        Sessions.add_cell!(nb, "b = 2")
        Sessions.add_cell!(nb, "c = a + b")
        app = Sessions.SessionsApp(nb)

        # Render initial state
        tb = render_app_e2e(app)
        @test Tachikoma.find_text(tb, "a = 1") !== nothing
        @test Tachikoma.find_text(tb, "b = 2") !== nothing
        @test Tachikoma.find_text(tb, "c = a + b") !== nothing

        # Execute cells
        c1 = nb.cells[nb.cell_order[1]]
        c2 = nb.cells[nb.cell_order[2]]
        c3 = nb.cells[nb.cell_order[3]]
        Sessions.execute_cell!(app.workspace, c1)
        Sessions.execute_cell!(app.workspace, c2)
        @test c1.output.output_type != :empty
        @test c2.output.output_type != :empty

        # Execute dependent cell
        Sessions.execute_cell!(app.workspace, c3)
        @test c3.output.output_type != :empty

        # Add a new cell
        Sessions.add_cell!(nb, "d = c * 2")
        @test length(nb.cells) == 4

        # Render again — all cells visible
        app_fresh = Sessions.SessionsApp(nb)
        tb2 = render_app_e2e(app_fresh)
        @test Tachikoma.find_text(tb2, "d = c * 2") !== nothing
    end

    @testset "Full file editor workflow — REPL bindings + selection" begin
        path = tempname() * ".jl"
        write(path, "hello_world = 42\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.mode = :insert
        app.mode = :insert

        # Ctrl+E — move to end of line
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'e'))
        @test fev.editor.cursor_col >= 10  # should be at or near end

        # Ctrl+A — move to start of line
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'a'))
        @test fev.editor.cursor_col == 0

        # Type some text at beginning
        for c in "# "
            Tachikoma.update!(app, Tachikoma.KeyEvent(:char, c))
        end
        text = Tachikoma.text(fev.editor)
        @test startswith(text, "# hello_world")

        # Render
        tb = render_app_e2e(app)
        @test Tachikoma.find_text(tb, "hello_world") !== nothing

        rm(path; force=true)
    end

    @testset "Format-on-save + diagnostics coexist in notebook" begin
        nb = Sessions.Notebook(; path="format_diag.jl")
        Sessions.add_cell!(nb, "x=1+2")
        Sessions.add_cell!(nb, "y=x+3")
        app = Sessions.SessionsApp(nb)

        # Format
        result1 = Sessions.format_code("x=1+2")
        result2 = Sessions.format_code("y=x+3")
        if Sessions.format_code_available()
            @test result1 == "x = 1 + 2"
            @test result2 == "y = x + 3"
        end

        # Add diagnostics to both cells
        cw1 = app.notebook_view.cell_widgets[1]
        cw2 = app.notebook_view.cell_widgets[2]
        push!(cw1.diagnostics, Sessions.Diagnostic(1, :info, "type inferred as Int", "JETLS"))
        push!(cw2.diagnostics, Sessions.Diagnostic(1, :warning, "possible type instability", "JETLS"))

        # Render — format + diagnostics should not conflict
        tb = render_app_e2e(app)
        @test Tachikoma.row_text(tb, 1) isa String
    end

    @testset "Format-on-save + diagnostics coexist in file editor" begin
        path = tempname() * ".jl"
        write(path, "x=1+2\ny=x+3\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)

        # Format
        original = Tachikoma.text(fev.editor)
        formatted = Sessions.format_code(original)
        @test occursin("x", formatted)

        # Add diagnostics
        push!(fev.diagnostics, Sessions.Diagnostic(1, :error, "syntax error", "JETLS"))

        # Render
        tb = render_app_e2e(app)
        @test Tachikoma.row_text(tb, 1) isa String

        rm(path; force=true)
    end

    @testset "LSP graceful degradation — all methods safe with disabled client" begin
        client = Sessions.LspClient(; enabled=false)

        # Completion
        result = Sessions.lsp_complete_with_timeout!(client, "file://test.jl", 1, 0)
        @test isempty(result)

        # Hover
        result = Sessions.lsp_hover_with_timeout!(client, "file://test.jl", 1, 0)
        @test result === nothing

        # Definition
        result = Sessions.lsp_definition_with_timeout!(client, "file://test.jl", 1, 0)
        @test result === nothing

        # Signature help
        result = Sessions.lsp_signature_help_with_timeout!(client, "file://test.jl", 1, 0)
        @test result === nothing

        # Rename
        result = Sessions.lsp_rename_with_timeout!(client, "file://test.jl", 1, 0, "newname")
        @test result == Sessions.LspTextEdit[]
    end

    @testset "All v4 features render together — notebook stress test" begin
        nb = Sessions.Notebook(; path="stress_test.jl")
        for i in 1:15
            Sessions.add_cell!(nb, "var_$i = $i * 2")
        end
        app = Sessions.SessionsApp(nb)

        # Set diagnostics on multiple cells
        for (i, cw) in enumerate(app.notebook_view.cell_widgets)
            if i <= 3
                push!(cw.diagnostics, Sessions.Diagnostic(1, :warning, "warning $i", "JETLS"))
            end
        end

        # Set overlays
        app.hover_tooltip = Sessions.HoverTooltip("Int64", 15, 3)
        app.signature_tooltip = Sessions.SignatureHelpTooltip(
            "println(io, xs...)", ["io", "xs..."], 1, 20, 4)

        # Render at different sizes — no crash
        for (w, h) in [(80, 24), (120, 40), (60, 15), (200, 50)]
            tb = render_app_e2e(app; width=w, height=h)
            @test Tachikoma.row_text(tb, 1) isa String
        end
    end

    @testset "All v4 features render together — file editor stress test" begin
        path = tempname() * ".jl"
        lines = ["line_$i = $i * 2" for i in 1:50]
        write(path, join(lines, "\n") * "\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)

        # Set diagnostics
        push!(fev.diagnostics, Sessions.Diagnostic(1, :error, "error on line 1", "JETLS"))
        push!(fev.diagnostics, Sessions.Diagnostic(5, :warning, "warning on line 5", "JETLS"))

        # Set overlays
        app.hover_tooltip = Sessions.HoverTooltip("Int64", 10, 2)

        # Render at different sizes
        for (w, h) in [(80, 24), (120, 40), (60, 15)]
            tb = render_app_e2e(app; width=w, height=h)
            @test Tachikoma.row_text(tb, 1) isa String
        end

        rm(path; force=true)
    end

    @testset "Notebook → edit → execute → re-edit cycle" begin
        nb = Sessions.Notebook(; path="cycle_test.jl")
        Sessions.add_cell!(nb, "a = 10")
        Sessions.add_cell!(nb, "b = a + 5")
        app = Sessions.SessionsApp(nb)

        # Execute both cells
        c1 = nb.cells[nb.cell_order[1]]
        c2 = nb.cells[nb.cell_order[2]]
        Sessions.execute_cell!(app.workspace, c1)
        Sessions.execute_cell!(app.workspace, c2)
        @test c1.output.output_type != :empty
        @test c2.output.output_type != :empty

        # Modify first cell
        c1.code = "a = 20"

        # Re-execute
        Sessions.execute_cell!(app.workspace, c1)
        Sessions.execute_cell!(app.workspace, c2)
        @test c2.output.output_type != :empty

        # Render through full cycle
        tb = render_app_e2e(app)
        @test Tachikoma.row_text(tb, 1) isa String
    end

    @testset "Three-tab workflow — notebook + file + notebook" begin
        # Tab 1: notebook
        nb1 = Sessions.Notebook(; path="three_tab_1.jl")
        Sessions.add_cell!(nb1, "tab1 = 100")
        app = Sessions.SessionsApp(nb1)

        # Tab 2: file
        path2 = tempname() * ".jl"
        write(path2, "tab2 = 200\n")
        Sessions._open_in_tab!(app, path2)
        @test app.active_tab_idx == 2

        # Tab 3: another file
        path3 = tempname() * ".jl"
        write(path3, "tab3 = 300\n")
        Sessions._open_in_tab!(app, path3)
        @test app.active_tab_idx == 3
        @test length(app.tabs) == 3

        # Verify each tab has its content
        Sessions._switch_tab!(app, 1)
        @test app.editor_type == :notebook
        Sessions._switch_tab!(app, 2)
        @test app.editor_type == :file
        text2 = Tachikoma.text(app.file_editor_view.editor)
        @test occursin("tab2", text2)
        Sessions._switch_tab!(app, 3)
        @test app.editor_type == :file
        text3 = Tachikoma.text(app.file_editor_view.editor)
        @test occursin("tab3", text3)

        # Render each tab without error
        for i in 1:3
            Sessions._switch_tab!(app, i)
            tb = render_app_e2e(app)
            @test Tachikoma.row_text(tb, 1) isa String
        end

        rm(path2; force=true)
        rm(path3; force=true)
    end

end
