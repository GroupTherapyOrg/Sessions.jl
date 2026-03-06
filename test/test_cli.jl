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

    @testset "bin/sessions wrapper exists and is executable" begin
        wrapper = joinpath(@__DIR__, "..", "bin", "sessions")
        @test isfile(wrapper)
        # Check executable permission (Unix)
        @test (filemode(wrapper) & 0o111) != 0
    end

    @testset "bin/sessions wrapper content is correct" begin
        wrapper = joinpath(@__DIR__, "..", "bin", "sessions")
        content = read(wrapper, String)
        @test startswith(content, "#!/bin/sh")
        @test contains(content, "Sessions.main()")
        @test contains(content, "julia")
    end

    @testset "install_cli creates wrapper" begin
        dest = tempname()
        result = Sessions.install_cli(; dest)
        @test isfile(dest)
        @test result == dest
        content = read(dest, String)
        @test startswith(content, "#!/bin/sh")
        @test contains(content, "Sessions.main()")
        # Executable
        @test (filemode(dest) & 0o111) != 0
        rm(dest; force=true)
    end

    @testset "install_cli creates parent directories" begin
        dest = joinpath(tempdir(), "sessions_test_install", "bin", "sessions")
        result = Sessions.install_cli(; dest)
        @test isfile(dest)
        rm(dirname(dirname(dest)); force=true, recursive=true)
    end
end
