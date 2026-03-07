@testset "Go-to-Definition" begin

    import Tachikoma

    # ── parse_definition ──────────────────────────────────────────────

    @testset "parse_definition — Location object" begin
        response = Dict{String,Any}(
            "uri" => "file:///tmp/test.jl",
            "range" => Dict{String,Any}(
                "start" => Dict{String,Any}("line" => 9, "character" => 4),
                "end" => Dict{String,Any}("line" => 9, "character" => 10)
            )
        )
        loc = Sessions.parse_definition(response)
        @test loc !== nothing
        @test loc.uri == "file:///tmp/test.jl"
        @test loc.line == 10  # 0-based → 1-based
        @test loc.col == 4
    end

    @testset "parse_definition — Location[] array" begin
        response = [
            Dict{String,Any}(
                "uri" => "file:///tmp/a.jl",
                "range" => Dict{String,Any}(
                    "start" => Dict{String,Any}("line" => 0, "character" => 0),
                    "end" => Dict{String,Any}("line" => 0, "character" => 5)
                )
            ),
            Dict{String,Any}(
                "uri" => "file:///tmp/b.jl",
                "range" => Dict{String,Any}(
                    "start" => Dict{String,Any}("line" => 5, "character" => 2),
                    "end" => Dict{String,Any}("line" => 5, "character" => 8)
                )
            )
        ]
        loc = Sessions.parse_definition(response)
        @test loc !== nothing
        @test loc.uri == "file:///tmp/a.jl"
        @test loc.line == 1  # first location used
    end

    @testset "parse_definition — LocationLink" begin
        response = [
            Dict{String,Any}(
                "targetUri" => "file:///tmp/target.jl",
                "targetRange" => Dict{String,Any}(
                    "start" => Dict{String,Any}("line" => 3, "character" => 0),
                    "end" => Dict{String,Any}("line" => 3, "character" => 15)
                ),
                "originSelectionRange" => Dict{String,Any}(
                    "start" => Dict{String,Any}("line" => 1, "character" => 0),
                    "end" => Dict{String,Any}("line" => 1, "character" => 5)
                )
            )
        ]
        loc = Sessions.parse_definition(response)
        @test loc !== nothing
        @test loc.uri == "file:///tmp/target.jl"
        @test loc.line == 4
    end

    @testset "parse_definition — null response" begin
        @test Sessions.parse_definition(nothing) === nothing
    end

    @testset "parse_definition — empty array" begin
        @test Sessions.parse_definition(Any[]) === nothing
    end

    @testset "parse_definition — non-dict response" begin
        @test Sessions.parse_definition("unexpected") === nothing
        @test Sessions.parse_definition(42) === nothing
    end

    @testset "parse_definition — missing uri" begin
        response = Dict{String,Any}(
            "range" => Dict{String,Any}(
                "start" => Dict{String,Any}("line" => 0, "character" => 0),
                "end" => Dict{String,Any}("line" => 0, "character" => 0)
            )
        )
        @test Sessions.parse_definition(response) === nothing
    end

    # ── LspLocation struct ────────────────────────────────────────────

    @testset "LspLocation construction" begin
        loc = Sessions.LspLocation("file:///tmp/test.jl", 10, 4)
        @test loc.uri == "file:///tmp/test.jl"
        @test loc.line == 10
        @test loc.col == 4
    end

    # ── lsp_definition_with_timeout! — graceful degradation ───────────

    @testset "lsp_definition_with_timeout! — client not ready" begin
        client = LspClient(; enabled=false)
        @test Sessions.lsp_definition_with_timeout!(client, "file://test.jl", 1, 0) === nothing
    end

    @testset "lsp_definition_with_timeout! — client starting" begin
        client = LspClient(; enabled=true)
        @test client.status == lsp_starting
        @test Sessions.lsp_definition_with_timeout!(client, "file://test.jl", 1, 0) === nothing
    end

    @testset "lsp_definition_with_timeout! — client error" begin
        client = LspClient(; enabled=true)
        client.status = lsp_error
        @test Sessions.lsp_definition_with_timeout!(client, "file://test.jl", 1, 0) === nothing
    end

    # ── _uri_to_path ──────────────────────────────────────────────────

    @testset "_uri_to_path — file:// prefix" begin
        @test Sessions._uri_to_path("file:///tmp/test.jl") == "/tmp/test.jl"
    end

    @testset "_uri_to_path — no prefix" begin
        @test Sessions._uri_to_path("/tmp/test.jl") == "/tmp/test.jl"
    end

    # ── _goto_definition! — same file jump ────────────────────────────

    @testset "_goto_definition! — no LSP shows message" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        app.mode = :normal

        Sessions._goto_definition!(app)
        @test occursin("No definition", app.message) || occursin("definition", lowercase(app.message))
    end

    @testset "_goto_definition! — file editor no LSP shows message" begin
        path = tempname() * ".jl"
        write(path, "x = 1\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)

        Sessions._goto_definition!(app)
        @test occursin("No definition", app.message) || occursin("definition", lowercase(app.message))
        rm(path; force=true)
    end

    # ── Ctrl+G binding exists ─────────────────────────────────────────

    @testset "Ctrl+G triggers go-to-definition in notebook mode" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert

        # Ctrl+G — should not crash, just show "No definition" (no LSP)
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'g'))
        @test occursin("definition", lowercase(app.message))
    end

    @testset "Ctrl+G triggers go-to-definition in file editor mode" begin
        path = tempname() * ".jl"
        write(path, "y = 2\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'g'))
        @test occursin("definition", lowercase(app.message))
        rm(path; force=true)
    end

    # ── Exported symbols ──────────────────────────────────────────────

    @testset "Definition types and functions are exported" begin
        @test isdefined(Sessions, :LspLocation)
        @test isdefined(Sessions, :parse_definition)
        @test isdefined(Sessions, :lsp_definition!)
        @test isdefined(Sessions, :lsp_definition_with_timeout!)
    end

end
