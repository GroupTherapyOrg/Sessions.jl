using Test
using Sessions
using UUIDs
using TOML

@testset "session.jl" begin

    @testset "session_path" begin
        @test Sessions.session_path("foo.jl") == "foo.jl.session"
        @test Sessions.session_path("/path/to/notebook.jl") == "/path/to/notebook.jl.session"
        @test Sessions.session_path("relative/path.jl") == "relative/path.jl.session"
    end

    @testset "truncation" begin
        short = "hello"
        @test Sessions._truncate(short, 100) == short

        long = "x" ^ 200
        result = Sessions._truncate(long, 100)
        @test length(result) > 100  # truncated + marker
        @test startswith(result, "x" ^ 100)
        @test contains(result, "truncated")

        # Exact boundary — no truncation
        exact = "y" ^ 100
        @test Sessions._truncate(exact, 100) == exact
    end

    @testset "build_session_dict — basic structure" begin
        nb = Notebook(; path="test.jl")
        c1 = add_cell!(nb, "x = 1 + 1")
        mark_executed!(c1)
        c1.state = cell_done
        c1.output.output_type = :text
        c1.output.text_representation = "2"
        c1.output.stdout = ""
        c1.output.runtime_ns = UInt64(1234567)

        dict = Sessions.build_session_dict(nb)

        # Meta section
        @test haskey(dict, "meta")
        @test dict["meta"]["version"] == 1
        @test haskey(dict["meta"], "notebook_path")
        @test haskey(dict["meta"], "created_at")

        # Cells section
        @test haskey(dict, "cells")
        @test haskey(dict["cells"], string(c1.id))

        cell_data = dict["cells"][string(c1.id)]
        @test cell_data["execution_hash"] == c1.produced_by_hash
        @test cell_data["output_type"] == "text"
        @test cell_data["text_representation"] == "2"
        @test cell_data["stdout"] == ""
        @test cell_data["runtime_ns"] == 1234567
        @test cell_data["error_message"] == ""
        @test haskey(cell_data, "executed_at")
    end

    @testset "build_session_dict — skips never-executed cells" begin
        nb = Notebook(; path="test.jl")
        c1 = add_cell!(nb, "x = 1")
        mark_executed!(c1)
        c1.state = cell_done

        c2 = add_cell!(nb, "y = 2")
        # c2 never executed — produced_by_hash is ""

        dict = Sessions.build_session_dict(nb)
        @test haskey(dict["cells"], string(c1.id))
        @test !haskey(dict["cells"], string(c2.id))
    end

    @testset "build_session_dict — error cell" begin
        nb = Notebook(; path="test.jl")
        c1 = add_cell!(nb, "error(\"boom\")")
        mark_executed!(c1)
        c1.state = cell_errored
        c1.output.output_type = :error
        c1.output.text_representation = "boom"
        c1.output.error = CapturedException(ErrorException("boom"), backtrace())

        dict = Sessions.build_session_dict(nb)
        cell_data = dict["cells"][string(c1.id)]
        @test cell_data["output_type"] == "error"
        @test cell_data["error_message"] == "boom"
    end

    @testset "build_session_dict — stdout" begin
        nb = Notebook(; path="test.jl")
        c1 = add_cell!(nb, "println(\"hello\")")
        mark_executed!(c1)
        c1.state = cell_done
        c1.output.stdout = "hello\n"
        c1.output.output_type = :text

        dict = Sessions.build_session_dict(nb)
        @test dict["cells"][string(c1.id)]["stdout"] == "hello\n"
    end

    @testset "save_session! — creates file" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 42")
        mark_executed!(c1)
        c1.state = cell_done
        c1.output.output_type = :text
        c1.output.text_representation = "42"
        c1.output.runtime_ns = UInt64(999)

        Sessions.save_session!(nb)
        session_file = Sessions.session_path(path)

        @test isfile(session_file)

        # Verify it's valid TOML
        data = TOML.parsefile(session_file)
        @test data["meta"]["version"] == 1
        @test haskey(data["cells"], string(c1.id))
        @test data["cells"][string(c1.id)]["execution_hash"] == c1.produced_by_hash

        rm(session_file; force=true)
    end

    @testset "save_session! — atomic write (no .tmp left)" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1")
        mark_executed!(c1)
        c1.state = cell_done

        Sessions.save_session!(nb)
        session_file = Sessions.session_path(path)
        tmp_file = session_file * ".tmp"

        @test isfile(session_file)
        @test !isfile(tmp_file)

        rm(session_file; force=true)
    end

    @testset "save_session! — multiple cells" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "a = 1")
        c2 = add_cell!(nb, "b = 2")
        c3 = add_cell!(nb, "c = 3")

        for c in [c1, c2, c3]
            mark_executed!(c)
            c.state = cell_done
            c.output.output_type = :text
            c.output.text_representation = "val"
        end

        Sessions.save_session!(nb)
        data = TOML.parsefile(Sessions.session_path(path))

        @test length(data["cells"]) == 3
        @test haskey(data["cells"], string(c1.id))
        @test haskey(data["cells"], string(c2.id))
        @test haskey(data["cells"], string(c3.id))

        rm(Sessions.session_path(path); force=true)
    end

    @testset "save_session! — truncates large output" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1")
        mark_executed!(c1)
        c1.state = cell_done
        c1.output.output_type = :text
        c1.output.text_representation = "x" ^ 100_000  # larger than MAX_TEXT_REPRESENTATION

        Sessions.save_session!(nb)
        data = TOML.parsefile(Sessions.session_path(path))

        saved_text = data["cells"][string(c1.id)]["text_representation"]
        @test length(saved_text) < 100_000
        @test contains(saved_text, "truncated")

        rm(Sessions.session_path(path); force=true)
    end

    @testset "save_session! — overwrites existing file" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1")
        mark_executed!(c1)
        c1.state = cell_done
        c1.output.text_representation = "first"
        c1.output.output_type = :text

        Sessions.save_session!(nb)

        # Change output and save again
        c1.output.text_representation = "second"
        Sessions.save_session!(nb)

        data = TOML.parsefile(Sessions.session_path(path))
        @test data["cells"][string(c1.id)]["text_representation"] == "second"

        rm(Sessions.session_path(path); force=true)
    end
end
