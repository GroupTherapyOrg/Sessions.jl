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
        @test isempty(diff.metadata_changed)
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

    @testset "diff_notebooks — folded state changed" begin
        nb1 = Notebook()
        c1 = add_cell!(nb1, "x = 1")
        c2 = add_cell!(nb1, "y = 2")

        nb2 = parse_notebook(serialize_notebook(nb1))
        nb2.cells[c1.id].folded = true  # fold cell on disk

        diff = Sessions.diff_notebooks(nb1, nb2)
        @test isempty(diff.added)
        @test isempty(diff.removed)
        @test isempty(diff.changed)
        @test length(diff.metadata_changed) == 1
        @test diff.metadata_changed[1] == (c1.id, true, false)
        @test length(diff.unchanged) == 1
        @test c2.id in diff.unchanged
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

    # --- DebouncedWatcher tests ---

    @testset "DebouncedWatcher — single change fires callback" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        add_cell!(nb, "x = 1")
        save_notebook(nb)

        fired = Ref(0)
        dw = Sessions.DebouncedWatcher(nb, _ -> (fired[] += 1);
                                       delay=0.1, poll_interval=0.1)
        Sessions.start_watching!(dw)

        sleep(0.2)
        open(path, "a") do io
            println(io, "# change1")
        end
        sleep(0.5)  # poll + debounce + margin

        Sessions.stop_watching!(dw)
        @test fired[] == 1

        rm(path; force=true)
    end

    @testset "DebouncedWatcher — rapid changes coalesce" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        add_cell!(nb, "x = 1")
        save_notebook(nb)

        fired = Ref(0)
        dw = Sessions.DebouncedWatcher(nb, _ -> (fired[] += 1);
                                       delay=0.3, poll_interval=0.05)
        Sessions.start_watching!(dw)

        # Rapid changes within debounce window
        sleep(0.1)
        for i in 1:5
            open(path, "a") do io
                println(io, "# rapid$i")
            end
            sleep(0.06)  # within 0.3s debounce
        end
        sleep(0.5)  # wait for debounce to fire

        Sessions.stop_watching!(dw)
        # Should fire at most once (all changes coalesced)
        @test fired[] <= 1

        rm(path; force=true)
    end

    @testset "DebouncedWatcher — configurable delay" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        add_cell!(nb, "x = 1")
        save_notebook(nb)

        dw = Sessions.DebouncedWatcher(nb, _ -> nothing;
                                       delay=0.5, poll_interval=0.1)
        @test dw.delay == 0.5
        @test dw.poll_interval == 0.1

        rm(path; force=true)
    end

    @testset "DebouncedWatcher — stop cancels pending" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        add_cell!(nb, "x = 1")
        save_notebook(nb)

        fired = Ref(0)
        dw = Sessions.DebouncedWatcher(nb, _ -> (fired[] += 1);
                                       delay=1.0, poll_interval=0.1)
        Sessions.start_watching!(dw)

        sleep(0.2)
        open(path, "a") do io
            println(io, "# change")
        end
        sleep(0.2)  # poll triggers but debounce timer hasn't fired yet

        Sessions.stop_watching!(dw)
        @test dw.pending[] == false
        @test dw.handle === nothing
        sleep(1.0)  # wait past what would have been the debounce
        @test fired[] == 0  # callback should NOT have fired

        rm(path; force=true)
    end

    @testset "DebouncedWatcher — start is idempotent" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        add_cell!(nb, "x = 1")
        save_notebook(nb)

        dw = Sessions.DebouncedWatcher(nb, _ -> nothing;
                                       delay=0.1, poll_interval=0.1)
        Sessions.start_watching!(dw)
        handle1 = dw.handle
        Sessions.start_watching!(dw)  # should be no-op
        @test dw.handle === handle1

        Sessions.stop_watching!(dw)
        rm(path; force=true)
    end

    @testset "DebouncedWatcher — changes after quiet period fire again" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        add_cell!(nb, "x = 1")
        save_notebook(nb)

        fired = Ref(0)
        dw = Sessions.DebouncedWatcher(nb, _ -> (fired[] += 1);
                                       delay=0.1, poll_interval=0.1)
        Sessions.start_watching!(dw)

        # First change
        sleep(0.2)
        open(path, "a") do io
            println(io, "# first")
        end
        sleep(0.4)  # wait for debounce to fire
        count_after_first = fired[]

        # Second change after quiet period
        open(path, "a") do io
            println(io, "# second")
        end
        sleep(0.4)  # wait for debounce to fire

        Sessions.stop_watching!(dw)
        @test fired[] >= count_after_first  # at least as many as after first
        @test fired[] >= 1  # at least one fired

        rm(path; force=true)
    end

    # --- Smart merge tests (SESSIONS-6018) ---

    @testset "merge_external_changes! — user local edit + agent disk edit both preserved" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "a = 1")
        c2 = add_cell!(nb, "b = 2")
        save_notebook(nb)

        # Take snapshot (simulates last_disk_nb)
        last_disk_nb = deepcopy(nb)

        # User edits c1 locally (in-memory only)
        nb.cells[c1.id].code = "a = 100"

        # Agent edits c2 on disk
        nb_ext = load_notebook(path)
        nb_ext.cells[c2.id].code = "b = 200"
        save_notebook(nb_ext, path)

        # Smart merge: should update c2 from disk, preserve user's c1 edit
        diff = Sessions.merge_external_changes!(nb, last_disk_nb)

        @test nb.cells[c1.id].code == "a = 100"  # user edit preserved
        @test nb.cells[c2.id].code == "b = 200"  # agent edit applied
        @test length(diff.changed) == 1
        @test diff.changed[1][1] == c2.id
    end

    @testset "merge_external_changes! — agent adds cell, user has local edits" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1")
        save_notebook(nb)

        last_disk_nb = deepcopy(nb)

        # User edits c1 locally
        nb.cells[c1.id].code = "x = 999"

        # Agent adds a new cell on disk
        nb_ext = load_notebook(path)
        c2 = add_cell!(nb_ext, "y = 2")
        save_notebook(nb_ext, path)

        diff = Sessions.merge_external_changes!(nb, last_disk_nb)

        @test nb.cells[c1.id].code == "x = 999"  # user edit preserved
        @test haskey(nb.cells, c2.id)             # agent cell added
        @test nb.cells[c2.id].code == "y = 2"
        @test length(diff.added) == 1
    end

    @testset "merge_external_changes! — agent removes cell" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "a = 1")
        c2 = add_cell!(nb, "b = 2")
        save_notebook(nb)

        last_disk_nb = deepcopy(nb)

        # Agent removes c2 on disk
        nb_ext = load_notebook(path)
        remove_cell!(nb_ext, c2.id)
        save_notebook(nb_ext, path)

        diff = Sessions.merge_external_changes!(nb, last_disk_nb)

        @test haskey(nb.cells, c1.id)
        @test !haskey(nb.cells, c2.id)
        @test length(diff.removed) == 1
    end

    @testset "merge_external_changes! — agent reorders cells" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "first = 1")
        c2 = add_cell!(nb, "second = 2")
        save_notebook(nb)

        last_disk_nb = deepcopy(nb)

        # Agent reorders on disk
        nb_ext = load_notebook(path)
        nb_ext.cell_order = [c2.id, c1.id]
        save_notebook(nb_ext, path)

        diff = Sessions.merge_external_changes!(nb, last_disk_nb)

        @test nb.cell_order == [c2.id, c1.id]
    end

    @testset "merge_external_changes! — changed cell becomes stale" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "s = 1")
        mark_executed!(c1)
        c1.state = cell_done
        c1.output.result = 1
        save_notebook(nb)

        last_disk_nb = deepcopy(nb)

        # Agent changes c1 on disk
        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "s = 999"
        save_notebook(nb_ext, path)

        Sessions.merge_external_changes!(nb, last_disk_nb)

        @test nb.cells[c1.id].code == "s = 999"
        @test is_stale(nb.cells[c1.id])
        @test nb.cells[c1.id].output.result == 1  # old output preserved
    end

    @testset "merge_external_changes! — no disk changes is no-op" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "noop = 42")
        save_notebook(nb)

        last_disk_nb = deepcopy(nb)

        # User edits locally
        nb.cells[c1.id].code = "noop = 999"

        diff = Sessions.merge_external_changes!(nb, last_disk_nb)

        @test isempty(diff.added)
        @test isempty(diff.removed)
        @test isempty(diff.changed)
        @test nb.cells[c1.id].code == "noop = 999"  # user edit preserved

        rm(path; force=true)
    end

    @testset "merge_external_changes! — combined add+change+remove" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "a = 1")
        c2 = add_cell!(nb, "b = 2")
        c3 = add_cell!(nb, "c = 3")
        save_notebook(nb)

        last_disk_nb = deepcopy(nb)

        # User edits c3 locally
        nb.cells[c3.id].code = "c = 300"

        # Agent: change c1, remove c2, add c4
        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "a = 100"
        remove_cell!(nb_ext, c2.id)
        c4 = add_cell!(nb_ext, "d = 4")
        save_notebook(nb_ext, path)

        diff = Sessions.merge_external_changes!(nb, last_disk_nb)

        @test nb.cells[c1.id].code == "a = 100"   # agent change
        @test !haskey(nb.cells, c2.id)              # agent removal
        @test nb.cells[c3.id].code == "c = 300"    # user edit preserved
        @test haskey(nb.cells, c4.id)               # agent addition
        @test nb.cells[c4.id].code == "d = 4"

        @test length(diff.changed) == 1
        @test length(diff.removed) == 1
        @test length(diff.added) == 1

        rm(path; force=true)
    end
end
