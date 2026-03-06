using Test
using Sessions
using UUIDs

@testset "format.jl" begin
    @testset "parse basic_notebook.jl" begin
        nb = Sessions.load_notebook("test/fixtures/test_basic.jl")
        @test nb.path == "test/fixtures/test_basic.jl"
        @test length(nb) == 3

        cells = ordered_cells(nb)
        @test cells[1].code == "x = 1"
        @test cells[2].code == "y = x + 1"
        @test cells[3].code == "z = x * y"

        # All cells should be visible (not folded)
        @test all(c -> !c.folded, cells)

        # UUIDs should match fixture
        @test cells[1].id == UUID("00000001-0000-0000-0000-000000000001")
        @test cells[2].id == UUID("00000002-0000-0000-0000-000000000002")
        @test cells[3].id == UUID("00000003-0000-0000-0000-000000000003")
    end

    @testset "parse folded_notebook.jl" begin
        nb = Sessions.load_notebook("test/fixtures/folded_notebook.jl")
        @test length(nb) == 3

        cells = ordered_cells(nb)
        @test cells[1].folded == false
        @test cells[2].folded == true   # ╟─ = folded
        @test cells[3].folded == false

        @test cells[1].code == "# This cell is visible\nvisible_var = 42"
        @test cells[2].code == "# This cell is folded (hidden by default)\nfolded_var = 100"
        @test cells[3].code == "# Another visible cell\nresult = visible_var + folded_var"
    end

    @testset "parse pluto_sample_basic.jl" begin
        nb = Sessions.load_notebook("test/fixtures/pluto_sample_basic.jl")
        @test length(nb) == 4

        cells = ordered_cells(nb)
        # Cell order in file differs from definition order
        # First in order is the markdown cell (folded)
        @test cells[1].folded == true
        @test occursin("Basel problem", cells[1].code)

        # Other cells are visible
        @test cells[2].folded == false
        @test cells[3].folded == false
        @test cells[4].folded == false
    end

    @testset "parse with_pkgs_notebook.jl" begin
        nb = Sessions.load_notebook("test/fixtures/with_pkgs_notebook.jl")
        @test length(nb) == 3

        cells = ordered_cells(nb)
        @test cells[1].code == "using Statistics"
        @test cells[2].code == "data = [1, 2, 3, 4, 5]"
        @test cells[3].code == "mean_value = mean(data)"
    end

    @testset "serialize_notebook roundtrip" begin
        # Create a notebook programmatically
        nb = Notebook(; path="test_roundtrip.jl")
        id1 = UUID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        id2 = UUID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        id3 = UUID("cccccccc-cccc-cccc-cccc-cccccccccccc")

        add_cell!(nb, Cell(; id=id1, code="x = 1"))
        add_cell!(nb, Cell(; id=id2, code="y = x + 1", folded=true))
        add_cell!(nb, Cell(; id=id3, code="z = x * y"))

        content = Sessions.serialize_notebook(nb)

        # Verify header
        @test startswith(content, "### A Pluto.jl notebook ###\n")

        # Verify cell markers present
        @test occursin("# ╔═╡ aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", content)
        @test occursin("# ╔═╡ bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", content)

        # Verify cell order section
        @test occursin("# ╔═╡ Cell order:", content)
        @test occursin("# ╠═aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", content)
        @test occursin("# ╟─bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", content)  # folded
        @test occursin("# ╠═cccccccc-cccc-cccc-cccc-cccccccccccc", content)

        # Roundtrip: parse the serialized content
        nb2 = Sessions.parse_notebook(content; path="test_roundtrip.jl")
        @test length(nb2) == 3

        cells2 = ordered_cells(nb2)
        @test cells2[1].id == id1
        @test cells2[1].code == "x = 1"
        @test cells2[1].folded == false

        @test cells2[2].id == id2
        @test cells2[2].code == "y = x + 1"
        @test cells2[2].folded == true

        @test cells2[3].id == id3
        @test cells2[3].code == "z = x * y"
        @test cells2[3].folded == false
    end

    @testset "save_notebook and reload" begin
        nb = Notebook(; path=tempname() * ".jl")
        add_cell!(nb, Cell(; code="a = 1"))
        add_cell!(nb, Cell(; code="b = a + 1"))

        Sessions.save_notebook(nb)
        @test isfile(nb.path)

        nb2 = Sessions.load_notebook(nb.path)
        @test length(nb2) == 2
        cells2 = ordered_cells(nb2)
        @test cells2[1].code == "a = 1"
        @test cells2[2].code == "b = a + 1"

        # Cleanup
        rm(nb.path; force=true)
    end

    @testset "empty notebook" begin
        nb = Notebook(; path="empty.jl")
        content = Sessions.serialize_notebook(nb)
        @test startswith(content, "### A Pluto.jl notebook ###")
        @test occursin("# ╔═╡ Cell order:", content)

        nb2 = Sessions.parse_notebook(content)
        @test length(nb2) == 0
    end

    @testset "multiline cell code" begin
        nb = Notebook()
        code = "function foo(x)\n    return x + 1\nend"
        add_cell!(nb, Cell(; code))

        content = Sessions.serialize_notebook(nb)
        nb2 = Sessions.parse_notebook(content)
        cells = ordered_cells(nb2)
        @test cells[1].code == code
    end
end
