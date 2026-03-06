using Test
using Sessions
using UUIDs

@testset "kernel.jl" begin
    @testset "Workspace creation" begin
        ws = Sessions.Workspace()
        @test ws.mod isa Module
        @test ws.ns isa Symbol

        # Each workspace gets a unique module
        ws2 = Sessions.Workspace()
        @test ws.ns != ws2.ns
    end

    @testset "execute_cell! — simple assignment" begin
        ws = Sessions.Workspace()
        cell = Cell("x = 42")
        Sessions.execute_cell!(ws, cell)

        @test cell.state == cell_done
        @test cell.output.result == 42
        @test cell.output.error === nothing
        @test cell.output.runtime_ns > 0
    end

    @testset "execute_cell! — stdout capture" begin
        ws = Sessions.Workspace()
        cell = Cell("println(\"hello world\")")
        Sessions.execute_cell!(ws, cell)

        @test cell.state == cell_done
        @test cell.output.stdout == "hello world\n"
    end

    @testset "execute_cell! — error handling" begin
        ws = Sessions.Workspace()
        cell = Cell("error(\"test error\")")
        Sessions.execute_cell!(ws, cell)

        @test cell.state == cell_errored
        @test cell.output.error !== nothing
        @test cell.output.result === nothing
    end

    @testset "execute_cell! — variable persistence in workspace" begin
        ws = Sessions.Workspace()

        c1 = Cell("a = 10")
        Sessions.execute_cell!(ws, c1)
        @test c1.output.result == 10

        c2 = Cell("b = a + 5")
        Sessions.execute_cell!(ws, c2)
        @test c2.output.result == 15
    end

    @testset "execute_cell! — multiline code" begin
        ws = Sessions.Workspace()
        cell = Cell("function square(n)\n    n^2\nend")
        Sessions.execute_cell!(ws, cell)
        @test cell.state == cell_done

        cell2 = Cell("square(7)")
        Sessions.execute_cell!(ws, cell2)
        @test cell2.output.result == 49
    end

    @testset "execute_cell! — undefined variable error" begin
        ws = Sessions.Workspace()
        cell = Cell("result = undefined_var + 1")
        Sessions.execute_cell!(ws, cell)

        @test cell.state == cell_errored
        @test cell.output.error !== nothing
    end

    @testset "execute_notebook! — basic reactive execution" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 10")
        c2 = add_cell!(nb, "y = x + 5")
        c3 = add_cell!(nb, "z = x * y")

        Sessions.execute_notebook!(nb)

        @test c1.state == cell_done
        @test c1.output.result == 10

        @test c2.state == cell_done
        @test c2.output.result == 15

        @test c3.state == cell_done
        @test c3.output.result == 150
    end

    @testset "execute_notebook! — out of order cells" begin
        nb = Notebook()
        # Cells in reverse dependency order
        c1 = add_cell!(nb, "result = a + b")
        c2 = add_cell!(nb, "b = a * 2")
        c3 = add_cell!(nb, "a = 5")

        Sessions.execute_notebook!(nb)

        # All should succeed despite being out of order
        @test c3.output.result == 5
        @test c2.output.result == 10
        @test c1.output.result == 15
    end

    @testset "execute_notebook! — cycle detection marks cells as errored" begin
        nb = Notebook()
        c1 = add_cell!(nb, "p = q + 1")
        c2 = add_cell!(nb, "q = p + 1")

        Sessions.execute_notebook!(nb)

        # Both cells should be errored (cycle)
        @test c1.state == cell_errored
        @test c2.state == cell_errored
    end

    @testset "execute_notebook! — multiple definitions marks cells as errored" begin
        nb = Notebook()
        c1 = add_cell!(nb, "dup = 1")
        c2 = add_cell!(nb, "dup = 2")

        Sessions.execute_notebook!(nb)

        @test c1.state == cell_errored
        @test c2.state == cell_errored
    end

    @testset "execute_notebook! — loaded fixture" begin
        nb = load_notebook("test/fixtures/basic_notebook.jl")
        Sessions.execute_notebook!(nb)

        cells = ordered_cells(nb)
        # x = 1
        @test cells[1].output.result == 1
        # y = x + 1
        @test cells[2].output.result == 2
        # z = x * y
        @test cells[3].output.result == 2
    end

    @testset "execute_changed! — partial re-execution" begin
        nb = Notebook()
        c1 = add_cell!(nb, "base_val = 10")
        c2 = add_cell!(nb, "derived = base_val + 1")
        c3 = add_cell!(nb, "independent = 999")

        ws = Sessions.Workspace()
        Sessions.execute_notebook!(nb; workspace=ws)

        @test c1.output.result == 10
        @test c2.output.result == 11
        @test c3.output.result == 999

        # Change c1
        c1.code = "base_val = 20"
        Sessions.execute_changed!(nb, [c1]; workspace=ws)

        @test c1.output.result == 20
        @test c2.output.result == 21
    end

    @testset "workspace isolation" begin
        ws1 = Sessions.Workspace()
        ws2 = Sessions.Workspace()

        c1 = Cell("isolated_var = 42")
        Sessions.execute_cell!(ws1, c1)

        c2 = Cell("isolated_var")
        Sessions.execute_cell!(ws2, c2)

        # ws2 shouldn't see ws1's variable
        @test c2.state == cell_errored
    end
end
