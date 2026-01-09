using Test
using UUIDs

# Test Cell and Executor without needing full Sessions module
include("../src/Notebook/Cell.jl")
include("../src/Notebook/Executor.jl")

@testset "Sessions.jl" begin

    @testset "Cell" begin
        @testset "Cell creation" begin
            cell = Cell()
            @test cell.code == ""
            @test cell.status == IDLE
            @test cell.output === nothing
        end

        @testset "Cell with code" begin
            cell = Cell("x = 1 + 1")
            @test cell.code == "x = 1 + 1"
            @test cell.status == IDLE
        end

        @testset "Cell serialization" begin
            cell = Cell("test")
            d = Dict(cell)
            @test d["code"] == "test"
            @test d["status"] == "IDLE"
        end
    end

    @testset "Executor" begin
        exec = Executor()

        @testset "Simple execution" begin
            result = execute(exec, "1 + 1")
            @test result.success
            @test result.value == 2
        end

        @testset "Variable persistence" begin
            execute(exec, "test_var = 42")
            result = execute(exec, "test_var")
            @test result.success
            @test result.value == 42
        end

        @testset "Error handling" begin
            result = execute(exec, "undefined_var")
            @test !result.success
            @test contains(result.error_msg, "undefined")
        end

        @testset "Stdout capture" begin
            result = execute(exec, "println(\"hello\")")
            @test result.success
            @test contains(result.stdout, "hello")
        end

        @testset "Restart" begin
            execute(exec, "restart_test = 123")
            restart!(exec)
            result = execute(exec, "restart_test")
            @test !result.success
        end
    end

    @testset "Cell execution" begin
        exec = Executor()
        cell = Cell("2 + 2")

        execute_cell!(exec, cell)

        @test cell.status == COMPLETED
        @test cell.output == 4
        @test cell.execution_count == 1
    end

end

println("\nAll tests passed!")
