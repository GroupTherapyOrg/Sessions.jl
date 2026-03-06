using Test
using Sessions
using Tachikoma

@testset "tui" begin
    @testset "CellWidget" begin
        cell = Cell("x = 42")
        cw = Sessions.CellWidget(cell; focused=true)
        @test cw.focused == true
        @test cw.cell === cell

        # Render to TestBackend
        tb = TestBackend(60, 5)
        Tachikoma.render_widget!(tb, cw)
        @test Tachikoma.find_text(tb, "Cell") !== nothing
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

        cell.state = cell_idle
        char, _ = Sessions.state_indicator(cell)
        @test char == "○"

        cell.state = cell_done
        char, _ = Sessions.state_indicator(cell)
        @test char == "●"

        cell.state = cell_errored
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
        @test Tachikoma.find_text(tb, "Save+Run") !== nothing
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

    @testset "SessionsApp — mode switching" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test app.mode == :normal

        # Enter insert mode
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter))
        @test app.mode == :insert

        # Back to normal
        Tachikoma.update!(app, Tachikoma.KeyEvent(:escape))
        @test app.mode == :normal
    end

    @testset "SessionsApp — cell navigation" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        add_cell!(nb, "c = 3")
        app = Sessions.SessionsApp(nb)

        @test app.notebook_view.focused_idx == 1

        Tachikoma.update!(app, Tachikoma.KeyEvent(:tab))
        @test app.notebook_view.focused_idx == 2

        Tachikoma.update!(app, Tachikoma.KeyEvent(:tab))
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

        # Check that content was rendered into the buffer
        found = false
        for r in 1:24
            text = Tachikoma.row_text(tb, r)
            if occursin("test_view.jl", text)
                found = true
                break
            end
        end
        @test found
    end
end
