@testset "API Routes" begin

    # ── Notebook API route definitions ──
    @testset "notebook_api_routes returns route pairs" begin
        routes_file = joinpath(@__DIR__, "..", "src", "api", "notebook.jl")
        @test isfile(routes_file)
        fn = include(routes_file)
        @test fn isa Function

        state = Sessions.WebNotebookState(
            [Sessions.WebTab(uuid4(), Sessions.Notebook(; path="test.jl"),
                Sessions.NotebookWorker(), "test.jl", abspath("test.jl"))],
            1, false, false)

        routes = fn(() -> state)
        @test routes isa Vector
        @test length(routes) == 4

        paths = [r.first for r in routes]
        @test "/api/notebook" in paths
        @test "/api/notebook/open" in paths
        @test "/api/notebook/save" in paths
        @test "/api/notebook/export" in paths
    end

    @testset "notebook GET handler returns tab list" begin
        nb = Sessions.Notebook(; path="mynotebook.jl")
        Sessions.add_cell!(nb, "x = 1")
        worker = Sessions.NotebookWorker()
        tab = Sessions.WebTab(uuid4(), nb, worker, "mynotebook.jl", abspath("mynotebook.jl"))
        state = Sessions.WebNotebookState([tab], 1, false, false)

        routes_file = joinpath(@__DIR__, "..", "src", "api", "notebook.jl")
        fn = include(routes_file)
        routes = fn(() -> state)

        get_handler = routes[1].second["GET"]
        @test get_handler isa Function
    end

    @testset "notebook routes with nil state" begin
        routes_file = joinpath(@__DIR__, "..", "src", "api", "notebook.jl")
        fn = include(routes_file)
        routes = fn(() -> nothing)

        get_handler = routes[1].second["GET"]
        @test get_handler isa Function
    end

    # ── Files API route definitions ──
    @testset "files_api_routes returns route pairs" begin
        routes_file = joinpath(@__DIR__, "..", "src", "api", "files.jl")
        @test isfile(routes_file)
        fn = include(routes_file)
        @test fn isa Function

        routes = fn(() -> mktempdir())
        @test routes isa Vector
        @test length(routes) == 3

        paths = [r.first for r in routes]
        @test "/api/files/tree" in paths
        @test "/api/files/read" in paths
        @test "/api/files/write" in paths
    end

    @testset "files tree handler returns tree structure" begin
        routes_file = joinpath(@__DIR__, "..", "src", "api", "files.jl")
        fn = include(routes_file)

        mktempdir() do tmpdir
            write(joinpath(tmpdir, "hello.jl"), "x = 1")
            mkdir(joinpath(tmpdir, "subdir"))
            write(joinpath(tmpdir, "subdir", "inner.jl"), "y = 2")

            routes = fn(() -> tmpdir)
            get_handler = routes[1].second["GET"]
            @test get_handler isa Function
        end
    end

    # ── Terminal API route definitions ──
    @testset "terminal_api_routes returns route pairs" begin
        routes_file = joinpath(@__DIR__, "..", "src", "api", "terminal.jl")
        @test isfile(routes_file)
        fn = include(routes_file)
        @test fn isa Function

        ts = Sessions.TerminalState()
        nb = Sessions.Notebook(; path="test.jl")
        worker = Sessions.NotebookWorker()
        tab = Sessions.WebTab(uuid4(), nb, worker, "test.jl", abspath("test.jl"))
        ws = Sessions.WebNotebookState([tab], 1, false, false)

        routes = fn(() -> ts, () -> ws)
        @test routes isa Vector
        @test length(routes) == 4

        paths = [r.first for r in routes]
        @test "/api/terminal/tabs" in paths
        @test "/api/terminal/create" in paths
        @test "/api/terminal/close" in paths
        @test "/api/terminal/resize" in paths
    end

    @testset "terminal tabs handler with empty state" begin
        routes_file = joinpath(@__DIR__, "..", "src", "api", "terminal.jl")
        fn = include(routes_file)

        ts = Sessions.TerminalState()
        nb = Sessions.Notebook(; path="test.jl")
        worker = Sessions.NotebookWorker()
        tab = Sessions.WebTab(uuid4(), nb, worker, "test.jl", abspath("test.jl"))
        ws = Sessions.WebNotebookState([tab], 1, false, false)

        routes = fn(() -> ts, () -> ws)
        get_handler = routes[1].second["GET"]
        @test get_handler isa Function
    end
end
