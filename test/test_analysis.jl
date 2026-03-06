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

    @testset "build_topology" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        add_cell!(nb, "y = x + 1")
        add_cell!(nb, "z = x * y")

        topology, session_cells = Sessions.build_topology(nb)
        @test length(session_cells) == 3
        @test topology isa Sessions.PDE.NotebookTopology
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

    @testset "execution_order from loaded notebook" begin
        nb = load_notebook("test/fixtures/basic_notebook.jl")
        result = Sessions.execution_order(nb)
        @test isempty(result.errable)
        @test length(result.runnable) == 3

        cells = ordered_cells(nb)
        ids = [c.id for c in result.runnable]
        # x=1 must run before y=x+1, and both before z=x*y
        @test findfirst(==(cells[1].id), ids) < findfirst(==(cells[2].id), ids)
        @test findfirst(==(cells[2].id), ids) < findfirst(==(cells[3].id), ids)
    end
end
