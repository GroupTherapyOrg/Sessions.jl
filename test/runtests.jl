using Test
using Sessions

@testset "Sessions.jl v2" begin
    @testset "Module loads" begin
        @test true  # Sessions loaded successfully
    end

    include("test_types.jl")
    include("test_format.jl")
    include("test_analysis.jl")
    include("test_kernel.jl")
    include("test_output.jl")
    include("test_run.jl")
    include("test_tui.jl")
    include("test_cli.jl")
    include("test_session.jl")
    include("test_watcher.jl")
    include("test_e2e.jl")
    include("test_pluto_compat.jl")
end
