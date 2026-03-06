using Test
using Sessions

@testset "cli.jl" begin
    @testset "main with no args shows help" begin
        old_stdout = stdout
        rd, wr = redirect_stdout()
        try
            Sessions.main(String[])
        finally
            redirect_stdout(old_stdout)
            close(wr)
        end
        output = String(read(rd))
        @test occursin("Sessions.jl", output)
        @test occursin("Usage", output)
    end

    @testset "main run command" begin
        old_stdout = stdout
        rd, wr = redirect_stdout()
        try
            Sessions.main(["run", "test/fixtures/basic_notebook.jl"])
        finally
            redirect_stdout(old_stdout)
            close(wr)
        end
        output = String(read(rd))
        # No errors, so no output expected (exit code 0 path)
        @test true  # Didn't throw
    end

    @testset "main run with verbose" begin
        old_stdout = stdout
        rd, wr = redirect_stdout()
        try
            Sessions.main(["run", "test/fixtures/basic_notebook.jl", "--verbose"])
        finally
            redirect_stdout(old_stdout)
            close(wr)
        end
        output = String(read(rd))
        @test occursin("Sessions.run", output)
    end

    @testset "main with .jl file path opens" begin
        # We can't actually test opening the TUI, but we can test that
        # giving a non-existent file throws
        @test_throws Exception Sessions.main(["nonexistent.jl"])
    end

    @testset "main unknown command errors" begin
        @test_throws Exception Sessions.main(["invalidcommand"])
    end
end
