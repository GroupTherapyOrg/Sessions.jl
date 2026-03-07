using Test
using Sessions
import Tachikoma

@testset "Output Cache — SESSIONS-9001" begin
    @testset "OutputWidget has _cached_output_lines field" begin
        cell = Cell("42")
        cell.state = Sessions.cell_done
        cell.output.output_type = :text
        cell.output.result = 42
        ow = Sessions.OutputWidget(cell)
        @test ow._cached_output_lines === nothing
        @test ow._cached_output_lines_id == UInt64(0)
    end

    @testset "cached_output_lines caches on first call" begin
        cell = Cell("42")
        cell.state = Sessions.cell_done
        cell.output.output_type = :text
        cell.output.result = 42
        ow = Sessions.OutputWidget(cell)

        lines1 = Sessions.cached_output_lines(ow)
        @test !isempty(lines1)
        @test any(l -> contains(l, "42"), lines1)

        # Cache should now be populated
        @test ow._cached_output_lines !== nothing
        @test ow._cached_output_lines_id == objectid(cell.output)

        # Second call returns same cached object
        lines2 = Sessions.cached_output_lines(ow)
        @test lines2 === lines1  # same object (pointer identity)
    end

    @testset "cached_output_lines invalidates on output change" begin
        ws = Workspace()
        cell = Cell("42")
        execute_cell!(ws, cell)
        ow = Sessions.OutputWidget(cell)

        lines1 = Sessions.cached_output_lines(ow)
        @test any(l -> contains(l, "42"), lines1)
        id1 = ow._cached_output_lines_id

        # Re-execute cell with different code
        cell.code = "99"
        execute_cell!(ws, cell)

        # Output object changed → cache should invalidate
        lines2 = Sessions.cached_output_lines(ow)
        @test any(l -> contains(l, "99"), lines2)
        @test ow._cached_output_lines_id != id1
        @test lines2 !== lines1  # different object
    end

    @testset "cached_output_lines returns empty for idle cell" begin
        cell = Cell("x")
        cell.state = Sessions.cell_idle
        ow = Sessions.OutputWidget(cell)

        lines = Sessions.cached_output_lines(ow)
        @test isempty(lines)
    end

    @testset "cached_output_lines handles stdout" begin
        ws = Workspace()
        cell = Cell("println(\"hello\"); 42")
        execute_cell!(ws, cell)
        ow = Sessions.OutputWidget(cell)

        lines = Sessions.cached_output_lines(ow)
        @test any(l -> contains(l, "hello"), lines)
        @test any(l -> contains(l, "42"), lines)
    end

    @testset "cached_output_lines handles errors" begin
        ws = Workspace()
        cell = Cell("error(\"boom\")")
        execute_cell!(ws, cell)
        ow = Sessions.OutputWidget(cell)

        lines = Sessions.cached_output_lines(ow)
        @test any(l -> contains(l, "boom"), lines)
    end

    @testset "render uses cached output_lines" begin
        ws = Workspace()
        cell = Cell("42")
        execute_cell!(ws, cell)
        ow = Sessions.OutputWidget(cell)

        # First render populates cache
        tb1 = Tachikoma.TestBackend(40, 5)
        Tachikoma.render_widget!(tb1, ow)
        @test ow._cached_output_lines !== nothing

        cached_ref = ow._cached_output_lines

        # Second render reuses cache
        tb2 = Tachikoma.TestBackend(40, 5)
        Tachikoma.render_widget!(tb2, ow)
        @test ow._cached_output_lines === cached_ref  # same object
    end

    @testset "output_lines function still works standalone" begin
        cell = Cell("42")
        cell.state = Sessions.cell_done
        cell.output.output_type = :text
        cell.output.result = 42
        lines = Sessions.output_lines(cell)
        @test any(l -> contains(l, "42"), lines)
    end
end
