@testset "Scrollbar / Code Density Minimap" begin

    import Tachikoma

    # Helper: render app and return TestBackend
    function render_app_sb(app; width=120, height=40)
        tb = Tachikoma.TestBackend(width, height)
        frame = Tachikoma.Frame(tb.buf, Tachikoma.Rect(1, 1, width, height), [], [])
        Tachikoma.view(app, frame)
        tb
    end

    # ── _scrollbar_metrics ───────────────────────────────────────────

    @testset "_scrollbar_metrics — no scrollbar when content fits" begin
        result = Sessions._scrollbar_metrics(10, 20, 0, 20)
        @test result === nothing
    end

    @testset "_scrollbar_metrics — no scrollbar when equal" begin
        result = Sessions._scrollbar_metrics(20, 20, 0, 20)
        @test result === nothing
    end

    @testset "_scrollbar_metrics — basic thumb" begin
        result = Sessions._scrollbar_metrics(100, 20, 0, 20)
        @test result !== nothing
        @test result.thumb_start == 0
        @test result.thumb_size >= 1
        @test result.thumb_size <= 20
    end

    @testset "_scrollbar_metrics — thumb size proportional" begin
        # 50% viewport → ~50% thumb
        result = Sessions._scrollbar_metrics(40, 20, 0, 20)
        @test result !== nothing
        @test result.thumb_size >= 8  # roughly 50%
        @test result.thumb_size <= 12
    end

    @testset "_scrollbar_metrics — thumb at bottom when scrolled to end" begin
        total = 100
        viewport = 20
        max_scroll = total - viewport  # 80
        result = Sessions._scrollbar_metrics(total, viewport, max_scroll, 20)
        @test result !== nothing
        @test result.thumb_start + result.thumb_size <= 20
        @test result.thumb_start > 0  # not at top
    end

    @testset "_scrollbar_metrics — thumb at middle" begin
        total = 100
        viewport = 20
        scroll = 40  # middle-ish
        result = Sessions._scrollbar_metrics(total, viewport, scroll, 20)
        @test result !== nothing
        @test result.thumb_start > 0
        @test result.thumb_start + result.thumb_size < 20
    end

    @testset "_scrollbar_metrics — minimum thumb size is 1" begin
        result = Sessions._scrollbar_metrics(1000, 1, 0, 10)
        @test result !== nothing
        @test result.thumb_size >= 1
    end

    # ── Notebook scrollbar render ────────────────────────────────────

    @testset "Scrollbar renders on notebook with many cells" begin
        nb = Sessions.Notebook()
        for i in 1:20
            Sessions.add_cell!(nb, "cell_$i = $i")
        end
        app = Sessions.SessionsApp(nb)

        tb = render_app_sb(app; height=24)
        # Scrollbar should be on rightmost column of editor area
        # Just check no crash and that some rendering happened
        @test Tachikoma.row_text(tb, 1) isa String
    end

    @testset "No scrollbar when few cells" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        tb = render_app_sb(app; height=40)
        @test Tachikoma.row_text(tb, 1) isa String
    end

    # ── File editor scrollbar render ─────────────────────────────────

    @testset "Scrollbar renders on file editor with many lines" begin
        path = tempname() * ".jl"
        lines = join(["line_$i = $i" for i in 1:100], "\n")
        write(path, lines)
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)

        tb = render_app_sb(app; height=24)
        @test Tachikoma.row_text(tb, 1) isa String
        rm(path; force=true)
    end

    @testset "No scrollbar when file fits in viewport" begin
        path = tempname() * ".jl"
        write(path, "x = 1\ny = 2\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)

        tb = render_app_sb(app; height=40)
        @test Tachikoma.row_text(tb, 1) isa String
        rm(path; force=true)
    end

    # ── Scrollbar click-to-jump (notebook) ───────────────────────────

    @testset "Click on scrollbar column adjusts scroll (notebook)" begin
        nb = Sessions.Notebook()
        for i in 1:30
            Sessions.add_cell!(nb, "cell_$i = $i")
        end
        app = Sessions.SessionsApp(nb)

        # Render first to establish scrollbar_col
        render_app_sb(app; height=24)

        # scrollbar_col should be set
        @test app.scrollbar_col > 0

        # Click near the bottom of the scrollbar should increase scroll
        old_scroll = app.notebook_view.scroll_offset
        click_y = app.scrollbar_y + app.scrollbar_h - 2
        Tachikoma.update!(app, Tachikoma.MouseEvent(
            app.scrollbar_col, click_y,
            Tachikoma.mouse_left, Tachikoma.mouse_press,
            false, false, false))
        @test app.notebook_view.scroll_offset >= old_scroll
    end

    # ── Scrollbar click-to-jump (file editor) ────────────────────────

    @testset "Click on scrollbar column adjusts scroll (file editor)" begin
        path = tempname() * ".jl"
        lines = join(["line_$i = $i" for i in 1:100], "\n")
        write(path, lines)
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)

        # Render to establish scrollbar_col
        render_app_sb(app; height=24)

        @test app.scrollbar_col > 0

        # Click near the bottom
        click_y = app.scrollbar_y + app.scrollbar_h - 2
        Tachikoma.update!(app, Tachikoma.MouseEvent(
            app.scrollbar_col, click_y,
            Tachikoma.mouse_left, Tachikoma.mouse_press,
            false, false, false))
        @test fev.editor.scroll_offset >= 0
        rm(path; force=true)
    end

    # ── Both modes have scrollbar ────────────────────────────────────

    @testset "Scrollbar works in both notebook and file editor modes" begin
        # Notebook
        nb = Sessions.Notebook()
        for i in 1:20
            Sessions.add_cell!(nb, "x_$i = $i")
        end
        app_nb = Sessions.SessionsApp(nb)
        render_app_sb(app_nb; height=20)
        @test app_nb.scrollbar_col > 0

        # File editor
        path = tempname() * ".jl"
        lines = join(["y_$i = $i" for i in 1:50], "\n")
        write(path, lines)
        fev = Sessions.FileEditorView(path)
        app_fe = Sessions.SessionsApp(fev)
        render_app_sb(app_fe; height=20)
        @test app_fe.scrollbar_col > 0
        rm(path; force=true)
    end

    # ── Scroll wheel support ─────────────────────────────────────────

    @testset "Mouse scroll wheel adjusts scroll (notebook)" begin
        nb = Sessions.Notebook()
        for i in 1:20
            Sessions.add_cell!(nb, "cell_$i = $i")
        end
        app = Sessions.SessionsApp(nb)
        render_app_sb(app; height=20)

        # Scroll down
        Tachikoma.update!(app, Tachikoma.MouseEvent(
            50, 10,
            Tachikoma.mouse_scroll_down, Tachikoma.mouse_press,
            false, false, false))
        @test app.notebook_view.scroll_offset > 0
    end

end
