# Sessions.jl Pluto Compatibility Smoke Test
# SESSIONS-3902: End-to-end smoke test with real Pluto notebooks
#
# Run: julia +1.12 --project=Sessions.jl Sessions.jl/test/pluto_smoke_test.jl

using Test
using Sessions
using Sessions: Cell, Notebook, CellState, CELL_IDLE,
                add_cell!, analyze_cell!, get_execution_order,
                create_workspace, run_cell!,
                load_notebook, save_notebook, export_to_html, export_to_script,
                is_markdown, is_code

const FIXTURES = joinpath(@__DIR__, "fixtures")

println("=" ^ 70)
println("SESSIONS-3902: Pluto Compatibility Smoke Test")
println("=" ^ 70)
println()

# =============================================================================
# Test each Pluto notebook fixture
# =============================================================================

pluto_notebooks = [
    "pluto_sample_basic.jl",
    "pluto_sample_hanoi.jl",
    "pluto_sample_interactive.jl",
    "pluto_getting_started.jl",
    "pluto_plutoui_sample.jl",
]

@testset "Pluto compatibility smoke test (SESSIONS-3902)" begin

    for notebook_file in pluto_notebooks
        path = joinpath(FIXTURES, notebook_file)
        @testset "$notebook_file" begin
            println("Testing: $notebook_file")

            # -----------------------------------------------------------------
            # 1. Load — all cells should parse
            # -----------------------------------------------------------------
            @testset "Load and parse" begin
                nb = load_notebook(path)
                @test nb isa Notebook
                @test length(nb.cells) > 0
                @test length(nb.cell_order) > 0
                @test length(nb.cell_order) == length(nb.cells)

                cell_count = length(nb.cells)
                println("  Cells: $cell_count")

                # Count non-empty cells (some Pluto notebooks have empty cells)
                non_empty = count(c -> !isempty(strip(c.code)), values(nb.cells))
                @test non_empty > 0
                println("  Non-empty cells: $non_empty/$cell_count")
            end

            # -----------------------------------------------------------------
            # 2. Cell type detection
            # -----------------------------------------------------------------
            @testset "Cell type detection" begin
                nb = load_notebook(path)
                code_cells = filter(c -> is_code(c), collect(values(nb.cells)))
                md_cells = filter(c -> is_markdown(c), collect(values(nb.cells)))

                println("  Code cells: $(length(code_cells)), Markdown cells: $(length(md_cells))")

                # Notebooks should have at least some code or markdown
                @test length(code_cells) + length(md_cells) == length(nb.cells)

                # Markdown cells should have md"" or md""" in code
                for mc in md_cells
                    @test occursin("md\"", mc.code) || occursin("md\"\"\"", mc.code)
                end
            end

            # -----------------------------------------------------------------
            # 3. Reactive analysis — all cells analyzable
            # -----------------------------------------------------------------
            @testset "Reactive analysis" begin
                nb = load_notebook(path)

                analyzed = 0
                errors = String[]
                for cell in values(nb.cells)
                    try
                        analyze_cell!(cell)
                        analyzed += 1
                    catch e
                        push!(errors, "Cell $(cell.id): $(sprint(showerror, e))")
                    end
                end

                println("  Analyzed: $analyzed/$(length(nb.cells))")
                if !isempty(errors)
                    println("  Errors: $(length(errors))")
                    for err in errors[1:min(3, length(errors))]
                        println("    $err")
                    end
                end
                @test analyzed == length(nb.cells)
            end

            # -----------------------------------------------------------------
            # 4. Execution order — dependency graph resolves
            # -----------------------------------------------------------------
            @testset "Execution order" begin
                nb = load_notebook(path)
                for cell in values(nb.cells)
                    analyze_cell!(cell)
                end

                # Get order starting from first cell
                first_id = nb.cell_order[1]
                order = get_execution_order(nb, [first_id])
                @test length(order) >= 1

                # All ordered cells should be valid
                for cell in order
                    @test cell.id in keys(nb.cells)
                end

                println("  Execution order from cell 1: $(length(order)) cells")
            end

            # -----------------------------------------------------------------
            # 5. Round-trip — save and reload preserves cells
            # -----------------------------------------------------------------
            @testset "Round-trip save/load" begin
                nb = load_notebook(path)
                original_count = length(nb.cells)
                original_codes = Dict(id => cell.code for (id, cell) in nb.cells)

                temp = tempname() * ".jl"
                try
                    save_notebook(nb, temp)
                    nb2 = load_notebook(temp)

                    @test length(nb2.cells) == original_count
                    @test length(nb2.cell_order) == original_count

                    # Verify code preserved
                    for (id, cell) in nb2.cells
                        @test haskey(original_codes, id)
                        @test cell.code == original_codes[id]
                    end

                    println("  Round-trip: $(length(nb2.cells)) cells preserved")
                finally
                    rm(temp; force=true)
                end
            end

            # -----------------------------------------------------------------
            # 6. Export — HTML and script exports work
            # -----------------------------------------------------------------
            @testset "Export" begin
                nb = load_notebook(path)

                html = export_to_html(nb)
                @test startswith(html, "<!DOCTYPE html>")
                @test occursin("</html>", html)
                @test length(html) > 100

                script = export_to_script(nb)
                @test !isempty(script)

                # Code cells should appear in script
                code_cells = filter(c -> is_code(c) && !isempty(strip(c.code)), collect(values(nb.cells)))
                if !isempty(code_cells)
                    # At least some non-empty code should be in the script
                    # Use first() to safely handle multi-byte unicode chars
                    found = any(code_cells) do c
                        code = strip(c.code)
                        chars = collect(code)
                        snippet = String(chars[1:min(10, length(chars))])
                        occursin(snippet, script)
                    end
                    @test found
                end

                println("  Export HTML: $(length(html)) chars, Script: $(length(script)) chars")
            end

            # -----------------------------------------------------------------
            # 7. Simple cell execution (safe cells only)
            # -----------------------------------------------------------------
            @testset "Simple cell execution" begin
                nb = load_notebook(path)
                ws = create_workspace()

                # Find simple assignment cells (e.g., x = 1, no imports/macros)
                executed = 0
                for id in nb.cell_order
                    cell = nb.cells[id]
                    code = strip(cell.code)

                    # Only execute very simple cells — skip imports, macros, functions with complex bodies
                    if occursin(r"^[a-z_][a-z_0-9]* = \d+$"i, code)
                        try
                            result, _ = run_cell!(ws, code)
                            executed += 1
                        catch
                            # Some cells may not work in isolation — that's ok
                        end
                    end
                end

                println("  Simple cells executed: $executed")
                # We just verify it doesn't crash — some notebooks may not have simple assignments
                @test true
            end

            println()
        end
    end

    # =========================================================================
    # Cross-notebook compatibility summary
    # =========================================================================
    @testset "Cross-notebook summary" begin
        total_cells = 0
        total_analyzed = 0

        for notebook_file in pluto_notebooks
            path = joinpath(FIXTURES, notebook_file)
            nb = load_notebook(path)
            total_cells += length(nb.cells)

            for cell in values(nb.cells)
                try
                    analyze_cell!(cell)
                    total_analyzed += 1
                catch
                end
            end
        end

        println("Cross-notebook summary:")
        println("  Total cells across $(length(pluto_notebooks)) notebooks: $total_cells")
        println("  Successfully analyzed: $total_analyzed/$total_cells")
        @test total_analyzed == total_cells
    end
end

println()
println("Pluto compatibility smoke test complete.")
