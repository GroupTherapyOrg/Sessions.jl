@testset "File Editor Feature Parity" begin

    function render_fev_app(app; width=120, height=40)
        tb = TestBackend(width, height)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, width, height), [], [])
        Tachikoma.view(app, frame)
        tb
    end

    @testset "FileEditorView has selection field" begin
        path = tempname() * ".jl"
        write(path, "hello world\n")
        fev = Sessions.FileEditorView(path)
        @test fev.selection isa Sessions.SelectionState
        @test !fev.selection.active
        rm(path; force=true)
    end

    @testset "Ctrl+A: move to line start" begin
        path = tempname() * ".jl"
        write(path, "hello world\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.cursor_col = 5

        evt = Tachikoma.KeyEvent(:ctrl, 'a')
        Sessions._handle_file_editor_key!(app, evt)
        @test fev.editor.cursor_col == 0
        rm(path; force=true)
    end

    @testset "Ctrl+E: move to line end" begin
        path = tempname() * ".jl"
        write(path, "hello world\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.cursor_col = 0

        evt = Tachikoma.KeyEvent(:ctrl, 'e')
        Sessions._handle_file_editor_key!(app, evt)
        @test fev.editor.cursor_col == length(fev.editor.lines[1])
        rm(path; force=true)
    end

    @testset "Ctrl+K: kill line forward" begin
        path = tempname() * ".jl"
        write(path, "hello world\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.cursor_col = 5

        evt = Tachikoma.KeyEvent(:ctrl, 'k')
        Sessions._handle_file_editor_key!(app, evt)
        @test String(fev.editor.lines[1]) == "hello"
        @test fev.dirty
        rm(path; force=true)
    end

    @testset "Ctrl+U: kill line backward" begin
        path = tempname() * ".jl"
        write(path, "hello world\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.cursor_col = 5

        evt = Tachikoma.KeyEvent(:ctrl, 'u')
        Sessions._handle_file_editor_key!(app, evt)
        @test String(fev.editor.lines[1]) == " world"
        @test fev.editor.cursor_col == 0
        @test fev.dirty
        rm(path; force=true)
    end

    @testset "Ctrl+V: paste from clipboard" begin
        path = tempname() * ".jl"
        write(path, "x = 1\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.cursor_col = 0
        fev.editor.cursor_row = 1

        # Copy some text to internal clipboard
        Sessions._clipboard_copy!("PASTED")

        evt = Tachikoma.KeyEvent(:ctrl, 'v')
        Sessions._handle_file_editor_key!(app, evt)
        text = Tachikoma.text(fev.editor)
        @test occursin("PASTED", text)
        @test fev.dirty
        rm(path; force=true)
    end

    @testset "Shift+Arrow: text selection" begin
        path = tempname() * ".jl"
        write(path, "hello world\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.cursor_col = 0

        # Shift+Right 3 times
        for _ in 1:3
            evt = Tachikoma.KeyEvent(:shift_right, '\0')
            Sessions._handle_file_editor_key!(app, evt)
        end

        @test fev.selection.active
        @test fev.selection.anchor_row == 1
        @test fev.selection.anchor_col == 0
        @test fev.editor.cursor_col == 3

        # Get selected text
        text = Sessions._selected_text(fev.editor.lines, fev.selection,
            fev.editor.cursor_row, fev.editor.cursor_col)
        @test text == "hel"
        rm(path; force=true)
    end

    @testset "Alt+Arrow: word motion" begin
        path = tempname() * ".jl"
        write(path, "hello world foo\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.cursor_col = 0

        # Alt+Right: jump to end of word
        evt = Tachikoma.KeyEvent(:alt_right, '\0')
        Sessions._handle_file_editor_key!(app, evt)
        @test fev.editor.cursor_col > 0  # moved past first word

        # Alt+Left: jump back
        col_before = fev.editor.cursor_col
        evt = Tachikoma.KeyEvent(:alt_left, '\0')
        Sessions._handle_file_editor_key!(app, evt)
        @test fev.editor.cursor_col < col_before
        rm(path; force=true)
    end

    @testset "Ctrl+C: copy selection" begin
        path = tempname() * ".jl"
        write(path, "abcdef\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.cursor_col = 3

        # Set up selection manually
        fev.selection.active = true
        fev.selection.anchor_row = 1
        fev.selection.anchor_col = 0

        evt = Tachikoma.KeyEvent(:ctrl, 'c')
        Sessions._handle_file_editor_key!(app, evt)

        # Clipboard should have "abc"
        clip = Sessions._clipboard_paste()
        @test clip == "abc"
        rm(path; force=true)
    end

    @testset "Ctrl+X: cut selection" begin
        path = tempname() * ".jl"
        write(path, "abcdef\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.cursor_col = 3

        # Set up selection
        fev.selection.active = true
        fev.selection.anchor_row = 1
        fev.selection.anchor_col = 0

        evt = Tachikoma.KeyEvent(:ctrl, 'x')
        Sessions._handle_file_editor_key!(app, evt)

        @test String(fev.editor.lines[1]) == "def"
        clip = Sessions._clipboard_paste()
        @test clip == "abc"
        @test fev.dirty
        rm(path; force=true)
    end

    @testset "Selection cleared on navigation key" begin
        path = tempname() * ".jl"
        write(path, "hello\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)

        fev.selection.active = true
        fev.selection.anchor_row = 1
        fev.selection.anchor_col = 0
        fev.editor.cursor_col = 3

        # Any non-shift key should clear selection
        evt = Tachikoma.KeyEvent(:left, '\0')
        Sessions._handle_file_editor_key!(app, evt)
        @test !fev.selection.active
        rm(path; force=true)
    end

    @testset "Ctrl+Y: yank/paste" begin
        path = tempname() * ".jl"
        write(path, "x = 1\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.cursor_col = 0

        Sessions._clipboard_copy!("YANKED")
        evt = Tachikoma.KeyEvent(:ctrl, 'y')
        Sessions._handle_file_editor_key!(app, evt)
        text = Tachikoma.text(fev.editor)
        @test occursin("YANKED", text)
        rm(path; force=true)
    end

    @testset "Ctrl+W: delete word backward" begin
        path = tempname() * ".jl"
        write(path, "hello world\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.cursor_col = 11  # end of "hello world"

        evt = Tachikoma.KeyEvent(:ctrl, 'w')
        Sessions._handle_file_editor_key!(app, evt)
        line1 = String(fev.editor.lines[1])
        # "world" should be deleted (word backward from end)
        @test !occursin("world", line1) || length(line1) < 11
        @test fev.dirty
        rm(path; force=true)
    end

    @testset "_fev_delete_selection! removes selected text" begin
        path = tempname() * ".jl"
        write(path, "ABCDEF\n")
        fev = Sessions.FileEditorView(path)

        fev.selection.active = true
        fev.selection.anchor_row = 1
        fev.selection.anchor_col = 0
        fev.editor.cursor_col = 3

        Sessions._fev_delete_selection!(fev)
        @test String(fev.editor.lines[1]) == "DEF"
        @test !fev.selection.active
        @test fev.editor.cursor_col == 0
        rm(path; force=true)
    end

    @testset "Breathing cursor renders without crash" begin
        path = tempname() * ".jl"
        write(path, "x = 1\ny = 2\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)

        # Render should include breathing cursor (editor.focused = true in insert mode)
        tb = render_fev_app(app; height=20)
        # Just verify it doesn't crash and content is visible
        @test Tachikoma.find_text(tb, "x = 1") !== nothing
        @test Tachikoma.find_text(tb, "y = 2") !== nothing
        rm(path; force=true)
    end

    @testset "Selection rendering visible in file editor" begin
        path = tempname() * ".jl"
        write(path, "hello world\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)

        # Set up selection
        fev.selection.active = true
        fev.selection.anchor_row = 1
        fev.selection.anchor_col = 0
        fev.editor.cursor_col = 5

        # Should render without crash
        tb = render_fev_app(app; height=20)
        @test Tachikoma.find_text(tb, "hello") !== nothing
        rm(path; force=true)
    end
end
