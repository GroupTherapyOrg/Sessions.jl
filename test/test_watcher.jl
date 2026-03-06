using Test
using Sessions

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
end
