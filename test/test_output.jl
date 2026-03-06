using Test
using Sessions
using Markdown: @md_str, MD

@testset "output.jl — classify_output + text_representation" begin
    @testset "classify_output — basic types" begin
        @test classify_output(nothing) == :nothing
        @test classify_output(42) == :text
        @test classify_output(3.14) == :text
        @test classify_output("hello") == :text
        @test classify_output([1, 2, 3]) == :text
        @test classify_output(Dict(:a => 1)) == :text
        @test classify_output(true) == :text
        @test classify_output(:symbol) == :text
    end

    @testset "classify_output — Markdown" begin
        md = md"# Hello"
        @test classify_output(md) == :markdown

        md2 = md"Some **bold** text"
        @test classify_output(md2) == :markdown
    end

    @testset "classify_output — NamedTuple table" begin
        table = [(a=1, b=2), (a=3, b=4)]
        @test classify_output(table) == :dataframe
    end

    @testset "classify_output — empty collections" begin
        @test classify_output(Int[]) == :text
        @test classify_output(Dict()) == :text
    end

    @testset "text_representation — basic types" begin
        @test text_representation(nothing) == ""
        @test contains(text_representation(42), "42")
        @test contains(text_representation("hello"), "hello")
    end

    @testset "text_representation — collections" begin
        repr = text_representation([1, 2, 3])
        @test contains(repr, "1")
        @test contains(repr, "3")
    end

    @testset "text_representation — Markdown" begin
        md = md"# Hello"
        repr = text_representation(md)
        @test !isempty(repr)
    end

    @testset "text_representation — large output" begin
        big = collect(1:1000)
        repr = text_representation(big)
        @test !isempty(repr)
        @test length(repr) < 100_000  # not infinite
    end

    @testset "CellOutput fields — output_type and text_representation" begin
        co = CellOutput()
        @test co.output_type == :nothing
        @test co.text_representation == ""
    end

    @testset "execute_cell! sets output_type" begin
        ws = Workspace()

        # Integer result
        c1 = Cell("42")
        execute_cell!(ws, c1)
        @test c1.output.output_type == :text
        @test contains(c1.output.text_representation, "42")

        # Nothing result
        c2 = Cell("nothing")
        execute_cell!(ws, c2)
        @test c2.output.output_type == :nothing
        @test c2.output.text_representation == ""

        # Markdown — test classify_output directly (workspace eval can't load Markdown)
        md_val = md"# Test"
        @test classify_output(md_val) == :markdown

        # Error result
        c4 = Cell("error(\"boom\")")
        execute_cell!(ws, c4)
        @test c4.output.output_type == :error
        @test contains(c4.output.text_representation, "boom")
    end

    @testset "execute_cell! — stdout separate from result" begin
        ws = Workspace()
        c = Cell("println(\"hello\"); 42")
        execute_cell!(ws, c)
        @test c.output.output_type == :text
        @test contains(c.output.text_representation, "42")
        @test contains(c.output.stdout, "hello")
    end

    @testset "execute_cell! — string result" begin
        ws = Workspace()
        c = Cell("\"world\"")
        execute_cell!(ws, c)
        @test c.output.output_type == :text
        @test contains(c.output.text_representation, "world")
    end

    @testset "execute_cell! — boolean result" begin
        ws = Workspace()
        c = Cell("true")
        execute_cell!(ws, c)
        @test c.output.output_type == :text
        @test contains(c.output.text_representation, "true")
    end

    @testset "execute_cell! — vector result" begin
        ws = Workspace()
        c = Cell("[1, 2, 3]")
        execute_cell!(ws, c)
        @test c.output.output_type == :text
        @test !isempty(c.output.text_representation)
    end
end
