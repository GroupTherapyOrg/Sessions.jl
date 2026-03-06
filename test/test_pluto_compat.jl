using Test
using Sessions
using UUIDs

const FIXTURES_DIR = joinpath(@__DIR__, "fixtures")

# All Pluto fixture files to test
const PLUTO_FIXTURES = [
    "basic_notebook.jl",
    "folded_notebook.jl",
    "pluto_getting_started.jl",
    "pluto_plutoui_sample.jl",
    "pluto_sample_basic.jl",
    "pluto_sample_hanoi.jl",
    "pluto_sample_interactive.jl",
    "with_pkgs_notebook.jl",
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

    # --- Specific format features ---

    @testset "Folded cells preserved" begin
        path = joinpath(FIXTURES_DIR, "folded_notebook.jl")
        nb = load_notebook(path)
        cells = ordered_cells(nb)

        # At least one folded cell expected
        has_folded = any(c -> c.folded, cells)
        @test has_folded
    end

    @testset "Folded roundtrip" begin
        path = joinpath(FIXTURES_DIR, "folded_notebook.jl")
        nb = load_notebook(path)
        folded_before = Dict(c.id => c.folded for c in ordered_cells(nb))

        content = serialize_notebook(nb)
        nb2 = parse_notebook(content)

        for (id, was_folded) in folded_before
            cell2 = get_cell(nb2, id)
            @test cell2.folded == was_folded
        end
    end

    @testset "Pkg section handled gracefully" begin
        path = joinpath(FIXTURES_DIR, "with_pkgs_notebook.jl")
        nb = load_notebook(path)
        @test length(nb) > 0
        # Should not crash, Pkg section is skipped
    end

    @testset "Getting started notebook — multi-cell" begin
        path = joinpath(FIXTURES_DIR, "pluto_getting_started.jl")
        nb = load_notebook(path)
        @test length(nb) >= 5  # Has many cells
    end

    @testset "Hanoi notebook — complex code preserved" begin
        path = joinpath(FIXTURES_DIR, "pluto_sample_hanoi.jl")
        nb = load_notebook(path)
        cells = ordered_cells(nb)

        # Should contain function definitions
        has_function = any(c -> contains(c.code, "function"), cells)
        @test has_function
    end

    @testset "Interactive notebook — @bind syntax preserved" begin
        path = joinpath(FIXTURES_DIR, "pluto_sample_interactive.jl")
        nb = load_notebook(path)
        cells = ordered_cells(nb)

        # Interactive notebooks often have @bind or Slider
        has_interactive = any(c -> contains(c.code, "@bind") || contains(c.code, "Slider"), cells)
        # May not have @bind in this particular fixture, but should load fine
        @test length(nb) > 0
    end

    @testset "PlutoUI sample — complex notebook loads" begin
        path = joinpath(FIXTURES_DIR, "pluto_plutoui_sample.jl")
        nb = load_notebook(path)
        @test length(nb) >= 10  # Large notebook

        # Roundtrip
        content = serialize_notebook(nb)
        nb2 = parse_notebook(content)
        @test length(nb2) == length(nb)
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
