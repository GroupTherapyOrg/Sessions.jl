@testset "Auto-Indent — Tachikoma built-in verification" begin

    # Helper: type a string character by character into a CodeEditor in insert mode
    function type_string!(editor, s::String)
        for ch in s
            Tachikoma.handle_key!(editor, Tachikoma.KeyEvent(:char, ch))
        end
    end

    # Helper: press Enter
    function press_enter!(editor)
        Tachikoma.handle_key!(editor, Tachikoma.KeyEvent(:enter, '\0'))
    end

    # Helper: get text of a specific line (1-indexed)
    function line_text(editor, row::Int)
        String(editor.lines[row])
    end

    # Helper: count leading spaces
    function leading_spaces(s::String)
        count = 0
        for ch in s
            ch == ' ' ? (count += 1) : break
        end
        count
    end

    # ── CodeEditor direct tests ──────────────────────────────────────

    @testset "Enter after 'function f()' adds +4 indent (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "function f()")
        press_enter!(editor)
        @test editor.cursor_col == 4
        @test leading_spaces(line_text(editor, 2)) == 4
    end

    @testset "Enter after 'if true' adds +4 indent (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "if true")
        press_enter!(editor)
        @test editor.cursor_col == 4
        @test leading_spaces(line_text(editor, 2)) == 4
    end

    @testset "Enter after 'for i in 1:10' adds +4 indent (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "for i in 1:10")
        press_enter!(editor)
        @test editor.cursor_col == 4
        @test leading_spaces(line_text(editor, 2)) == 4
    end

    @testset "Enter after 'while true' adds +4 indent (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "while true")
        press_enter!(editor)
        @test editor.cursor_col == 4
        @test leading_spaces(line_text(editor, 2)) == 4
    end

    @testset "Enter after 'begin' adds +4 indent (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "begin")
        press_enter!(editor)
        @test editor.cursor_col == 4
        @test leading_spaces(line_text(editor, 2)) == 4
    end

    @testset "Enter after 'let' adds +4 indent (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "let")
        press_enter!(editor)
        @test editor.cursor_col == 4
        @test leading_spaces(line_text(editor, 2)) == 4
    end

    @testset "Enter after 'try' adds +4 indent (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "try")
        press_enter!(editor)
        @test editor.cursor_col == 4
        @test leading_spaces(line_text(editor, 2)) == 4
    end

    @testset "Enter after 'struct Foo' adds +4 indent (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "struct Foo")
        press_enter!(editor)
        @test editor.cursor_col == 4
        @test leading_spaces(line_text(editor, 2)) == 4
    end

    @testset "Enter after 'map(x) do' adds +4 indent (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "map(x) do")
        press_enter!(editor)
        @test editor.cursor_col == 4
        @test leading_spaces(line_text(editor, 2)) == 4
    end

    @testset "Plain Enter copies current indentation (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "    x = 1")
        press_enter!(editor)
        @test editor.cursor_col == 4
        @test leading_spaces(line_text(editor, 2)) == 4
    end

    @testset "Enter on non-block line preserves indent (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "        y = 2")
        press_enter!(editor)
        @test editor.cursor_col == 8
        @test leading_spaces(line_text(editor, 2)) == 8
    end

    @testset "Nested indentation: function → if (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "function f()")
        press_enter!(editor)
        @test editor.cursor_col == 4
        type_string!(editor, "if true")
        press_enter!(editor)
        @test editor.cursor_col == 8
        @test leading_spaces(line_text(editor, 3)) == 8
    end

    @testset "Nested indentation: 3 levels deep (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "module M")
        press_enter!(editor)
        @test editor.cursor_col == 4
        type_string!(editor, "function f()")
        press_enter!(editor)
        @test editor.cursor_col == 8
        type_string!(editor, "for i in 1:10")
        press_enter!(editor)
        @test editor.cursor_col == 12
        @test leading_spaces(line_text(editor, 4)) == 12
    end

    @testset "Typing 'end' auto-dedents (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "function f()")
        press_enter!(editor)
        @test editor.cursor_col == 4
        type_string!(editor, "end")
        # After auto-dedent, line should have 0 indent
        @test leading_spaces(line_text(editor, 2)) == 0
        @test line_text(editor, 2) == "end"
    end

    @testset "Typing 'else' auto-dedents (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "if true")
        press_enter!(editor)
        @test editor.cursor_col == 4
        type_string!(editor, "x = 1")
        press_enter!(editor)
        type_string!(editor, "else")
        # 'else' should auto-dedent from 4 → 0
        @test leading_spaces(line_text(editor, 3)) == 0
    end

    @testset "Typing 'elseif' auto-dedents (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "if true")
        press_enter!(editor)
        type_string!(editor, "elseif")
        @test leading_spaces(line_text(editor, 2)) == 0
    end

    @testset "Typing 'catch' auto-dedents (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "try")
        press_enter!(editor)
        type_string!(editor, "catch")
        @test leading_spaces(line_text(editor, 2)) == 0
    end

    @testset "Typing 'finally' auto-dedents (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "try")
        press_enter!(editor)
        type_string!(editor, "finally")
        @test leading_spaces(line_text(editor, 2)) == 0
    end

    @testset "'append' does NOT trigger dedent (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "function f()")
        press_enter!(editor)
        type_string!(editor, "append")
        # "append" should NOT dedent — it stays at 4 indent
        @test leading_spaces(line_text(editor, 2)) == 4
        @test strip(line_text(editor, 2)) == "append"
    end

    @testset "'render' does NOT trigger dedent (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "function f()")
        press_enter!(editor)
        type_string!(editor, "render")
        @test leading_spaces(line_text(editor, 2)) == 4
    end

    @testset "'blend' does NOT trigger dedent (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "function f()")
        press_enter!(editor)
        type_string!(editor, "blend")
        @test leading_spaces(line_text(editor, 2)) == 4
    end

    @testset "'endpoint' eagerly dedents at 'end' prefix (CodeEditor)" begin
        # Tachikoma auto-dedent fires eagerly: typing "end" triggers dedent
        # even if you continue typing "endpoint". This is expected behavior.
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "function f()")
        press_enter!(editor)
        type_string!(editor, "endpoint")
        @test leading_spaces(line_text(editor, 2)) == 0
    end

    # ── CellWidget mode tests ──────────────────────────────────────

    @testset "Enter after block opener indents in CellWidget" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        type_string!(cw.editor, "function g(x)")
        press_enter!(cw.editor)
        @test cw.editor.cursor_col == 4
        @test leading_spaces(line_text(cw.editor, 2)) == 4
    end

    @testset "Typing 'end' auto-dedents in CellWidget" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        type_string!(cw.editor, "function g(x)")
        press_enter!(cw.editor)
        type_string!(cw.editor, "end")
        @test line_text(cw.editor, 2) == "end"
        @test leading_spaces(line_text(cw.editor, 2)) == 0
    end

    @testset "Nested indent in CellWidget" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        type_string!(cw.editor, "if cond")
        press_enter!(cw.editor)
        type_string!(cw.editor, "for i in 1:n")
        press_enter!(cw.editor)
        @test cw.editor.cursor_col == 8
    end

    @testset "'append' does NOT dedent in CellWidget" begin
        cell = Sessions.Cell(code="")
        cw = Sessions.CellWidget(cell; focused=true)
        cw.editor.focused = true
        cw.editor.mode = :insert
        type_string!(cw.editor, "for i in 1:n")
        press_enter!(cw.editor)
        type_string!(cw.editor, "append")
        @test leading_spaces(line_text(cw.editor, 2)) == 4
    end

    # ── FileEditorView mode tests ──────────────────────────────────

    @testset "Enter after block opener indents in FileEditorView" begin
        path = tempname() * ".jl"
        write(path, "")
        fev = Sessions.FileEditorView(path)
        fev.editor.mode = :insert
        type_string!(fev.editor, "function h()")
        press_enter!(fev.editor)
        @test fev.editor.cursor_col == 4
        @test leading_spaces(line_text(fev.editor, 2)) == 4
        rm(path; force=true)
    end

    @testset "Typing 'end' auto-dedents in FileEditorView" begin
        path = tempname() * ".jl"
        write(path, "")
        fev = Sessions.FileEditorView(path)
        fev.editor.mode = :insert
        type_string!(fev.editor, "function h()")
        press_enter!(fev.editor)
        type_string!(fev.editor, "end")
        @test line_text(fev.editor, 2) == "end"
        @test leading_spaces(line_text(fev.editor, 2)) == 0
        rm(path; force=true)
    end

    @testset "Nested indent in FileEditorView" begin
        path = tempname() * ".jl"
        write(path, "")
        fev = Sessions.FileEditorView(path)
        fev.editor.mode = :insert
        type_string!(fev.editor, "while true")
        press_enter!(fev.editor)
        type_string!(fev.editor, "if x > 0")
        press_enter!(fev.editor)
        @test fev.editor.cursor_col == 8
        rm(path; force=true)
    end

    @testset "Plain Enter copies indentation in FileEditorView" begin
        path = tempname() * ".jl"
        write(path, "")
        fev = Sessions.FileEditorView(path)
        fev.editor.mode = :insert
        type_string!(fev.editor, "    y = 42")
        press_enter!(fev.editor)
        @test fev.editor.cursor_col == 4
        @test leading_spaces(line_text(fev.editor, 2)) == 4
        rm(path; force=true)
    end

    @testset "'append' does NOT dedent in FileEditorView" begin
        path = tempname() * ".jl"
        write(path, "")
        fev = Sessions.FileEditorView(path)
        fev.editor.mode = :insert
        type_string!(fev.editor, "function h()")
        press_enter!(fev.editor)
        type_string!(fev.editor, "append")
        @test leading_spaces(line_text(fev.editor, 2)) == 4
        rm(path; force=true)
    end

    @testset "'endpoint' eagerly dedents at 'end' prefix in FileEditorView" begin
        path = tempname() * ".jl"
        write(path, "")
        fev = Sessions.FileEditorView(path)
        fev.editor.mode = :insert
        type_string!(fev.editor, "function h()")
        press_enter!(fev.editor)
        type_string!(fev.editor, "endpoint")
        @test leading_spaces(line_text(fev.editor, 2)) == 0
        rm(path; force=true)
    end

    @testset "Typing 'catch' auto-dedents in FileEditorView" begin
        path = tempname() * ".jl"
        write(path, "")
        fev = Sessions.FileEditorView(path)
        fev.editor.mode = :insert
        type_string!(fev.editor, "try")
        press_enter!(fev.editor)
        type_string!(fev.editor, "catch")
        @test leading_spaces(line_text(fev.editor, 2)) == 0
        rm(path; force=true)
    end

    @testset "Typing 'finally' auto-dedents in FileEditorView" begin
        path = tempname() * ".jl"
        write(path, "")
        fev = Sessions.FileEditorView(path)
        fev.editor.mode = :insert
        type_string!(fev.editor, "try")
        press_enter!(fev.editor)
        type_string!(fev.editor, "finally")
        @test leading_spaces(line_text(fev.editor, 2)) == 0
        rm(path; force=true)
    end

    @testset "'else' indent+dedent cycle in FileEditorView" begin
        path = tempname() * ".jl"
        write(path, "")
        fev = Sessions.FileEditorView(path)
        fev.editor.mode = :insert
        type_string!(fev.editor, "if cond")
        press_enter!(fev.editor)
        @test fev.editor.cursor_col == 4
        type_string!(fev.editor, "x = 1")
        press_enter!(fev.editor)
        type_string!(fev.editor, "else")
        # else should dedent from 4 → 0
        @test leading_spaces(line_text(fev.editor, 3)) == 0
        # Enter after 'else' should indent +4
        press_enter!(fev.editor)
        @test fev.editor.cursor_col == 4
        rm(path; force=true)
    end

    @testset "'mutable struct' adds indent (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "mutable struct Foo")
        press_enter!(editor)
        @test editor.cursor_col == 4
        @test leading_spaces(line_text(editor, 2)) == 4
    end

    @testset "'macro m()' adds indent (CodeEditor)" begin
        editor = Tachikoma.CodeEditor(; mode=:insert, focused=true)
        type_string!(editor, "macro m()")
        press_enter!(editor)
        @test editor.cursor_col == 4
        @test leading_spaces(line_text(editor, 2)) == 4
    end
end
