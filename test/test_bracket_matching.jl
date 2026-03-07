@testset "Bracket Matching" begin

    # Helper: convert string to Vector{Vector{Char}} (editor lines format)
    function to_lines(strs::Vector{String})
        [collect(s) for s in strs]
    end

    # ── _find_matching_bracket ──────────────────────────────────────

    @testset "Match forward: ( → )" begin
        lines = to_lines(["(hello)"])
        result = Sessions._find_matching_bracket(lines, 1, 1)  # '(' at col 1
        @test result == (1, 7)  # ')' at col 7
    end

    @testset "Match backward: ) → (" begin
        lines = to_lines(["(hello)"])
        result = Sessions._find_matching_bracket(lines, 1, 7)  # ')' at col 7
        @test result == (1, 1)  # '(' at col 1
    end

    @testset "Nested brackets: outer" begin
        lines = to_lines(["(a(b)c)"])
        result = Sessions._find_matching_bracket(lines, 1, 1)  # outer '('
        @test result == (1, 7)
    end

    @testset "Nested brackets: inner" begin
        lines = to_lines(["(a(b)c)"])
        result = Sessions._find_matching_bracket(lines, 1, 3)  # inner '('
        @test result == (1, 5)
    end

    @testset "Unmatched bracket returns nothing" begin
        lines = to_lines(["(hello"])
        result = Sessions._find_matching_bracket(lines, 1, 1)
        @test result === nothing
    end

    @testset "Square brackets" begin
        lines = to_lines(["a[b[c]]"])
        @test Sessions._find_matching_bracket(lines, 1, 2) == (1, 7)  # outer [
        @test Sessions._find_matching_bracket(lines, 1, 4) == (1, 6)  # inner [
    end

    @testset "Curly braces" begin
        lines = to_lines(["{x: {y}}"])
        @test Sessions._find_matching_bracket(lines, 1, 1) == (1, 8)  # outer {
        @test Sessions._find_matching_bracket(lines, 1, 5) == (1, 7)  # inner {
    end

    @testset "Multi-line bracket match" begin
        lines = to_lines(["function f(", "    x", ")"])
        @test Sessions._find_matching_bracket(lines, 1, 11) == (3, 1)  # ( → )
        @test Sessions._find_matching_bracket(lines, 3, 1) == (1, 11)  # ) → (
    end

    @testset "Non-bracket char returns nothing" begin
        lines = to_lines(["hello"])
        @test Sessions._find_matching_bracket(lines, 1, 1) === nothing
    end

    @testset "Out of bounds returns nothing" begin
        lines = to_lines(["()"])
        @test Sessions._find_matching_bracket(lines, 1, 0) === nothing
        @test Sessions._find_matching_bracket(lines, 1, 3) === nothing
        @test Sessions._find_matching_bracket(lines, 0, 1) === nothing
        @test Sessions._find_matching_bracket(lines, 2, 1) === nothing
    end

    # ── _bracket_match_positions ────────────────────────────────────

    @testset "Cursor on opening bracket" begin
        lines = to_lines(["(abc)"])
        # cursor_col=0 means cursor is at position 0 (before char index 1)
        # char right of cursor: col 1 = '('
        result = Sessions._bracket_match_positions(lines, 1, 0)
        @test result !== nothing
        @test result == ((1, 1), (1, 5))
    end

    @testset "Cursor on closing bracket" begin
        lines = to_lines(["(abc)"])
        # cursor_col=4, char right = ')' at col 5
        result = Sessions._bracket_match_positions(lines, 1, 4)
        @test result !== nothing
        @test result == ((1, 5), (1, 1))
    end

    @testset "Cursor adjacent (left of bracket)" begin
        lines = to_lines(["x(y)z"])
        # cursor_col=1, char right = '(' at col 2
        result = Sessions._bracket_match_positions(lines, 1, 1)
        @test result !== nothing
        @test result[1] == (1, 2)
        @test result[2] == (1, 4)
    end

    @testset "Cursor not near bracket returns nothing" begin
        lines = to_lines(["hello"])
        result = Sessions._bracket_match_positions(lines, 1, 2)
        @test result === nothing
    end

    # ── Render smoke tests ──────────────────────────────────────────

    function render_cell_app(app; width=120, height=40)
        tb = Tachikoma.TestBackend(width, height)
        frame = Tachikoma.Frame(tb.buf, Tachikoma.Rect(1, 1, width, height), [], [])
        Tachikoma.view(app, frame)
        tb
    end

    @testset "Bracket match renders in CellWidget without crash" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "f(x)")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert
        cw.editor.cursor_col = 1  # right after '('

        tb = render_cell_app(app)
        @test Tachikoma.find_text(tb, "f(x)") !== nothing
    end

    @testset "Bracket match renders in FileEditorView without crash" begin
        path = tempname() * ".jl"
        write(path, "g(y)\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.mode = :insert
        fev.editor.cursor_col = 1  # right after '('

        tb = render_cell_app(app)
        @test Tachikoma.find_text(tb, "g(y)") !== nothing
        rm(path; force=true)
    end

    @testset "Mixed bracket types match correctly" begin
        lines = to_lines(["f([x])"])
        # [ at col 3
        @test Sessions._find_matching_bracket(lines, 1, 3) == (1, 5)
        # ( at col 2
        @test Sessions._find_matching_bracket(lines, 1, 2) == (1, 6)
    end

    @testset "Mismatched brackets don't match" begin
        lines = to_lines(["(x]"])
        result = Sessions._find_matching_bracket(lines, 1, 1)
        @test result === nothing  # ( has no matching )
    end
end
