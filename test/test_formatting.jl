@testset "Formatting (Runic.jl)" begin
    @testset "format_code basic" begin
        # Spaces around operators
        result = Sessions.format_code("x=1+2")
        @test result == "x = 1 + 2"

        # Already formatted code unchanged
        result = Sessions.format_code("x = 1 + 2")
        @test result == "x = 1 + 2"

        # Empty string
        result = Sessions.format_code("")
        @test result == ""
    end

    @testset "format_code multiline" begin
        input = "function f(x)\nreturn x+1\nend"
        result = Sessions.format_code(input)
        @test occursin("function f(x)", result)
        @test occursin("return x + 1", result)
        @test occursin("end", result)
        # Should have proper indentation
        @test occursin("    return", result)
    end

    @testset "format_code preserves valid code" begin
        # Well-formatted code should roundtrip
        code = "function hello()\n    println(\"world\")\n    return 42\nend"
        result = Sessions.format_code(code)
        @test occursin("println", result)
        @test occursin("return 42", result)
        @test occursin("hello", result)
    end

    @testset "format_code handles invalid syntax gracefully" begin
        # Invalid syntax should return original
        bad = "function f(\n  # incomplete"
        result = Sessions.format_code(bad)
        @test result == bad  # returned unchanged

        # Another invalid case
        bad2 = "if x ==\n  # broken"
        result2 = Sessions.format_code(bad2)
        @test result2 == bad2
    end

    @testset "format_code handles edge cases" begin
        # Single expression
        @test Sessions.format_code("42") == "42"

        # Just a comment
        result = Sessions.format_code("# hello")
        @test occursin("# hello", result)

        # Multiple statements
        input = "x=1\ny=2\nz=x+y"
        result = Sessions.format_code(input)
        @test occursin("x = 1", result)
        @test occursin("y = 2", result)
        @test occursin("z = x + y", result)

        # Trailing newline handling
        input = "x = 1\n"
        result = Sessions.format_code(input)
        @test occursin("x = 1", result)
    end

    @testset "format_code_available" begin
        # Should report whether Runic is available
        @test Sessions.format_code_available() isa Bool
    end

    @testset "format-on-save: notebook cells" begin
        nb = Sessions.Notebook(; path="test_format.jl")
        Sessions.add_cell!(nb, "x=1+2")
        Sessions.add_cell!(nb, "y = 3")  # already formatted
        app = Sessions.SessionsApp(nb)

        n = Sessions._format_notebook_cells!(app)
        @test n == 1  # only first cell changed

        # First cell should now be formatted
        cw1 = app.notebook_view.cell_widgets[1]
        @test cw1.cell.code == "x = 1 + 2"
        @test Tachikoma.text(cw1.editor) == "x = 1 + 2"

        # Second cell unchanged
        cw2 = app.notebook_view.cell_widgets[2]
        @test cw2.cell.code == "y = 3"
    end

    @testset "format-on-save: cursor preservation" begin
        nb = Sessions.Notebook(; path="test_format.jl")
        Sessions.add_cell!(nb, "function f(x)\nreturn x+1\nend")
        app = Sessions.SessionsApp(nb)

        cw = app.notebook_view.cell_widgets[1]
        cw.editor.cursor_row = 2
        cw.editor.cursor_col = 5

        Sessions._format_notebook_cells!(app)

        # Cursor should be clamped to valid position
        @test cw.editor.cursor_row >= 1
        @test cw.editor.cursor_row <= length(cw.editor.lines)
        @test cw.editor.cursor_col >= 0
        @test cw.editor.cursor_col <= length(cw.editor.lines[cw.editor.cursor_row])
    end

    @testset "format-on-save: disabled cells skipped" begin
        nb = Sessions.Notebook(; path="test_format.jl")
        Sessions.add_cell!(nb, "x=1+2")
        nb.cells[nb.cell_order[1]].disabled = true
        app = Sessions.SessionsApp(nb)

        n = Sessions._format_notebook_cells!(app)
        @test n == 0  # disabled cell skipped

        cw = app.notebook_view.cell_widgets[1]
        @test cw.cell.code == "x=1+2"  # unchanged
    end

    @testset "format-on-save: file editor" begin
        path = tempname() * ".jl"
        write(path, "x=1+2\ny=3+4\n")
        fev = Sessions.FileEditorView(path)

        did_format = Sessions._format_file_editor!(fev)
        @test did_format == true
        @test occursin("x = 1 + 2", Tachikoma.text(fev.editor))
        @test occursin("y = 3 + 4", Tachikoma.text(fev.editor))

        # Already formatted — should return false
        did_format2 = Sessions._format_file_editor!(fev)
        @test did_format2 == false

        rm(path; force=true)
    end

    @testset "format-on-save: file editor cursor preservation" begin
        path = tempname() * ".jl"
        write(path, "function g()\nreturn 42+1\nend\n")
        fev = Sessions.FileEditorView(path)
        fev.editor.cursor_row = 2
        fev.editor.cursor_col = 5

        Sessions._format_file_editor!(fev)

        @test fev.editor.cursor_row >= 1
        @test fev.editor.cursor_row <= length(fev.editor.lines)
        @test fev.editor.cursor_col >= 0
        @test fev.editor.cursor_col <= length(fev.editor.lines[fev.editor.cursor_row])

        rm(path; force=true)
    end
end
