using Test
using Sessions
using UUIDs
using TOML

@testset "session.jl" begin

    @testset "session_path" begin
        @test Sessions.session_path("foo.jl") == "foo.sessions.toml"
        @test Sessions.session_path("/path/to/notebook.jl") == "/path/to/notebook.sessions.toml"
        @test Sessions.session_path("relative/path.jl") == "relative/path.sessions.toml"
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
        @test Sessions.load_session("/nonexistent/path.sessions.toml") === nothing
    end

    @testset "load_session — corrupt file returns nothing" begin
        path = tempname() * ".sessions.toml"
        Base.write(path, "this is not valid TOML {{{")
        @test Sessions.load_session(path) === nothing
        rm(path; force=true)
    end

    @testset "load_session — future version returns nothing" begin
        path = tempname() * ".sessions.toml"
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

    # --- load_notebook_with_session tests ---

    @testset "load_notebook_with_session — exported" begin
        @test isdefined(Sessions, :load_notebook_with_session)
        @test load_notebook_with_session isa Function
    end

    @testset "load_notebook_with_session — reads both files" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1 + 1")
        c2 = add_cell!(nb, "y = 10")
        save_notebook(nb)

        ws = Workspace()
        execute_cell!(ws, c1)
        execute_cell!(ws, c2)
        Sessions.save_session!(nb)

        nb2 = load_notebook_with_session(path)

        c1b = get_cell(nb2, c1.id)
        c2b = get_cell(nb2, c2.id)

        @test c1b.state == cell_done
        @test c1b.output.text_representation == "2"
        @test c1b.output.output_type == :text
        @test !is_stale(c1b)

        @test c2b.state == cell_done
        @test c2b.output.text_representation == "10"
        @test !is_stale(c2b)

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "load_notebook_with_session — matching hashes show cell_done" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "42")
        save_notebook(nb)

        ws = Workspace()
        execute_cell!(ws, c1)
        Sessions.save_session!(nb)

        nb2 = load_notebook_with_session(path)
        c1b = get_cell(nb2, c1.id)

        @test c1b.state == cell_done
        @test c1b.produced_by_hash == source_hash(c1b)
        @test !is_stale(c1b)

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "load_notebook_with_session — mismatching hashes show stale" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1")
        save_notebook(nb)

        ws = Workspace()
        execute_cell!(ws, c1)
        Sessions.save_session!(nb)

        # Modify the cell code on disk
        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "x = 999"
        save_notebook(nb_ext, path)

        nb2 = load_notebook_with_session(path)
        c1b = get_cell(nb2, c1.id)

        @test c1b.code == "x = 999"
        @test is_stale(c1b)
        @test c1b.output.text_representation == "1"  # cached old output

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "load_notebook_with_session — missing session file returns idle cells" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "y = 2")
        save_notebook(nb)
        # No session file saved

        nb2 = load_notebook_with_session(path)

        @test get_cell(nb2, c1.id).state == cell_idle
        @test get_cell(nb2, c2.id).state == cell_idle
        @test is_never_run(get_cell(nb2, c1.id))
        @test is_never_run(get_cell(nb2, c2.id))

        rm(path; force=true)
    end

    @testset "load_notebook_with_session — new cells not in session stay idle" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1")
        save_notebook(nb)

        ws = Workspace()
        execute_cell!(ws, c1)
        Sessions.save_session!(nb)

        # Add a new cell on disk (agent adds code)
        nb_ext = load_notebook(path)
        c2 = add_cell!(nb_ext, "z = 99")
        save_notebook(nb_ext, path)

        nb2 = load_notebook_with_session(path)
        c1b = get_cell(nb2, c1.id)
        c2b = get_cell(nb2, c2.id)

        @test c1b.state == cell_done
        @test !is_stale(c1b)
        @test c2b.state == cell_idle
        @test is_never_run(c2b)

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "load_notebook_with_session — deleted cells in session silently ignored" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "y = 2")
        save_notebook(nb)

        ws = Workspace()
        execute_cell!(ws, c1)
        execute_cell!(ws, c2)
        Sessions.save_session!(nb)

        # Remove c2 from the notebook on disk
        nb_ext = load_notebook(path)
        remove_cell!(nb_ext, c2.id)
        save_notebook(nb_ext, path)

        nb2 = load_notebook_with_session(path)

        @test haskey(nb2.cells, c1.id)
        @test !haskey(nb2.cells, c2.id)
        @test get_cell(nb2, c1.id).state == cell_done

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "load_notebook_with_session — error cell restored" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "error(\"kaboom\")")
        save_notebook(nb)

        ws = Workspace()
        execute_cell!(ws, c1)
        @test c1.state == cell_errored
        Sessions.save_session!(nb)

        nb2 = load_notebook_with_session(path)
        c1b = get_cell(nb2, c1.id)

        @test c1b.state == cell_errored
        @test c1b.output.output_type == :error
        @test c1b.output.error !== nothing

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "load_notebook_with_session — stdout preserved" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "println(\"hello\")\n42")
        save_notebook(nb)

        ws = Workspace()
        execute_cell!(ws, c1)
        Sessions.save_session!(nb)

        nb2 = load_notebook_with_session(path)
        c1b = get_cell(nb2, c1.id)

        @test c1b.output.stdout == "hello\n"
        @test c1b.output.text_representation == "42"
        @test c1b.state == cell_done

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "load_notebook_with_session — runtime_ns preserved" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "sleep(0.01); 1")
        save_notebook(nb)

        ws = Workspace()
        execute_cell!(ws, c1)
        original_ns = c1.output.runtime_ns
        @test original_ns > 0
        Sessions.save_session!(nb)

        nb2 = load_notebook_with_session(path)
        @test get_cell(nb2, c1.id).output.runtime_ns == original_ns

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "load_notebook_with_session — identical to load_notebook when no session" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "a = 1")
        c2 = add_cell!(nb, "b = 2")
        save_notebook(nb)

        nb_plain = load_notebook(path)
        nb_with = load_notebook_with_session(path)

        # Both should have identical cell states
        for id in nb_plain.cell_order
            @test nb_plain.cells[id].state == nb_with.cells[id].state
            @test nb_plain.cells[id].code == nb_with.cells[id].code
            @test nb_plain.cells[id].produced_by_hash == nb_with.cells[id].produced_by_hash
        end

        rm(path; force=true)
    end

    # --- Auto-save session after execution (SESSIONS-6015) ---

    @testset "auto-save — run_focused_cell! creates session file" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 42")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        Sessions.run_focused_cell!(app)

        session_file = Sessions.session_path(path)
        @test isfile(session_file)

        data = TOML.parsefile(session_file)
        @test haskey(data["cells"], string(c1.id))
        @test data["cells"][string(c1.id)]["execution_hash"] == source_hash(c1)

        rm(path; force=true)
        rm(session_file; force=true)
    end

    @testset "auto-save — run_all_cells! creates session file" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "a = 10")
        c2 = add_cell!(nb, "b = a + 5")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        Sessions.run_all_cells!(app)

        session_file = Sessions.session_path(path)
        @test isfile(session_file)

        data = TOML.parsefile(session_file)
        @test length(data["cells"]) == 2
        @test haskey(data["cells"], string(c1.id))
        @test haskey(data["cells"], string(c2.id))

        rm(path; force=true)
        rm(session_file; force=true)
    end

    @testset "auto-save — run_stale_cells! creates session file" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "stale_auto = 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)

        # Execute first, then make stale
        execute_cell!(app.workspace, c1)
        c1.code = "stale_auto = 2"
        Sessions.sync_from_cell!(app.notebook_view.cell_widgets[1])
        @test is_stale(c1)

        Sessions.run_stale_cells!(app)

        session_file = Sessions.session_path(path)
        @test isfile(session_file)

        data = TOML.parsefile(session_file)
        @test haskey(data["cells"], string(c1.id))

        rm(path; force=true)
        rm(session_file; force=true)
    end

    @testset "auto-save — Sessions.run() headless creates session file" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "headless_x = 7 * 6")
        save_notebook(nb)

        Sessions.run(path)

        session_file = Sessions.session_path(path)
        @test isfile(session_file)

        data = TOML.parsefile(session_file)
        @test haskey(data["cells"], string(c1.id))
        @test data["cells"][string(c1.id)]["text_representation"] == "42"

        rm(path; force=true)
        rm(session_file; force=true)
    end

    @testset "auto-save — run_cell_at_index! creates session file" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "idx_val = 99")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        Sessions.run_cell_at_index!(app, 1)

        session_file = Sessions.session_path(path)
        @test isfile(session_file)

        data = TOML.parsefile(session_file)
        @test haskey(data["cells"], string(c1.id))

        rm(path; force=true)
        rm(session_file; force=true)
    end

    @testset "auto-save — headless run with multiple cells" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "multi_a = 1")
        c2 = add_cell!(nb, "multi_b = multi_a + 1")
        c3 = add_cell!(nb, "multi_c = multi_b * 3")
        save_notebook(nb)

        Sessions.run(path)

        session_file = Sessions.session_path(path)
        data = TOML.parsefile(session_file)
        @test length(data["cells"]) == 3
        @test data["cells"][string(c1.id)]["text_representation"] == "1"
        @test data["cells"][string(c2.id)]["text_representation"] == "2"
        @test data["cells"][string(c3.id)]["text_representation"] == "6"

        rm(path; force=true)
        rm(session_file; force=true)
    end

    # --- Execution-session roundtrip verification (SESSIONS-6016) ---

    @testset "exec-roundtrip — auto-save then fresh load shows cell_done" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "rt_x = 1 + 1")
        c2 = add_cell!(nb, "rt_y = rt_x * 3")
        save_notebook(nb)

        # Execute via TUI path (auto-saves session)
        app = Sessions.SessionsApp(nb)
        Sessions.run_all_cells!(app)

        # Fresh load from disk
        nb2 = load_notebook_with_session(path)
        c1b = get_cell(nb2, c1.id)
        c2b = get_cell(nb2, c2.id)

        @test c1b.state == cell_done
        @test c1b.output.text_representation == "2"
        @test !is_stale(c1b)

        @test c2b.state == cell_done
        @test c2b.output.text_representation == "6"
        @test !is_stale(c2b)

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "exec-roundtrip — modified cell shows stale, others clean" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "mod_a = 10")
        c2 = add_cell!(nb, "mod_b = mod_a + 5")
        c3 = add_cell!(nb, "mod_c = 100")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        Sessions.run_all_cells!(app)

        # Modify c2's code on disk (simulating agent edit)
        nb_ext = load_notebook(path)
        nb_ext.cells[c2.id].code = "mod_b = mod_a + 99"
        save_notebook(nb_ext, path)

        # Reload with session
        nb2 = load_notebook_with_session(path)
        c1b = get_cell(nb2, c1.id)
        c2b = get_cell(nb2, c2.id)
        c3b = get_cell(nb2, c3.id)

        # c1 and c3 unchanged — clean
        @test c1b.state == cell_done
        @test !is_stale(c1b)
        @test c3b.state == cell_done
        @test !is_stale(c3b)

        # c2 modified — stale with old cached output
        @test c2b.code == "mod_b = mod_a + 99"
        @test is_stale(c2b)
        @test c2b.output.text_representation == "15"  # old value

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "exec-roundtrip — error cell survives" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "good_rt = 42")
        c2 = add_cell!(nb, "error(\"roundtrip error\")")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        Sessions.run_all_cells!(app)
        @test c2.state == cell_errored

        nb2 = load_notebook_with_session(path)
        c1b = get_cell(nb2, c1.id)
        c2b = get_cell(nb2, c2.id)

        @test c1b.state == cell_done
        @test c1b.output.text_representation == "42"

        @test c2b.state == cell_errored
        @test c2b.output.output_type == :error
        @test c2b.output.error !== nothing

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "exec-roundtrip — stdout preserved" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "println(\"roundtrip stdout\")\n77")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        Sessions.run_all_cells!(app)

        nb2 = load_notebook_with_session(path)
        c1b = get_cell(nb2, c1.id)

        @test c1b.output.stdout == "roundtrip stdout\n"
        @test c1b.output.text_representation == "77"
        @test c1b.state == cell_done

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "exec-roundtrip — runtime_ns preserved" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "sleep(0.01); 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        Sessions.run_all_cells!(app)
        original_ns = c1.output.runtime_ns
        @test original_ns > 0

        nb2 = load_notebook_with_session(path)
        @test get_cell(nb2, c1.id).output.runtime_ns == original_ns

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "exec-roundtrip — headless run then fresh load" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "hl_a = 5")
        c2 = add_cell!(nb, "hl_b = hl_a^2")
        save_notebook(nb)

        Sessions.run(path)

        nb2 = load_notebook_with_session(path)
        c1b = get_cell(nb2, c1.id)
        c2b = get_cell(nb2, c2.id)

        @test c1b.state == cell_done
        @test c1b.output.text_representation == "5"
        @test c2b.state == cell_done
        @test c2b.output.text_representation == "25"
        @test !is_stale(c1b)
        @test !is_stale(c2b)

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    # --- Edge Cases (SESSIONS-6025) ---

    @testset "edge — corrupt session file: TUI opens with idle cells" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "edge_a = 1")
        save_notebook(nb)

        # Write corrupt session file
        sp = Sessions.session_path(path)
        write(sp, "this is {{ not valid TOML")

        nb2 = load_notebook_with_session(path)
        @test nb2.cells[c1.id].state == cell_idle
        @test nb2.cells[c1.id].output.text_representation == ""

        rm(path; force=true)
        rm(sp; force=true)
    end

    @testset "edge — empty notebook with session file: no crash" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        save_notebook(nb)
        @test length(nb) == 0

        # Create session file with some orphaned data
        sp = Sessions.session_path(path)
        data = Dict(
            "meta" => Dict("version" => 1, "sessions_version" => "0.1.0",
                           "notebook_path" => basename(path), "created_at" => "2026-01-01T00:00:00"),
            "cells" => Dict(string(uuid4()) => Dict(
                "execution_hash" => "abc", "output_type" => "text",
                "text_representation" => "42", "stdout" => "",
                "error_message" => "", "runtime_ns" => 1000,
                "executed_at" => "2026-01-01T00:00:00"))
        )
        open(sp, "w") do io; TOML.print(io, data); end

        nb2 = load_notebook_with_session(path)
        @test length(nb2) == 0  # no cells, no crash

        rm(path; force=true)
        rm(sp; force=true)
    end

    @testset "edge — future version session file: cells show as never-run" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "future_x = 1")
        save_notebook(nb)

        sp = Sessions.session_path(path)
        data = Dict(
            "meta" => Dict("version" => 99, "sessions_version" => "99.0.0",
                           "notebook_path" => basename(path), "created_at" => "2030-01-01T00:00:00"),
            "cells" => Dict(string(c1.id) => Dict(
                "execution_hash" => source_hash(c1), "output_type" => "text",
                "text_representation" => "1", "stdout" => "",
                "error_message" => "", "runtime_ns" => 100,
                "executed_at" => "2030-01-01T00:00:00"))
        )
        open(sp, "w") do io; TOML.print(io, data); end

        nb2 = load_notebook_with_session(path)
        @test nb2.cells[c1.id].state == cell_idle
        @test nb2.cells[c1.id].output.text_representation == ""

        rm(path; force=true)
        rm(sp; force=true)
    end

    @testset "edge — truncated output loads with marker visible" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "trunc_val = 1")
        save_notebook(nb)

        # Manually set a large text_representation to trigger truncation
        c1.produced_by_hash = source_hash(c1)
        c1.state = cell_done
        c1.output.output_type = :text
        c1.output.text_representation = repeat("y", 60000)
        save_session!(nb)

        nb2 = load_notebook_with_session(path)
        @test nb2.cells[c1.id].state == cell_done
        @test contains(nb2.cells[c1.id].output.text_representation, "truncated")
        @test length(nb2.cells[c1.id].output.text_representation) < 60000

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "edge — session file with only some cells: others remain idle" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "partial_a = 1")
        c2 = add_cell!(nb, "partial_b = 2")
        save_notebook(nb)

        # Only execute c1, save session
        ws = Workspace()
        execute_cell!(ws, c1)
        save_session!(nb)

        nb2 = load_notebook_with_session(path)
        @test nb2.cells[c1.id].state == cell_done
        @test nb2.cells[c2.id].state == cell_idle  # never executed

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end
end
