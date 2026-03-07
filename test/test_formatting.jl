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
end
