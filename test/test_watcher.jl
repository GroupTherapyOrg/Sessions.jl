using Test
using Sessions
using UUIDs

@testset "watcher.jl" begin
    @testset "watch_notebook creates a running watcher" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        add_cell!(nb, "x = 1")
        save_notebook(nb)

        handle = Sessions.watch_notebook(nb, _ -> nothing; poll_interval=0.1)
        @test handle isa Sessions.WatcherHandle
        @test handle.running[] == true
        @test !istaskdone(handle.task)

        Sessions.stop_watcher(handle)
        @test handle.running[] == false
        @test istaskdone(handle.task)

        rm(path; force=true)
    end

    @testset "watch_notebook detects changes" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        add_cell!(nb, "x = 1")
        save_notebook(nb)

        changed = Ref(false)
        handle = Sessions.watch_notebook(nb, _ -> (changed[] = true); poll_interval=0.1)

        # Modify the file after a short delay
        sleep(0.2)
        open(path, "a") do io
            println(io, "# modified")
        end
        sleep(0.5)  # Wait for poll + callback

        Sessions.stop_watcher(handle)
        @test changed[] == true

        rm(path; force=true)
    end

    @testset "watch_notebook errors on missing file" begin
        nb = Notebook(; path="/nonexistent/path.jl")
        @test_throws Exception Sessions.watch_notebook(nb, _ -> nothing)
    end

    # --- NotebookDiff tests ---

    @testset "diff_notebooks — no changes" begin
        nb1 = Notebook()
        c1 = add_cell!(nb1, "x = 1")
        c2 = add_cell!(nb1, "y = 2")

        # Clone via serialize/parse roundtrip
        nb2 = parse_notebook(serialize_notebook(nb1))

        diff = Sessions.diff_notebooks(nb1, nb2)
        @test isempty(diff.added)
        @test isempty(diff.removed)
        @test isempty(diff.changed)
        @test length(diff.unchanged) == 2
        @test c1.id in diff.unchanged
        @test c2.id in diff.unchanged
    end

    @testset "diff_notebooks — cell source changed" begin
        nb1 = Notebook()
        c1 = add_cell!(nb1, "x = 1")
        c2 = add_cell!(nb1, "y = 2")

        nb2 = parse_notebook(serialize_notebook(nb1))
        nb2.cells[c1.id].code = "x = 999"

        diff = Sessions.diff_notebooks(nb1, nb2)
        @test isempty(diff.added)
        @test isempty(diff.removed)
        @test length(diff.changed) == 1
        @test diff.changed[1] == (c1.id, "x = 999")
        @test length(diff.unchanged) == 1
        @test c2.id in diff.unchanged
    end

    @testset "diff_notebooks — cell added" begin
        nb1 = Notebook()
        c1 = add_cell!(nb1, "x = 1")

        nb2 = parse_notebook(serialize_notebook(nb1))
        new_cell = Cell("z = 3")
        add_cell!(nb2, new_cell)

        diff = Sessions.diff_notebooks(nb1, nb2)
        @test length(diff.added) == 1
        @test diff.added[1].id == new_cell.id
        @test diff.added[1].code == "z = 3"
        @test isempty(diff.removed)
        @test isempty(diff.changed)
    end

    @testset "diff_notebooks — cell removed" begin
        nb1 = Notebook()
        c1 = add_cell!(nb1, "x = 1")
        c2 = add_cell!(nb1, "y = 2")

        nb2 = parse_notebook(serialize_notebook(nb1))
        remove_cell!(nb2, c2.id)

        diff = Sessions.diff_notebooks(nb1, nb2)
        @test isempty(diff.added)
        @test length(diff.removed) == 1
        @test c2.id in diff.removed
        @test isempty(diff.changed)
    end

    @testset "diff_notebooks — reorder cells" begin
        nb1 = Notebook()
        c1 = add_cell!(nb1, "x = 1")
        c2 = add_cell!(nb1, "y = 2")

        nb2 = parse_notebook(serialize_notebook(nb1))
        nb2.cell_order = [c2.id, c1.id]

        diff = Sessions.diff_notebooks(nb1, nb2)
        @test isempty(diff.added)
        @test isempty(diff.removed)
        @test isempty(diff.changed)
        @test diff.new_order == [c2.id, c1.id]
    end

    @testset "apply_diff! — changed cell marked stale" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        mark_executed!(c1)
        c1.state = cell_done
        @test !is_stale(c1)

        nb2 = parse_notebook(serialize_notebook(nb))
        nb2.cells[c1.id].code = "x = 999"

        diff = Sessions.diff_notebooks(nb, nb2)
        Sessions.apply_diff!(nb, diff)

        @test c1.code == "x = 999"
        @test is_stale(c1)  # code changed → stale
    end

    @testset "apply_diff! — unchanged cell preserves output" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 42")
        mark_executed!(c1)
        c1.state = cell_done
        c1.output.result = 42

        nb2 = parse_notebook(serialize_notebook(nb))
        diff = Sessions.diff_notebooks(nb, nb2)
        Sessions.apply_diff!(nb, diff)

        @test c1.output.result == 42
        @test c1.state == cell_done
        @test !is_stale(c1)
    end

    @testset "apply_diff! — changed cell preserves old output" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 42")
        mark_executed!(c1)
        c1.state = cell_done
        c1.output.result = 42

        nb2 = parse_notebook(serialize_notebook(nb))
        nb2.cells[c1.id].code = "x = 99"

        diff = Sessions.diff_notebooks(nb, nb2)
        Sessions.apply_diff!(nb, diff)

        @test c1.code == "x = 99"
        @test c1.output.result == 42  # old output preserved until re-execution
        @test is_stale(c1)
    end

    @testset "apply_diff! — adds new cells" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")

        nb2 = parse_notebook(serialize_notebook(nb))
        new_cell = Cell("z = 3")
        add_cell!(nb2, new_cell)

        diff = Sessions.diff_notebooks(nb, nb2)
        Sessions.apply_diff!(nb, diff)

        @test length(nb) == 2
        @test nb.cell_order[2] == new_cell.id
        @test get_cell(nb, new_cell.id).code == "z = 3"
    end

    @testset "apply_diff! — removes cells" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "y = 2")

        nb2 = parse_notebook(serialize_notebook(nb))
        remove_cell!(nb2, c2.id)

        diff = Sessions.diff_notebooks(nb, nb2)
        Sessions.apply_diff!(nb, diff)

        @test length(nb) == 1
        @test get_cell(nb, c2.id) === nothing
    end

    @testset "apply_diff! — reorders cells" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "y = 2")
        @test nb.cell_order == [c1.id, c2.id]

        nb2 = parse_notebook(serialize_notebook(nb))
        nb2.cell_order = [c2.id, c1.id]

        diff = Sessions.diff_notebooks(nb, nb2)
        Sessions.apply_diff!(nb, diff)

        @test nb.cell_order == [c2.id, c1.id]
    end

    @testset "reload_notebook! — roundtrip no changes" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1")
        mark_executed!(c1)
        c1.state = cell_done
        c1.output.result = 1
        save_notebook(nb)

        diff = Sessions.reload_notebook!(nb)
        @test isempty(diff.added)
        @test isempty(diff.removed)
        @test isempty(diff.changed)
        @test c1.output.result == 1  # output preserved
        @test c1.state == cell_done

        rm(path; force=true)
    end

    @testset "reload_notebook! — detects external edit" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1")
        mark_executed!(c1)
        c1.state = cell_done
        save_notebook(nb)

        # Externally modify the file: change cell code
        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "x = 999"
        save_notebook(nb_ext, path)

        diff = Sessions.reload_notebook!(nb)
        @test length(diff.changed) == 1
        @test c1.code == "x = 999"
        @test is_stale(c1)

        rm(path; force=true)
    end

    @testset "reload_notebook! — detects added cell" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1")
        save_notebook(nb)

        # Externally add a cell
        nb_ext = load_notebook(path)
        new_cell = Cell("y = 2")
        add_cell!(nb_ext, new_cell)
        save_notebook(nb_ext, path)

        diff = Sessions.reload_notebook!(nb)
        @test length(diff.added) == 1
        @test length(nb) == 2
        @test get_cell(nb, new_cell.id).code == "y = 2"

        rm(path; force=true)
    end

    @testset "reload_notebook! — errors on missing file" begin
        nb = Notebook(; path="/nonexistent/path.jl")
        @test_throws Exception Sessions.reload_notebook!(nb)
    end

    @testset "diff_notebooks — combined add+change+remove" begin
        nb1 = Notebook()
        c1 = add_cell!(nb1, "a = 1")
        c2 = add_cell!(nb1, "b = 2")
        c3 = add_cell!(nb1, "c = 3")

        nb2 = parse_notebook(serialize_notebook(nb1))
        nb2.cells[c1.id].code = "a = 999"  # changed
        remove_cell!(nb2, c2.id)            # removed
        new_cell = Cell("d = 4")
        add_cell!(nb2, new_cell)            # added

        diff = Sessions.diff_notebooks(nb1, nb2)
        @test length(diff.changed) == 1
        @test length(diff.removed) == 1
        @test length(diff.added) == 1
        @test length(diff.unchanged) == 1
        @test c3.id in diff.unchanged
    end
end
