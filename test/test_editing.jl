using Test, Sessions
import Tachikoma

@testset "World-class editing" begin
    @testset "SelectionState" begin
        sel = Sessions.SelectionState()
        @test sel.active == false
        @test sel.anchor_row == 1
        @test sel.anchor_col == 0
    end

    @testset "Word boundaries (REPL-matching)" begin
        @test Sessions._is_non_word_char(' ')
        @test Sessions._is_non_word_char('.')
        @test Sessions._is_non_word_char('+')
        @test Sessions._is_non_word_char('(')
        @test !Sessions._is_non_word_char('a')
        @test !Sessions._is_non_word_char('_')
        @test !Sessions._is_non_word_char('1')
        @test !Sessions._is_non_word_char('!')  # ! is word char in REPL
        @test !Sessions._is_non_word_char('#')  # # is word char in REPL
    end

    @testset "Selection range" begin
        sel = Sessions.SelectionState(true, 1, 3)
        sr, sc, er, ec = Sessions._selection_range(sel, 2, 5)
        @test (sr, sc) == (1, 3)
        @test (er, ec) == (2, 5)

        # Reversed direction
        sel2 = Sessions.SelectionState(true, 3, 7)
        sr, sc, er, ec = Sessions._selection_range(sel2, 1, 2)
        @test (sr, sc) == (1, 2)
        @test (er, ec) == (3, 7)
    end

    @testset "Selected text" begin
        lines = [collect("hello"), collect("world"), collect("foo")]
        sel = Sessions.SelectionState(true, 1, 2)
        text = Sessions._selected_text(lines, sel, 1, 5)
        @test text == "llo"

        # Multi-line
        sel2 = Sessions.SelectionState(true, 1, 3)
        text2 = Sessions._selected_text(lines, sel2, 2, 3)
        @test text2 == "lo\nwor"
    end

    @testset "Clipboard" begin
        Sessions._clipboard_copy!("test text")
        @test Sessions._CLIPBOARD[] == "test text"
    end

    @testset "Word motion" begin
        editor = Tachikoma.CodeEditor(text="hello world foo")
        editor.cursor_row = 1
        editor.cursor_col = 11  # after "d" in "world"
        Sessions._word_left!(editor)
        @test editor.cursor_col == 6  # before "w"

        Sessions._word_left!(editor)
        @test editor.cursor_col == 0  # before "h"

        editor.cursor_col = 0
        Sessions._word_right!(editor)
        @test editor.cursor_col == 5  # after "hello"

        Sessions._word_right!(editor)
        @test editor.cursor_col == 11  # after "world"
    end

    @testset "Word motion with operators" begin
        editor = Tachikoma.CodeEditor(text="x = foo(bar)")
        editor.cursor_row = 1
        editor.cursor_col = 12  # after ")"

        Sessions._word_left!(editor)
        @test editor.cursor_col == 8  # before "bar"

        Sessions._word_left!(editor)
        @test editor.cursor_col == 4  # before "foo"

        Sessions._word_left!(editor)
        @test editor.cursor_col == 0  # before "x"
    end

    @testset "CellWidget has selection" begin
        cell = Sessions.Cell("x = 1")
        cw = Sessions.CellWidget(cell)
        @test cw.selection.active == false
        @test cw.selection.anchor_row == 1
    end

    @testset "Modifier arrow keys (CSI)" begin
        # Shift+Right: ESC[1;2C
        evt = Tachikoma.csi_to_key(UInt8[0x31, 0x3b, 0x32], 'C')
        @test evt.key == :shift_right

        # Ctrl+Left: ESC[1;5D
        evt2 = Tachikoma.csi_to_key(UInt8[0x31, 0x3b, 0x35], 'D')
        @test evt2.key == :ctrl_left

        # Ctrl+Shift+Right: ESC[1;6C
        evt3 = Tachikoma.csi_to_key(UInt8[0x31, 0x3b, 0x36], 'C')
        @test evt3.key == :ctrl_shift_right

        # Plain arrow (no modifier): ESC[A
        evt4 = Tachikoma.csi_to_key(UInt8[], 'A')
        @test evt4.key == :up

        # Shift+Home: ESC[1;2H
        evt5 = Tachikoma.csi_to_key(UInt8[0x31, 0x3b, 0x32], 'H')
        @test evt5.key == :shift_home

        # Shift+Up: ESC[1;2A
        evt6 = Tachikoma.csi_to_key(UInt8[0x31, 0x3b, 0x32], 'A')
        @test evt6.key == :shift_up

        # Ctrl+Right: ESC[1;5C
        evt7 = Tachikoma.csi_to_key(UInt8[0x31, 0x3b, 0x35], 'C')
        @test evt7.key == :ctrl_right

        # Cmd+Left on macOS: ESC[1;9D (mod=9, super → Home)
        evt8 = Tachikoma.csi_to_key(UInt8[0x31, 0x3b, 0x39], 'D')
        @test evt8.key == :home

        # Cmd+Right on macOS: ESC[1;9C (mod=9, super → End)
        evt9 = Tachikoma.csi_to_key(UInt8[0x31, 0x3b, 0x39], 'C')
        @test evt9.key == :end_key

        # Cmd+Shift+Left: ESC[1;10D (mod=10, super+shift → Shift+Home)
        evt10 = Tachikoma.csi_to_key(UInt8[0x31, 0x3b, 0x31, 0x30], 'D')
        @test evt10.key == :shift_home

        # Option+Left on macOS: ESC[1;3D (mod=3, alt → word left)
        evt11 = Tachikoma.csi_to_key(UInt8[0x31, 0x3b, 0x33], 'D')
        @test evt11.key == :alt_left

        # Option+Right on macOS: ESC[1;3C (mod=3, alt → word right)
        evt12 = Tachikoma.csi_to_key(UInt8[0x31, 0x3b, 0x33], 'C')
        @test evt12.key == :alt_right

        # Option+Shift+Left: ESC[1;4D (mod=4, alt+shift → word select left)
        evt13 = Tachikoma.csi_to_key(UInt8[0x31, 0x3b, 0x34], 'D')
        @test evt13.key == :alt_shift_left

        # Option+Shift+Right: ESC[1;4C (mod=4, alt+shift → word select right)
        evt14 = Tachikoma.csi_to_key(UInt8[0x31, 0x3b, 0x34], 'C')
        @test evt14.key == :alt_shift_right
    end

    @testset "Shift+Arrow starts selection" begin
        cell = Sessions.Cell("hello world")
        cw = Sessions.CellWidget(cell)
        cw.editor.focused = true
        cw.editor.cursor_row = 1
        cw.editor.cursor_col = 5  # after "hello"

        # Shift+Right should start selection
        evt = Tachikoma.KeyEvent(:shift_right)
        Tachikoma.handle_key!(cw, evt)

        @test cw.selection.active == true
        @test cw.selection.anchor_row == 1
        @test cw.selection.anchor_col == 5
        @test cw.editor.cursor_col == 6  # moved right
    end

    @testset "Ctrl+Left word jump" begin
        cell = Sessions.Cell("hello world")
        cw = Sessions.CellWidget(cell)
        cw.editor.focused = true
        cw.editor.cursor_row = 1
        cw.editor.cursor_col = 11  # end of line

        evt = Tachikoma.KeyEvent(:ctrl_left)
        Tachikoma.handle_key!(cw, evt)
        @test cw.editor.cursor_col == 6  # before "world"

        Tachikoma.handle_key!(cw, evt)
        @test cw.editor.cursor_col == 0  # before "hello"
    end

    @testset "Alt+Arrow (Option+Arrow) word jump" begin
        cell = Sessions.Cell("hello world foo")
        cw = Sessions.CellWidget(cell)
        cw.editor.focused = true
        cw.editor.cursor_row = 1
        cw.editor.cursor_col = 0

        # Option+Right: jump to end of "hello"
        evt = Tachikoma.KeyEvent(:alt_right)
        Tachikoma.handle_key!(cw, evt)
        @test cw.editor.cursor_col == 5

        # Option+Right: jump to end of "world"
        Tachikoma.handle_key!(cw, evt)
        @test cw.editor.cursor_col == 11

        # Option+Left: jump back to start of "world"
        evt2 = Tachikoma.KeyEvent(:alt_left)
        Tachikoma.handle_key!(cw, evt2)
        @test cw.editor.cursor_col == 6

        # Option+Left: jump to start of "hello"
        Tachikoma.handle_key!(cw, evt2)
        @test cw.editor.cursor_col == 0
    end

    @testset "Alt+Shift+Arrow word selection" begin
        cell = Sessions.Cell("hello world")
        cw = Sessions.CellWidget(cell)
        cw.editor.focused = true
        cw.editor.cursor_row = 1
        cw.editor.cursor_col = 6  # before "world"

        # Option+Shift+Right: select "world"
        evt = Tachikoma.KeyEvent(:alt_shift_right)
        Tachikoma.handle_key!(cw, evt)
        @test cw.selection.active == true
        @test cw.selection.anchor_col == 6
        @test cw.editor.cursor_col == 11
    end

    @testset "Alt+Backspace deletes word backward" begin
        cell = Sessions.Cell("hello world")
        cw = Sessions.CellWidget(cell)
        cw.editor.focused = true
        cw.editor.cursor_row = 1
        cw.editor.cursor_col = 11  # end of line

        evt = Tachikoma.KeyEvent(:alt_backspace)
        Tachikoma.handle_key!(cw, evt)
        @test Tachikoma.text(cw.editor) == "hello "
        @test cw.editor.cursor_col == 6
    end

    @testset "Ctrl+A moves to line start" begin
        cell = Sessions.Cell("hello world")
        cw = Sessions.CellWidget(cell)
        cw.editor.focused = true
        cw.editor.cursor_row = 1
        cw.editor.cursor_col = 7

        evt = Tachikoma.KeyEvent(:ctrl, 'a')
        Tachikoma.handle_key!(cw, evt)
        @test cw.editor.cursor_col == 0
    end

    @testset "Ctrl+E moves to line end" begin
        cell = Sessions.Cell("hello world")
        cw = Sessions.CellWidget(cell)
        cw.editor.focused = true
        cw.editor.cursor_row = 1
        cw.editor.cursor_col = 0

        evt = Tachikoma.KeyEvent(:ctrl, 'e')
        Tachikoma.handle_key!(cw, evt)
        @test cw.editor.cursor_col == 11
    end

    @testset "Delete selection" begin
        cell = Sessions.Cell("hello world")
        cw = Sessions.CellWidget(cell)
        cw.editor.focused = true
        cw.editor.cursor_row = 1
        cw.editor.cursor_col = 8  # after "wo" (select "rld")
        cw.selection.active = true
        cw.selection.anchor_row = 1
        cw.selection.anchor_col = 5  # after "hello"

        Sessions._delete_selection!(cw)
        @test Tachikoma.text(cw.editor) == "hellorld"
        @test cw.selection.active == false
        @test cw.editor.cursor_col == 5
    end

    @testset "Cmd+C copies selection (Kitty protocol)" begin
        # On Kitty-protocol terminals, Cmd+C produces :ctrl + 'c' (not :ctrl_c)
        cell = Sessions.Cell("hello world")
        cw = Sessions.CellWidget(cell)
        cw.editor.focused = true
        cw.editor.cursor_row = 1
        cw.editor.cursor_col = 8
        cw.selection.active = true
        cw.selection.anchor_row = 1
        cw.selection.anchor_col = 6

        evt = Tachikoma.KeyEvent(:ctrl, 'c')
        Tachikoma.handle_key!(cw, evt)
        @test Sessions._CLIPBOARD[] == "wo"
        @test cw.selection.active == true  # copy doesn't clear selection
    end

    @testset "Auto-copy on selection" begin
        cell = Sessions.Cell("hello world")
        cw = Sessions.CellWidget(cell)
        cw.editor.focused = true
        cw.editor.cursor_row = 1
        cw.editor.cursor_col = 0

        Sessions._CLIPBOARD[] = ""  # clear

        # Shift+Right 5 times to select "hello"
        evt = Tachikoma.KeyEvent(:shift_right)
        for _ in 1:5
            Tachikoma.handle_key!(cw, evt)
        end
        @test cw.selection.active == true
        @test Sessions._CLIPBOARD[] == "hello"  # auto-copied
    end

    @testset "Ctrl+C in insert mode copies line when no selection" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "hello world")
        app = Sessions.SessionsApp(nb)

        # Enter insert mode
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter))
        @test app.mode == :insert

        Sessions._CLIPBOARD[] = ""

        # Ctrl+C with no selection copies current line
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'c'))
        @test Sessions._CLIPBOARD[] == "hello world"
        @test app.message == "Copied line"
    end

    @testset "Ctrl+C in normal mode copies cell code" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 42\ny = x + 1")
        app = Sessions.SessionsApp(nb)

        @test app.mode == :normal

        Sessions._CLIPBOARD[] = ""

        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'c'))
        @test Sessions._CLIPBOARD[] == "x = 42\ny = x + 1"
        @test app.message == "Copied cell"
    end

    @testset "Ctrl+C in panel mode quits" begin
        nb = Sessions.Notebook()
        Sessions.add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        # Enter panel mode
        Tachikoma.update!(app, Tachikoma.KeyEvent(:escape))
        @test app.mode == :panel

        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'c'))
        @test app.quit == true
    end

    @testset "Click to editor position" begin
        editor = Tachikoma.CodeEditor(text="hello\nworld")
        editor.show_line_numbers = true
        area = Tachikoma.Rect(5, 3, 20, 5)
        # gw = ndigits(2) + 1 = 2 (for "1│" and "2│")
        # code_x = 5 + 2 = 7
        # Click at (9, 3) → col = 9 - 7 + 0 = 2, row = (3-3) + 1 + 0 = 1
        row, col = Sessions.click_to_editor_pos(editor, area, 9, 3)
        @test row == 1
        @test col == 2

        # Click at (7, 4) → col = 7 - 7 + 0 = 0, row = (4-3) + 1 + 0 = 2
        row2, col2 = Sessions.click_to_editor_pos(editor, area, 7, 4)
        @test row2 == 2
        @test col2 == 0
    end
end

println("All editing tests passed!")
