@testset "LSP Rename" begin

    import Tachikoma

    # Helper: render app and return TestBackend
    function render_app_rename(app; width=120, height=40)
        tb = Tachikoma.TestBackend(width, height)
        frame = Tachikoma.Frame(tb.buf, Tachikoma.Rect(1, 1, width, height), [], [])
        Tachikoma.view(app, frame)
        tb
    end

    # ── parse_workspace_edit ─────────────────────────────────────────

    @testset "parse_workspace_edit — single file edit" begin
        response = Dict{String,Any}(
            "changes" => Dict{String,Any}(
                "file:///tmp/test.jl" => [
                    Dict{String,Any}(
                        "range" => Dict{String,Any}(
                            "start" => Dict{String,Any}("line" => 0, "character" => 0),
                            "end" => Dict{String,Any}("line" => 0, "character" => 3)
                        ),
                        "newText" => "bar"
                    )
                ]
            )
        )
        edits = Sessions.parse_workspace_edit(response)
        @test length(edits) == 1
        @test edits[1].uri == "file:///tmp/test.jl"
        @test edits[1].new_text == "bar"
        @test edits[1].start_line == 1
        @test edits[1].start_col == 0
    end

    @testset "parse_workspace_edit — multiple edits in one file" begin
        response = Dict{String,Any}(
            "changes" => Dict{String,Any}(
                "file:///tmp/test.jl" => [
                    Dict{String,Any}(
                        "range" => Dict{String,Any}(
                            "start" => Dict{String,Any}("line" => 0, "character" => 0),
                            "end" => Dict{String,Any}("line" => 0, "character" => 3)
                        ),
                        "newText" => "bar"
                    ),
                    Dict{String,Any}(
                        "range" => Dict{String,Any}(
                            "start" => Dict{String,Any}("line" => 5, "character" => 4),
                            "end" => Dict{String,Any}("line" => 5, "character" => 7)
                        ),
                        "newText" => "bar"
                    )
                ]
            )
        )
        edits = Sessions.parse_workspace_edit(response)
        @test length(edits) == 2
    end

    @testset "parse_workspace_edit — documentChanges format" begin
        response = Dict{String,Any}(
            "documentChanges" => [
                Dict{String,Any}(
                    "textDocument" => Dict{String,Any}("uri" => "file:///tmp/test.jl"),
                    "edits" => [
                        Dict{String,Any}(
                            "range" => Dict{String,Any}(
                                "start" => Dict{String,Any}("line" => 2, "character" => 0),
                                "end" => Dict{String,Any}("line" => 2, "character" => 5)
                            ),
                            "newText" => "renamed"
                        )
                    ]
                )
            ]
        )
        edits = Sessions.parse_workspace_edit(response)
        @test length(edits) == 1
        @test edits[1].uri == "file:///tmp/test.jl"
        @test edits[1].new_text == "renamed"
        @test edits[1].start_line == 3
    end

    @testset "parse_workspace_edit — null response" begin
        @test Sessions.parse_workspace_edit(nothing) == Sessions.LspTextEdit[]
    end

    @testset "parse_workspace_edit — empty changes" begin
        response = Dict{String,Any}("changes" => Dict{String,Any}())
        @test Sessions.parse_workspace_edit(response) == Sessions.LspTextEdit[]
    end

    @testset "parse_workspace_edit — non-dict response" begin
        @test Sessions.parse_workspace_edit("bad") == Sessions.LspTextEdit[]
        @test Sessions.parse_workspace_edit(42) == Sessions.LspTextEdit[]
    end

    # ── LspTextEdit struct ───────────────────────────────────────────

    @testset "LspTextEdit construction" begin
        edit = Sessions.LspTextEdit("file:///test.jl", 1, 0, 1, 3, "bar")
        @test edit.uri == "file:///test.jl"
        @test edit.start_line == 1
        @test edit.start_col == 0
        @test edit.end_line == 1
        @test edit.end_col == 3
        @test edit.new_text == "bar"
    end

    # ── lsp_rename_with_timeout! — graceful degradation ──────────────

    @testset "lsp_rename_with_timeout! — client not ready" begin
        client = LspClient(; enabled=false)
        @test Sessions.lsp_rename_with_timeout!(client, "file://test.jl", 1, 0, "new") == Sessions.LspTextEdit[]
    end

    @testset "lsp_rename_with_timeout! — client starting" begin
        client = LspClient(; enabled=true)
        @test client.status == lsp_starting
        @test Sessions.lsp_rename_with_timeout!(client, "file://test.jl", 1, 0, "new") == Sessions.LspTextEdit[]
    end

    @testset "lsp_rename_with_timeout! — client error" begin
        client = LspClient(; enabled=true)
        client.status = lsp_error
        @test Sessions.lsp_rename_with_timeout!(client, "file://test.jl", 1, 0, "new") == Sessions.LspTextEdit[]
    end

    # ── RenamePrompt struct ──────────────────────────────────────────

    @testset "RenamePrompt construction" begin
        rp = Sessions.RenamePrompt("foo", "foo", 3)
        @test rp.old_name == "foo"
        @test rp.new_name == "foo"
        @test rp.cursor == 3
    end

    # ── _word_at_cursor ──────────────────────────────────────────────

    @testset "_word_at_cursor — middle of word" begin
        lines = [collect("hello world")]
        word = Sessions._word_at_cursor(lines, 1, 3)
        @test word == "hello"
    end

    @testset "_word_at_cursor — start of word" begin
        lines = [collect("hello world")]
        word = Sessions._word_at_cursor(lines, 1, 0)
        @test word == "hello"
    end

    @testset "_word_at_cursor — end of line" begin
        lines = [collect("hello")]
        word = Sessions._word_at_cursor(lines, 1, 5)
        @test word == "hello"
    end

    @testset "_word_at_cursor — no word" begin
        lines = [collect("  ")]
        word = Sessions._word_at_cursor(lines, 1, 1)
        @test word == ""
    end

    # ── F2 triggers rename prompt ────────────────────────────────────

    @testset "F2 triggers rename prompt in notebook" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "hello = 1")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert
        cw.editor.cursor_col = 2  # inside "hello"

        Tachikoma.update!(app, Tachikoma.KeyEvent(:f2, '\0'))
        @test app.rename_prompt !== nothing
        @test app.rename_prompt.old_name == "hello"
        @test app.mode == :rename
    end

    @testset "F2 triggers rename prompt in file editor" begin
        path = tempname() * ".jl"
        write(path, "hello = 1\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.cursor_col = 2  # inside "hello"

        Tachikoma.update!(app, Tachikoma.KeyEvent(:f2, '\0'))
        @test app.rename_prompt !== nothing
        @test app.rename_prompt.old_name == "hello"
        @test app.mode == :rename
        rm(path; force=true)
    end

    @testset "F2 with no word under cursor shows message" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "  ")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert
        cw.editor.cursor_col = 1  # on space

        Tachikoma.update!(app, Tachikoma.KeyEvent(:f2, '\0'))
        @test app.rename_prompt === nothing
        @test occursin("No symbol", app.message)
    end

    # ── Rename prompt key handling ───────────────────────────────────

    @testset "Escape dismisses rename prompt" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        app.mode = :rename
        app.rename_prompt = Sessions.RenamePrompt("x", "x", 1)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:escape, '\0'))
        @test app.rename_prompt === nothing
        @test app.mode == :insert
    end

    @testset "Typing in rename prompt updates new_name" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        app.mode = :rename
        app.rename_prompt = Sessions.RenamePrompt("x", "x", 1)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:backspace, '\0'))
        @test app.rename_prompt.new_name == ""
        @test app.rename_prompt.cursor == 0

        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, 'y'))
        @test app.rename_prompt.new_name == "y"
        @test app.rename_prompt.cursor == 1
    end

    @testset "Enter submits rename (no LSP — shows message)" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "foo = 1")
        app = Sessions.SessionsApp(nb)
        app.mode = :rename
        app.rename_prompt = Sessions.RenamePrompt("foo", "bar", 3)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter, '\0'))
        @test app.rename_prompt === nothing
        @test app.mode == :insert
        # Without LSP, falls back to local find-replace
    end

    @testset "Enter with same name dismisses" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        app.mode = :rename
        app.rename_prompt = Sessions.RenamePrompt("x", "x", 1)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter, '\0'))
        @test app.rename_prompt === nothing
        @test app.mode == :insert
    end

    # ── Render smoke tests ───────────────────────────────────────────

    @testset "Render rename prompt — notebook smoke test" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "hello = 1")
        app = Sessions.SessionsApp(nb)
        app.mode = :rename
        app.rename_prompt = Sessions.RenamePrompt("hello", "world", 5)

        tb = render_app_rename(app)
        @test Tachikoma.row_text(tb, 1) isa String
    end

    @testset "Render rename prompt — file editor smoke test" begin
        path = tempname() * ".jl"
        write(path, "hello = 1\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        app.mode = :rename
        app.rename_prompt = Sessions.RenamePrompt("hello", "world", 5)

        tb = render_app_rename(app)
        @test Tachikoma.row_text(tb, 1) isa String
        rm(path; force=true)
    end

    # ── _apply_text_edits! ───────────────────────────────────────────

    @testset "_apply_rename_local! — replaces in current editor" begin
        path = tempname() * ".jl"
        write(path, "foo = 1\nbar = foo + 1\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)

        Sessions._apply_rename_local!(app, "foo", "baz")
        text = Tachikoma.text(fev.editor)
        @test occursin("baz = 1", text)
        @test occursin("bar = baz + 1", text)
        @test !occursin("foo", text)
        rm(path; force=true)
    end

    @testset "_apply_rename_local! — notebook cell" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "foo = 1\nbar = foo + 1")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert

        Sessions._apply_rename_local!(app, "foo", "baz")
        cw = app.notebook_view.cell_widgets[1]
        text = Tachikoma.text(cw.editor)
        @test occursin("baz = 1", text)
        @test occursin("bar = baz + 1", text)
    end

    # ── Exported symbols ──────────────────────────────────────────────

    @testset "Rename types and functions are exported" begin
        @test isdefined(Sessions, :LspTextEdit)
        @test isdefined(Sessions, :parse_workspace_edit)
        @test isdefined(Sessions, :lsp_rename!)
        @test isdefined(Sessions, :lsp_rename_with_timeout!)
    end

end
