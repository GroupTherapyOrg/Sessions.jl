using Test
using Sessions
using UUIDs

@testset "types.jl" begin
    @testset "CellState enum" begin
        @test cell_idle isa Sessions.CellState
        @test cell_queued isa Sessions.CellState
        @test cell_running isa Sessions.CellState
        @test cell_done isa Sessions.CellState
        @test cell_errored isa Sessions.CellState
    end

    @testset "CellOutput" begin
        out = Sessions.CellOutput()
        @test out.result === nothing
        @test out.stdout == ""
        @test out.error === nothing
        @test out.runtime_ns == UInt64(0)

        out.result = 42
        @test out.result == 42

        out.stdout = "hello\n"
        @test out.stdout == "hello\n"
    end

    @testset "Cell construction" begin
        # Default constructor
        c = Sessions.Cell()
        @test c.id isa UUID
        @test c.code == ""
        @test c.state == cell_idle
        @test c.folded == false
        @test c.output isa Sessions.CellOutput

        # From code string
        c2 = Sessions.Cell("x = 1")
        @test c2.code == "x = 1"
        @test c2.state == cell_idle

        # With keyword args
        id = uuid4()
        c3 = Sessions.Cell(; id, code="y = 2", folded=true)
        @test c3.id == id
        @test c3.code == "y = 2"
        @test c3.folded == true
    end

    @testset "Cell mutability" begin
        c = Sessions.Cell("x = 1")
        c.code = "x = 2"
        @test c.code == "x = 2"
        c.state = cell_done
        @test c.state == cell_done
    end

    @testset "Notebook construction" begin
        nb = Sessions.Notebook()
        @test nb.path == "Untitled.jl"
        @test length(nb) == 0
        @test isempty(nb.cells)
        @test isempty(nb.cell_order)

        nb2 = Sessions.Notebook(; path="test.jl")
        @test nb2.path == "test.jl"
    end

    @testset "add_cell!" begin
        nb = Sessions.Notebook()

        # Add by Cell object
        c1 = Sessions.Cell("x = 1")
        Sessions.add_cell!(nb, c1)
        @test length(nb) == 1
        @test nb.cell_order[1] == c1.id
        @test Sessions.get_cell(nb, c1.id) === c1

        # Add by code string
        c2 = Sessions.add_cell!(nb, "y = 2")
        @test length(nb) == 2
        @test c2.code == "y = 2"
        @test nb.cell_order[2] == c2.id

        # Add folded cell
        c3 = Sessions.add_cell!(nb, "z = 3"; folded=true)
        @test c3.folded == true
        @test length(nb) == 3
    end

    @testset "insert_cell!" begin
        nb = Sessions.Notebook()
        c1 = Sessions.add_cell!(nb, "first")
        c2 = Sessions.add_cell!(nb, "third")

        c_mid = Sessions.Cell("second")
        Sessions.insert_cell!(nb, 2, c_mid)
        @test length(nb) == 3
        @test nb.cell_order == [c1.id, c_mid.id, c2.id]
    end

    @testset "remove_cell!" begin
        nb = Sessions.Notebook()
        c1 = Sessions.add_cell!(nb, "x = 1")
        c2 = Sessions.add_cell!(nb, "y = 2")
        c3 = Sessions.add_cell!(nb, "z = 3")

        removed = Sessions.remove_cell!(nb, c2.id)
        @test removed === c2
        @test length(nb) == 2
        @test nb.cell_order == [c1.id, c3.id]
        @test Sessions.get_cell(nb, c2.id) === nothing

        # Removing non-existent cell returns nothing
        @test Sessions.remove_cell!(nb, uuid4()) === nothing
    end

    @testset "ordered_cells" begin
        nb = Sessions.Notebook()
        c1 = Sessions.add_cell!(nb, "a")
        c2 = Sessions.add_cell!(nb, "b")
        c3 = Sessions.add_cell!(nb, "c")

        cells = Sessions.ordered_cells(nb)
        @test length(cells) == 3
        @test cells[1] === c1
        @test cells[2] === c2
        @test cells[3] === c3
    end

    @testset "swap_cell_up!" begin
        nb = Sessions.Notebook()
        c1 = Sessions.add_cell!(nb, "a")
        c2 = Sessions.add_cell!(nb, "b")
        c3 = Sessions.add_cell!(nb, "c")

        # Swap middle cell up
        @test swap_cell_up!(nb, 2) == true
        @test nb.cell_order == [c2.id, c1.id, c3.id]

        # Can't swap first cell up
        @test swap_cell_up!(nb, 1) == false
        @test nb.cell_order == [c2.id, c1.id, c3.id]

        # Out of range
        @test swap_cell_up!(nb, 0) == false
        @test swap_cell_up!(nb, 4) == false
    end

    @testset "swap_cell_down!" begin
        nb = Sessions.Notebook()
        c1 = Sessions.add_cell!(nb, "a")
        c2 = Sessions.add_cell!(nb, "b")
        c3 = Sessions.add_cell!(nb, "c")

        # Swap middle cell down
        @test swap_cell_down!(nb, 2) == true
        @test nb.cell_order == [c1.id, c3.id, c2.id]

        # Can't swap last cell down
        @test swap_cell_down!(nb, 3) == false
        @test nb.cell_order == [c1.id, c3.id, c2.id]

        # Out of range
        @test swap_cell_down!(nb, 0) == false
        @test swap_cell_down!(nb, 4) == false
    end

    @testset "swap preserves cells dict" begin
        nb = Sessions.Notebook()
        c1 = Sessions.add_cell!(nb, "x = 1")
        c2 = Sessions.add_cell!(nb, "y = 2")

        swap_cell_down!(nb, 1)
        @test Sessions.get_cell(nb, c1.id) === c1
        @test Sessions.get_cell(nb, c2.id) === c2
        @test Sessions.ordered_cells(nb) == [c2, c1]
    end

    @testset "get_cell" begin
        nb = Sessions.Notebook()
        c = Sessions.add_cell!(nb, "x = 1")

        @test Sessions.get_cell(nb, c.id) === c
        @test Sessions.get_cell(nb, uuid4()) === nothing
    end
end
