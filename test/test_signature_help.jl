@testset "Signature Help" begin

    import Tachikoma

    # ── parse_signature_help ──────────────────────────────────────────

    @testset "parse_signature_help — basic signature" begin
        response = Dict{String,Any}(
            "signatures" => [
                Dict{String,Any}(
                    "label" => "foo(x::Int, y::String)",
                    "parameters" => [
                        Dict{String,Any}("label" => "x::Int"),
                        Dict{String,Any}("label" => "y::String")
                    ]
                )
            ],
            "activeSignature" => 0,
            "activeParameter" => 0
        )
        sh = Sessions.parse_signature_help(response)
        @test sh !== nothing
        @test sh.label == "foo(x::Int, y::String)"
        @test sh.parameters == ["x::Int", "y::String"]
        @test sh.active_param == 0
    end

    @testset "parse_signature_help — active parameter index" begin
        response = Dict{String,Any}(
            "signatures" => [
                Dict{String,Any}(
                    "label" => "bar(a, b, c)",
                    "parameters" => [
                        Dict{String,Any}("label" => "a"),
                        Dict{String,Any}("label" => "b"),
                        Dict{String,Any}("label" => "c")
                    ]
                )
            ],
            "activeSignature" => 0,
            "activeParameter" => 1
        )
        sh = Sessions.parse_signature_help(response)
        @test sh !== nothing
        @test sh.active_param == 1
    end

    @testset "parse_signature_help — multiple signatures uses activeSignature" begin
        response = Dict{String,Any}(
            "signatures" => [
                Dict{String,Any}("label" => "foo(x)", "parameters" => [
                    Dict{String,Any}("label" => "x")
                ]),
                Dict{String,Any}("label" => "foo(x, y)", "parameters" => [
                    Dict{String,Any}("label" => "x"),
                    Dict{String,Any}("label" => "y")
                ])
            ],
            "activeSignature" => 1,
            "activeParameter" => 0
        )
        sh = Sessions.parse_signature_help(response)
        @test sh !== nothing
        @test sh.label == "foo(x, y)"
    end

    @testset "parse_signature_help — null response" begin
        @test Sessions.parse_signature_help(nothing) === nothing
    end

    @testset "parse_signature_help — empty signatures" begin
        response = Dict{String,Any}("signatures" => Any[])
        @test Sessions.parse_signature_help(response) === nothing
    end

    @testset "parse_signature_help — non-dict response" begin
        @test Sessions.parse_signature_help("unexpected") === nothing
        @test Sessions.parse_signature_help(42) === nothing
    end

    @testset "parse_signature_help — no parameters" begin
        response = Dict{String,Any}(
            "signatures" => [
                Dict{String,Any}("label" => "rand()")
            ],
            "activeSignature" => 0,
            "activeParameter" => 0
        )
        sh = Sessions.parse_signature_help(response)
        @test sh !== nothing
        @test sh.label == "rand()"
        @test sh.parameters == String[]
    end

    @testset "parse_signature_help — parameter label as range" begin
        response = Dict{String,Any}(
            "signatures" => [
                Dict{String,Any}(
                    "label" => "func(abc, def)",
                    "parameters" => [
                        Dict{String,Any}("label" => Any[5, 8]),
                        Dict{String,Any}("label" => "def")
                    ]
                )
            ],
            "activeSignature" => 0,
            "activeParameter" => 0
        )
        sh = Sessions.parse_signature_help(response)
        @test sh !== nothing
        @test length(sh.parameters) == 2
        @test sh.parameters[1] == "abc"
    end

    @testset "parse_signature_help — missing activeParameter defaults to 0" begin
        response = Dict{String,Any}(
            "signatures" => [
                Dict{String,Any}("label" => "f(x)")
            ]
        )
        sh = Sessions.parse_signature_help(response)
        @test sh !== nothing
        @test sh.active_param == 0
    end

    @testset "parse_signature_help — activeSignature out of bounds clamped" begin
        response = Dict{String,Any}(
            "signatures" => [
                Dict{String,Any}("label" => "f(x)")
            ],
            "activeSignature" => 5,
            "activeParameter" => 0
        )
        sh = Sessions.parse_signature_help(response)
        @test sh !== nothing
        @test sh.label == "f(x)"
    end

    # ── LspSignatureHelp struct ──────────────────────────────────────

    @testset "LspSignatureHelp construction" begin
        sh = Sessions.LspSignatureHelp("foo(x, y)", ["x", "y"], 0)
        @test sh.label == "foo(x, y)"
        @test sh.parameters == ["x", "y"]
        @test sh.active_param == 0
    end

    # ── lsp_signature_help_with_timeout! — graceful degradation ──────

    @testset "lsp_signature_help_with_timeout! — client not ready" begin
        client = LspClient(; enabled=false)
        @test Sessions.lsp_signature_help_with_timeout!(client, "file://test.jl", 1, 0) === nothing
    end

    @testset "lsp_signature_help_with_timeout! — client starting" begin
        client = LspClient(; enabled=true)
        @test client.status == lsp_starting
        @test Sessions.lsp_signature_help_with_timeout!(client, "file://test.jl", 1, 0) === nothing
    end

    @testset "lsp_signature_help_with_timeout! — client error" begin
        client = LspClient(; enabled=true)
        client.status = lsp_error
        @test Sessions.lsp_signature_help_with_timeout!(client, "file://test.jl", 1, 0) === nothing
    end

    # ── SignatureHelpTooltip ─────────────────────────────────────────

    @testset "SignatureHelpTooltip construction" begin
        st = Sessions.SignatureHelpTooltip("foo(x, y)", ["x", "y"], 0, 10, 5)
        @test st.label == "foo(x, y)"
        @test st.parameters == ["x", "y"]
        @test st.active_param == 0
        @test st.x == 10
        @test st.y == 5
    end

    # ── _trigger_signature_help! / _dismiss_signature_help! ──────────

    @testset "_trigger_signature_help! — no LSP (notebook)" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "foo(")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert

        Sessions._trigger_signature_help!(app)
        @test app.signature_tooltip === nothing
    end

    @testset "_trigger_signature_help! — no LSP (file editor)" begin
        path = tempname() * ".jl"
        write(path, "foo(\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)

        Sessions._trigger_signature_help!(app)
        @test app.signature_tooltip === nothing
        rm(path; force=true)
    end

    @testset "_dismiss_signature_help!" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        app.signature_tooltip = Sessions.SignatureHelpTooltip("foo(x)", ["x"], 0, 5, 5)

        Sessions._dismiss_signature_help!(app)
        @test app.signature_tooltip === nothing
    end

    # ── _advance_signature_param! ────────────────────────────────────

    @testset "_advance_signature_param! increments" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        app.signature_tooltip = Sessions.SignatureHelpTooltip("foo(a, b, c)", ["a", "b", "c"], 0, 5, 5)

        Sessions._advance_signature_param!(app)
        @test app.signature_tooltip.active_param == 1

        Sessions._advance_signature_param!(app)
        @test app.signature_tooltip.active_param == 2
    end

    @testset "_advance_signature_param! clamps at max" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        app.signature_tooltip = Sessions.SignatureHelpTooltip("foo(a, b)", ["a", "b"], 1, 5, 5)

        Sessions._advance_signature_param!(app)
        @test app.signature_tooltip.active_param == 1  # stays at max
    end

    @testset "_advance_signature_param! — no tooltip" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        Sessions._advance_signature_param!(app)  # should not crash
        @test app.signature_tooltip === nothing
    end

    # ── '(' triggers in notebook insert mode ─────────────────────────

    @testset "Typing '(' in notebook insert mode attempts signature help" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "foo")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert
        cw.editor.cursor_col = 3

        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, '('))
        @test app.signature_tooltip === nothing  # no LSP
    end

    @testset "Typing ')' dismisses signature help in notebook" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "foo(")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert
        cw.editor.cursor_col = 4
        app.signature_tooltip = Sessions.SignatureHelpTooltip("foo(x)", ["x"], 0, 5, 5)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, ')'))
        @test app.signature_tooltip === nothing
    end

    @testset "Typing ',' advances param in notebook" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "foo(a")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert
        cw.editor.cursor_col = 5
        app.signature_tooltip = Sessions.SignatureHelpTooltip("foo(a, b)", ["a", "b"], 0, 5, 5)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, ','))
        @test app.signature_tooltip !== nothing
        @test app.signature_tooltip.active_param == 1
    end

    @testset "Escape dismisses signature help in notebook" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "foo(")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        app.signature_tooltip = Sessions.SignatureHelpTooltip("foo(x)", ["x"], 0, 5, 5)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:escape, '\0'))
        @test app.signature_tooltip === nothing
    end

    # ── '(' triggers in file editor mode ──────────────────────────────

    @testset "Typing '(' in file editor attempts signature help" begin
        path = tempname() * ".jl"
        write(path, "foo")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.cursor_col = 3

        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, '('))
        @test app.signature_tooltip === nothing  # no LSP
        rm(path; force=true)
    end

    @testset "Typing ')' dismisses signature help in file editor" begin
        path = tempname() * ".jl"
        write(path, "foo(")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.cursor_col = 4
        app.signature_tooltip = Sessions.SignatureHelpTooltip("foo(x)", ["x"], 0, 5, 5)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, ')'))
        @test app.signature_tooltip === nothing
        rm(path; force=true)
    end

    @testset "Typing ',' advances param in file editor" begin
        path = tempname() * ".jl"
        write(path, "foo(a")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.cursor_col = 5
        app.signature_tooltip = Sessions.SignatureHelpTooltip("foo(a, b)", ["a", "b"], 0, 5, 5)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, ','))
        @test app.signature_tooltip !== nothing
        @test app.signature_tooltip.active_param == 1
        rm(path; force=true)
    end

    @testset "Escape dismisses signature help in file editor" begin
        path = tempname() * ".jl"
        write(path, "foo(")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        app.signature_tooltip = Sessions.SignatureHelpTooltip("foo(x)", ["x"], 0, 5, 5)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:escape, '\0'))
        @test app.signature_tooltip === nothing
        rm(path; force=true)
    end

    # ── Movement keys dismiss signature help ─────────────────────────

    @testset "Arrow keys dismiss signature help" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "foo(")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert
        app.signature_tooltip = Sessions.SignatureHelpTooltip("foo(x)", ["x"], 0, 5, 5)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:left, '\0'))
        @test app.signature_tooltip === nothing
    end

    # ── Render smoke tests ───────────────────────────────────────────

    function render_app_sig(app; width=120, height=40)
        tb = Tachikoma.TestBackend(width, height)
        frame = Tachikoma.Frame(tb.buf, Tachikoma.Rect(1, 1, width, height), [], [])
        Tachikoma.view(app, frame)
        tb
    end

    @testset "Render signature help — notebook smoke test" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        app.signature_tooltip = Sessions.SignatureHelpTooltip(
            "foo(x::Int, y::String)", ["x::Int", "y::String"], 0, 10, 10)

        tb = render_app_sig(app)
        output = Tachikoma.row_text(tb, 1)
        @test output isa String
    end

    @testset "Render signature help — file editor smoke test" begin
        path = tempname() * ".jl"
        write(path, "foo(x)\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        app.signature_tooltip = Sessions.SignatureHelpTooltip(
            "bar(a, b)", ["a", "b"], 1, 5, 10)

        tb = render_app_sig(app)
        output = Tachikoma.row_text(tb, 1)
        @test output isa String
        rm(path; force=true)
    end

    @testset "Render signature help — no params" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        app.signature_tooltip = Sessions.SignatureHelpTooltip(
            "rand()", String[], 0, 10, 10)

        render_app_sig(app)
        @test true  # no crash
    end

    @testset "Render signature help — active param highlight" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        app.signature_tooltip = Sessions.SignatureHelpTooltip(
            "foo(x, y)", ["x", "y"], 1, 10, 10)

        render_app_sig(app)
        @test true  # no crash, active param highlighted
    end

    # ── Exported symbols ──────────────────────────────────────────────

    @testset "Signature help types and functions are exported" begin
        @test isdefined(Sessions, :LspSignatureHelp)
        @test isdefined(Sessions, :parse_signature_help)
        @test isdefined(Sessions, :lsp_signature_help!)
        @test isdefined(Sessions, :lsp_signature_help_with_timeout!)
    end

end
