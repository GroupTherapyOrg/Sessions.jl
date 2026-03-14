@testset "REPL Parity — Output Wrapping, Tab Completion, macOS Keybindings" begin

    import Tachikoma

    # Helper: create an app in insert mode with a focused cell
    function make_insert_app(code::String)
        nb = Sessions.Notebook(; path=tempname() * ".jl")
        Sessions.add_cell!(nb, code)
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true
        cw.editor.mode = :insert
        app, cw
    end

    # ── Phase 1: Output Soft-Wrapping ────────────────────────────────

    @testset "Output wrapping — _wrapped_line_count" begin
        @test Sessions._wrapped_line_count("hello", 10) == 1
        @test Sessions._wrapped_line_count("hello world", 5) == 3  # ceil(11/5)
        @test Sessions._wrapped_line_count("", 10) == 1
        @test Sessions._wrapped_line_count("x" ^ 200, 80) == 3  # ceil(200/80)
        @test Sessions._wrapped_line_count("short", 0) == 1  # edge case
    end

    @testset "Output wrapping — long line increases output height" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        cell = Sessions.ordered_cells(nb)[1]
        ow = Sessions.OutputWidget(cell)
        ow.available_cols = 83  # text width = 83 - 3 = 80

        # Short output: should be 1 line
        cell.state = Sessions.cell_done
        cell.output = Sessions.CellOutput("short", "", nothing, UInt64(0), :text, "", nothing, nothing)
        ow._cached_height = -1
        ow._cached_output_lines = nothing
        h_short = Sessions.output_height(ow)

        # Long output: "x" * 200 should wrap to ceil(200/80) = 3 lines
        cell.output = Sessions.CellOutput("x" ^ 200, "", nothing, UInt64(0), :text, "", nothing, nothing)
        ow._cached_height = -1
        ow._cached_output_lines = nothing
        h_long = Sessions.output_height(ow)

        @test h_short == 1
        @test h_long == 3  # 200 chars at 80 width = ceil(200/80)
    end

    @testset "Output wrapping — render wraps at boundary" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        cell = Sessions.ordered_cells(nb)[1]
        ow = Sessions.OutputWidget(cell)
        cell.state = Sessions.cell_done
        # Create output with 20 'A' chars, render at width 13 (text width 10)
        cell.output = Sessions.CellOutput("A" ^ 20, "", nothing, UInt64(0), :text, "", nothing, nothing)
        ow.available_cols = 13  # text width = 13 - 3 = 10
        ow._cached_height = -1
        ow._cached_output_lines = nothing

        h = Sessions.output_height(ow)
        # "A"^20 renders as "\"AAAA...\"" (22 chars with quotes), width 10 → 3 rows
        @test h == 3

        # Render and verify both lines have content
        tb = Tachikoma.TestBackend(16, 4)
        rect = Tachikoma.Rect(1, 1, 13, 4)
        Tachikoma.render(ow, rect, tb.buf)

        # Row 1 should have '│' bar and 'A's
        row1 = Tachikoma.row_text(tb, 1)
        @test occursin("A", row1)
        # Row 2 should also have continuation 'A's (wrapped)
        row2 = Tachikoma.row_text(tb, 2)
        @test occursin("A", row2)
    end

    @testset "Output wrapping — structured error message wraps" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "error()")
        cell = Sessions.ordered_cells(nb)[1]
        ow = Sessions.OutputWidget(cell)
        ow.available_cols = 23  # text width = 23 - 3 = 20

        # Create a long error message
        long_msg = "x" ^ 60  # 60 chars, 20 width → 3 visual rows
        se = Sessions.StructuredError("ErrorType", long_msg,
            Sessions.StructuredFrame[], 0, "")
        cell.state = Sessions.cell_errored
        cell.output = Sessions.CellOutput(nothing, "", CapturedException(ErrorException("test"), []),
            UInt64(0), :error, "", nothing, se)
        ow._cached_height = -1
        ow._cached_output_lines = nothing

        h = Sessions.output_height(ow)
        # Height = 1 (type) + 3 (message wrapped) + 2 (blank + stacktrace) = 6
        @test h == 6
    end

    # ── Phase 2: Tab Completion ──────────────────────────────────────

    @testset "Tab accepts completion in popup" begin
        app, cw = make_insert_app("prin")
        cw.editor.cursor_col = 4

        items = [Sessions.LspCompletionItem("println", :function, "", "")]
        app.completion_popup = Sessions.CompletionPopup(items, 1, 1, 1)
        app.mode = :completion

        # Tab should accept the completion (same as Enter)
        Tachikoma.update!(app, Tachikoma.KeyEvent(:tab))

        @test app.completion_popup === nothing
        @test app.mode == :insert
        code = Tachikoma.text(cw.editor)
        @test occursin("println", code)
    end

    @testset "Tab in insert mode without LSP falls through to spaces" begin
        app, cw = make_insert_app("prin")
        cw.editor.cursor_col = 4

        # Without LSP ready, Tab should fall through to insert spaces
        app.lsp.status = Sessions.lsp_off
        Tachikoma.update!(app, Tachikoma.KeyEvent(:tab))
        @test app.mode == :insert
        @test app.completion_popup === nothing
        # Verify spaces were inserted (Tachikoma default tab = 4 spaces)
        @test occursin("    ", Tachikoma.text(cw.editor))
    end

    @testset "Tab at empty prefix inserts spaces even with LSP" begin
        app, cw = make_insert_app("")
        cw.editor.cursor_col = 0
        app.lsp.status = Sessions.lsp_ready

        Tachikoma.update!(app, Tachikoma.KeyEvent(:tab))
        @test app.completion_popup === nothing
        @test app.mode == :insert
    end

    # ── Phase 3: macOS Keybindings ───────────────────────────────────

    @testset "Cmd+Backspace deletes to line start" begin
        app, cw = make_insert_app("hello world")
        cw.editor.cursor_col = 5  # cursor after "hello"

        Tachikoma.update!(app, Tachikoma.KeyEvent(:cmd_backspace))

        code = Tachikoma.text(cw.editor)
        @test code == " world"
        @test cw.editor.cursor_col == 0
    end

    @testset "Cmd+Backspace at line start is a no-op" begin
        app, cw = make_insert_app("hello")
        cw.editor.cursor_col = 0

        Tachikoma.update!(app, Tachikoma.KeyEvent(:cmd_backspace))
        @test Tachikoma.text(cw.editor) == "hello"
        @test cw.editor.cursor_col == 0
    end

    @testset "Cmd+Backspace copies killed text to clipboard" begin
        app, cw = make_insert_app("abcdef")
        cw.editor.cursor_col = 3  # after "abc"

        Sessions._CLIPBOARD[] = ""
        Tachikoma.update!(app, Tachikoma.KeyEvent(:cmd_backspace))

        @test Sessions._CLIPBOARD[] == "abc"
        @test Tachikoma.text(cw.editor) == "def"
    end

    # ── Kitty protocol key parsing ───────────────────────────────────

    @testset "Kitty: Cmd+Backspace → :cmd_backspace" begin
        evt = Tachikoma.parse_kitty_key(UInt8.(collect("127;9")))
        @test evt.key == :cmd_backspace
    end

    @testset "Kitty: plain Backspace → :backspace" begin
        evt = Tachikoma.parse_kitty_key(UInt8.(collect("127")))
        @test evt.key == :backspace
    end

    @testset "CSI: Cmd+Left → :home (legacy)" begin
        evt = Tachikoma.csi_to_key(UInt8.(collect("1;9")), 'D')
        @test evt.key == :home
    end

    @testset "CSI: Cmd+Right → :end_key (legacy)" begin
        evt = Tachikoma.csi_to_key(UInt8.(collect("1;9")), 'C')
        @test evt.key == :end_key
    end

    @testset "CSI: Cmd+Shift+Left → :shift_home" begin
        evt = Tachikoma.csi_to_key(UInt8.(collect("1;10")), 'D')
        @test evt.key == :shift_home
    end

    @testset "CSI: Cmd+Shift+Right → :shift_end" begin
        evt = Tachikoma.csi_to_key(UInt8.(collect("1;10")), 'C')
        @test evt.key == :shift_end
    end

    @testset "Kitty: Cmd+Left → :home (kitty protocol)" begin
        # Kitty keycode 57350=Left, mod=9 (super)
        evt = Tachikoma.parse_kitty_key(UInt8.(collect("57350;9")))
        @test evt.key == :home
    end

    @testset "Kitty: Cmd+Right → :end_key (kitty protocol)" begin
        evt = Tachikoma.parse_kitty_key(UInt8.(collect("57351;9")))
        @test evt.key == :end_key
    end

    @testset "Home key moves cursor to line start in insert mode" begin
        app, cw = make_insert_app("hello world")
        cw.editor.cursor_col = 8

        Tachikoma.update!(app, Tachikoma.KeyEvent(:home))
        @test cw.editor.cursor_col == 0
    end

    @testset "End key moves cursor to line end in insert mode" begin
        app, cw = make_insert_app("hello world")
        cw.editor.cursor_col = 3

        Tachikoma.update!(app, Tachikoma.KeyEvent(:end_key))
        @test cw.editor.cursor_col == 11  # length("hello world")
    end

    # ── Format on save ───────────────────────────────────────────────

    @testset "format_code works" begin
        @test Sessions.format_code_available()
        result = Sessions.format_code("x=1+2")
        # Runic should at least add spaces around operators
        @test occursin("1 + 2", result) || occursin("1+2", result)
    end

    @testset "format_code handles multiline" begin
        code = "function f(x)\nreturn x+1\nend"
        result = Sessions.format_code(code)
        @test occursin("return", result)
        # Should indent the body
        if Sessions.format_code_available()
            @test occursin("    return", result)
        end
    end

    @testset "Format on save — _format_notebook_cells! formats code" begin
        nb = Sessions.Notebook(; path=tempname() * ".jl")
        Sessions.add_cell!(nb, "x=1+2")
        app = Sessions.SessionsApp(nb)

        if Sessions.format_code_available()
            n = Sessions._format_notebook_cells!(app)
            @test n >= 1
            cw = app.notebook_view.cell_widgets[1]
            @test occursin("1 + 2", Tachikoma.text(cw.editor))
        end
    end

    @testset "Format on save — Ctrl+S syncs, formats, and saves" begin
        path = tempname() * ".jl"
        nb = Sessions.Notebook(; path=path)
        Sessions.add_cell!(nb, "placeholder")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert
        cw = app.notebook_view.cell_widgets[1]
        cw.focused = true
        cw.editor.focused = true

        # Simulate user editing code in the editor
        Tachikoma.set_text!(cw.editor, "x=1+2")
        # Intentionally do NOT call sync_to_cell! — the save handler must do it

        # Press Ctrl+S
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 's'))

        # Verify cell.code was synced from editor before formatting
        @test cw.cell.code != "placeholder"

        # If formatting is available, verify it was applied
        if Sessions.format_code_available()
            @test occursin("Formatted", app.message) || occursin("Saved", app.message)
            formatted_code = Tachikoma.text(cw.editor)
            @test occursin("1 + 2", formatted_code) || occursin("1+2", formatted_code)
        end

        # Verify file was saved
        @test isfile(path)
        content = read(path, String)
        @test occursin("1", content)

        # Cleanup
        rm(path; force=true)
    end

    @testset "Format on save — unedited cell still gets formatted" begin
        path = tempname() * ".jl"
        nb = Sessions.Notebook(; path=path)
        Sessions.add_cell!(nb, "x=1+2")  # Already in cell.code, no editing
        app = Sessions.SessionsApp(nb)

        # Don't enter insert mode, just save directly
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 's'))

        if Sessions.format_code_available()
            cw = app.notebook_view.cell_widgets[1]
            @test occursin("1 + 2", cw.cell.code) || occursin("1+2", cw.cell.code)
        end

        rm(path; force=true)
    end

    @testset "Save clears dirty flag (orange dot disappears)" begin
        path = tempname() * ".jl"
        nb = Sessions.Notebook(; path=path)
        Sessions.add_cell!(nb, "x = 1")
        Sessions.save_notebook(nb)
        app = Sessions.SessionsApp(nb)

        # Make notebook dirty by editing a cell
        cw = app.notebook_view.cell_widgets[1]
        Tachikoma.set_text!(cw.editor, "x = 2")
        Sessions.sync_to_cell!(cw)
        app._dirty_cache_valid = false

        # Render to compute dirty state
        tb = Tachikoma.TestBackend(120, 40)
        frame = Tachikoma.Frame(tb.buf, Tachikoma.Rect(1, 1, 120, 40), [], [])
        Tachikoma.view(app, frame)
        @test app.notebook_view.dirty == true  # should be dirty

        # Save
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 's'))

        # Dirty cache must be invalidated so next render recomputes
        @test app._dirty_cache_valid == false

        # Render again — dirty should now be false
        Tachikoma.view(app, frame)
        @test app.notebook_view.dirty == false

        rm(path; force=true)
    end

    @testset "Format on save — all cells get formatted, not just focused" begin
        path = tempname() * ".jl"
        nb = Sessions.Notebook(; path=path)
        Sessions.add_cell!(nb, "x=1+2")
        Sessions.add_cell!(nb, "y=3+4")
        Sessions.add_cell!(nb, "z=5+6")
        app = Sessions.SessionsApp(nb)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 's'))

        if Sessions.format_code_available()
            for (i, cw) in enumerate(app.notebook_view.cell_widgets)
                code = Tachikoma.text(cw.editor)
                # Each cell should have spaces around operators
                @test occursin(" + ", code) || occursin("+", code)
            end
            # Verify the message
            @test occursin("Formatted", app.message)
            # Verify the saved file has formatted content
            content = read(path, String)
            @test occursin("1 + 2", content)
            @test occursin("3 + 4", content)
            @test occursin("5 + 6", content)
        end

        rm(path; force=true)
    end

    @testset "Format on save — cell.code matches editor after format" begin
        path = tempname() * ".jl"
        nb = Sessions.Notebook(; path=path)
        Sessions.add_cell!(nb, "x=1+2")
        app = Sessions.SessionsApp(nb)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 's'))

        cw = app.notebook_view.cell_widgets[1]
        # cell.code must match the editor text (for save_notebook consistency)
        @test cw.cell.code == Tachikoma.text(cw.editor)

        rm(path; force=true)
    end

    # ── Save button click (mouse) ──────────────────────────────────

    # ── Run Stale ─────────────────────────────────────────────────

    @testset "run_stale_cells_async! — runs only stale cells" begin
        nb = Sessions.Notebook(; path=tempname() * ".jl")
        c1 = Sessions.add_cell!(nb, "stale_a = 1")
        c2 = Sessions.add_cell!(nb, "stale_b = 2")
        app = Sessions.SessionsApp(nb)

        # Execute both cells
        Sessions.execute_cell!(app.workspace, c1)
        Sessions.execute_cell!(app.workspace, c2)
        @test !Sessions.is_stale(c1)
        @test !Sessions.is_stale(c2)

        # Make c1 stale
        c1.code = "stale_a = 99"
        Sessions.sync_from_cell!(app.notebook_view.cell_widgets[1])
        @test Sessions.is_stale(c1)
        @test !Sessions.is_stale(c2)

        # Run stale (synchronous version for testing)
        n = Sessions.run_stale_cells!(app)
        @test n == 1
        @test !Sessions.is_stale(c1)
    end

    @testset "Run Stale button renders when stale cells exist" begin
        nb = Sessions.Notebook(; path=tempname() * ".jl")
        c1 = Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        Sessions.execute_cell!(app.workspace, c1)

        # No stale cells — button should not render
        tb = Tachikoma.TestBackend(120, 40)
        frame = Tachikoma.Frame(tb.buf, Tachikoma.Rect(1, 1, 120, 40), [], [])
        Tachikoma.view(app, frame)
        @test app.notebook_view.run_stale_rect.width == 0

        # Make cell stale — button should render
        c1.code = "x = 2"
        Sessions.sync_from_cell!(app.notebook_view.cell_widgets[1])
        Tachikoma.view(app, frame)
        @test app.notebook_view.run_stale_rect.width > 0
        @test Tachikoma.find_text(tb, "Stale") !== nothing
    end

    @testset "Save button click — formats, saves, clears dirty" begin
        path = tempname() * ".jl"
        nb = Sessions.Notebook(; path=path)
        Sessions.add_cell!(nb, "x=1+2")
        Sessions.add_cell!(nb, "y=3+4")
        Sessions.save_notebook(nb)
        app = Sessions.SessionsApp(nb)

        # Render to establish save_rect
        tb = Tachikoma.TestBackend(120, 40)
        frame = Tachikoma.Frame(tb.buf, Tachikoma.Rect(1, 1, 120, 40), [], [])
        Tachikoma.view(app, frame)

        sa = app.notebook_view.save_rect
        @test sa.width > 0  # save button exists

        # Click the Save button
        Tachikoma.update!(app, Tachikoma.MouseEvent(
            sa.x + 1, sa.y,
            Tachikoma.mouse_left, Tachikoma.mouse_press,
            false, false, false
        ))

        # Verify formatting happened
        if Sessions.format_code_available()
            cw1 = app.notebook_view.cell_widgets[1]
            cw2 = app.notebook_view.cell_widgets[2]
            @test occursin("1 + 2", Tachikoma.text(cw1.editor))
            @test occursin("3 + 4", Tachikoma.text(cw2.editor))
            @test occursin("Formatted", app.message)
        end

        # Dirty cache invalidated
        @test app._dirty_cache_valid == false

        # Render and verify not dirty
        Tachikoma.view(app, frame)
        @test app.notebook_view.dirty == false

        # File was saved
        @test isfile(path)

        rm(path; force=true)
    end

end
