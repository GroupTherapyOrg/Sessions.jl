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

    # --- load_session tests ---

    @testset "load_session — valid file" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 42")
        mark_executed!(c1)
        c1.state = cell_done
        c1.output.output_type = :text
        c1.output.text_representation = "42"
        c1.output.runtime_ns = UInt64(5000)

        Sessions.save_session!(nb)
        data = Sessions.load_session(Sessions.session_path(path))

        @test data !== nothing
        @test data["meta"]["version"] == 1
        @test haskey(data["cells"], string(c1.id))

        rm(Sessions.session_path(path); force=true)
    end

    @testset "load_session — missing file returns nothing" begin
        @test Sessions.load_session("/nonexistent/path.jl.session") === nothing
    end

    @testset "load_session — corrupt file returns nothing" begin
        path = tempname() * ".jl.session"
        Base.write(path, "this is not valid TOML {{{")
        @test Sessions.load_session(path) === nothing
        rm(path; force=true)
    end

    @testset "load_session — future version returns nothing" begin
        path = tempname() * ".jl.session"
        Base.open(path, "w") do io
            TOML.print(io, Dict(
                "meta" => Dict("version" => 99),
                "cells" => Dict()
            ))
        end
        @test Sessions.load_session(path) === nothing
        rm(path; force=true)
    end

    # --- apply_session! tests ---

    @testset "apply_session! — sets produced_by_hash and output" begin
        nb = Notebook(; path="test.jl")
        c1 = add_cell!(nb, "x = 42")

        hash = source_hash(c1)
        session_data = Dict(
            "meta" => Dict("version" => 1),
            "cells" => Dict(string(c1.id) => Dict(
                "execution_hash" => hash,
                "output_type" => "text",
                "text_representation" => "42",
                "stdout" => "",
                "error_message" => "",
                "runtime_ns" => 5000,
                "executed_at" => "2026-03-06T12:00:00"
            ))
        )

        Sessions.apply_session!(nb, session_data)
        @test c1.produced_by_hash == hash
        @test c1.output.output_type == :text
        @test c1.output.text_representation == "42"
        @test c1.output.runtime_ns == UInt64(5000)
        @test c1.state == cell_done
        @test !is_stale(c1)
    end

    @testset "apply_session! — detects stale cell (hash mismatch)" begin
        nb = Notebook(; path="test.jl")
        c1 = add_cell!(nb, "x = 99")

        session_data = Dict(
            "meta" => Dict("version" => 1),
            "cells" => Dict(string(c1.id) => Dict(
                "execution_hash" => "old_hash_from_different_code",
                "output_type" => "text",
                "text_representation" => "42",
                "stdout" => "",
                "error_message" => "",
                "runtime_ns" => 5000,
                "executed_at" => "2026-03-06T12:00:00"
            ))
        )

        Sessions.apply_session!(nb, session_data)
        @test c1.produced_by_hash == "old_hash_from_different_code"
        @test is_stale(c1)
        @test c1.output.text_representation == "42"
    end

    @testset "apply_session! — ignores cells not in notebook" begin
        nb = Notebook(; path="test.jl")
        c1 = add_cell!(nb, "x = 1")

        orphan_id = uuid4()
        session_data = Dict(
            "meta" => Dict("version" => 1),
            "cells" => Dict(
                string(c1.id) => Dict(
                    "execution_hash" => source_hash(c1),
                    "output_type" => "text",
                    "text_representation" => "1",
                    "stdout" => "",
                    "error_message" => "",
                    "runtime_ns" => 100,
                    "executed_at" => "2026-03-06T12:00:00"
                ),
                string(orphan_id) => Dict(
                    "execution_hash" => "orphan",
                    "output_type" => "text",
                    "text_representation" => "orphan",
                    "stdout" => "",
                    "error_message" => "",
                    "runtime_ns" => 100,
                    "executed_at" => "2026-03-06T12:00:00"
                )
            )
        )

        Sessions.apply_session!(nb, session_data)
        @test c1.produced_by_hash == source_hash(c1)
        @test c1.state == cell_done
    end

    @testset "apply_session! — cells not in session stay idle" begin
        nb = Notebook(; path="test.jl")
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "y = 2")

        session_data = Dict(
            "meta" => Dict("version" => 1),
            "cells" => Dict(string(c1.id) => Dict(
                "execution_hash" => source_hash(c1),
                "output_type" => "text",
                "text_representation" => "1",
                "stdout" => "",
                "error_message" => "",
                "runtime_ns" => 100,
                "executed_at" => "2026-03-06T12:00:00"
            ))
        )

        Sessions.apply_session!(nb, session_data)
        @test c1.state == cell_done
        @test c2.state == cell_idle
        @test c2.produced_by_hash == ""
    end

    @testset "apply_session! — error cell restoration" begin
        nb = Notebook(; path="test.jl")
        c1 = add_cell!(nb, "error(\"boom\")")

        session_data = Dict(
            "meta" => Dict("version" => 1),
            "cells" => Dict(string(c1.id) => Dict(
                "execution_hash" => source_hash(c1),
                "output_type" => "error",
                "text_representation" => "boom",
                "stdout" => "",
                "error_message" => "boom",
                "runtime_ns" => 200,
                "executed_at" => "2026-03-06T12:00:00"
            ))
        )

        Sessions.apply_session!(nb, session_data)
        @test c1.state == cell_errored
        @test c1.output.output_type == :error
        @test c1.output.error !== nothing
        @test c1.output.error.ex isa ErrorException
    end

    @testset "apply_session! — nothing input is no-op" begin
        nb = Notebook(; path="test.jl")
        c1 = add_cell!(nb, "x = 1")

        Sessions.apply_session!(nb, nothing)
        @test c1.state == cell_idle
    end

    @testset "apply_session! — stdout preservation" begin
        nb = Notebook(; path="test.jl")
        c1 = add_cell!(nb, "println(\"hi\")")

        session_data = Dict(
            "meta" => Dict("version" => 1),
            "cells" => Dict(string(c1.id) => Dict(
                "execution_hash" => source_hash(c1),
                "output_type" => "text",
                "text_representation" => "nothing",
                "stdout" => "hi\n",
                "error_message" => "",
                "runtime_ns" => 300,
                "executed_at" => "2026-03-06T12:00:00"
            ))
        )

        Sessions.apply_session!(nb, session_data)
        @test c1.output.stdout == "hi\n"
    end

    # --- Roundtrip tests (execute -> save -> load -> apply -> verify) ---

    @testset "roundtrip — execute, save, load, apply" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1 + 1")
        c2 = add_cell!(nb, "y = 10")
        save_notebook(nb)

        ws = Workspace()
        execute_cell!(ws, c1)
        execute_cell!(ws, c2)
        Sessions.save_session!(nb)

        # Load fresh notebook from disk + session
        nb2 = load_notebook(path)
        session_data = Sessions.load_session(Sessions.session_path(path))
        Sessions.apply_session!(nb2, session_data)

        c1b = get_cell(nb2, c1.id)
        c2b = get_cell(nb2, c2.id)

        @test c1b.state == cell_done
        @test c1b.output.text_representation == "2"
        @test !is_stale(c1b)

        @test c2b.state == cell_done
        @test c2b.output.text_representation == "10"
        @test !is_stale(c2b)

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "roundtrip — error cell survives" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "error(\"test error\")")
        save_notebook(nb)

        ws = Workspace()
        execute_cell!(ws, c1)
        @test c1.state == cell_errored
        Sessions.save_session!(nb)

        nb2 = load_notebook(path)
        Sessions.apply_session!(nb2, Sessions.load_session(Sessions.session_path(path)))

        c1b = get_cell(nb2, c1.id)
        @test c1b.state == cell_errored
        @test c1b.output.output_type == :error
        @test c1b.output.error !== nothing

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "roundtrip — stdout preserved" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "println(\"hello world\")\n42")
        save_notebook(nb)

        ws = Workspace()
        execute_cell!(ws, c1)
        Sessions.save_session!(nb)

        nb2 = load_notebook(path)
        Sessions.apply_session!(nb2, Sessions.load_session(Sessions.session_path(path)))

        c1b = get_cell(nb2, c1.id)
        @test c1b.output.stdout == "hello world\n"
        @test c1b.output.text_representation == "42"

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "roundtrip — runtime_ns preserved" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "sleep(0.01); 99")
        save_notebook(nb)

        ws = Workspace()
        execute_cell!(ws, c1)
        original_ns = c1.output.runtime_ns
        @test original_ns > 0
        Sessions.save_session!(nb)

        nb2 = load_notebook(path)
        Sessions.apply_session!(nb2, Sessions.load_session(Sessions.session_path(path)))

        @test get_cell(nb2, c1.id).output.runtime_ns == original_ns

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "roundtrip — modified code shows stale" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1")
        save_notebook(nb)

        ws = Workspace()
        execute_cell!(ws, c1)
        Sessions.save_session!(nb)

        # Modify the .jl file (change cell code)
        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "x = 999"
        save_notebook(nb_ext, path)

        # Reload with session — cell should be stale
        nb2 = load_notebook(path)
        Sessions.apply_session!(nb2, Sessions.load_session(Sessions.session_path(path)))

        c1b = get_cell(nb2, c1.id)
        @test c1b.code == "x = 999"
        @test is_stale(c1b)  # hash mismatch
        @test c1b.output.text_representation == "1"  # old cached output

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "roundtrip — never-executed cells stay idle" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "y = 2")  # never executed
        save_notebook(nb)

        ws = Workspace()
        execute_cell!(ws, c1)  # only execute c1
        Sessions.save_session!(nb)

        nb2 = load_notebook(path)
        Sessions.apply_session!(nb2, Sessions.load_session(Sessions.session_path(path)))

        @test get_cell(nb2, c1.id).state == cell_done
        @test get_cell(nb2, c2.id).state == cell_idle
        @test is_never_run(get_cell(nb2, c2.id))

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "roundtrip — truncated output loads with marker" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1")
        mark_executed!(c1)
        c1.state = cell_done
        c1.output.output_type = :text
        c1.output.text_representation = "z" ^ 100_000
        save_notebook(nb)

        Sessions.save_session!(nb)

        nb2 = load_notebook(path)
        Sessions.apply_session!(nb2, Sessions.load_session(Sessions.session_path(path)))

        c1b = get_cell(nb2, c1.id)
        @test contains(c1b.output.text_representation, "truncated")
        @test length(c1b.output.text_representation) < 100_000

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "roundtrip — missing session file works like v2" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1")
        save_notebook(nb)

        # Load without session file
        nb2 = load_notebook(path)
        Sessions.apply_session!(nb2, Sessions.load_session(Sessions.session_path(path)))

        @test get_cell(nb2, c1.id).state == cell_idle
        @test is_never_run(get_cell(nb2, c1.id))

        rm(path; force=true)
    end
end
