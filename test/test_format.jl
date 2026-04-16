using Test
using Sessions
using UUIDs

@testset "format.jl" begin
    # Parser tests use inline strings instead of fixture files so test/fixtures/
    # can stay focused on user-facing demos (welcome.jl, interactive.jl, script.jl)
    # without their content needing to satisfy hard-coded assertions.

    @testset "parse — basic 3-cell notebook" begin
        content = """
            ### A Pluto.jl notebook ###
            # v0.19.0

            # ╔═╡ 00000001-0000-0000-0000-000000000001
            x = 1

            # ╔═╡ 00000002-0000-0000-0000-000000000002
            y = x + 1

            # ╔═╡ 00000003-0000-0000-0000-000000000003
            z = x * y

            # ╔═╡ Cell order:
            # ╠═00000001-0000-0000-0000-000000000001
            # ╠═00000002-0000-0000-0000-000000000002
            # ╠═00000003-0000-0000-0000-000000000003
            """
        nb = Sessions.parse_notebook(content; path="basic.jl")
        @test length(nb) == 3
        cells = ordered_cells(nb)
        @test cells[1].code == "x = 1"
        @test cells[2].code == "y = x + 1"
        @test cells[3].code == "z = x * y"
        @test all(c -> !c.folded, cells)
        @test cells[1].id == UUID("00000001-0000-0000-0000-000000000001")
    end

    @testset "parse — folded marker (╟─)" begin
        content = """
            ### A Pluto.jl notebook ###
            # v0.19.0

            # ╔═╡ aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
            visible_var = 42

            # ╔═╡ bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
            folded_var = 100

            # ╔═╡ Cell order:
            # ╠═aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
            # ╟─bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
            """
        nb = Sessions.parse_notebook(content; path="folded.jl")
        cells = ordered_cells(nb)
        @test cells[1].folded == false
        @test cells[2].folded == true
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

    @testset "is_notebook_file — detects Pluto notebooks" begin
        @test Sessions.is_notebook_file("test/fixtures/welcome.jl") == true
        @test Sessions.is_notebook_file("test/fixtures/interactive.jl") == true
    end

    @testset "is_notebook_file — rejects plain .jl files" begin
        @test Sessions.is_notebook_file("test/fixtures/script.jl") == false
        @test Sessions.is_notebook_file("src/Sessions.jl") == false
    end

    @testset "is_notebook_file — handles edge cases" begin
        @test Sessions.is_notebook_file("nonexistent_file.jl") == false
        @test Sessions.is_notebook_file("") == false
    end
end

# File editor tests removed (TUI layer deleted)
