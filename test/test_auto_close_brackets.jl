@testset "Auto-Close Brackets" begin

    # Helper: type a string character by character
    function type_string!(editor, s::String)
        for ch in s
            Tachikoma.handle_key!(editor, Tachikoma.KeyEvent(:char, ch))
        end
    end

    function press_backspace!(editor)
        Tachikoma.handle_key!(editor, Tachikoma.KeyEvent(:backspace, '\0'))
    end

    function line_text(editor, row::Int)
        String(editor.lines[row])
    end

    # ── Parentheses ────────────────────────────────────────────────

    @testset "Typing '(' inserts '()' in CellWidget" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '('))
        @test line_text(cw.editor, 1) == "()"
        @test cw.editor.cursor_col == 1  # between parens
    end

    @testset "Typing '(' inserts '()' in FileEditorView" begin
        path = tempname() * ".jl"
        write(path, "")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.mode = :insert
        Sessions._handle_file_editor_key!(app, Tachikoma.KeyEvent(:char, '('))
        @test line_text(fev.editor, 1) == "()"
        @test fev.editor.cursor_col == 1
        rm(path; force=true)
    end

    @testset "Skip-over ')' when next char is ')'" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '('))
        # Now cursor is between () — type )
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, ')'))
        @test line_text(cw.editor, 1) == "()"
        @test cw.editor.cursor_col == 2  # past closing paren
    end

    @testset "Backspace on empty '()' deletes both" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '('))
        @test line_text(cw.editor, 1) == "()"
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:backspace, '\0'))
        @test line_text(cw.editor, 1) == ""
        @test cw.editor.cursor_col == 0
    end

    # ── Square brackets ────────────────────────────────────────────

    @testset "Typing '[' inserts '[]' in CellWidget" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '['))
        @test line_text(cw.editor, 1) == "[]"
        @test cw.editor.cursor_col == 1
    end

    @testset "Skip-over ']' when next char is ']'" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '['))
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, ']'))
        @test line_text(cw.editor, 1) == "[]"
        @test cw.editor.cursor_col == 2
    end

    @testset "Backspace on empty '[]' deletes both" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '['))
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:backspace, '\0'))
        @test line_text(cw.editor, 1) == ""
    end

    # ── Curly braces ───────────────────────────────────────────────

    @testset "Typing '{' inserts '{}' in CellWidget" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '{'))
        @test line_text(cw.editor, 1) == "{}"
        @test cw.editor.cursor_col == 1
    end

    @testset "Skip-over '}' when next char is '}'" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '{'))
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '}'))
        @test line_text(cw.editor, 1) == "{}"
        @test cw.editor.cursor_col == 2
    end

    @testset "Backspace on empty '{}' deletes both" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '{'))
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:backspace, '\0'))
        @test line_text(cw.editor, 1) == ""
    end

    # ── Double quotes ──────────────────────────────────────────────

    @testset "Typing '\"' inserts '\"\"' in CellWidget" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '"'))
        @test line_text(cw.editor, 1) == "\"\""
        @test cw.editor.cursor_col == 1
    end

    @testset "Skip-over '\"' when next char is '\"'" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '"'))
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '"'))
        @test line_text(cw.editor, 1) == "\"\""
        @test cw.editor.cursor_col == 2
    end

    @testset "Backspace on empty '\"\"' deletes both" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '"'))
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:backspace, '\0'))
        @test line_text(cw.editor, 1) == ""
    end

    # ── Content between brackets ───────────────────────────────────

    @testset "Typing content between auto-closed parens" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        type_string!(cw.editor, "f")
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '('))
        type_string!(cw.editor, "x, y")
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, ')'))
        @test line_text(cw.editor, 1) == "f(x, y)"
    end

    @testset "Backspace with content doesn't delete closing bracket" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '('))
        type_string!(cw.editor, "x")
        # Cursor is after 'x', before ')' — backspace should delete 'x' only
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:backspace, '\0'))
        @test line_text(cw.editor, 1) == "()"
    end

    # ── FileEditorView mode ────────────────────────────────────────

    @testset "Auto-close all bracket types in FileEditorView" begin
        path = tempname() * ".jl"
        write(path, "")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.mode = :insert

        # Test (
        Sessions._handle_file_editor_key!(app, Tachikoma.KeyEvent(:char, '('))
        @test line_text(fev.editor, 1) == "()"

        # Type content and skip over
        Sessions._handle_file_editor_key!(app, Tachikoma.KeyEvent(:char, ')'))
        @test line_text(fev.editor, 1) == "()"
        @test fev.editor.cursor_col == 2

        # Test [
        Sessions._handle_file_editor_key!(app, Tachikoma.KeyEvent(:char, '['))
        @test line_text(fev.editor, 1) == "()[]"

        # Test {
        Sessions._handle_file_editor_key!(app, Tachikoma.KeyEvent(:char, '}'))
        @test fev.editor.cursor_col == 4  # skip over ]
        Sessions._handle_file_editor_key!(app, Tachikoma.KeyEvent(:char, '{'))
        @test occursin("{}", line_text(fev.editor, 1))

        rm(path; force=true)
    end

    @testset "Backspace deletes pair in FileEditorView" begin
        path = tempname() * ".jl"
        write(path, "")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.mode = :insert

        Sessions._handle_file_editor_key!(app, Tachikoma.KeyEvent(:char, '('))
        @test line_text(fev.editor, 1) == "()"
        Sessions._handle_file_editor_key!(app, Tachikoma.KeyEvent(:backspace, '\0'))
        @test line_text(fev.editor, 1) == ""

        rm(path; force=true)
    end

    # ── Normal mode: no auto-close ─────────────────────────────────

    @testset "Auto-close does not fire in normal mode" begin
        editor = Tachikoma.CodeEditor(; mode=:normal, focused=true)
        result = Sessions._handle_auto_close!(editor, Tachikoma.KeyEvent(:char, '('))
        @test result == false
    end

    # ── Nested brackets ────────────────────────────────────────────

    @testset "Nested auto-close brackets" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        # f([])
        type_string!(cw.editor, "f")
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '('))
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, '['))
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, ']'))
        Tachikoma.handle_key!(cw, Tachikoma.KeyEvent(:char, ')'))
        @test line_text(cw.editor, 1) == "f([])"
    end
end
