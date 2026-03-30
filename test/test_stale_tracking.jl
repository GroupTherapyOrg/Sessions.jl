@testset "Stale Tracking" begin
    @testset "source_hash is deterministic" begin
        c = Sessions.Cell(code="x = 1")
        h1 = Sessions.source_hash(c)
        h2 = Sessions.source_hash(c)
        @test h1 == h2
        @test !isempty(h1)
    end

    @testset "source_hash changes with code" begin
        c = Sessions.Cell(code="x = 1")
        h1 = Sessions.source_hash(c)
        c.code = "x = 2"
        h2 = Sessions.source_hash(c)
        @test h1 != h2
    end

    @testset "source_hash ignores whitespace" begin
        c1 = Sessions.Cell(code="x = 1")
        c2 = Sessions.Cell(code="  x = 1  ")
        @test Sessions.source_hash(c1) == Sessions.source_hash(c2)
    end

    @testset "never-run cell is not stale" begin
        c = Sessions.Cell(code="x = 1")
        @test Sessions.is_never_run(c)
        @test !Sessions.is_stale(c)
    end

    @testset "executed cell is not stale" begin
        c = Sessions.Cell(code="x = 1")
        Sessions.mark_executed!(c)
        @test !Sessions.is_never_run(c)
        @test !Sessions.is_stale(c)
    end

    @testset "edited cell becomes stale" begin
        c = Sessions.Cell(code="x = 1")
        Sessions.mark_executed!(c)
        c.code = "x = 2"
        @test Sessions.is_stale(c)
    end

    @testset "code change during execution preserves stale" begin
        # Simulate: capture hash before execution, then code changes
        c = Sessions.Cell(code="x = 1")
        executed_hash = Sessions.source_hash(c)
        # External edit changes code while cell is "running"
        c.code = "x = 999"
        # remote_execute_cell! sets produced_by_hash to the captured hash
        c.produced_by_hash = executed_hash
        # Cell should be stale because current code != executed code
        @test Sessions.is_stale(c)
    end

    @testset "code unchanged during execution is not stale" begin
        c = Sessions.Cell(code="x = 1")
        executed_hash = Sessions.source_hash(c)
        # No external edit — code stays the same
        c.produced_by_hash = executed_hash
        @test !Sessions.is_stale(c)
    end

    @testset "stale_cells returns correct cells" begin
        nb = Sessions.Notebook()
        c1 = Sessions.Cell(code="a = 1")
        c2 = Sessions.Cell(code="b = 2")
        c3 = Sessions.Cell(code="")  # empty — should not be stale
        Sessions.add_cell!(nb, c1)
        Sessions.add_cell!(nb, c2)
        Sessions.add_cell!(nb, c3)

        # Initially: c1 and c2 are never-run with code → should be in stale_cells
        sc = Sessions.stale_cells(nb)
        @test length(sc) == 2
        @test c1 in sc
        @test c2 in sc

        # Execute c1
        Sessions.mark_executed!(c1)
        sc = Sessions.stale_cells(nb)
        @test length(sc) == 1
        @test c2 in sc

        # Edit c1 after execution → stale again
        c1.code = "a = 100"
        sc = Sessions.stale_cells(nb)
        @test length(sc) == 2
    end

    @testset "WebNotebookState has interrupted field" begin
        nb = Sessions.Notebook()
        worker = Sessions.NotebookWorker()
        tab = Sessions.WebTab(Base.UUID(rand(UInt128)), nb, worker, "test.jl", "test.jl")
        state = Sessions.WebNotebookState([tab], 1, false, false)
        @test state.interrupted == false
        state.interrupted = true
        @test state.interrupted == true
    end
end
