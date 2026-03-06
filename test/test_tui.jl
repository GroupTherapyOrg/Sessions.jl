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
        tb = TestBackend(80, 1)
        Tachikoma.render_widget!(tb, bar)
        @test Tachikoma.find_text(tb, "Ctrl+Q") !== nothing
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
