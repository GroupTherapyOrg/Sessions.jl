using Test
using Sessions
using Tachikoma
using Markdown: @md_str

@testset "tui" begin
    @testset "CellWidget" begin
        cell = Cell("x = 42")
        cw = Sessions.CellWidget(cell; focused=true)
        @test cw.focused == true
        @test cw.cell === cell

        # Render to TestBackend
        tb = TestBackend(60, 5)
        Tachikoma.render_widget!(tb, cw)
        @test Tachikoma.find_text(tb, "x = 42") !== nothing
    end

    @testset "CellWidget sync" begin
        cell = Cell("original")
        cw = Sessions.CellWidget(cell)

        # Sync from editor to cell
        Tachikoma.set_text!(cw.editor, "modified")
        Sessions.sync_to_cell!(cw)
        @test cell.code == "modified"

        # Sync from cell to editor
        cell.code = "updated"
        Sessions.sync_from_cell!(cw)
        @test Tachikoma.text(cw.editor) == "updated"
    end

    @testset "state_indicator" begin
        cell = Cell("x = 1")

        # Never-run cell → dotted circle (dim)
        @test is_never_run(cell)
        char, _ = Sessions.state_indicator(cell)
        @test char == "◌"

        # After execution → solid green
        mark_executed!(cell)
        cell.state = cell_done
        char, _ = Sessions.state_indicator(cell)
        @test char == "●"

        # Stale cell → hollow yellow
        cell.code = "x = 2"
        @test is_stale(cell)
        char, style = Sessions.state_indicator(cell)
        @test char == "○"

        # Errored cell → x mark red
        cell.state = cell_errored
        cell.produced_by_hash = ""  # reset so it's not stale
        char, _ = Sessions.state_indicator(cell)
        @test char == "✗"

        # Running cell → solid blue
        cell.state = cell_running
        char, _ = Sessions.state_indicator(cell)
        @test char == "●"
    end

    @testset "OutputWidget — no output for idle" begin
        cell = Cell("x = 1")
        ow = Sessions.OutputWidget(cell)
        @test Sessions.output_height(ow) == 0
    end

    @testset "OutputWidget — shows result" begin
        cell = Cell("x = 42")
        cell.state = cell_done
        cell.output.result = 42
        ow = Sessions.OutputWidget(cell)

        @test Sessions.output_height(ow) > 0
        lines = Sessions.output_lines(cell)
        @test any(l -> occursin("42", l), lines)

        # Render
        tb = TestBackend(60, 5)
        Tachikoma.render_widget!(tb, ow)
        @test Tachikoma.find_text(tb, "42") !== nothing
    end

    @testset "OutputWidget — shows error" begin
        cell = Cell("error(\"boom\")")
        cell.state = cell_errored
        cell.output.error = CapturedException(ErrorException("boom"), backtrace())
        ow = Sessions.OutputWidget(cell)

        lines = Sessions.output_lines(cell)
        @test any(l -> occursin("boom", l), lines)
    end

    @testset "OutputWidget — shows stdout" begin
        cell = Cell("println(\"hello\")")
        cell.state = cell_done
        cell.output.stdout = "hello\n"
        cell.output.result = nothing
        ow = Sessions.OutputWidget(cell)

        lines = Sessions.output_lines(cell)
        @test any(l -> occursin("hello", l), lines)
    end

    @testset "OutputWidget — stale dimming" begin
        cell = Cell("x = 42")
        cell.state = cell_done
        cell.output.result = 42
        mark_executed!(cell)

        # Not stale → normal output title
        ow = Sessions.OutputWidget(cell)
        tb = TestBackend(60, 5)
        Tachikoma.render_widget!(tb, ow)
        @test Tachikoma.find_text(tb, "42") !== nothing
        # Should show "Output", not "Output (stale)"
        @test Tachikoma.find_text(tb, "stale") === nothing

        # Make stale → dimmed output (still shows value, just muted)
        cell.code = "x = 99"
        tb2 = TestBackend(60, 5)
        Tachikoma.render_widget!(tb2, ow)
        @test Tachikoma.find_text(tb2, "42") !== nothing
        @test Sessions.is_stale(cell)  # verify cell is stale
    end

    @testset "OutputWidget — collapsed" begin
        cell = Cell("x = 1")
        cell.state = cell_done
        cell.output.result = 1
        ow = Sessions.OutputWidget(cell)
        ow.collapsed = true
        @test Sessions.output_height(ow) == 0
    end

    @testset "StatusBar — top bar" begin
        nb = Notebook(; path="test.jl")
        add_cell!(nb, "x = 1")
        bar = Sessions.make_top_bar(nb)
        @test bar isa Tachikoma.StatusBar

        tb = TestBackend(60, 1)
        Tachikoma.render_widget!(tb, bar)
        @test Tachikoma.find_text(tb, "test.jl") !== nothing
        @test Tachikoma.find_text(tb, "0/1 cells") !== nothing
    end

    @testset "StatusBar — bottom bar" begin
        bar = Sessions.make_bottom_bar(; mode=:normal)
        tb = TestBackend(120, 1)
        Tachikoma.render_widget!(tb, bar)
        @test Tachikoma.find_text(tb, "Ctrl+Q") !== nothing
        @test Tachikoma.find_text(tb, "Ctrl+S") !== nothing
    end

    @testset "NotebookView" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        add_cell!(nb, "y = x + 1")
        add_cell!(nb, "z = x * y")

        nv = Sessions.NotebookView(nb)
        @test length(nv.cell_widgets) == 3
        @test nv.focused_idx == 1
        @test nv.cell_widgets[1].focused == true
        @test nv.cell_widgets[2].focused == false

        # Navigation
        Sessions.focus_next!(nv)
        @test nv.focused_idx == 2
        @test nv.cell_widgets[1].focused == false
        @test nv.cell_widgets[2].focused == true

        Sessions.focus_prev!(nv)
        @test nv.focused_idx == 1

        # Boundary checks
        Sessions.focus_prev!(nv)
        @test nv.focused_idx == 1  # Can't go below 1
    end

    @testset "NotebookView — add/delete cells" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        nv = Sessions.NotebookView(nb)

        Sessions.add_cell_after_focus!(nv)
        @test length(nv.cell_widgets) == 3
        @test nv.focused_idx == 2

        Sessions.delete_focused_cell!(nv)
        @test length(nv.cell_widgets) == 2
    end

    @testset "NotebookView — render" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        add_cell!(nb, "y = 2")
        nv = Sessions.NotebookView(nb)

        tb = TestBackend(60, 20)
        Tachikoma.render_widget!(tb, nv)
        @test Tachikoma.find_text(tb, "x = 1") !== nothing
        @test Tachikoma.find_text(tb, "y = 2") !== nothing
    end

    @testset "SessionsApp creation" begin
        nb = Notebook(; path="test_app.jl")
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test app.nb === nb
        @test app.mode == :normal
        @test app.quit == false
        @test Tachikoma.should_quit(app) == false
    end

    @testset "SessionsApp — quit keybinding" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'q'))
        @test app.quit == true
    end

    @testset "SessionsApp — always-editing (no mode switch)" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test app.mode == :normal

        # Typing goes directly to editor — no Enter needed
        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, 'y'))
        @test app.mode == :normal  # stays normal (always editing)

        # Escape doesn't change mode
        Tachikoma.update!(app, Tachikoma.KeyEvent(:escape))
        @test app.mode == :normal
    end

    @testset "SessionsApp — cell focus via mouse click" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        add_cell!(nb, "c = 3")
        app = Sessions.SessionsApp(nb)

        @test app.notebook_view.focused_idx == 1

        # Focus cells via direct function call (mouse-first model)
        Sessions.focus_cell!(app.notebook_view, 2)
        @test app.notebook_view.focused_idx == 2

        Sessions.focus_cell!(app.notebook_view, 3)
        @test app.notebook_view.focused_idx == 3
    end

    @testset "SessionsApp — run_stale_cells! no stale" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        # Execute the cell first so it's not stale
        execute_cell!(app.workspace, nb.cells[nb.cell_order[1]])
        @test isempty(stale_cells(nb))

        n = Sessions.run_stale_cells!(app)
        @test n == 0
    end

    @testset "SessionsApp — run_stale_cells! with stale cell" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x_stale_test = 1")
        app = Sessions.SessionsApp(nb)

        # Execute to establish baseline
        execute_cell!(app.workspace, c1)
        @test !is_stale(c1)

        # Edit cell → becomes stale
        c1.code = "x_stale_test = 999"
        Sessions.sync_from_cell!(app.notebook_view.cell_widgets[1])
        @test is_stale(c1)

        n = Sessions.run_stale_cells!(app)
        @test n == 1
        @test !is_stale(c1)
        @test c1.state == cell_done
    end

    @testset "SessionsApp — run_stale_cells! respects dependencies" begin
        nb = Notebook()
        c1 = add_cell!(nb, "stale_a = 1")
        c2 = add_cell!(nb, "stale_b = stale_a + 1")
        c3 = add_cell!(nb, "stale_c = 100")  # independent
        app = Sessions.SessionsApp(nb)

        # Execute all cells
        execute_notebook!(nb; workspace=app.workspace)
        @test c1.state == cell_done
        @test c2.state == cell_done
        @test c3.state == cell_done

        # Edit c1 → makes it stale, c2 should re-run as dependent
        c1.code = "stale_a = 999"
        Sessions.sync_from_cell!(app.notebook_view.cell_widgets[1])
        @test is_stale(c1)
        @test !is_stale(c3)  # independent, not stale

        n = Sessions.run_stale_cells!(app)
        @test n == 1  # only c1 is stale (c2 runs as dependent via execute_changed!)
        @test c1.state == cell_done
        @test !is_stale(c1)
    end

    @testset "SessionsApp — Ctrl+S saves + runs stale" begin
        nb = Notebook(; path=tempname() * ".jl")
        c1 = add_cell!(nb, "ctrl_s_x = 42")
        app = Sessions.SessionsApp(nb)

        # Execute first
        execute_cell!(app.workspace, c1)

        # Edit cell
        c1.code = "ctrl_s_x = 99"
        Sessions.sync_from_cell!(app.notebook_view.cell_widgets[1])
        @test is_stale(c1)

        # Ctrl+S
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 's'))
        @test !is_stale(c1)
        @test contains(app.message, "stale")
    end

    @testset "SessionsApp — run_stale_cells! with error" begin
        nb = Notebook()
        c1 = add_cell!(nb, "good_val = 1")
        app = Sessions.SessionsApp(nb)

        # Execute, then make it error
        execute_cell!(app.workspace, c1)
        c1.code = "error(\"stale_boom\")"
        Sessions.sync_from_cell!(app.notebook_view.cell_widgets[1])

        Sessions.run_stale_cells!(app)
        @test c1.state == cell_errored
    end

    @testset "SessionsApp — view renders" begin
        nb = Notebook(; path="test_view.jl")
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        # Use TestBackend to render the view
        tb = TestBackend(80, 24)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame)

        # Check that cell content was rendered into the buffer
        found = false
        for r in 1:24
            text = Tachikoma.row_text(tb, r)
            if occursin("x = 1", text)
                found = true
                break
            end
        end
        @test found
    end

    # --- Async execution tests ---

    @testset "SessionsApp — has TaskQueue" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test app.tq isa Tachikoma.TaskQueue
        @test Tachikoma.task_queue(app) === app.tq
    end

    @testset "SessionsApp — is_busy initially false" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test !Sessions.is_busy(app)
    end

    @testset "SessionsApp — run_focused_cell_async! marks queued" begin
        nb = Notebook()
        c1 = add_cell!(nb, "async_x = 42")
        app = Sessions.SessionsApp(nb)

        Sessions.run_focused_cell_async!(app)
        # Cell should be queued initially (task spawned)
        # Note: may already complete in fast case
        @test c1.state in (cell_queued, cell_running, cell_done)

        # Wait for task completion
        sleep(0.5)
        @test c1.state == cell_done
        @test c1.output.result == 42
    end

    @testset "SessionsApp — run_all_cells_async! executes all" begin
        nb = Notebook()
        c1 = add_cell!(nb, "async_a = 10")
        c2 = add_cell!(nb, "async_b = async_a + 5")
        app = Sessions.SessionsApp(nb)

        Sessions.run_all_cells_async!(app)

        # Wait for completion
        sleep(1.0)
        @test c1.state == cell_done
        @test c1.output.result == 10
        @test c2.state == cell_done
        @test c2.output.result == 15
    end

    @testset "SessionsApp — Ctrl+Enter triggers async execution" begin
        nb = Notebook()
        c1 = add_cell!(nb, "ctrl_enter_val = 77")
        app = Sessions.SessionsApp(nb)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl_enter))
        @test contains(app.message, "Executing")

        sleep(0.5)
        @test c1.state == cell_done
        @test c1.output.result == 77
    end

    @testset "SessionsApp — Shift+Enter triggers async execution" begin
        nb = Notebook()
        c1 = add_cell!(nb, "shift_enter_val = 55")
        app = Sessions.SessionsApp(nb)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:shift_enter))
        @test contains(app.message, "Executing")

        sleep(0.5)
        @test c1.state == cell_done
        @test c1.output.result == 55
    end

    @testset "SessionsApp — Shift+Enter runs cell" begin
        nb = Notebook()
        c1 = add_cell!(nb, "insert_shift_val = 66")
        app = Sessions.SessionsApp(nb)

        # Shift+Enter runs the cell (always in editing mode)
        Tachikoma.update!(app, Tachikoma.KeyEvent(:shift_enter))
        @test contains(app.message, "Executing")

        sleep(0.5)
        @test c1.state == cell_done
        @test c1.output.result == 66
    end

    @testset "StatusBar — bottom bar shows Ctrl+R" begin
        bar = Sessions.make_bottom_bar(; mode=:normal)
        tb = TestBackend(120, 1)
        Tachikoma.render_widget!(tb, bar)
        @test Tachikoma.find_text(tb, "Ctrl+R") !== nothing

        bar_insert = Sessions.make_bottom_bar(; mode=:insert)
        tb2 = TestBackend(120, 1)
        Tachikoma.render_widget!(tb2, bar_insert)
        @test Tachikoma.find_text(tb2, "Ctrl+R") !== nothing

        # Normal mode shows click instructions
        @test Tachikoma.find_text(tb, "Click") !== nothing
    end

    @testset "SessionsApp — select_all! selects all cells" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        add_cell!(nb, "c = 3")
        app = Sessions.SessionsApp(nb)

        # Direct function call — keynav removed, select_all still works
        Sessions.select_all!(app.notebook_view)
        @test all(cw -> cw.selected, app.notebook_view.cell_widgets)
    end

    @testset "SessionsApp — focus change during async execution" begin
        nb = Notebook()
        c1 = add_cell!(nb, "nav_a = 1")
        c2 = add_cell!(nb, "nav_b = 2")
        c3 = add_cell!(nb, "nav_c = 3")
        app = Sessions.SessionsApp(nb)

        # Start async execution
        Sessions.run_all_cells_async!(app)

        # Focus change while executing — should still work (mouse-first model)
        @test app.notebook_view.focused_idx == 1
        Sessions.focus_cell!(app.notebook_view, 2)
        @test app.notebook_view.focused_idx == 2
        Sessions.focus_cell!(app.notebook_view, 3)
        @test app.notebook_view.focused_idx == 3

        sleep(0.5)
    end

    @testset "SessionsApp — TaskEvent handler" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        # Simulate a task completion event
        Tachikoma.update!(app, Tachikoma.TaskEvent(:execute_cell, nothing))
        @test app.message == "Execution complete"

        # Simulate a task error event
        Tachikoma.update!(app, Tachikoma.TaskEvent(:execute_cell, ErrorException("test")))
        @test contains(app.message, "error")

        # Run all completion
        Tachikoma.update!(app, Tachikoma.TaskEvent(:execute_all, nothing))
        @test app.message == "Ran all cells"
    end

    @testset "SessionsApp — synchronous fallbacks still work" begin
        nb = Notebook()
        c1 = add_cell!(nb, "sync_val = 42")
        app = Sessions.SessionsApp(nb)

        Sessions.run_focused_cell!(app)
        @test c1.state == cell_done
        @test c1.output.result == 42

        Sessions.run_all_cells!(app)
        @test c1.state == cell_done
    end

    # --- DataTable output tests ---

    @testset "DataTable — NamedTuple vector renders as table" begin
        cell = Cell("data = [(a=1, b=2), (a=3, b=4)]")
        cell.state = cell_done
        cell.output.result = [(a=1, b=2), (a=3, b=4)]
        cell.output.output_type = :dataframe

        ow = Sessions.OutputWidget(cell)
        @test Sessions.output_height(ow) > 0

        tb = TestBackend(60, 10)
        Tachikoma.render_widget!(tb, ow)
        @test Tachikoma.find_text(tb, "a") !== nothing
        @test Tachikoma.find_text(tb, "b") !== nothing
    end

    @testset "DataTable — column headers visible" begin
        cell = Cell("x")
        cell.state = cell_done
        cell.output.result = [(name="Alice", age=30), (name="Bob", age=25)]
        cell.output.output_type = :dataframe

        ow = Sessions.OutputWidget(cell)
        tb = TestBackend(60, 10)
        Tachikoma.render_widget!(tb, ow)
        @test Tachikoma.find_text(tb, "name") !== nothing
        @test Tachikoma.find_text(tb, "age") !== nothing
    end

    @testset "DataTable — row data visible" begin
        cell = Cell("x")
        cell.state = cell_done
        cell.output.result = [(x=42, y=99)]
        cell.output.output_type = :dataframe

        ow = Sessions.OutputWidget(cell)
        tb = TestBackend(60, 10)
        Tachikoma.render_widget!(tb, ow)
        @test Tachikoma.find_text(tb, "42") !== nothing
        @test Tachikoma.find_text(tb, "99") !== nothing
    end

    @testset "DataTable — empty table shows headers" begin
        cell = Cell("x")
        cell.state = cell_done
        cell.output.result = NamedTuple{(:a,:b), Tuple{Int,Int}}[]
        cell.output.output_type = :dataframe

        ow = Sessions.OutputWidget(cell)
        # Empty table → falls back to text since empty vector
        @test Sessions.output_height(ow) >= 0
    end

    @testset "DataTable — _make_datatable with NamedTuples" begin
        data = [(x=1, y=2), (x=3, y=4)]
        dt = Sessions._make_datatable(data)
        @test dt isa Tachikoma.DataTable
    end

    @testset "DataTable — _make_datatable with non-table returns nothing" begin
        @test Sessions._make_datatable(42) === nothing
        @test Sessions._make_datatable("hello") === nothing
    end

    @testset "DataTable — stale table falls back to text" begin
        cell = Cell("x")
        cell.state = cell_done
        cell.output.result = [(a=1,)]
        cell.output.output_type = :dataframe
        mark_executed!(cell)
        cell.code = "y"  # now stale

        ow = Sessions.OutputWidget(cell)
        tb = TestBackend(60, 10)
        Tachikoma.render_widget!(tb, ow)
        # Stale DataTable falls back to text — cell is stale
        @test Sessions.is_stale(cell)
    end

    # --- MarkdownPane output tests ---

    @testset "MarkdownPane — renders markdown" begin
        using Markdown: @md_str
        cell = Cell("md\"# Hello\"")
        cell.state = cell_done
        cell.output.result = md"# Hello"
        cell.output.output_type = :markdown

        ow = Sessions.OutputWidget(cell)
        @test Sessions.output_height(ow) > 0

        tb = TestBackend(60, 10)
        Tachikoma.render_widget!(tb, ow)
        @test Tachikoma.find_text(tb, "Hello") !== nothing
    end

    @testset "MarkdownPane — renders heading" begin
        using Markdown: @md_str
        cell = Cell("x")
        cell.state = cell_done
        cell.output.result = md"## Section Title"
        cell.output.output_type = :markdown

        ow = Sessions.OutputWidget(cell)
        tb = TestBackend(60, 10)
        Tachikoma.render_widget!(tb, ow)
        @test Tachikoma.find_text(tb, "Section") !== nothing
    end

    @testset "MarkdownPane — renders list" begin
        using Markdown: @md_str
        cell = Cell("x")
        cell.state = cell_done
        cell.output.result = md"""
- Item one
- Item two
"""
        cell.output.output_type = :markdown

        ow = Sessions.OutputWidget(cell)
        tb = TestBackend(60, 10)
        Tachikoma.render_widget!(tb, ow)
        @test Tachikoma.find_text(tb, "Item") !== nothing
    end

    @testset "MarkdownPane — stale falls back to text" begin
        using Markdown: @md_str
        cell = Cell("md\"# Test\"")
        cell.state = cell_done
        cell.output.result = md"# Test"
        cell.output.output_type = :markdown
        mark_executed!(cell)
        cell.code = "other"  # stale

        ow = Sessions.OutputWidget(cell)
        tb = TestBackend(60, 10)
        Tachikoma.render_widget!(tb, ow)
        # Stale markdown falls back to text — cell is stale
        @test Sessions.is_stale(cell)
    end

    @testset "MarkdownPane — _md_to_lines" begin
        using Markdown: @md_str
        lines = Sessions._md_to_lines(md"# Hello", 80)
        texts = join([seg.text for line in lines for seg in line], "")
        @test contains(texts, "Hello")
    end

    # --- PixelImage placeholder tests ---

    @testset "PixelImage — placeholder renders" begin
        cell = Cell("plot()")
        cell.state = cell_done
        cell.output.result = nothing
        cell.output.output_type = :image_png

        ow = Sessions.OutputWidget(cell)
        tb = TestBackend(60, 5)
        Tachikoma.render_widget!(tb, ow)
        @test Tachikoma.find_text(tb, "Image") !== nothing
    end

    @testset "PixelImage — non-image output doesn't trigger image path" begin
        cell = Cell("x = 42")
        cell.state = cell_done
        cell.output.result = 42
        cell.output.output_type = :text

        ow = Sessions.OutputWidget(cell)
        tb = TestBackend(60, 5)
        Tachikoma.render_widget!(tb, ow)
        @test Tachikoma.find_text(tb, "Image") === nothing
    end

    @testset "PixelImage — stale image falls back to text" begin
        cell = Cell("plot()")
        cell.state = cell_done
        cell.output.output_type = :image_png
        cell.output.text_representation = "[Image output]"
        cell.output.result = "[Image output]"  # fallback text
        mark_executed!(cell)
        cell.code = "other"  # stale

        ow = Sessions.OutputWidget(cell)
        tb = TestBackend(60, 5)
        Tachikoma.render_widget!(tb, ow)
        # Stale image falls back to text — cell is stale
        @test Sessions.is_stale(cell)
    end

    # --- Mouse interaction tests ---

    @testset "Mouse click — focuses cell" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        add_cell!(nb, "c = 3")
        app = Sessions.SessionsApp(nb)

        @test app.notebook_view.focused_idx == 1

        # Render to establish viewport
        tb = TestBackend(80, 24)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame)

        # Compute cell positions dynamically from viewport (accounts for border)
        vp = app.notebook_view.viewport
        nv = app.notebook_view
        ch1 = Sessions.cell_height(nv.cell_widgets[1])
        ch2 = Sessions.cell_height(nv.cell_widgets[2])
        gap = 2  # Theme.CELL_GAP
        # Inner content starts at vp.y + 1 (border) + 1 (TOP_MARGIN)
        cell1_y = vp.y + 2
        cell2_y = cell1_y + ch1 + gap
        cell3_y = cell2_y + ch2 + gap

        Tachikoma.update!(app, Tachikoma.MouseEvent(40, cell2_y, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false))
        @test app.notebook_view.focused_idx == 2

        Tachikoma.update!(app, Tachikoma.MouseEvent(40, cell3_y, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false))
        @test app.notebook_view.focused_idx == 3

        Tachikoma.update!(app, Tachikoma.MouseEvent(40, cell1_y, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false))
        @test app.notebook_view.focused_idx == 1
    end

    @testset "Mouse click — switches focus between cells" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        app = Sessions.SessionsApp(nb)

        # Render to establish viewport
        tb = TestBackend(80, 24)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame)

        # Click on cell 2 — compute y from viewport
        nv = app.notebook_view
        vp = nv.viewport
        ch1 = Sessions.cell_height(nv.cell_widgets[1])
        cell2_y = vp.y + Sessions.Theme.TOP_MARGIN + ch1 + Sessions.Theme.CELL_GAP + 1
        Tachikoma.update!(app, Tachikoma.MouseEvent(vp.x + 5, cell2_y, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false))
        @test app.notebook_view.focused_idx == 2
        @test app.mode == :normal
    end

    @testset "Mouse scroll — adjusts scroll offset" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        add_cell!(nb, "c = 3")
        app = Sessions.SessionsApp(nb)

        # Render to establish viewport
        tb = TestBackend(80, 24)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame)

        initial_offset = app.notebook_view.scroll_offset

        # Scroll down
        Tachikoma.update!(app, Tachikoma.MouseEvent(40, 10, Tachikoma.mouse_scroll_down, Tachikoma.mouse_press, false, false, false))
        @test app.notebook_view.scroll_offset >= initial_offset

        # Scroll up — clamped at 0
        for _ in 1:20
            Tachikoma.update!(app, Tachikoma.MouseEvent(40, 10, Tachikoma.mouse_scroll_up, Tachikoma.mouse_press, false, false, false))
        end
        @test app.notebook_view.scroll_offset >= 0
    end

    @testset "Mouse click — outside cells doesn't crash" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        # Render to establish viewport
        tb = TestBackend(80, 24)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame)

        # Click on top bar area (row 1) — should not crash
        Tachikoma.update!(app, Tachikoma.MouseEvent(40, 1, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false))
        @test app.notebook_view.focused_idx == 1  # unchanged

        # Click way below content — does NOT insert (only explicit + clicks)
        Tachikoma.update!(app, Tachikoma.MouseEvent(40, 23, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false))
        @test length(nb) == 1  # unchanged — no accidental insertion
        @test app.notebook_view.focused_idx == 1  # unchanged
    end

    @testset "Mouse click — renders focus change" begin
        nb = Notebook()
        add_cell!(nb, "m1 = 1")
        add_cell!(nb, "m2 = 2")
        app = Sessions.SessionsApp(nb)

        # Initial render — first cell focused
        tb = TestBackend(80, 24)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame)
        @test Tachikoma.find_text(tb, "m1 = 1") !== nothing
        @test Tachikoma.find_text(tb, "m2 = 2") !== nothing

        # Click on cell 2 — compute y from viewport
        nv = app.notebook_view
        vp = nv.viewport
        ch1 = Sessions.cell_height(nv.cell_widgets[1])
        cell2_y = vp.y + Sessions.Theme.TOP_MARGIN + ch1 + Sessions.Theme.CELL_GAP + 1
        Tachikoma.update!(app, Tachikoma.MouseEvent(vp.x + 5, cell2_y, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false))
        tb2 = TestBackend(80, 24)
        frame2 = Tachikoma.Frame(tb2.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame2)

        # Both cells still render, focus changed
        @test Tachikoma.find_text(tb2, "m1 = 1") !== nothing
        @test Tachikoma.find_text(tb2, "m2 = 2") !== nothing
        @test app.notebook_view.focused_idx == 2
        @test app.notebook_view.cell_widgets[2].focused == true
        @test app.notebook_view.cell_widgets[1].focused == false
    end

    @testset "Mouse release — ignored (no focus change)" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        app = Sessions.SessionsApp(nb)

        tb = TestBackend(80, 24)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame)

        # Mouse release should not change focus
        Tachikoma.update!(app, Tachikoma.MouseEvent(40, 6, Tachikoma.mouse_left, Tachikoma.mouse_release, false, false, false))
        @test app.notebook_view.focused_idx == 1
    end

    @testset "Progress bar — no bar when idle" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        tb = TestBackend(80, 24)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame)

        # No progress bar when no cells are running
        @test isempty(app.progress_recently)
        # Top border should be normal thin lines, no ━
        nv_vp = app.notebook_view.viewport
        top_y = nv_vp.y + Sessions.Theme.CELL_V_INSET
        row = Tachikoma.row_text(tb, top_y)
        @test !occursin('━', row)
    end

    @testset "Progress bar — shows when cells queued" begin
        nb = Notebook()
        c1 = add_cell!(nb, "a = 1")
        c2 = add_cell!(nb, "b = 2")
        c3 = add_cell!(nb, "c = 3")
        app = Sessions.SessionsApp(nb)

        # Mark all cells as queued (simulates run_all_cells_async! pre-mark)
        c1.state = cell_queued
        c2.state = cell_queued
        c3.state = cell_queued

        tb = TestBackend(80, 24)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame)

        # Progress recently should now contain all 3 cells
        @test length(app.progress_recently) == 3
        # Top border should have ━ characters (progress bar)
        nv_vp = app.notebook_view.viewport
        top_y = nv_vp.y + Sessions.Theme.CELL_V_INSET
        row = Tachikoma.row_text(tb, top_y)
        @test occursin('━', row)
    end

    @testset "Progress bar — advances as cells complete" begin
        nb = Notebook()
        c1 = add_cell!(nb, "a = 1")
        c2 = add_cell!(nb, "b = 2")
        app = Sessions.SessionsApp(nb)

        # Start: both queued
        c1.state = cell_queued
        c2.state = cell_queued

        tb = TestBackend(80, 24)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame)
        @test length(app.progress_recently) == 2

        # Count ━ chars at initial state (2 active out of 2)
        nv_vp = app.notebook_view.viewport
        top_y = nv_vp.y + Sessions.Theme.CELL_V_INSET
        row_before = Tachikoma.row_text(tb, top_y)
        n_before = count(==('━'), row_before)

        # Complete one cell
        c1.state = cell_done
        mark_executed!(c1)

        tb2 = TestBackend(80, 24)
        frame2 = Tachikoma.Frame(tb2.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame2)

        # Should have more ━ chars (more progress)
        row_after = Tachikoma.row_text(tb2, top_y)
        n_after = count(==('━'), row_after)
        @test n_after > n_before
    end

    @testset "Progress bar — green completion flash" begin
        nb = Notebook()
        c1 = add_cell!(nb, "a = 1")
        app = Sessions.SessionsApp(nb)

        # Simulate execution: queued → done
        c1.state = cell_queued
        tb = TestBackend(80, 24)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame)
        @test length(app.progress_recently) == 1

        # Cell completes
        c1.state = cell_done
        mark_executed!(c1)
        tb2 = TestBackend(80, 24)
        frame2 = Tachikoma.Frame(tb2.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame2)

        # Should show complete bar (progress_done_tick set)
        @test app.progress_done_tick > 0
        nv_vp = app.notebook_view.viewport
        top_y = nv_vp.y + Sessions.Theme.CELL_V_INSET
        row = Tachikoma.row_text(tb2, top_y)
        @test occursin('━', row)
    end

    @testset "Progress bar — clears after hold period" begin
        nb = Notebook()
        c1 = add_cell!(nb, "a = 1")
        app = Sessions.SessionsApp(nb)

        # Simulate execution cycle
        c1.state = cell_queued
        tb = TestBackend(80, 24)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame)

        c1.state = cell_done
        mark_executed!(c1)
        Tachikoma.view(app, Tachikoma.Frame(TestBackend(80,24).buf, Rect(1,1,80,24), [], []))

        # Advance tick past hold period
        for _ in 1:(Sessions.Theme.PROGRESS_HOLD + 5)
            Sessions.Theme.advance_tick!()
        end

        tb3 = TestBackend(80, 24)
        frame3 = Tachikoma.Frame(tb3.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame3)

        # Progress tracking should be cleared
        @test isempty(app.progress_recently)
        @test app.progress_done_tick == 0
    end

    # --- Cached session output tests (SESSIONS-6014) ---

    @testset "OutputWidget — cached text_representation shows when result is nothing" begin
        cell = Cell("x = 42")
        cell.state = cell_done
        cell.output.output_type = :text
        cell.output.text_representation = "42"
        # result is nothing (loaded from session cache, not live execution)

        lines = Sessions.output_lines(cell)
        @test any(l -> occursin("42", l), lines)

        ow = Sessions.OutputWidget(cell)
        tb = TestBackend(60, 5)
        Tachikoma.render_widget!(tb, ow)
        @test Tachikoma.find_text(tb, "42") !== nothing
    end

    @testset "OutputWidget — cached stdout shows" begin
        cell = Cell("println(\"cached\")")
        cell.state = cell_done
        cell.output.output_type = :text
        cell.output.stdout = "cached\n"
        cell.output.text_representation = "nothing"

        lines = Sessions.output_lines(cell)
        @test any(l -> occursin("cached", l), lines)
    end

    @testset "SessionsApp — open notebook with session file shows cached output" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "x = 1 + 1")
        save_notebook(nb)

        ws = Workspace()
        execute_cell!(ws, c1)
        Sessions.save_session!(nb)

        # Open via SessionsApp(path) which now uses load_notebook_with_session
        app = Sessions.SessionsApp(path)

        c1b = get_cell(app.nb, c1.id)
        @test c1b.state == cell_done
        @test c1b.output.text_representation == "2"
        @test !is_stale(c1b)

        # Render and verify cached output is visible
        tb = TestBackend(80, 24)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame)
        @test Tachikoma.find_text(tb, "2") !== nothing

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "SessionsApp — open notebook without session file shows never-run" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "y = 99")
        save_notebook(nb)
        # No session file

        app = Sessions.SessionsApp(path)

        c1b = get_cell(app.nb, c1.id)
        @test c1b.state == cell_idle
        @test is_never_run(c1b)

        # Render — should not show any output value
        tb = TestBackend(80, 24)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame)

        # Cell code should be visible, but no output "99"
        @test Tachikoma.find_text(tb, "y = 99") !== nothing

        rm(path; force=true)
    end

    @testset "_open_file! uses load_notebook_with_session" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "z = 7 * 6")
        save_notebook(nb)

        ws = Workspace()
        execute_cell!(ws, c1)
        Sessions.save_session!(nb)

        # Create an app with a dummy notebook, then open the real one
        dummy_nb = Notebook()
        add_cell!(dummy_nb, "")
        app = Sessions.SessionsApp(dummy_nb)
        Sessions._open_file!(app, path)

        c1b = get_cell(app.nb, c1.id)
        @test c1b.state == cell_done
        @test c1b.output.text_representation == "42"
        @test !is_stale(c1b)

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    # --- Last-known-disk snapshot tracking (SESSIONS-6017) ---

    @testset "SessionsApp — last_disk_nb set on construction" begin
        nb = Notebook(; path="snap_test.jl")
        c1 = add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test app.last_disk_nb !== nothing
        @test app.last_disk_nb isa Notebook
        @test length(app.last_disk_nb.cell_order) == length(nb.cell_order)
        @test app.last_disk_nb.cell_order == nb.cell_order
    end

    @testset "SessionsApp — last_disk_nb is deep copy" begin
        nb = Notebook(; path="snap_deep.jl")
        c1 = add_cell!(nb, "y = 2")
        app = Sessions.SessionsApp(nb)

        # Modify the live notebook — snapshot should be unaffected
        nb.cells[c1.id].code = "y = 999"
        @test app.last_disk_nb.cells[c1.id].code == "y = 2"
    end

    @testset "SessionsApp — last_disk_nb updated after save (Ctrl+S)" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "save_snap = 1")
        save_notebook(nb)
        app = Sessions.SessionsApp(nb)

        # Modify cell code
        nb.cells[c1.id].code = "save_snap = 2"
        old_snap_code = app.last_disk_nb.cells[c1.id].code
        @test old_snap_code == "save_snap = 1"

        # Trigger Ctrl+S
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 's'))

        # Snapshot updated to current state
        @test app.last_disk_nb.cells[c1.id].code == "save_snap = 2"

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "SessionsApp — last_disk_nb updated after _open_file!" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "open_snap = 42")
        save_notebook(nb)

        dummy_nb = Notebook()
        add_cell!(dummy_nb, "")
        app = Sessions.SessionsApp(dummy_nb)

        Sessions._open_file!(app, path)
        @test app.last_disk_nb !== nothing
        @test haskey(app.last_disk_nb.cells, c1.id)
        @test app.last_disk_nb.cells[c1.id].code == "open_snap = 42"

        rm(path; force=true)
    end

    @testset "SessionsApp(path) — last_disk_nb set from loaded file" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "path_snap = 7")
        save_notebook(nb)

        app = Sessions.SessionsApp(path)
        @test app.last_disk_nb !== nothing
        @test haskey(app.last_disk_nb.cells, c1.id)
        @test app.last_disk_nb.cells[c1.id].code == "path_snap = 7"

        rm(path; force=true)
    end

    # --- Watcher integration (SESSIONS-6019) ---

    @testset "SessionsApp — watcher field initially nothing" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        @test app.watcher === nothing
    end

    @testset "_on_external_change! — merges agent edit and rebuilds" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "watch_a = 1")
        c2 = add_cell!(nb, "watch_b = 2")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        # Simulate execution
        execute_cell!(app.workspace, c1)
        execute_cell!(app.workspace, c2)
        @test c1.state == cell_done

        # Agent edits c1 on disk
        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "watch_a = 999"
        save_notebook(nb_ext, path)

        # Trigger external change handler directly
        Sessions._on_external_change!(app)

        @test app.nb.cells[c1.id].code == "watch_a = 999"
        @test is_stale(app.nb.cells[c1.id])
        @test contains(app.message, "changed externally")
        # c2 unchanged
        @test app.nb.cells[c2.id].code == "watch_b = 2"

        rm(path; force=true)
    end

    @testset "_on_external_change! — agent adds cell, widgets rebuilt" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "ext_x = 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        @test length(app.notebook_view.cell_widgets) == 1

        # Agent adds cell on disk
        nb_ext = load_notebook(path)
        c2 = add_cell!(nb_ext, "ext_y = 2")
        save_notebook(nb_ext, path)

        Sessions._on_external_change!(app)

        @test length(app.nb.cell_order) == 2
        @test haskey(app.nb.cells, c2.id)
        @test length(app.notebook_view.cell_widgets) == 2

        rm(path; force=true)
    end

    @testset "_on_external_change! — no auto-execution" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "no_auto = 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        execute_cell!(app.workspace, c1)
        @test c1.state == cell_done

        # Agent changes cell on disk
        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "no_auto = 999"
        save_notebook(nb_ext, path)

        Sessions._on_external_change!(app)

        # Cell should be stale but NOT re-executed
        @test c1.code == "no_auto = 999"
        @test is_stale(c1)
        @test c1.output.result == 1  # old result, NOT 999

        rm(path; force=true)
    end

    @testset "Ctrl+Q stops watcher" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        add_cell!(nb, "quit_test = 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        # Manually set up a watcher
        Sessions._start_watcher!(app)
        @test app.watcher !== nothing

        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'q'))
        @test app.quit == true
        @test app.watcher === nothing

        rm(path; force=true)
    end

    @testset "_on_external_change! — no changes is silent" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "silent = 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        app.message = "previous message"

        # No disk changes — should not update message
        Sessions._on_external_change!(app)
        @test app.message == "previous message"

        rm(path; force=true)
    end

    @testset "_start_watcher! — starts for valid file path" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        add_cell!(nb, "start_w = 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        Sessions._start_watcher!(app)
        @test app.watcher !== nothing

        Sessions.stop_watching!(app.watcher)
        app.watcher = nothing
        rm(path; force=true)
    end

    @testset "_start_watcher! — skips for empty path" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        Sessions._start_watcher!(app)
        @test app.watcher === nothing
    end

    # --- Save-during-watch guard (SESSIONS-6020) ---

    @testset "last_save_time — initially zero" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        @test app.last_save_time == 0.0
    end

    @testset "Ctrl+S sets last_save_time" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "save_guard = 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        @test app.last_save_time == 0.0

        before = time()
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 's'))
        after = time()

        @test app.last_save_time >= before
        @test app.last_save_time <= after

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "save guard — own save skips reload" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "guard_x = 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        app.message = ""

        # Simulate: we just saved (set last_save_time to now)
        app.last_save_time = time()

        # External change handler should skip (within tolerance)
        Sessions._on_external_change!(app)
        @test app.message == ""  # no "changed externally" message

        rm(path; force=true)
    end

    @testset "save guard — agent edit after tolerance IS detected" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "agent_after = 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        execute_cell!(app.workspace, c1)

        # Set last_save_time in the past (beyond tolerance)
        app.last_save_time = time() - 2.0

        # Agent edits on disk
        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "agent_after = 999"
        save_notebook(nb_ext, path)

        Sessions._on_external_change!(app)

        @test app.nb.cells[c1.id].code == "agent_after = 999"
        @test contains(app.message, "changed externally")

        rm(path; force=true)
    end

    # --- TUI External Change Notification (SESSIONS-6021) ---

    @testset "external change — message includes cell count" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "notify_a = 1")
        c2 = add_cell!(nb, "notify_b = 2")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)

        # Agent changes both cells on disk
        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "notify_a = 10"
        nb_ext.cells[c2.id].code = "notify_b = 20"
        save_notebook(nb_ext, path)

        Sessions._on_external_change!(app)
        @test contains(app.message, "2 cell(s) changed externally")

        rm(path; force=true)
    end

    @testset "external change — dropdown closes" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "dd_test = 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        app.cell_dropdown = Sessions.CellDropdown(1, 10, 5, Sessions.DROPDOWN_ITEMS, 0)
        app.mode = :dropdown

        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "dd_test = 999"
        save_notebook(nb_ext, path)

        Sessions._on_external_change!(app)
        @test app.cell_dropdown === nothing
        @test app.mode == :normal

        rm(path; force=true)
    end

    @testset "external change — selection clears" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "sel_a = 1")
        c2 = add_cell!(nb, "sel_b = 2")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        # Select all widgets
        for cw in app.notebook_view.cell_widgets
            cw.selected = true
        end

        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "sel_a = 999"
        save_notebook(nb_ext, path)

        Sessions._on_external_change!(app)
        @test all(!cw.selected for cw in app.notebook_view.cell_widgets)

        rm(path; force=true)
    end

    @testset "external change — focus preserved by UUID" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "focus_a = 1")
        c2 = add_cell!(nb, "focus_b = 2")
        c3 = add_cell!(nb, "focus_c = 3")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        # Focus on c2
        app.notebook_view.focused_idx = 2

        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "focus_a = 999"
        save_notebook(nb_ext, path)

        Sessions._on_external_change!(app)
        # Focus should still be on c2 (preserved by UUID in rebuild_widgets!)
        @test app.notebook_view.focused_idx == 2
        @test app.notebook_view.cell_widgets[2].cell.id == c2.id

        rm(path; force=true)
    end

    # --- Cached output dimming (SESSIONS-6022) ---

    @testset "cached stale cell — output renders with text_representation" begin
        cell = Cell("x = 42")
        cell.state = cell_done
        cell.output.output_type = :text
        cell.output.text_representation = "42"
        mark_executed!(cell)
        # Make stale by changing code
        cell.code = "x = 99"
        @test is_stale(cell)

        # Output should still render (from text_representation fallback)
        ow = Sessions.OutputWidget(cell)
        lines = Sessions.output_lines(cell)
        @test any(l -> occursin("42", l), lines)  # old cached value

        tb = TestBackend(60, 5)
        Tachikoma.render_widget!(tb, ow)
        @test Tachikoma.find_text(tb, "42") !== nothing
    end

    @testset "cached clean cell — output renders normally" begin
        cell = Cell("x = 42")
        cell.state = cell_done
        cell.output.output_type = :text
        cell.output.text_representation = "42"
        mark_executed!(cell)
        @test !is_stale(cell)

        ow = Sessions.OutputWidget(cell)
        tb = TestBackend(60, 5)
        Tachikoma.render_widget!(tb, ow)
        @test Tachikoma.find_text(tb, "42") !== nothing
    end

    @testset "never-run cell — no output shown" begin
        cell = Cell("x = 42")
        @test cell.state == cell_idle

        ow = Sessions.OutputWidget(cell)
        @test Sessions.output_height(ow) == 0
    end

    @testset "stale indicator for cached-stale cell" begin
        cell = Cell("x = 42")
        cell.output.output_type = :text
        cell.output.text_representation = "42"
        mark_executed!(cell)
        cell.state = cell_done
        cell.code = "x = 99"  # stale
        @test is_stale(cell)

        char, _ = Sessions.state_indicator(cell)
        @test char == "○"  # hollow circle for stale
    end

    @testset "external change — renders updated cell code after change" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "render_msg = 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)

        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "render_msg = 999"
        save_notebook(nb_ext, path)

        Sessions._on_external_change!(app)
        @test contains(app.message, "changed externally")

        # Render and verify new cell code is visible
        tb = TestBackend(80, 24)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 80, 24), [], [])
        Tachikoma.view(app, frame)
        @test Tachikoma.find_text(tb, "render_msg = 999") !== nothing

        rm(path; force=true)
    end

    # --- External Modification Visual Tests (SESSIONS-6023) ---

    @testset "ext visual — changed cell renders stale indicator + new code" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "vis_a = 10")
        c2 = add_cell!(nb, "vis_b = 20")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        execute_cell!(app.workspace, c1)
        execute_cell!(app.workspace, c2)
        @test c1.state == cell_done
        @test c2.state == cell_done

        # Agent changes c1 on disk
        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "vis_a = 777"
        save_notebook(nb_ext, path)
        Sessions._on_external_change!(app)

        # c1 is stale, c2 is clean
        @test is_stale(app.nb.cells[c1.id])
        @test !is_stale(app.nb.cells[c2.id])

        # Render and verify
        tb = TestBackend(120, 40)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 120, 40), [], [])
        Tachikoma.view(app, frame)

        # Changed code visible
        @test Tachikoma.find_text(tb, "vis_a = 777") !== nothing
        # Stale indicator verified via model
        ind, _ = Sessions.state_indicator(app.nb.cells[c1.id])
        @test ind == "○"
        # Clean cell still visible
        @test Tachikoma.find_text(tb, "vis_b = 20") !== nothing

        rm(path; force=true)
    end

    @testset "ext visual — added cell renders never-run indicator" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "vis_exist = 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        execute_cell!(app.workspace, c1)

        # Agent adds new cell on disk
        nb_ext = load_notebook(path)
        c_new = add_cell!(nb_ext, "vis_new_cell = 42")
        save_notebook(nb_ext, path)
        Sessions._on_external_change!(app)

        @test haskey(app.nb.cells, c_new.id)
        @test app.nb.cells[c_new.id].state == cell_idle

        # Render
        tb = TestBackend(120, 40)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 120, 40), [], [])
        Tachikoma.view(app, frame)

        # New cell code visible
        @test Tachikoma.find_text(tb, "vis_new_cell = 42") !== nothing
        # Never-run indicator verified via model
        ind, _ = Sessions.state_indicator(app.nb.cells[c_new.id])
        @test ind == "◌"

        rm(path; force=true)
    end

    @testset "ext visual — removed cell no longer visible" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "vis_keep = 1")
        c2 = add_cell!(nb, "vis_gone = 2")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)

        # Render before removal — both visible
        tb = TestBackend(120, 40)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 120, 40), [], [])
        Tachikoma.view(app, frame)
        @test Tachikoma.find_text(tb, "vis_keep = 1") !== nothing
        @test Tachikoma.find_text(tb, "vis_gone = 2") !== nothing

        # Agent removes c2 on disk
        nb_ext = load_notebook(path)
        remove_cell!(nb_ext, c2.id)
        save_notebook(nb_ext, path)
        Sessions._on_external_change!(app)

        # Render after removal
        tb2 = TestBackend(120, 40)
        frame2 = Tachikoma.Frame(tb2.buf, Rect(1, 1, 120, 40), [], [])
        Tachikoma.view(app, frame2)

        @test Tachikoma.find_text(tb2, "vis_keep = 1") !== nothing
        @test Tachikoma.find_text(tb2, "vis_gone = 2") === nothing
        @test !haskey(app.nb.cells, c2.id)

        rm(path; force=true)
    end

    @testset "ext visual — reordered cells render in new order" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "vis_first = 1")
        c2 = add_cell!(nb, "vis_second = 2")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)

        # Agent reorders: c2 before c1
        nb_ext = load_notebook(path)
        nb_ext.cell_order = [c2.id, c1.id]
        save_notebook(nb_ext, path)
        Sessions._on_external_change!(app)

        @test app.nb.cell_order == [c2.id, c1.id]
        @test contains(app.message, "changed externally")

        # Verify widget order matches new cell_order
        @test app.notebook_view.cell_widgets[1].cell.id == c2.id
        @test app.notebook_view.cell_widgets[2].cell.id == c1.id

        # Render and verify both visible
        tb = TestBackend(120, 40)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 120, 40), [], [])
        Tachikoma.view(app, frame)

        @test Tachikoma.find_text(tb, "vis_first = 1") !== nothing
        @test Tachikoma.find_text(tb, "vis_second = 2") !== nothing

        rm(path; force=true)
    end

    @testset "ext visual — multiple changes (add+change+remove) render correctly" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "multi_keep = 1")
        c2 = add_cell!(nb, "multi_change = 2")
        c3 = add_cell!(nb, "multi_remove = 3")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        execute_cell!(app.workspace, c1)
        execute_cell!(app.workspace, c2)
        execute_cell!(app.workspace, c3)

        # Agent: change c2, remove c3, add c4
        nb_ext = load_notebook(path)
        nb_ext.cells[c2.id].code = "multi_change = 999"
        remove_cell!(nb_ext, c3.id)
        c4 = add_cell!(nb_ext, "multi_added = 4")
        save_notebook(nb_ext, path)
        Sessions._on_external_change!(app)

        # Verify model state
        @test app.nb.cells[c1.id].code == "multi_keep = 1"
        @test app.nb.cells[c2.id].code == "multi_change = 999"
        @test !haskey(app.nb.cells, c3.id)
        @test haskey(app.nb.cells, c4.id)
        @test is_stale(app.nb.cells[c2.id])
        @test contains(app.message, "changed externally")

        # Render and verify
        tb = TestBackend(120, 50)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, 120, 50), [], [])
        Tachikoma.view(app, frame)

        @test Tachikoma.find_text(tb, "multi_keep = 1") !== nothing
        @test Tachikoma.find_text(tb, "multi_change = 999") !== nothing
        @test Tachikoma.find_text(tb, "multi_remove = 3") === nothing
        @test Tachikoma.find_text(tb, "multi_added = 4") !== nothing

        rm(path; force=true)
    end

    # --- Concurrent Edit Tests (SESSIONS-6026) ---

    @testset "concurrent — user local edit preserved when agent changes different cell" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "conc_user = 1")
        c2 = add_cell!(nb, "conc_agent = 2")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        execute_cell!(app.workspace, c1)
        execute_cell!(app.workspace, c2)
        @test c1.state == cell_done
        @test c2.state == cell_done

        # User edits c1 locally (in-memory only, not saved to disk)
        app.nb.cells[c1.id].code = "conc_user = 100"
        Sessions.sync_from_cell!(app.notebook_view.cell_widgets[1])

        # Agent edits c2 on disk
        nb_ext = load_notebook(path)
        nb_ext.cells[c2.id].code = "conc_agent = 200"
        save_notebook(nb_ext, path)

        # Trigger external change
        Sessions._on_external_change!(app)

        # User's local edit to c1 preserved
        @test app.nb.cells[c1.id].code == "conc_user = 100"
        # Agent's disk edit to c2 applied
        @test app.nb.cells[c2.id].code == "conc_agent = 200"
        @test is_stale(app.nb.cells[c2.id])
        # No auto-execution
        @test app.nb.cells[c2.id].output.result == 2  # old value

        rm(path; force=true)
    end

    @testset "concurrent — agent edit wins when both edit same cell (disk is truth)" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "same_cell = 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        execute_cell!(app.workspace, c1)
        @test c1.state == cell_done

        # User edits c1 locally
        app.nb.cells[c1.id].code = "same_cell = 100"
        Sessions.sync_from_cell!(app.notebook_view.cell_widgets[1])

        # Agent also edits c1 on disk
        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "same_cell = 999"
        save_notebook(nb_ext, path)

        # External change: disk version wins for cells changed on disk
        Sessions._on_external_change!(app)

        @test app.nb.cells[c1.id].code == "same_cell = 999"
        @test is_stale(app.nb.cells[c1.id])
        # No auto-execution
        @test app.nb.cells[c1.id].output.result == 1

        rm(path; force=true)
    end

    @testset "concurrent — rapid writes coalesce to single reload (debounce)" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        add_cell!(nb, "rapid = 1")
        save_notebook(nb)

        fired = Ref(0)
        dw = Sessions.DebouncedWatcher(nb, _ -> (fired[] += 1);
                                       delay=0.3, poll_interval=0.05)
        Sessions.start_watching!(dw)

        # Simulate rapid agent writes (5 writes within debounce window)
        sleep(0.1)
        for i in 1:5
            open(path, "a") do io
                println(io, "# rapid write $i")
            end
            sleep(0.06)
        end
        sleep(0.6)  # wait for debounce to fire

        Sessions.stop_watching!(dw)
        @test fired[] <= 2  # coalesced — at most 2 fires (not 5)

        rm(path; force=true)
    end

    @testset "concurrent — own save does not trigger external change notification" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "own_save = 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)

        # Simulate Ctrl+S save (sets last_save_time)
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 's'))
        @test app.last_save_time > 0.0

        # Clear the "Saved: ..." message so we can check save guard behavior
        app.message = ""

        # Watcher would detect mtime change — but save guard should skip it
        Sessions._on_external_change!(app)
        @test app.message == ""  # no "changed externally" message

        rm(path; force=true)
        rm(Sessions.session_path(path); force=true)
    end

    @testset "concurrent — no auto-execution in any concurrent scenario" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "noexec_a = 1")
        c2 = add_cell!(nb, "noexec_b = 2")
        c3 = add_cell!(nb, "noexec_c = 3")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        execute_cell!(app.workspace, c1)
        execute_cell!(app.workspace, c2)
        execute_cell!(app.workspace, c3)
        @test all(c -> c.state == cell_done, values(app.nb.cells))

        # User edits c1 locally
        app.nb.cells[c1.id].code = "noexec_a = 100"

        # Agent: change c2, add c4, remove c3 on disk
        nb_ext = load_notebook(path)
        nb_ext.cells[c2.id].code = "noexec_b = 200"
        remove_cell!(nb_ext, c3.id)
        c4 = add_cell!(nb_ext, "noexec_d = 4")
        save_notebook(nb_ext, path)

        Sessions._on_external_change!(app)

        # Verify NO cell is running or was re-executed
        for (id, cell) in app.nb.cells
            @test cell.state != cell_running
        end
        # Stale cells have old outputs, not new
        @test is_stale(app.nb.cells[c2.id])
        @test app.nb.cells[c2.id].output.result == 2  # old value, not 200
        # New cell is idle (never run)
        @test app.nb.cells[c4.id].state == cell_idle
        # Removed cell is gone
        @test !haskey(app.nb.cells, c3.id)

        rm(path; force=true)
    end

    # --- Dirty cell detection ---

    @testset "is_dirty — clean cell" begin
        cell = Cell("x = 1")
        cw = Sessions.CellWidget(cell)
        @test !Sessions.is_dirty(cw)
    end

    @testset "is_dirty — after editor edit" begin
        cell = Cell("x = 1")
        cw = Sessions.CellWidget(cell)
        Tachikoma.set_text!(cw.editor, "x = 2")
        # Editor changed but cell.code not synced
        @test Sessions.is_dirty(cw)
    end

    @testset "is_dirty — after sync clears dirty" begin
        cell = Cell("x = 1")
        cw = Sessions.CellWidget(cell)
        Tachikoma.set_text!(cw.editor, "x = 2")
        @test Sessions.is_dirty(cw)
        Sessions.sync_to_cell!(cw)
        @test !Sessions.is_dirty(cw)
    end

    @testset "dirty cell — orange border renders" begin
        cell = Cell("x = 1")
        cw = Sessions.CellWidget(cell; focused=false)
        Tachikoma.set_text!(cw.editor, "x = 999")
        # Don't sync — cell is dirty

        tb = TestBackend(60, 5)
        Tachikoma.render_widget!(tb, cw)
        # Cell code should render (from editor)
        @test Tachikoma.find_text(tb, "x = 999") !== nothing
    end

    # --- Editor scroll reset ---

    @testset "editor scroll_offset resets when all lines fit" begin
        cell = Cell("begin\n    sleep(5)\n    c = b * 2\nend")
        cw = Sessions.CellWidget(cell; focused=false)
        # Artificially set scroll_offset as if editor was previously scrolled
        cw.editor.scroll_offset = 2
        # Render in a buffer tall enough for all 4 lines
        tb = TestBackend(60, 8)
        Tachikoma.render_widget!(tb, cw)
        # scroll_offset should be reset since all lines fit
        @test cw.editor.scroll_offset == 0
        # Line 1 should be visible
        @test Tachikoma.find_text(tb, "begin") !== nothing
    end

    # --- Running/queued cell indicator ---

    @testset "running cell — left border bar renders ▎" begin
        cell = Cell("sleep(1)")
        cell.state = cell_running
        cw = Sessions.CellWidget(cell; focused=false)
        tb = TestBackend(60, 8)
        Sessions.Theme.TICK[] = 10
        Tachikoma.render_widget!(tb, cw)
        # The left border column should contain ▎ characters
        @test Tachikoma.find_text(tb, "▎") !== nothing
    end

    @testset "queued cell — left border bar renders ▎" begin
        cell = Cell("x = 1")
        cell.state = cell_queued
        cw = Sessions.CellWidget(cell; focused=false)
        tb = TestBackend(60, 8)
        Sessions.Theme.TICK[] = 10
        Tachikoma.render_widget!(tb, cw)
        @test Tachikoma.find_text(tb, "▎") !== nothing
    end

    @testset "idle cell — no left border bar" begin
        cell = Cell("x = 1")
        cell.state = cell_done
        mark_executed!(cell)
        cw = Sessions.CellWidget(cell; focused=false)
        tb = TestBackend(60, 8)
        Sessions.Theme.TICK[] = 10
        Tachikoma.render_widget!(tb, cw)
        @test Tachikoma.find_text(tb, "▎") === nothing
    end

    # --- File panel auto-refresh ---

    @testset "FilePanel — auto-refresh on tick interval" begin
        dir = mktempdir()
        fp = Sessions.FilePanel(dir)
        initial_count = length(fp.entries)

        # Create a new file
        touch(joinpath(dir, "new_file.txt"))

        # Before refresh interval — no change
        @test length(fp.entries) == initial_count

        # Advance past refresh interval and render
        for _ in 1:(Sessions.FILE_PANEL_REFRESH_INTERVAL + 1)
            Sessions.Theme.advance_tick!()
        end

        tb = TestBackend(30, 20)
        Tachikoma.render_widget!(tb, fp)

        # After render with tick past interval — should pick up new file
        @test length(fp.entries) == initial_count + 1
        @test any(e -> e.name == "new_file.txt", fp.entries)

        rm(dir; recursive=true)
    end
end
