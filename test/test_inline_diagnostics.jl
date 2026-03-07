@testset "Inline Diagnostics" begin

    # --- Helper: render app to TestBackend and return it ---
    function render_app_diag(app; width=120, height=40)
        tb = TestBackend(width, height)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, width, height), [], [])
        Tachikoma.view(app, frame)
        tb
    end

    # Helper: set diagnostics on app (not nv, since view() overwrites nv.cell_diags)
    function set_diags(app, cell_id, diags)
        app.cell_diagnostics_cache[cell_id] = diags
    end

    @testset "cell_height: no diagnostics" begin
        nb = Notebook(; path="diag_test.jl")
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        cw = app.notebook_view.cell_widgets[1]

        @test isempty(cw.diagnostics)
        h_base = Sessions.cell_height(cw)
        @test h_base == 3  # 1 code line + 2 border
    end

    @testset "cell_height: with diagnostics, focused" begin
        nb = Notebook(; path="diag_test.jl")
        add_cell!(nb, "x = 1\ny = 2")
        app = Sessions.SessionsApp(nb)
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.diagnostics = [
            Sessions.Diagnostic(1, :error, "undefined variable", "JET"),
            Sessions.Diagnostic(2, :warning, "type instability", "JET"),
        ]

        h = Sessions.cell_height(cw)
        # 2 code lines + 2 diagnostics + 2 border = 6
        @test h == 6
    end

    @testset "cell_height: with diagnostics, not focused" begin
        nb = Notebook(; path="diag_test.jl")
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = false
        cw.diagnostics = [
            Sessions.Diagnostic(1, :error, "test error", "JET"),
        ]

        h = Sessions.cell_height(cw)
        # Not focused: diagnostics don't add to height
        @test h == 3  # 1 code line + 2 border
    end

    @testset "cell_height: diagnostics + folded" begin
        nb = Notebook(; path="diag_test.jl")
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.diagnostics = [Sessions.Diagnostic(1, :error, "err", "JET")]
        cw.cell.folded = true

        # Folded overrides everything
        @test Sessions.cell_height(cw) == 1
    end

    @testset "cell_height: disabled with diagnostics" begin
        nb = Notebook(; path="diag_test.jl")
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.diagnostics = [Sessions.Diagnostic(1, :error, "err", "JET")]
        cw.cell.disabled = true

        vi = Sessions.Theme.CELL_V_INSET
        @test Sessions.cell_height(cw) == 3 + 2 * vi
    end

    @testset "cell_height: multiple diagnostics" begin
        nb = Notebook(; path="diag_test.jl")
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.diagnostics = [
            Sessions.Diagnostic(1, :error, "err1", "JET"),
            Sessions.Diagnostic(1, :warning, "warn1", "JET"),
            Sessions.Diagnostic(1, :info, "info1", "JET"),
        ]

        h = Sessions.cell_height(cw)
        # 1 code line + 3 diagnostics + 2 border = 6
        @test h == 6
    end

    @testset "diagnostics sync: cell_diagnostics_cache → cw.diagnostics" begin
        nb = Notebook(; path="diag_test.jl")
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        cw = app.notebook_view.cell_widgets[1]
        cell_id = cw.cell.id

        # Initially empty
        @test isempty(cw.diagnostics)

        # Populate via app cache (view() copies this to nv.cell_diags)
        set_diags(app, cell_id, [
            Sessions.Diagnostic(1, :error, "sync test", "JET"),
        ])

        # Rendering syncs diagnostics
        render_app_diag(app)

        @test length(cw.diagnostics) == 1
        @test cw.diagnostics[1].message == "sync test"
    end

    @testset "E2E: inline diagnostic text visible in focused cell" begin
        nb = Notebook(; path="diag_test.jl")
        add_cell!(nb, "x = foo")
        app = Sessions.SessionsApp(nb)
        cw = app.notebook_view.cell_widgets[1]
        cell_id = cw.cell.id

        set_diags(app, cell_id, [
            Sessions.Diagnostic(1, :error, "undefined variable foo", "JET"),
        ])

        @test app.notebook_view.focused_idx == 1

        tb = render_app_diag(app; height=20)
        @test Tachikoma.find_text(tb, "undefined variable foo") !== nothing
    end

    @testset "E2E: inline diagnostics hidden for unfocused cell" begin
        nb = Notebook(; path="diag_test.jl")
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        app = Sessions.SessionsApp(nb)
        cell_id_2 = app.notebook_view.cell_widgets[2].cell.id

        # Diagnostics on cell 2 (not focused)
        set_diags(app, cell_id_2, [
            Sessions.Diagnostic(1, :warning, "hidden_diag_text", "JET"),
        ])

        @test app.notebook_view.focused_idx == 1

        tb = render_app_diag(app; height=30)
        @test Tachikoma.find_text(tb, "hidden_diag_text") === nothing
    end

    @testset "E2E: multiple diagnostics on focused cell" begin
        nb = Notebook(; path="diag_test.jl")
        add_cell!(nb, "x = foo\ny = bar")
        app = Sessions.SessionsApp(nb)
        cw = app.notebook_view.cell_widgets[1]
        cell_id = cw.cell.id

        set_diags(app, cell_id, [
            Sessions.Diagnostic(1, :error, "error on line 1", "JET"),
            Sessions.Diagnostic(2, :warning, "warning on line 2", "JET"),
        ])

        @test app.notebook_view.focused_idx == 1
        tb = render_app_diag(app; height=20)
        @test Tachikoma.find_text(tb, "error on line 1") !== nothing
        @test Tachikoma.find_text(tb, "warning on line 2") !== nothing
    end

    @testset "E2E: diagnostic prefix arrow visible" begin
        nb = Notebook(; path="diag_test.jl")
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        cell_id = app.notebook_view.cell_widgets[1].cell.id

        set_diags(app, cell_id, [
            Sessions.Diagnostic(1, :error, "test msg", "JET"),
        ])

        tb = render_app_diag(app; height=20)
        @test Tachikoma.find_text(tb, "↳") !== nothing
    end

    @testset "E2E: gutter markers alongside inline diagnostics" begin
        nb = Notebook(; path="diag_test.jl")
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        cell_id = app.notebook_view.cell_widgets[1].cell.id

        set_diags(app, cell_id, [
            Sessions.Diagnostic(1, :error, "gutter test msg", "JET"),
        ])

        tb = render_app_diag(app; height=20)
        # Gutter dot (●) should be present
        @test Tachikoma.find_text(tb, "●") !== nothing
        # Inline text should also be present
        @test Tachikoma.find_text(tb, "gutter test msg") !== nothing
    end

    @testset "diagnostics cleared when cache emptied" begin
        nb = Notebook(; path="diag_test.jl")
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        cw = app.notebook_view.cell_widgets[1]
        cell_id = cw.cell.id

        # Add diagnostics
        set_diags(app, cell_id, [
            Sessions.Diagnostic(1, :error, "temp error", "JET"),
        ])
        render_app_diag(app)
        @test length(cw.diagnostics) == 1

        # Clear diagnostics
        set_diags(app, cell_id, Sessions.Diagnostic[])
        render_app_diag(app)
        @test isempty(cw.diagnostics)
    end
end
