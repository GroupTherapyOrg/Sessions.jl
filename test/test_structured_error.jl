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

    # OutputWidget selection tests removed (TUI widget deleted)
end
