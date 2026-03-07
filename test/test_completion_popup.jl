@testset "Completion Popup" begin

    import Tachikoma

    # Helper: render app and return TestBackend
    function render_app(app; width=120, height=40)
        tb = Tachikoma.TestBackend(width, height)
        frame = Tachikoma.Frame(tb.buf, Tachikoma.Rect(1, 1, width, height), [], [])
        Tachikoma.view(app, frame)
        tb
    end

    # ── CompletionPopup struct ────────────────────────────────────────

    @testset "CompletionPopup construction" begin
        items = [
            Sessions.LspCompletionItem("println", :function, "println(xs...)", ""),
            Sessions.LspCompletionItem("print", :function, "print(xs...)", ""),
        ]
        popup = Sessions.CompletionPopup(items, 10, 5, 1)
        @test popup.items === items
        @test popup.x == 10
        @test popup.y == 5
        @test popup.selected_idx == 1
        @test length(popup.items) == 2
    end

    @testset "CompletionPopup — empty items" begin
        popup = Sessions.CompletionPopup(Sessions.LspCompletionItem[], 1, 1, 0)
        @test isempty(popup.items)
        @test popup.selected_idx == 0
    end

    # ── _completion_kind_icon ──────────────────────────────────────────

    @testset "_completion_kind_icon — known kinds" begin
        @test Sessions._completion_kind_icon(:function) == "ƒ"
        @test Sessions._completion_kind_icon(:method) == "ƒ"
        @test Sessions._completion_kind_icon(:variable) == "v"
        @test Sessions._completion_kind_icon(:module) == "M"
        @test Sessions._completion_kind_icon(:keyword) == "k"
        @test Sessions._completion_kind_icon(:constant) == "c"
        @test Sessions._completion_kind_icon(:field) == "□"
        @test Sessions._completion_kind_icon(:class) == "T"
        @test Sessions._completion_kind_icon(:constructor) == "T"
    end

    @testset "_completion_kind_icon — unknown kind" begin
        @test Sessions._completion_kind_icon(:unknown_xyz) == "·"
    end

    # ── _open_completion! / _close_completion! ─────────────────────────

    @testset "_open_completion! — sets popup and mode" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "prin")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert

        items = [Sessions.LspCompletionItem("println", :function, "", "")]
        Sessions._open_completion!(app, items)
        @test app.completion_popup !== nothing
        @test app.mode == :completion
        @test app.completion_popup.selected_idx == 1
        @test length(app.completion_popup.items) == 1
    end

    @testset "_open_completion! — empty items does not open" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert

        Sessions._open_completion!(app, Sessions.LspCompletionItem[])
        @test app.completion_popup === nothing
        @test app.mode == :insert
    end

    @testset "_close_completion! — clears popup and restores mode" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x")
        app = Sessions.SessionsApp(nb)
        app.mode = :completion
        app.completion_popup = Sessions.CompletionPopup(
            [Sessions.LspCompletionItem("x", :variable, "", "")],
            1, 1, 1
        )

        Sessions._close_completion!(app)
        @test app.completion_popup === nothing
        @test app.mode == :insert
    end

    # ── Completion mode key handling ──────────────────────────────────

    @testset "Escape dismisses completion popup" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x")
        app = Sessions.SessionsApp(nb)
        items = [Sessions.LspCompletionItem("x", :variable, "", "")]
        app.completion_popup = Sessions.CompletionPopup(items, 1, 1, 1)
        app.mode = :completion

        Tachikoma.update!(app, Tachikoma.KeyEvent(:escape))
        @test app.completion_popup === nothing
        @test app.mode == :insert
    end

    @testset "Down arrow moves selection down" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x")
        app = Sessions.SessionsApp(nb)
        items = [
            Sessions.LspCompletionItem("aaa", :variable, "", ""),
            Sessions.LspCompletionItem("bbb", :variable, "", ""),
            Sessions.LspCompletionItem("ccc", :variable, "", ""),
        ]
        app.completion_popup = Sessions.CompletionPopup(items, 1, 1, 1)
        app.mode = :completion

        Tachikoma.update!(app, Tachikoma.KeyEvent(:down))
        @test app.completion_popup.selected_idx == 2
        Tachikoma.update!(app, Tachikoma.KeyEvent(:down))
        @test app.completion_popup.selected_idx == 3
        # Wraps around
        Tachikoma.update!(app, Tachikoma.KeyEvent(:down))
        @test app.completion_popup.selected_idx == 1
    end

    @testset "Up arrow moves selection up" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x")
        app = Sessions.SessionsApp(nb)
        items = [
            Sessions.LspCompletionItem("aaa", :variable, "", ""),
            Sessions.LspCompletionItem("bbb", :variable, "", ""),
        ]
        app.completion_popup = Sessions.CompletionPopup(items, 1, 1, 1)
        app.mode = :completion

        Tachikoma.update!(app, Tachikoma.KeyEvent(:up))
        @test app.completion_popup.selected_idx == 2  # wraps to end
    end

    @testset "Enter accepts completion — inserts text in notebook cell" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "prin")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert
        # Cursor at end of "prin" (col 4)
        cw.editor.cursor_col = 4

        items = [
            Sessions.LspCompletionItem("println", :function, "", ""),
            Sessions.LspCompletionItem("print", :function, "", ""),
        ]
        app.completion_popup = Sessions.CompletionPopup(items, 1, 1, 1)
        app.mode = :completion

        # Accept first item "println"
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter))
        @test app.completion_popup === nothing
        @test app.mode == :insert
        # "prin" should become "println" — the completion replaces the prefix
        code = Tachikoma.text(cw.editor)
        @test occursin("println", code)
    end

    @testset "Enter accepts completion — inserts text in file editor" begin
        path = tempname() * ".jl"
        write(path, "prin")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        app.mode = :insert
        fev.editor.mode = :insert
        fev.editor.cursor_col = 4

        items = [
            Sessions.LspCompletionItem("println", :function, "", ""),
        ]
        app.completion_popup = Sessions.CompletionPopup(items, 1, 1, 1)
        app.mode = :completion

        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter))
        @test app.completion_popup === nothing
        code = Tachikoma.text(fev.editor)
        @test occursin("println", code)
        rm(path; force=true)
    end

    # ── Tab save collapses :completion mode ────────────────────────────

    @testset "Tab save collapses :completion to :normal" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        app.mode = :completion
        app.completion_popup = Sessions.CompletionPopup(
            [Sessions.LspCompletionItem("x", :variable, "", "")], 1, 1, 1)

        Sessions._save_to_tab!(app)
        tab = app.tabs[app.active_tab_idx]
        @test tab.mode == :normal  # completion is transient, collapsed to normal
    end

    # ── Render smoke tests ────────────────────────────────────────────

    @testset "Completion popup renders in notebook without crash" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "prin")
        app = Sessions.SessionsApp(nb)
        app.mode = :completion
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert
        cw.editor.cursor_col = 4

        items = [
            Sessions.LspCompletionItem("println", :function, "println(xs...)", "Print with newline"),
            Sessions.LspCompletionItem("print", :function, "print(xs...)", ""),
            Sessions.LspCompletionItem("printstyled", :function, "printstyled(xs...)", ""),
        ]
        app.completion_popup = Sessions.CompletionPopup(items, 15, 8, 1)

        tb = render_app(app)
        # Popup should show item labels
        @test Tachikoma.find_text(tb, "println") !== nothing
        @test Tachikoma.find_text(tb, "print") !== nothing
    end

    @testset "Completion popup renders in file editor without crash" begin
        path = tempname() * ".jl"
        write(path, "prin\n")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        app.mode = :completion

        items = [
            Sessions.LspCompletionItem("println", :function, "", ""),
        ]
        app.completion_popup = Sessions.CompletionPopup(items, 15, 8, 1)

        tb = render_app(app)
        @test Tachikoma.find_text(tb, "println") !== nothing
        rm(path; force=true)
    end

    @testset "Completion popup — selected item highlighted differently" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x")
        app = Sessions.SessionsApp(nb)
        app.mode = :completion

        items = [
            Sessions.LspCompletionItem("alpha", :variable, "", ""),
            Sessions.LspCompletionItem("beta", :variable, "", ""),
        ]
        app.completion_popup = Sessions.CompletionPopup(items, 15, 8, 2)

        # Should render without crash — visual verification of highlight is manual
        tb = render_app(app)
        @test Tachikoma.find_text(tb, "alpha") !== nothing
        @test Tachikoma.find_text(tb, "beta") !== nothing
    end

    # ── _accept_completion! helper ─────────────────────────────────────

    @testset "_accept_completion! — replaces prefix in editor" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "map")
        app = Sessions.SessionsApp(nb)
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert
        cw.editor.cursor_col = 3  # at end of "map"

        item = Sessions.LspCompletionItem("mapfoldl", :function, "", "")
        Sessions._accept_completion!(app, item)
        code = Tachikoma.text(cw.editor)
        @test occursin("mapfoldl", code)
    end

    @testset "_accept_completion! — mid-line replacement" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = pri")
        app = Sessions.SessionsApp(nb)
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert
        cw.editor.cursor_col = 7  # at end of "pri"

        item = Sessions.LspCompletionItem("println", :function, "", "")
        Sessions._accept_completion!(app, item)
        code = Tachikoma.text(cw.editor)
        @test occursin("println", code)
        @test occursin("x = ", code)
    end

    @testset "_accept_completion! — file editor mode" begin
        path = tempname() * ".jl"
        write(path, "x = len")
        fev = Sessions.FileEditorView(path)
        app = Sessions.SessionsApp(fev)
        fev.editor.mode = :insert
        fev.editor.cursor_col = 7  # at end of "len"

        item = Sessions.LspCompletionItem("length", :function, "", "")
        Sessions._accept_completion!(app, item)
        code = Tachikoma.text(fev.editor)
        @test occursin("length", code)
        @test occursin("x = ", code)
        rm(path; force=true)
    end

    # ── _completion_prefix ─────────────────────────────────────────────

    @testset "_completion_prefix — extracts word before cursor" begin
        lines = [collect("println(x)")]
        @test Sessions._completion_prefix(lines, 1, 7) == "println"
    end

    @testset "_completion_prefix — partial word" begin
        lines = [collect("x = pri")]
        @test Sessions._completion_prefix(lines, 1, 7) == "pri"
    end

    @testset "_completion_prefix — cursor at start" begin
        lines = [collect("hello")]
        @test Sessions._completion_prefix(lines, 1, 0) == ""
    end

    @testset "_completion_prefix — only identifier chars" begin
        lines = [collect("foo.bar")]
        @test Sessions._completion_prefix(lines, 1, 7) == "bar"
    end

    @testset "_completion_prefix — empty line" begin
        lines = [Char[]]
        @test Sessions._completion_prefix(lines, 1, 0) == ""
    end

    # ── _popup_max_items ──────────────────────────────────────────────

    @testset "Popup clamps to max visible items" begin
        items = [Sessions.LspCompletionItem("item$i", :text, "", "") for i in 1:20]
        popup = Sessions.CompletionPopup(items, 1, 1, 1)
        # _popup_visible_count returns min(length(items), MAX_VISIBLE)
        @test Sessions._popup_visible_count(popup) <= 10
        @test Sessions._popup_visible_count(popup) == min(length(items), Sessions.COMPLETION_MAX_VISIBLE)
    end

    # ── Any other key dismisses popup ──────────────────────────────────

    @testset "Non-navigation key dismisses popup and forwards to editor" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x")
        app = Sessions.SessionsApp(nb)
        app.mode = :completion
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert

        items = [Sessions.LspCompletionItem("x", :variable, "", "")]
        app.completion_popup = Sessions.CompletionPopup(items, 1, 1, 1)

        # Typing a regular character should dismiss
        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, 'z'))
        @test app.completion_popup === nothing
    end

end
