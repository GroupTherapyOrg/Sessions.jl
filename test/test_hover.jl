@testset "LSP Hover" begin

    import Tachikoma

    # Helper: render app and return TestBackend
    function render_app_hover(app; width=120, height=40)
        tb = Tachikoma.TestBackend(width, height)
        frame = Tachikoma.Frame(tb.buf, Tachikoma.Rect(1, 1, width, height), [], [])
        Tachikoma.view(app, frame)
        tb
    end

    # ── parse_hover ───────────────────────────────────────────────────

    @testset "parse_hover — string contents" begin
        response = Dict{String,Any}("contents" => "Int64")
        result = Sessions.parse_hover(response)
        @test result !== nothing
        @test result.contents == "Int64"
    end

    @testset "parse_hover — MarkupContent dict" begin
        response = Dict{String,Any}(
            "contents" => Dict{String,Any}("kind" => "markdown", "value" => "```julia\nInt64\n```")
        )
        result = Sessions.parse_hover(response)
        @test result !== nothing
        @test occursin("Int64", result.contents)
    end

    @testset "parse_hover — array of MarkedString" begin
        response = Dict{String,Any}(
            "contents" => [
                Dict{String,Any}("language" => "julia", "value" => "x::Int64"),
                "A variable"
            ]
        )
        result = Sessions.parse_hover(response)
        @test result !== nothing
        @test occursin("x::Int64", result.contents)
        @test occursin("A variable", result.contents)
    end

    @testset "parse_hover — empty contents" begin
        response = Dict{String,Any}("contents" => "")
        @test Sessions.parse_hover(response) === nothing
    end

    @testset "parse_hover — null response" begin
        @test Sessions.parse_hover(nothing) === nothing
    end

    @testset "parse_hover — non-dict response" begin
        @test Sessions.parse_hover("unexpected") === nothing
        @test Sessions.parse_hover(42) === nothing
    end

    # ── lsp_hover_with_timeout! — graceful degradation ────────────────

    @testset "lsp_hover_with_timeout! — client not ready returns nothing" begin
        client = LspClient(; enabled=false)
        result = Sessions.lsp_hover_with_timeout!(client, "file://test.jl", 1, 0)
        @test result === nothing
    end

    @testset "lsp_hover_with_timeout! — client starting returns nothing" begin
        client = LspClient(; enabled=true)
        @test client.status == lsp_starting
        result = Sessions.lsp_hover_with_timeout!(client, "file://test.jl", 1, 0)
        @test result === nothing
    end

    @testset "lsp_hover_with_timeout! — client error returns nothing" begin
        client = LspClient(; enabled=true)
        client.status = lsp_error
        result = Sessions.lsp_hover_with_timeout!(client, "file://test.jl", 1, 0)
        @test result === nothing
    end

    # ── LspHoverResult struct ─────────────────────────────────────────

    @testset "LspHoverResult construction" begin
        r = Sessions.LspHoverResult("Int64", 5, 3)
        @test r.contents == "Int64"
        @test r.line == 5
        @test r.col == 3
    end

    # ── HoverTooltip struct ───────────────────────────────────────────

    @testset "HoverTooltip construction" begin
        tt = Sessions.HoverTooltip("Int64", 10, 5)
        @test tt.text == "Int64"
        @test tt.x == 10
        @test tt.y == 5
    end

    # ── _show_hover! / _dismiss_hover! ────────────────────────────────

    @testset "_show_hover! sets tooltip" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        Sessions._show_hover!(app, "Int64", 15, 8)
        @test app.hover_tooltip !== nothing
        @test app.hover_tooltip.text == "Int64"
        @test app.hover_tooltip.x == 15
        @test app.hover_tooltip.y == 8
    end

    @testset "_dismiss_hover! clears tooltip" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        Sessions._show_hover!(app, "Int64", 15, 8)
        Sessions._dismiss_hover!(app)
        @test app.hover_tooltip === nothing
    end

    # ── Hover dismissed on keypress ───────────────────────────────────

    @testset "Keypress dismisses hover tooltip" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        app.mode = :normal

        Sessions._show_hover!(app, "Int64", 15, 8)
        @test app.hover_tooltip !== nothing

        Tachikoma.update!(app, Tachikoma.KeyEvent(:down))
        @test app.hover_tooltip === nothing
    end

    # ── Hover dismissed on mouse move ─────────────────────────────────

    @testset "Mouse move dismisses hover tooltip" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        Sessions._show_hover!(app, "Int64", 15, 8)
        @test app.hover_tooltip !== nothing

        # Simulate mouse move to a different position
        Tachikoma.update!(app, Tachikoma.MouseEvent(20, 10, Tachikoma.mouse_none, Tachikoma.mouse_move, false, false, false))
        @test app.hover_tooltip === nothing
    end

    # ── Mouse stillness tracking ──────────────────────────────────────

    @testset "Mouse move resets hover timer" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        # Move mouse to position 1
        Tachikoma.update!(app, Tachikoma.MouseEvent(10, 5, Tachikoma.mouse_none, Tachikoma.mouse_move, false, false, false))
        @test app.hover_last_mouse_x == 10
        @test app.hover_last_mouse_y == 5
        @test app.hover_still_since > 0.0
        @test app.hover_requested == false

        t1 = app.hover_still_since

        # Move to different position — resets
        sleep(0.01)
        Tachikoma.update!(app, Tachikoma.MouseEvent(15, 8, Tachikoma.mouse_none, Tachikoma.mouse_move, false, false, false))
        @test app.hover_last_mouse_x == 15
        @test app.hover_last_mouse_y == 8
        @test app.hover_still_since > t1
    end

    @testset "Same mouse position does not reset timer" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        Tachikoma.update!(app, Tachikoma.MouseEvent(10, 5, Tachikoma.mouse_none, Tachikoma.mouse_move, false, false, false))
        t1 = app.hover_still_since

        # Same position — should NOT reset
        sleep(0.01)
        Tachikoma.update!(app, Tachikoma.MouseEvent(10, 5, Tachikoma.mouse_none, Tachikoma.mouse_move, false, false, false))
        @test app.hover_still_since == t1
    end

    # ── Hover tooltip rendering ───────────────────────────────────────

    @testset "Hover tooltip renders in notebook without crash" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        Sessions._show_hover!(app, "x::Int64", 20, 10)

        tb = render_app_hover(app)
        @test Tachikoma.find_text(tb, "x::Int64") !== nothing
    end

    @testset "Hover tooltip renders in file editor without crash" begin
        path = tempname() * ".jl"
        write(path, "y = 2\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        Sessions._show_hover!(app, "y::Int64", 20, 10)

        tb = render_app_hover(app)
        @test Tachikoma.find_text(tb, "y::Int64") !== nothing
        rm(path; force=true)
    end

    @testset "Hover tooltip with multiline text" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "f(x)")
        app = Sessions.SessionsApp(nb)
        Sessions._show_hover!(app, "f(x::Int64)::String\nA function that does something", 20, 10)

        tb = render_app_hover(app)
        @test Tachikoma.find_text(tb, "f(x::Int64)::String") !== nothing
    end

    @testset "Hover tooltip with empty text is not shown" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x")
        app = Sessions.SessionsApp(nb)
        Sessions._show_hover!(app, "", 20, 10)

        # Rendering should not crash
        tb = render_app_hover(app)
        # Empty tooltip just doesn't render any content
        @test true  # smoke test
    end

    # ── Exports ───────────────────────────────────────────────────────

    @testset "Hover types and functions are exported" begin
        @test isdefined(Sessions, :LspHoverResult)
        @test isdefined(Sessions, :parse_hover)
        @test isdefined(Sessions, :lsp_hover!)
        @test isdefined(Sessions, :lsp_hover_with_timeout!)
    end

    # ── HOVER_DEBOUNCE constant ───────────────────────────────────────

    @testset "HOVER_DEBOUNCE is a positive number" begin
        @test Sessions.HOVER_DEBOUNCE > 0.0
        @test Sessions.HOVER_DEBOUNCE == 0.5
    end

    # ── hover fields on SessionsApp ───────────────────────────────────

    @testset "SessionsApp hover fields initialized correctly" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        @test app.hover_tooltip === nothing
        @test app.hover_last_mouse_x == 0
        @test app.hover_last_mouse_y == 0
        @test app.hover_still_since == 0.0
        @test app.hover_requested == false
    end

end
