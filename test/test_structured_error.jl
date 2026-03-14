using Test
using Sessions
using UUIDs

@testset "Structured Error Display" begin

    @testset "StructuredFrame construction" begin
        sf = StructuredFrame("my_func", "my_func", "/path/to/file.jl", "file.jl",
            42, false, false, false, true, :important)
        @test sf.func == "my_func"
        @test sf.func_short == "my_func"
        @test sf.file_short == "file.jl"
        @test sf.line == 42
        @test sf.from_user == true
        @test sf.importance == :important
        @test sf.inlined == false
        @test sf.from_c == false
    end

    @testset "StructuredError construction" begin
        frames = [
            StructuredFrame("f1", "f1", "a.jl", "a.jl", 1, false, false, false, true, :important),
            StructuredFrame("f2", "f2", "b.jl", "b.jl", 2, false, false, true, false, :normal),
        ]
        se = StructuredError("UndefVarError", "`x` is not defined", frames, 3, "plain text fallback")
        @test se.type_name == "UndefVarError"
        @test se.message == "`x` is not defined"
        @test length(se.frames) == 2
        @test se.hidden_frame_count == 3
        @test se.plain_text == "plain text fallback"
    end

    @testset "build_structured_error — from real exception" begin
        ws = Workspace()
        cell = Cell("undefined_var + 1")
        execute_cell!(ws, cell)

        @test cell.state == cell_errored
        @test cell.output.structured_error !== nothing

        se = cell.output.structured_error
        @test se.type_name == "UndefVarError"
        @test contains(se.message, "undefined_var")
        @test !isempty(se.plain_text)
    end

    @testset "build_structured_error — error() call" begin
        ws = Workspace()
        cell = Cell("error(\"test boom\")")
        execute_cell!(ws, cell)

        @test cell.state == cell_errored
        se = cell.output.structured_error
        @test se !== nothing
        @test se.type_name == "ErrorException"
        @test contains(se.message, "test boom")
    end

    @testset "build_structured_error — MethodError" begin
        ws = Workspace()
        cell = Cell("\"hello\" + 42")
        execute_cell!(ws, cell)

        @test cell.state == cell_errored
        se = cell.output.structured_error
        @test se !== nothing
        @test se.type_name == "MethodError"
        @test contains(se.message, "MethodError")
    end

    @testset "build_structured_error — BoundsError" begin
        ws = Workspace()
        cell = Cell("[1,2,3][10]")
        execute_cell!(ws, cell)

        @test cell.state == cell_errored
        se = cell.output.structured_error
        @test se !== nothing
        @test se.type_name == "BoundsError"
    end

    @testset "frame importance classification" begin
        ws = Workspace()
        cell = Cell("error(\"classify test\")")
        execute_cell!(ws, cell)

        se = cell.output.structured_error
        @test se !== nothing
        # Should have at least some frames (even after filtering)
        # Important frames from user code should exist, dim frames are filtered
        for frame in se.frames
            @test frame.importance in (:important, :normal, :dim)
        end
    end

    @testset "CellOutput backward compatibility — new field defaults to nothing" begin
        co = CellOutput()
        @test co.structured_error === nothing
        @test co.output_type == :nothing
        @test co.text_representation == ""
        @test co.image_data === nothing
    end

    @testset "successful cell has no structured_error" begin
        ws = Workspace()
        cell = Cell("42")
        execute_cell!(ws, cell)

        @test cell.state == cell_done
        @test cell.output.structured_error === nothing
    end

    @testset "plain_text fallback matches format_error" begin
        ws = Workspace()
        cell = Cell("error(\"fallback test\")")
        execute_cell!(ws, cell)

        se = cell.output.structured_error
        @test se !== nothing
        # plain_text should be a non-empty string usable for clipboard
        @test !isempty(se.plain_text)
        @test contains(se.plain_text, "fallback test")
    end

    @testset "_shorten_func strips type params" begin
        # Access internal function for testing
        @test Sessions._shorten_func("my_func{T}") == "my_func"
        @test Sessions._shorten_func("my_func") == "my_func"
        @test Sessions._shorten_func("foo{Int64, String}") == "foo"
    end

    @testset "OutputWidget selection state fields" begin
        cell = Cell("42")
        ow = Sessions.OutputWidget(cell)
        @test ow._sel_active == false
        @test ow._sel_anchor_row == 1
        @test ow._sel_anchor_col == 0
        @test ow._sel_cursor_row == 1
        @test ow._sel_cursor_col == 0
        @test ow._output_expanded == false
    end

    @testset "output selection — clear" begin
        ws = Workspace()
        cell = Cell("42")
        execute_cell!(ws, cell)
        ow = Sessions.OutputWidget(cell)

        # Simulate selection
        ow._sel_active = true
        ow._sel_anchor_row = 1
        ow._sel_anchor_col = 2
        ow._sel_cursor_row = 1
        ow._sel_cursor_col = 5
        @test ow._sel_active == true

        Sessions._clear_output_selection!(ow)
        @test ow._sel_active == false
    end

    @testset "output selection — selected text extraction" begin
        ws = Workspace()
        cell = Cell("[1, 2, 3]")
        execute_cell!(ws, cell)
        ow = Sessions.OutputWidget(cell)

        # Cache output lines
        lines = Sessions.cached_output_lines(ow)
        @test !isempty(lines)

        # Single-line selection
        stripped = Sessions._strip_ansi(lines[1])
        ow._sel_active = true
        ow._sel_anchor_row = 1
        ow._sel_anchor_col = 0
        ow._sel_cursor_row = 1
        ow._sel_cursor_col = min(3, length(stripped))
        text = Sessions._output_selected_text(ow)
        @test !isempty(text)
        @test length(text) <= length(stripped)
    end

    @testset "output selection — multi-line text" begin
        ws = Workspace()
        cell = Cell("println(\"line1\"); println(\"line2\"); 42")
        execute_cell!(ws, cell)
        ow = Sessions.OutputWidget(cell)

        lines = Sessions.cached_output_lines(ow)
        if length(lines) >= 2
            ow._sel_active = true
            ow._sel_anchor_row = 1
            ow._sel_anchor_col = 0
            ow._sel_cursor_row = 2
            ow._sel_cursor_col = min(3, length(Sessions._strip_ansi(lines[2])))
            text = Sessions._output_selected_text(ow)
            @test contains(text, "\n")
        end
    end

    @testset "output selection — no selection returns empty" begin
        cell = Cell("42")
        ow = Sessions.OutputWidget(cell)
        @test Sessions._output_selected_text(ow) == ""
    end

    @testset "output selection — range normalization" begin
        cell = Cell("42")
        ow = Sessions.OutputWidget(cell)

        # Forward selection
        ow._sel_active = true
        ow._sel_anchor_row = 1
        ow._sel_anchor_col = 2
        ow._sel_cursor_row = 3
        ow._sel_cursor_col = 5
        sr, sc, er, ec = Sessions._output_selection_range(ow)
        @test sr == 1
        @test sc == 2
        @test er == 3
        @test ec == 5

        # Backward selection (cursor before anchor)
        ow._sel_anchor_row = 3
        ow._sel_anchor_col = 5
        ow._sel_cursor_row = 1
        ow._sel_cursor_col = 2
        sr, sc, er, ec = Sessions._output_selection_range(ow)
        @test sr == 1
        @test sc == 2
        @test er == 3
        @test ec == 5
    end

    @testset "output selection cleared on output change" begin
        ws = Workspace()
        cell = Cell("42")
        execute_cell!(ws, cell)
        ow = Sessions.OutputWidget(cell)

        # Cache lines and set selection
        Sessions.cached_output_lines(ow)
        ow._sel_active = true
        ow._sel_anchor_row = 1
        ow._sel_anchor_col = 0

        # Re-execute cell (changes output)
        cell.code = "99"
        execute_cell!(ws, cell)
        # Calling cached_output_lines with new output invalidates cache and clears selection
        Sessions.cached_output_lines(ow)
        @test ow._sel_active == false
    end
end
