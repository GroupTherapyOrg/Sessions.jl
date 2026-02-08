# Sessions.jl Performance Benchmarks
# SESSIONS-3901: Benchmark startup, execution, notebook operations, and memory
#
# Run: julia +1.12 --project=Sessions.jl Sessions.jl/test/benchmarks.jl

using Test

# =============================================================================
# 1. Startup Time: `using Sessions` → module loaded
# =============================================================================
println("=" ^ 70)
println("SESSIONS-3901: Performance Benchmarks")
println("=" ^ 70)
println()

println("1. Startup Time")
println("-" ^ 40)
startup_time = @elapsed begin
    using Sessions
    using Sessions: Cell, Notebook, CellState, CELL_IDLE, CELL_RUNNING, CELL_ERROR,
                    add_cell!, analyze_cell!, get_execution_order,
                    create_workspace, run_cell!,
                    NotebookOptions, CellOutput,
                    save_notebook, load_notebook, export_to_html, export_to_script,
                    CellStateBadge, IDECellCard, IDECellsView, IDECodeCard,
                    IDEStatusBar, IDENotebookTabs, IDEFileBrowser,
                    render_markdown_html, list_directory, format_file_size,
                    cell_state_styles, codemirror_sessions_theme
    using Therapy
end
println("  using Sessions: $(round(startup_time, digits=3))s")
startup_pass = startup_time < 10.0  # generous target for first load
println("  Target: < 10s (first load)  → $(startup_pass ? "PASS" : "FAIL")")
println()

# =============================================================================
# 2. Cell Execution Latency
# =============================================================================
println("2. Cell Execution Latency")
println("-" ^ 40)

# Simple assignment
ws = create_workspace()
simple_times = Float64[]
for i in 1:100
    t = @elapsed run_cell!(ws, "x_$i = $i")
    push!(simple_times, t)
end
simple_median = sort(simple_times)[50] * 1000  # ms
simple_p99 = sort(simple_times)[99] * 1000
println("  Simple assignment (100 runs):")
println("    Median: $(round(simple_median, digits=2))ms")
println("    P99:    $(round(simple_p99, digits=2))ms")
simple_pass = simple_median < 50.0  # 50ms target for simple cells
println("    Target: < 50ms median      → $(simple_pass ? "PASS" : "FAIL")")
println()

# Function definition + call
ws2 = create_workspace()
func_times = Float64[]
for i in 1:50
    t = @elapsed begin
        run_cell!(ws2, "f_$i(x) = x^2 + $i")
        run_cell!(ws2, "result_$i = f_$i(42)")
    end
    push!(func_times, t)
end
func_median = sort(func_times)[25] * 1000
println("  Function def + call (50 runs):")
println("    Median: $(round(func_median, digits=2))ms")
func_pass = func_median < 100.0
println("    Target: < 100ms median     → $(func_pass ? "PASS" : "FAIL")")
println()

# Math expression
ws3 = create_workspace()
math_times = Float64[]
for i in 1:100
    t = @elapsed run_cell!(ws3, "result = sum(1:$i) * $(i + 1) / $(i + 2)")
    push!(math_times, t)
end
math_median = sort(math_times)[50] * 1000
println("  Math expression (100 runs):")
println("    Median: $(round(math_median, digits=2))ms")
math_pass = math_median < 50.0
println("    Target: < 50ms median      → $(math_pass ? "PASS" : "FAIL")")
println()

# =============================================================================
# 3. Notebook Operations
# =============================================================================
println("3. Notebook Operations")
println("-" ^ 40)

# Create notebook with many cells
nb_create_time = @elapsed begin
    big_nb = Notebook()
    for i in 1:100
        add_cell!(big_nb; code="cell_$i = $i * 2 + $(i - 1)")
    end
end
println("  Create 100-cell notebook: $(round(nb_create_time * 1000, digits=2))ms")
nb_create_pass = nb_create_time < 1.0  # < 1 second
println("    Target: < 1s               → $(nb_create_pass ? "PASS" : "FAIL")")
println()

# Analyze all cells
analyze_time = @elapsed begin
    for cell in values(big_nb.cells)
        analyze_cell!(cell)
    end
end
println("  Analyze 100 cells: $(round(analyze_time * 1000, digits=2))ms")
analyze_pass = analyze_time < 2.0
println("    Target: < 2s               → $(analyze_pass ? "PASS" : "FAIL")")
println()

# Save notebook
temp_path = tempname() * ".jl"
save_time = @elapsed save_notebook(big_nb, temp_path)
println("  Save 100-cell notebook: $(round(save_time * 1000, digits=2))ms")
save_pass = save_time < 1.0
println("    Target: < 1s               → $(save_pass ? "PASS" : "FAIL")")

# Load notebook
load_time = @elapsed loaded_nb = load_notebook(temp_path)
println("  Load 100-cell notebook: $(round(load_time * 1000, digits=2))ms")
load_pass = load_time < 1.0
println("    Target: < 1s               → $(load_pass ? "PASS" : "FAIL")")
rm(temp_path; force=true)
println()

# Export to HTML
export_html_time = @elapsed html = export_to_html(big_nb)
println("  Export 100-cell to HTML: $(round(export_html_time * 1000, digits=2))ms")
export_html_pass = export_html_time < 2.0
println("    Target: < 2s               → $(export_html_pass ? "PASS" : "FAIL")")

# Export to script
export_script_time = @elapsed script = export_to_script(big_nb)
println("  Export 100-cell to script: $(round(export_script_time * 1000, digits=2))ms")
export_script_pass = export_script_time < 1.0
println("    Target: < 1s               → $(export_script_pass ? "PASS" : "FAIL")")
println()

# =============================================================================
# 4. Component Rendering Performance
# =============================================================================
println("4. Component Rendering")
println("-" ^ 40)

# Render a single cell card
cell = Cell(; code="x = 42")
cell.output = CellOutput(nothing, "text/plain", "42", String[], String[])
render_times = Float64[]
for _ in 1:100
    t = @elapsed begin
        card = IDECellCard(cell)
        Therapy.render_to_string(card)
    end
    push!(render_times, t)
end
render_median = sort(render_times)[50] * 1000
println("  Render IDECellCard (100 runs):")
println("    Median: $(round(render_median, digits=2))ms")
render_pass = render_median < 10.0
println("    Target: < 10ms median      → $(render_pass ? "PASS" : "FAIL")")
println()

# Render cells view with 20 cells
cells = [Cell(; code="v_$i = $i") for i in 1:20]
view_times = Float64[]
for _ in 1:20
    t = @elapsed begin
        view = IDECellsView(cells)
        Therapy.render_to_string(view)
    end
    push!(view_times, t)
end
view_median = sort(view_times)[10] * 1000
println("  Render IDECellsView 20 cells (20 runs):")
println("    Median: $(round(view_median, digits=2))ms")
view_pass = view_median < 100.0
println("    Target: < 100ms median     → $(view_pass ? "PASS" : "FAIL")")
println()

# CSS/JS generation
css_times = Float64[]
for _ in 1:100
    t = @elapsed begin
        cell_state_styles()
        codemirror_sessions_theme()
    end
    push!(css_times, t)
end
css_median = sort(css_times)[50] * 1000
println("  Generate CSS/JS (100 runs):")
println("    Median: $(round(css_median, digits=3))ms")
css_pass = css_median < 5.0
println("    Target: < 5ms median       → $(css_pass ? "PASS" : "FAIL")")
println()

# =============================================================================
# 5. Markdown Rendering Performance
# =============================================================================
println("5. Markdown Rendering")
println("-" ^ 40)

md_source = """
# Chapter Title

This is a paragraph with **bold** and *italic* text.

## Section

- Item 1
- Item 2
- Item 3

```julia
function hello(name)
    println("Hello, \$name!")
end
```

[Link text](https://example.com)
"""

md_times = Float64[]
for _ in 1:100
    t = @elapsed render_markdown_html(md_source)
    push!(md_times, t)
end
md_median = sort(md_times)[50] * 1000
println("  Render markdown (100 runs):")
println("    Median: $(round(md_median, digits=3))ms")
md_pass = md_median < 10.0
println("    Target: < 10ms median      → $(md_pass ? "PASS" : "FAIL")")
println()

# =============================================================================
# 6. Reactivity / Dependency Analysis Performance
# =============================================================================
println("6. Reactivity Performance")
println("-" ^ 40)

# Create a chain of dependent cells
chain_nb = Notebook()
chain_cells = []
for i in 1:50
    if i == 1
        c = add_cell!(chain_nb; code="chain_1 = 1")
    else
        c = add_cell!(chain_nb; code="chain_$i = chain_$(i-1) + 1")
    end
    push!(chain_cells, c)
end

# Analyze all
for c in values(chain_nb.cells)
    analyze_cell!(c)
end

# Get execution order from first cell
order_times = Float64[]
for _ in 1:50
    t = @elapsed get_execution_order(chain_nb, [chain_cells[1].id])
    push!(order_times, t)
end
order_median = sort(order_times)[25] * 1000
println("  Execution order (50-cell chain, 50 runs):")
println("    Median: $(round(order_median, digits=3))ms")
order_pass = order_median < 50.0
println("    Target: < 50ms median      → $(order_pass ? "PASS" : "FAIL")")
println()

# =============================================================================
# 7. Memory Usage
# =============================================================================
println("7. Memory Usage")
println("-" ^ 40)

GC.gc()
mem_before = Base.summarysize(Sessions)

# Create 10 notebooks with 50 cells each
test_notebooks = Notebook[]
for n in 1:10
    nb = Notebook()
    for i in 1:50
        c = add_cell!(nb; code="nb$(n)_cell_$i = $i * $n")
        c.output = CellOutput(nothing, "text/plain", string(i * n), String[], String[])
    end
    push!(test_notebooks, nb)
end

mem_notebooks = sum(Base.summarysize(nb) for nb in test_notebooks)
println("  10 notebooks × 50 cells (with output):")
println("    Total: $(round(mem_notebooks / 1024 / 1024, digits=2)) MB")
mem_per_nb = mem_notebooks / 10 / 1024
println("    Per notebook: $(round(mem_per_nb, digits=1)) KB")
mem_pass = mem_notebooks < 100 * 1024 * 1024  # < 100 MB
println("    Target: < 100 MB total     → $(mem_pass ? "PASS" : "FAIL")")
println()

# Workspace memory
ws_mem = create_workspace()
for i in 1:100
    run_cell!(ws_mem, "big_array_$i = collect(1:1000)")
end
ws_size = Base.summarysize(ws_mem)
println("  Workspace with 100 arrays:")
println("    Size: $(round(ws_size / 1024 / 1024, digits=2)) MB")
println()

# =============================================================================
# Summary
# =============================================================================
println("=" ^ 70)
println("SUMMARY")
println("=" ^ 70)

results = [
    ("Startup time", startup_pass),
    ("Simple cell execution", simple_pass),
    ("Function def + call", func_pass),
    ("Math expression", math_pass),
    ("Create 100-cell notebook", nb_create_pass),
    ("Analyze 100 cells", analyze_pass),
    ("Save notebook", save_pass),
    ("Load notebook", load_pass),
    ("Export HTML", export_html_pass),
    ("Export script", export_script_pass),
    ("Render CellCard", render_pass),
    ("Render CellsView", view_pass),
    ("CSS/JS generation", css_pass),
    ("Markdown rendering", md_pass),
    ("Reactivity order", order_pass),
    ("Memory usage", mem_pass),
]

passed = count(r -> r[2], results)
total = length(results)
println("  $(passed)/$(total) benchmarks passed")
println()

for (name, pass) in results
    status = pass ? "✓" : "✗"
    println("  $(status) $(name)")
end

println()
println("Benchmarks complete.")

# Use @testset for CI integration
@testset "Performance benchmarks (SESSIONS-3901)" begin
    @test startup_pass
    @test simple_pass
    @test func_pass
    @test math_pass
    @test nb_create_pass
    @test analyze_pass
    @test save_pass
    @test load_pass
    @test export_html_pass
    @test export_script_pass
    @test render_pass
    @test view_pass
    @test css_pass
    @test md_pass
    @test order_pass
    @test mem_pass
end
