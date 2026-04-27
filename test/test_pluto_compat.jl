using Test
using Sessions
using UUIDs

const FIXTURES_DIR = joinpath(@__DIR__, "fixtures")

# Pluto-format fixtures we actually ship (curated to demo files in
# de66a12 — see test/fixtures/{welcome,interactive}.jl).
const PLUTO_FIXTURES = [
    "welcome.jl",
    "interactive.jl",
]

@testset "Pluto compatibility" begin

    # --- Load tests for each fixture ---

    @testset "Load $name — non-empty" for name in PLUTO_FIXTURES
        path = joinpath(FIXTURES_DIR, name)
        nb = load_notebook(path)
        @test length(nb) > 0
    end

    @testset "Load $name — valid UUIDs" for name in PLUTO_FIXTURES
        path = joinpath(FIXTURES_DIR, name)
        nb = load_notebook(path)
        for cell in ordered_cells(nb)
            @test cell.id isa UUID
        end
    end

    @testset "Load $name — cell_order complete" for name in PLUTO_FIXTURES
        path = joinpath(FIXTURES_DIR, name)
        nb = load_notebook(path)
        @test length(nb.cell_order) == length(nb.cells)
        for id in nb.cell_order
            @test haskey(nb.cells, id)
        end
    end

    @testset "Load $name — cells have code" for name in PLUTO_FIXTURES
        path = joinpath(FIXTURES_DIR, name)
        nb = load_notebook(path)
        for cell in ordered_cells(nb)
            @test cell.code isa String
        end
    end

    # --- Round-trip tests ---

    @testset "Roundtrip $name — save+load preserves cells" for name in PLUTO_FIXTURES
        path = joinpath(FIXTURES_DIR, name)
        nb = load_notebook(path)

        # Serialize → parse → compare
        content = serialize_notebook(nb)
        nb2 = parse_notebook(content; path=nb.path)

        @test length(nb2) == length(nb)
        @test nb2.cell_order == nb.cell_order

        for (id, cell) in nb.cells
            cell2 = get_cell(nb2, id)
            @test cell2 !== nothing
            @test cell2.code == cell.code
        end
    end

    # --- Specific format features (against shipped fixtures) ---

    @testset "Folded cells preserved (welcome.jl)" begin
        # welcome.jl is the markdown showcase — every cell is hidden so
        # the rendered output IS the experience. That makes it a natural
        # fold-flag fixture too.
        path = joinpath(FIXTURES_DIR, "welcome.jl")
        nb = load_notebook(path)
        @test any(c -> c.folded, ordered_cells(nb))
    end

    @testset "Folded roundtrip (welcome.jl)" begin
        path = joinpath(FIXTURES_DIR, "welcome.jl")
        nb = load_notebook(path)
        folded_before = Dict(c.id => c.folded for c in ordered_cells(nb))
        nb2 = parse_notebook(serialize_notebook(nb))
        for (id, was_folded) in folded_before
            cell2 = get_cell(nb2, id)
            @test cell2.folded == was_folded
        end
    end

    @testset "Pkg section handled gracefully (interactive.jl)" begin
        # interactive.jl opens with Pkg.activate(mktempdir()) + Pkg.add
        # cells, so it exercises the Pkg-bootstrap path through the
        # notebook parser without needing a separate fixture.
        path = joinpath(FIXTURES_DIR, "interactive.jl")
        nb = load_notebook(path)
        @test length(nb) > 0
    end

    @testset "Interactive notebook — @bind syntax preserved" begin
        path = joinpath(FIXTURES_DIR, "interactive.jl")
        nb = load_notebook(path)
        @test any(c -> contains(c.code, "@bind"), ordered_cells(nb))
    end

    # --- Parse robustness ---

    @testset "Empty notebook" begin
        content = """### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ Cell order:
"""
        nb = parse_notebook(content)
        @test length(nb) == 0
    end

    @testset "Single cell notebook" begin
        content = """### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 00000001-0000-0000-0000-000000000001
x = 42

# ╔═╡ Cell order:
# ╠═00000001-0000-0000-0000-000000000001
"""
        nb = parse_notebook(content)
        @test length(nb) == 1
        cells = ordered_cells(nb)
        @test cells[1].code == "x = 42"
    end

    @testset "Multiple cells with dependencies" begin
        content = """### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 00000001-0000-0000-0000-000000000001
a = 1

# ╔═╡ 00000002-0000-0000-0000-000000000002
b = a + 1

# ╔═╡ 00000003-0000-0000-0000-000000000003
c = a * b

# ╔═╡ Cell order:
# ╠═00000001-0000-0000-0000-000000000001
# ╠═00000002-0000-0000-0000-000000000002
# ╠═00000003-0000-0000-0000-000000000003
"""
        nb = parse_notebook(content)
        @test length(nb) == 3
        cells = ordered_cells(nb)
        @test cells[1].code == "a = 1"
        @test cells[2].code == "b = a + 1"
        @test cells[3].code == "c = a * b"
    end

    @testset "Multiline cell code" begin
        content = """### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 00000001-0000-0000-0000-000000000001
function foo(x)
    x^2
end

# ╔═╡ Cell order:
# ╠═00000001-0000-0000-0000-000000000001
"""
        nb = parse_notebook(content)
        cells = ordered_cells(nb)
        @test contains(cells[1].code, "function foo(x)")
        @test contains(cells[1].code, "x^2")
        @test contains(cells[1].code, "end")
    end

    @testset "Mixed folded and visible cells" begin
        content = """### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 00000001-0000-0000-0000-000000000001
x = 1

# ╔═╡ 00000002-0000-0000-0000-000000000002
md"# Hidden"

# ╔═╡ Cell order:
# ╠═00000001-0000-0000-0000-000000000001
# ╟─00000002-0000-0000-0000-000000000002
"""
        nb = parse_notebook(content)
        cells = ordered_cells(nb)
        @test cells[1].folded == false
        @test cells[2].folded == true
    end

    # --- Serialization format ---

    @testset "Serialize includes header" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        content = serialize_notebook(nb)
        @test startswith(content, "### A Pluto.jl notebook ###")
    end

    @testset "Serialize includes cell order" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        content = serialize_notebook(nb)
        @test contains(content, "# ╔═╡ Cell order:")
    end

    @testset "Serialize preserves cell UUIDs" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        content = serialize_notebook(nb)
        @test contains(content, string(c1.id))
    end

    @testset "Serialize + parse is identity" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "y = x + 1"; folded=true)

        content = serialize_notebook(nb)
        nb2 = parse_notebook(content)

        @test length(nb2) == 2
        @test get_cell(nb2, c1.id).code == "x = 1"
        @test get_cell(nb2, c2.id).code == "y = x + 1"
        @test get_cell(nb2, c2.id).folded == true
    end
end
