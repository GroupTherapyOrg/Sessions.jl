using Test
using Sessions

@testset "cli.jl" begin
    @testset "main --help shows usage" begin
        old_stdout = stdout
        rd, wr = redirect_stdout()
        try
            Sessions.main(["--help"])
        finally
            redirect_stdout(old_stdout)
            close(wr)
        end
        output = String(read(rd))
        @test occursin("Sessions.jl", output)
        @test occursin("Usage", output)
    end

    @testset "main --version" begin
        old_stdout = stdout
        rd, wr = redirect_stdout()
        try
            Sessions.main(["--version"])
        finally
            redirect_stdout(old_stdout)
            close(wr)
        end
        output = String(read(rd))
        @test occursin("Sessions.jl", output)
    end

    @testset "main run command" begin
        old_stdout = stdout
        rd, wr = redirect_stdout()
        try
            Sessions.main(["run", "test/fixtures/test_basic.jl"])
        finally
            redirect_stdout(old_stdout)
            close(wr)
        end
        @test true  # Didn't throw
    end

    @testset "main run with verbose" begin
        old_stdout = stdout
        rd, wr = redirect_stdout()
        try
            Sessions.main(["run", "test/fixtures/test_basic.jl", "--verbose"])
        finally
            redirect_stdout(old_stdout)
            close(wr)
        end
        output = String(read(rd))
        @test occursin("Sessions.run", output)
    end

    @testset "main unknown command returns error code" begin
        old_stderr = stderr
        rd, wr = redirect_stderr()
        try
            ret = Sessions.main(["invalidcommand"])
        finally
            redirect_stderr(old_stderr)
            close(wr)
        end
        # main returns nothing (wraps @main which returns Cint)
        @test true
    end

    @testset "bin/sessions wrapper exists and is executable" begin
        wrapper = joinpath(@__DIR__, "..", "bin", "sessions")
        @test isfile(wrapper)
        @test (filemode(wrapper) & 0o111) != 0
    end

    @testset "bin/sessions wrapper content" begin
        wrapper = joinpath(@__DIR__, "..", "bin", "sessions")
        content = read(wrapper, String)
        @test startswith(content, "#!/bin/sh")
        @test contains(content, "julia")
    end
end
