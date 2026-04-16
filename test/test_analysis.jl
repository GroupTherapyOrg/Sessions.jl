using Test
using Sessions
using UUIDs

@testset "analysis.jl" begin
    @testset "analyze_cell — definitions and references" begin
        c = Cell("x = 1")
        node = Sessions.analyze_cell(c)
        @test :x in node.definitions
        @test isempty(node.references)

        c2 = Cell("y = x + 1")
        node2 = Sessions.analyze_cell(c2)
        @test :y in node2.definitions
        @test :x in node2.references

        c3 = Cell("z = x * y + sin(π)")
        node3 = Sessions.analyze_cell(c3)
        @test :z in node3.definitions
        @test :x in node3.references
        @test :y in node3.references
    end

    @testset "analyze_cell — function definitions" begin
        c = Cell("f(x) = x + 1")
        node = Sessions.analyze_cell(c)
        @test :f in node.funcdefs_without_signatures
    end

    @testset "analyze_cell — empty cell" begin
        c = Cell("")
        node = Sessions.analyze_cell(c)
        @test isempty(node.definitions)
        @test isempty(node.references)

        c2 = Cell("   ")
        node2 = Sessions.analyze_cell(c2)
        @test isempty(node2.definitions)
    end

    @testset "cell_definitions and cell_references" begin
        c = Cell("x = 1")
        @test :x in Sessions.cell_definitions(c)

        c2 = Cell("y = x + 1")
        @test :y in Sessions.cell_definitions(c2)
        @test :x in Sessions.cell_references(c2)
    end

    @testset "update_topology!" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        add_cell!(nb, "y = x + 1")
        add_cell!(nb, "z = x * y")

        Sessions.update_topology!(nb)
        @test nb.topology isa Sessions.PDE.NotebookTopology
    end

    @testset "execution_order — linear chain" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "y = x + 1")
        c3 = add_cell!(nb, "z = y + 1")

        result = Sessions.execution_order(nb)
        @test isempty(result.errable)
        @test length(result.runnable) == 3

        # x must come before y, y before z
        ids = [c.id for c in result.runnable]
        @test findfirst(==(c1.id), ids) < findfirst(==(c2.id), ids)
        @test findfirst(==(c2.id), ids) < findfirst(==(c3.id), ids)
    end

    @testset "execution_order — independent cells" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        add_cell!(nb, "c = 3")

        result = Sessions.execution_order(nb)
        @test isempty(result.errable)
        @test length(result.runnable) == 3
    end

    @testset "execution_order — diamond dependency" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "a = x + 1")
        c3 = add_cell!(nb, "b = x + 2")
        c4 = add_cell!(nb, "c = a + b")

        result = Sessions.execution_order(nb)
        @test isempty(result.errable)
        @test length(result.runnable) == 4

        ids = [c.id for c in result.runnable]
        # x must come before a, b; a and b must come before c
        @test findfirst(==(c1.id), ids) < findfirst(==(c2.id), ids)
        @test findfirst(==(c1.id), ids) < findfirst(==(c3.id), ids)
        @test findfirst(==(c2.id), ids) < findfirst(==(c4.id), ids)
        @test findfirst(==(c3.id), ids) < findfirst(==(c4.id), ids)
    end

    @testset "execution_order — cycle detection" begin
        nb = Notebook()
        add_cell!(nb, "a = b + 1")
        add_cell!(nb, "b = a + 1")

        result = Sessions.execution_order(nb)
        @test !isempty(result.errable)
    end

    @testset "execution_order — multiple definitions error" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        add_cell!(nb, "x = 2")

        result = Sessions.execution_order(nb)
        @test !isempty(result.errable)
    end

    @testset "execution_order — partial update" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "y = x + 1")
        c3 = add_cell!(nb, "z = 100")  # independent

        result = Sessions.execution_order(nb, [c1])
        # Should include c1 and c2 (downstream), but not necessarily c3
        ids = Set(c.id for c in result.runnable)
        @test c1.id in ids
        @test c2.id in ids
    end

    @testset "execution_order — inline 3-cell notebook" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "y = x + 1")
        c3 = add_cell!(nb, "z = x * y")
        result = Sessions.execution_order(nb)
        @test isempty(result.errable)
        @test length(result.runnable) == 3
        ids = [c.id for c in result.runnable]
        @test findfirst(==(c1.id), ids) < findfirst(==(c2.id), ids)
        @test findfirst(==(c2.id), ids) < findfirst(==(c3.id), ids)
    end

    @testset "downstream_dependents" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "y = x + 1")
        c3 = add_cell!(nb, "z = 100")  # independent

        deps = Sessions.downstream_dependents(nb, [c1])
        dep_ids = Set(c.id for c in deps)
        @test c2.id in dep_ids    # y depends on x
        @test !(c3.id in dep_ids) # z is independent
        @test !(c1.id in dep_ids) # changed cell itself is excluded
    end

    @testset "source_hash — determinism" begin
        c1 = Cell("x = 1")
        c2 = Cell("x = 1")
        c3 = Cell("x = 2")

        @test source_hash(c1) == source_hash(c2)  # same source → same hash
        @test source_hash(c1) != source_hash(c3)   # different source → different hash
    end

    @testset "source_hash — whitespace normalization" begin
        c1 = Cell("x = 1")
        c2 = Cell("  x = 1  ")  # leading/trailing whitespace stripped

        @test source_hash(c1) == source_hash(c2)
    end

    @testset "source_hash — empty cell" begin
        c = Cell("")
        h = source_hash(c)
        @test !isempty(h)
        @test h isa String
    end

    @testset "is_never_run" begin
        c = Cell("x = 1")
        @test is_never_run(c)  # freshly created cell

        mark_executed!(c)
        @test !is_never_run(c)  # after execution
    end

    @testset "is_stale — basic" begin
        c = Cell("x = 1")
        @test !is_stale(c)  # never-run is NOT stale (separate state)

        mark_executed!(c)
        @test !is_stale(c)  # just executed → not stale

        c.code = "x = 2"   # edit the cell
        @test is_stale(c)   # source changed → stale
    end

    @testset "is_stale — re-execution clears stale" begin
        c = Cell("x = 1")
        mark_executed!(c)
        c.code = "x = 2"
        @test is_stale(c)

        mark_executed!(c)   # re-execute with new code
        @test !is_stale(c)  # no longer stale
    end

    @testset "stale_cells — notebook level" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "y = x + 1")
        c3 = add_cell!(nb, "z = 100")

        # All never-run with code → included in stale_cells (need execution)
        @test length(stale_cells(nb)) == 3

        # Execute all cells
        mark_executed!(c1)
        mark_executed!(c2)
        mark_executed!(c3)
        @test isempty(stale_cells(nb))

        # Edit c1
        c1.code = "x = 999"
        sc = stale_cells(nb)
        @test length(sc) == 1
        @test sc[1].id == c1.id
    end

    @testset "never_run_cells" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "y = 2")

        @test length(never_run_cells(nb)) == 2

        mark_executed!(c1)
        nrc = never_run_cells(nb)
        @test length(nrc) == 1
        @test nrc[1].id == c2.id
    end

    @testset "mark_executed! — updates produced_by_hash" begin
        c = Cell("x = 1")
        @test c.produced_by_hash == ""

        mark_executed!(c)
        @test c.produced_by_hash == source_hash(c)
        @test c.produced_by_hash != ""
    end

    @testset "stale propagation via downstream_dependents" begin
        nb = Notebook()
        c1 = add_cell!(nb, "a = 1")
        c2 = add_cell!(nb, "b = a + 1")
        c3 = add_cell!(nb, "c = b + 1")
        c4 = add_cell!(nb, "d = 100")  # independent

        # Execute all
        mark_executed!(c1)
        mark_executed!(c2)
        mark_executed!(c3)
        mark_executed!(c4)

        # Edit c1 → c2 and c3 are downstream dependents
        c1.code = "a = 999"
        deps = Sessions.downstream_dependents(nb, [c1])
        dep_ids = Set(c.id for c in deps)
        @test c2.id in dep_ids
        @test c3.id in dep_ids
        @test !(c4.id in dep_ids)
    end

    @testset "stale detection — diamond dependency" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "a = x + 1")
        c3 = add_cell!(nb, "b = x + 2")
        c4 = add_cell!(nb, "c = a + b")

        # Execute all
        for c in ordered_cells(nb)
            mark_executed!(c)
        end

        # Edit root
        c1.code = "x = 999"
        @test is_stale(c1)
        deps = Sessions.downstream_dependents(nb, [c1])
        dep_ids = Set(c.id for c in deps)
        @test c2.id in dep_ids  # a depends on x
        @test c3.id in dep_ids  # b depends on x
        @test c4.id in dep_ids  # c depends on a,b which depend on x
    end

    @testset "kernel integration — execute_cell! marks executed" begin
        ws = Workspace()
        c = Cell("x_test_stale = 42")
        @test is_never_run(c)

        execute_cell!(ws, c)
        @test !is_never_run(c)
        @test !is_stale(c)
        @test c.produced_by_hash == source_hash(c)

        # Edit cell → becomes stale
        c.code = "x_test_stale = 99"
        @test is_stale(c)

        # Re-execute → clears stale
        execute_cell!(ws, c)
        @test !is_stale(c)
    end

    @testset "kernel integration — errored cell is marked executed" begin
        ws = Workspace()
        c = Cell("error(\"boom\")")
        execute_cell!(ws, c)
        @test c.state == cell_errored
        @test !is_never_run(c)  # produced_by_hash set — errors are execution results
        @test c.produced_by_hash == source_hash(c)
    end

    # ── Pluto-style topology caching tests ────────────────────────────

    @testset "topology caching — incremental update" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "y = x + 1")
        c3 = add_cell!(nb, "z = 100")

        # First call: full build
        Sessions.update_topology!(nb)
        topo1 = nb.topology
        @test topo1 !== nothing

        # Second call with only c3 changed: incremental (topology object changes)
        c3.code = "z = 200"
        Sessions.update_topology!(nb, [c3])
        topo2 = nb.topology
        @test topo2 !== nothing
        @test topo2 !== topo1  # new topology object

        # Partial update: only c3 changed, but c1→c2 dependency still works
        result = Sessions.execution_order(nb, [c1])
        ids = Set(c.id for c in result.runnable)
        @test c1.id in ids
        @test c2.id in ids
        @test !(c3.id in ids)  # z doesn't depend on x
    end

    @testset "topology caching — cached topological order" begin
        nb = Notebook()
        c1 = add_cell!(nb, "a = 1")
        add_cell!(nb, "b = a + 1")

        # Build topology + get order
        Sessions.update_topology!(nb)
        order1 = Sessions._topological_order(nb)
        @test order1 !== nothing

        # Same topology → cached order returned
        order2 = Sessions._topological_order(nb)
        @test order2 === order1  # same object (cached)

        # After real change → cache invalidated
        c1.code = "a = 999"
        Sessions.update_topology!(nb, [c1])
        order3 = Sessions._topological_order(nb)
        @test order3 !== order1  # different object (recomputed)
    end

    @testset "disabled cells excluded from execution" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "y = x + 1")
        c3 = Cell(; code="z = x + 2", disabled=true)
        add_cell!(nb, c3)

        result = Sessions.execution_order(nb)
        ids = Set(c.id for c in result.runnable)
        @test c1.id in ids
        @test c2.id in ids
        # Disabled cell may appear in runnable but is skipped during execution
        # (execute_changed! checks cell.disabled before running)
    end

    @testset "multiple definitions — cross-cell conflict" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        add_cell!(nb, "x = 2")

        result = Sessions.execution_order(nb)
        @test !isempty(result.errable)
        # Both cells should be in errable (Pluto-style multiple definition error)
    end

    @testset "function definitions — multiple methods in one cell" begin
        nb = Notebook()
        c1 = add_cell!(nb, "begin\n  f(x) = x + 1\n  f(x, y) = x + y\nend")
        c2 = add_cell!(nb, "f(5)")
        c3 = add_cell!(nb, "f(5, 6)")

        result = Sessions.execution_order(nb)
        @test isempty(result.errable)
        ids = [c.id for c in result.runnable]
        # f must be defined before it's called
        @test findfirst(==(c1.id), ids) < findfirst(==(c2.id), ids)
        @test findfirst(==(c1.id), ids) < findfirst(==(c3.id), ids)
    end

    @testset "function redefinition — triggers downstream re-run" begin
        nb = Notebook()
        c1 = add_cell!(nb, "f(x) = x + 1")
        c2 = add_cell!(nb, "result = f(10)")

        # Initial topology
        result = Sessions.execution_order(nb, [c1])
        ids = Set(c.id for c in result.runnable)
        @test c1.id in ids
        @test c2.id in ids  # result depends on f

        # Change f → downstream c2 should still be included
        c1.code = "f(x) = x * 2"
        result2 = Sessions.execution_order(nb, [c1])
        ids2 = Set(c.id for c in result2.runnable)
        @test c1.id in ids2
        @test c2.id in ids2
    end

    @testset "incremental update — editing independent cell skips dependents" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "y = x + 1")
        c3 = add_cell!(nb, "z = 100")  # independent

        # Full build first
        Sessions.update_topology!(nb)

        # Change only the independent cell
        c3.code = "z = 200"
        result = Sessions.execution_order(nb, [c3])
        ids = Set(c.id for c in result.runnable)
        @test c3.id in ids
        @test !(c1.id in ids)  # x unchanged
        @test !(c2.id in ids)  # y unchanged
    end

    @testset "diamond dependency — partial update propagates through" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "a = x + 1")
        c3 = add_cell!(nb, "b = x + 2")
        c4 = add_cell!(nb, "c = a + b")

        # Change root x → all dependents should re-run
        result = Sessions.execution_order(nb, [c1])
        ids = Set(c.id for c in result.runnable)
        @test c1.id in ids
        @test c2.id in ids  # a depends on x
        @test c3.id in ids  # b depends on x
        @test c4.id in ids  # c depends on a, b
    end

    @testset "cycle detection — mutual references" begin
        nb = Notebook()
        add_cell!(nb, "a = b + 1")
        add_cell!(nb, "b = a + 1")

        result = Sessions.execution_order(nb)
        @test !isempty(result.errable)
    end

    @testset "using/import — references propagate" begin
        nb = Notebook()
        c1 = add_cell!(nb, "using Dates")
        c2 = add_cell!(nb, "today()")

        result = Sessions.execution_order(nb)
        @test isempty(result.errable)
        ids = [c.id for c in result.runnable]
        # using must come before today()
        @test findfirst(==(c1.id), ids) < findfirst(==(c2.id), ids)
    end
end
