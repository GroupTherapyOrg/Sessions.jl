using Test
using Sessions

@testset "run.jl" begin
    @testset "Sessions.run with file path" begin
        nb = Sessions.run("test/fixtures/test_basic.jl")
        @test nb isa Sessions.Notebook
        @test length(nb) == 3

        cells = ordered_cells(nb)
        @test cells[1].state == cell_done
        @test cells[1].output.result == 1   # x = 1
        @test cells[2].output.result == 2   # y = x + 1
        @test cells[3].output.result == 2   # z = x * y
    end

    @testset "Sessions.run with Notebook object" begin
        nb = Notebook()
        add_cell!(nb, "a = 5")
        add_cell!(nb, "b = a * 3")
        add_cell!(nb, "c = a + b")

        Sessions.run(nb)

        cells = ordered_cells(nb)
        @test cells[1].output.result == 5
        @test cells[2].output.result == 15
        @test cells[3].output.result == 20
    end

    @testset "Sessions.run verbose output" begin
        nb = Notebook(; path=tempname() * ".jl")
        add_cell!(nb, "x = 42")

        old_stdout = stdout
        rd, wr = redirect_stdout()
        try
            Sessions.run(nb; verbose=true)
        finally
            redirect_stdout(old_stdout)
            close(wr)
        end
        output = String(read(rd))

        @test occursin("Sessions.run", output)
        @test occursin("Cells: 1", output)
        @test occursin("Done:", output)
    end

    @testset "Sessions.run with errors" begin
        nb = Notebook()
        add_cell!(nb, "good = 1")
        add_cell!(nb, "bad = undefined_xyz + 1")

        Sessions.run(nb)

        cells = ordered_cells(nb)
        @test cells[1].state == cell_done
        @test cells[2].state == cell_errored
    end

    @testset "Sessions.run with reactive errors" begin
        nb = Notebook()
        add_cell!(nb, "conflict = 1")
        add_cell!(nb, "conflict = 2")

        Sessions.run(nb)

        cells = ordered_cells(nb)
        @test cells[1].state == cell_errored
        @test cells[2].state == cell_errored
    end

    @testset "Sessions.run folded notebook" begin
        nb = Sessions.run("test/fixtures/folded_notebook.jl")
        cells = ordered_cells(nb)

        @test cells[1].output.result == 42    # visible_var = 42
        @test cells[2].output.result == 100   # folded_var = 100
        @test cells[3].output.result == 142   # result = visible_var + folded_var
    end
end
