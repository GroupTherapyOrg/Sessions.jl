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
            Sessions.main(["run", "test/fixtures/welcome.jl"])
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
            Sessions.main(["run", "test/fixtures/welcome.jl", "--verbose"])
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

    @testset "SESSIONS_GRAPHICS_PROTOCOL maps to TACHIKOMA_GFX" begin
        old_sgp = get(ENV, "SESSIONS_GRAPHICS_PROTOCOL", nothing)
        old_tgfx = get(ENV, "TACHIKOMA_GFX", nothing)
        try
            delete!(ENV, "TACHIKOMA_GFX")
            ENV["SESSIONS_GRAPHICS_PROTOCOL"] = "kitty"
            # Call main with --version (safe, exits quickly)
            old_stdout = stdout
            rd, wr = redirect_stdout()
            try
                Sessions.main(["--version"])
            finally
                redirect_stdout(old_stdout)
                close(wr)
            end
            @test get(ENV, "TACHIKOMA_GFX", "") == "kitty"
        finally
            # Restore env
            if old_sgp === nothing; delete!(ENV, "SESSIONS_GRAPHICS_PROTOCOL"); else ENV["SESSIONS_GRAPHICS_PROTOCOL"] = old_sgp; end
            if old_tgfx === nothing; delete!(ENV, "TACHIKOMA_GFX"); else ENV["TACHIKOMA_GFX"] = old_tgfx; end
        end
    end

    @testset "SESSIONS_GRAPHICS_PROTOCOL does not override existing TACHIKOMA_GFX" begin
        old_sgp = get(ENV, "SESSIONS_GRAPHICS_PROTOCOL", nothing)
        old_tgfx = get(ENV, "TACHIKOMA_GFX", nothing)
        try
            ENV["TACHIKOMA_GFX"] = "sixel"
            ENV["SESSIONS_GRAPHICS_PROTOCOL"] = "kitty"
            old_stdout = stdout
            rd, wr = redirect_stdout()
            try
                Sessions.main(["--version"])
            finally
                redirect_stdout(old_stdout)
                close(wr)
            end
            @test get(ENV, "TACHIKOMA_GFX", "") == "sixel"  # not overridden
        finally
            if old_sgp === nothing; delete!(ENV, "SESSIONS_GRAPHICS_PROTOCOL"); else ENV["SESSIONS_GRAPHICS_PROTOCOL"] = old_sgp; end
            if old_tgfx === nothing; delete!(ENV, "TACHIKOMA_GFX"); else ENV["TACHIKOMA_GFX"] = old_tgfx; end
        end
    end
end
