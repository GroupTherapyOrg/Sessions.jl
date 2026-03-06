using Test
using Sessions
using Tachikoma
using Markdown: @md_str

@testset "E2E — Full notebook workflow" begin

    # --- Helper: render app to TestBackend and return it ---
    function render_app(app; width=120, height=40)
        tb = TestBackend(width, height)
        frame = Tachikoma.Frame(tb.buf, Rect(1, 1, width, height), [], [])
        Tachikoma.view(app, frame)
        tb
    end

    function find_in_render(app, text; width=120, height=40)
        tb = render_app(app; width, height)
        Tachikoma.find_text(tb, text) !== nothing
    end

    @testset "E2E: Initial state — cells visible" begin
        nb = Notebook(; path="e2e_test.jl")
        add_cell!(nb, "x = 1")
        add_cell!(nb, "y = x + 1")
        add_cell!(nb, "z = x * y")
        app = Sessions.SessionsApp(nb)

        tb = render_app(app)
        @test Tachikoma.find_text(tb, "e2e_test.jl") !== nothing
        @test Tachikoma.find_text(tb, "x = 1") !== nothing
        @test Tachikoma.find_text(tb, "y = x + 1") !== nothing
        @test Tachikoma.find_text(tb, "z = x * y") !== nothing
        @test Tachikoma.find_text(tb, "0/3 cells") !== nothing
    end

    @testset "E2E: Status bar shows keybindings" begin
        nb = Notebook(; path="e2e.jl")
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test find_in_render(app, "Ctrl+Q")
        @test find_in_render(app, "Run")
    end

    @testset "E2E: Navigate between cells" begin
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

        # Can't go past last
        Tachikoma.update!(app, Tachikoma.KeyEvent(:tab))
        @test app.notebook_view.focused_idx == 3
    end

    @testset "E2E: Enter/exit insert mode" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test app.mode == :normal
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter))
        @test app.mode == :insert
        Tachikoma.update!(app, Tachikoma.KeyEvent(:escape))
        @test app.mode == :normal
    end

    @testset "E2E: Execute cell and verify output" begin
        nb = Notebook()
        c1 = add_cell!(nb, "e2e_val = 42")
        app = Sessions.SessionsApp(nb)

        Sessions.run_focused_cell!(app)

        @test c1.state == cell_done
        @test c1.output.result == 42

        # Output should be visible in render
        @test find_in_render(app, "42")
    end

    @testset "E2E: Execute all cells reactively" begin
        nb = Notebook()
        c1 = add_cell!(nb, "e2e_x = 10")
        c2 = add_cell!(nb, "e2e_y = e2e_x + 5")
        c3 = add_cell!(nb, "e2e_z = e2e_x * e2e_y")
        app = Sessions.SessionsApp(nb)

        Sessions.run_all_cells!(app)

        @test c1.output.result == 10
        @test c2.output.result == 15
        @test c3.output.result == 150

        # Status bar should show all done (clear message first)
        app.message = ""
        @test find_in_render(app, "3/3 cells")
    end

    @testset "E2E: Stale detection after edit" begin
        nb = Notebook()
        c1 = add_cell!(nb, "e2e_stale = 1")
        c2 = add_cell!(nb, "e2e_dep = e2e_stale + 1")
        app = Sessions.SessionsApp(nb)

        Sessions.run_all_cells!(app)
        @test c1.state == cell_done
        @test c2.state == cell_done
        @test !is_stale(c1)

        # Modify cell
        c1.code = "e2e_stale = 999"
        Sessions.sync_from_cell!(app.notebook_view.cell_widgets[1])
        @test is_stale(c1)
    end

    @testset "E2E: Run stale cells" begin
        nb = Notebook()
        c1 = add_cell!(nb, "e2e_rs = 1")
        c2 = add_cell!(nb, "e2e_rs_dep = e2e_rs + 1")
        app = Sessions.SessionsApp(nb)

        Sessions.run_all_cells!(app)
        @test c2.output.result == 2

        c1.code = "e2e_rs = 100"
        Sessions.sync_from_cell!(app.notebook_view.cell_widgets[1])

        n = Sessions.run_stale_cells!(app)
        @test n == 1
        @test c1.output.result == 100
        # Dependent cell re-executed
        @test c2.output.result == 101
    end

    @testset "E2E: Ctrl+S save and run stale" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "e2e_save = 42")
        app = Sessions.SessionsApp(nb)

        execute_cell!(app.workspace, c1)
        c1.code = "e2e_save = 99"
        Sessions.sync_from_cell!(app.notebook_view.cell_widgets[1])

        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 's'))
        @test !is_stale(c1)
        @test c1.output.result == 99
        @test contains(app.message, "stale")

        rm(path; force=true)
    end

    @testset "E2E: Add new cell with Ctrl+N" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test length(nb) == 1
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'n'))
        @test length(nb) == 2
        @test app.notebook_view.focused_idx == 2
    end

    @testset "E2E: Move cell up with Alt+Up" begin
        nb = Notebook()
        c1 = add_cell!(nb, "a = 1")
        c2 = add_cell!(nb, "b = 2")
        c3 = add_cell!(nb, "c = 3")
        app = Sessions.SessionsApp(nb)

        # Focus second cell, then move it up
        Tachikoma.update!(app, Tachikoma.KeyEvent(:tab))
        @test app.notebook_view.focused_idx == 2

        Tachikoma.update!(app, Tachikoma.KeyEvent(:alt_up))
        @test app.notebook_view.focused_idx == 1
        @test ordered_cells(nb) == [c2, c1, c3]
    end

    @testset "E2E: Move cell down with Alt+Down" begin
        nb = Notebook()
        c1 = add_cell!(nb, "a = 1")
        c2 = add_cell!(nb, "b = 2")
        c3 = add_cell!(nb, "c = 3")
        app = Sessions.SessionsApp(nb)

        # Focus first cell, move it down
        @test app.notebook_view.focused_idx == 1
        Tachikoma.update!(app, Tachikoma.KeyEvent(:alt_down))
        @test app.notebook_view.focused_idx == 2
        @test ordered_cells(nb) == [c2, c1, c3]
    end

    @testset "E2E: Move cell — boundary no-ops" begin
        nb = Notebook()
        c1 = add_cell!(nb, "a = 1")
        c2 = add_cell!(nb, "b = 2")
        app = Sessions.SessionsApp(nb)

        # First cell can't move up
        Tachikoma.update!(app, Tachikoma.KeyEvent(:alt_up))
        @test app.notebook_view.focused_idx == 1
        @test ordered_cells(nb) == [c1, c2]

        # Move to last, then can't move down
        Tachikoma.update!(app, Tachikoma.KeyEvent(:tab))
        @test app.notebook_view.focused_idx == 2
        Tachikoma.update!(app, Tachikoma.KeyEvent(:alt_down))
        @test app.notebook_view.focused_idx == 2
        @test ordered_cells(nb) == [c1, c2]
    end

    @testset "E2E: Move cell — focus follows moved cell" begin
        nb = Notebook()
        c1 = add_cell!(nb, "first")
        c2 = add_cell!(nb, "second")
        c3 = add_cell!(nb, "third")
        app = Sessions.SessionsApp(nb)

        # Focus third cell
        Tachikoma.update!(app, Tachikoma.KeyEvent(:tab))
        Tachikoma.update!(app, Tachikoma.KeyEvent(:tab))
        @test app.notebook_view.focused_idx == 3

        # Move it up twice — should end at position 1
        Tachikoma.update!(app, Tachikoma.KeyEvent(:alt_up))
        @test app.notebook_view.focused_idx == 2
        Tachikoma.update!(app, Tachikoma.KeyEvent(:alt_up))
        @test app.notebook_view.focused_idx == 1
        @test ordered_cells(nb) == [c3, c1, c2]

        # Focused widget should show the right cell
        fw = Sessions.focused_widget(app.notebook_view)
        @test fw.cell === c3
    end

    @testset "E2E: Move cell — widgets rebuilt after reorder" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        c2 = add_cell!(nb, "y = 2")
        app = Sessions.SessionsApp(nb)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:alt_down))

        # Widgets should match new order
        @test length(app.notebook_view.cell_widgets) == 2
        @test app.notebook_view.cell_widgets[1].cell === c2
        @test app.notebook_view.cell_widgets[2].cell === c1
    end

    @testset "E2E: Move cell — render shows new order" begin
        nb = Notebook()
        add_cell!(nb, "alpha = 1")
        add_cell!(nb, "beta = 2")
        add_cell!(nb, "gamma = 3")
        app = Sessions.SessionsApp(nb)

        # Move first cell down
        Tachikoma.update!(app, Tachikoma.KeyEvent(:alt_down))

        tb = render_app(app)
        # Both cells should still be visible
        @test Tachikoma.find_text(tb, "alpha") !== nothing
        @test Tachikoma.find_text(tb, "beta") !== nothing
        @test Tachikoma.find_text(tb, "gamma") !== nothing
    end

    @testset "E2E: Fold cell with Ctrl+F" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1\ny = 2\nz = 3")
        app = Sessions.SessionsApp(nb)

        @test !c1.folded

        # Ctrl+F in normal mode toggles fold
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'f'))
        @test c1.folded

        # Render shows "[folded]" and first line
        tb = render_app(app)
        @test Tachikoma.find_text(tb, "folded") !== nothing
        @test Tachikoma.find_text(tb, "x = 1") !== nothing

        # Unfold
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'f'))
        @test !c1.folded
    end

    @testset "E2E: Folded cell height is minimal" begin
        nb = Notebook()
        c1 = add_cell!(nb, "line1\nline2\nline3\nline4\nline5")
        app = Sessions.SessionsApp(nb)

        cw = Sessions.focused_widget(app.notebook_view)
        unfolded_h = Sessions.cell_height(cw)
        @test unfolded_h == 7  # 5 lines + 2 border

        c1.folded = true
        @test Sessions.cell_height(cw) == 3  # 1 line + 2 border
    end

    @testset "E2E: Disable cell with Ctrl+E" begin
        nb = Notebook()
        c1 = add_cell!(nb, "dis_x = 1")
        c2 = add_cell!(nb, "dis_y = dis_x + 1")
        app = Sessions.SessionsApp(nb)

        @test !c1.disabled

        # Ctrl+E in normal mode toggles disabled
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'e'))
        @test c1.disabled

        # Render shows "[disabled]"
        tb = render_app(app)
        @test Tachikoma.find_text(tb, "disabled") !== nothing

        # Re-enable
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'e'))
        @test !c1.disabled
    end

    @testset "E2E: Disabled cells not executed" begin
        nb = Notebook()
        c1 = add_cell!(nb, "dis_skip = 42")
        c2 = add_cell!(nb, "dis_dep = 99")
        app = Sessions.SessionsApp(nb)

        c1.disabled = true
        Sessions.run_all_cells!(app)

        # c1 should NOT have been executed (still idle)
        @test c1.state == cell_idle
        @test c1.output.result === nothing

        # c2 should have been executed
        @test c2.state == cell_done
        @test c2.output.result == 99
    end

    @testset "E2E: Disabled state indicator" begin
        cell = Cell("x = 1")
        @test Sessions.state_indicator(cell)[1] == "◌"  # never-run

        cell.disabled = true
        char, _ = Sessions.state_indicator(cell)
        @test char == "⊘"  # disabled
    end

    @testset "E2E: Ctrl+E does nothing in insert mode" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        app.mode = :insert
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'e'))
        @test !c1.disabled
    end

    @testset "E2E: Disabled state preserved in format roundtrip" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "enabled = 1")
        c2 = add_cell!(nb, "disabled_cell = 2")
        c2.disabled = true

        save_notebook(nb)
        nb2 = load_notebook(path)
        cells = ordered_cells(nb2)
        @test !cells[1].disabled
        @test cells[2].disabled
        @test cells[2].code == "disabled_cell = 2"

        rm(path; force=true)
    end

    @testset "E2E: Ctrl+F does nothing in insert mode" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        app.mode = :insert
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'f'))
        @test !c1.folded  # should not fold in insert mode
    end

    @testset "E2E: Fold state preserved in format roundtrip" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "visible = 1")
        c2 = add_cell!(nb, "hidden = 2"; folded=true)

        save_notebook(nb)
        nb2 = load_notebook(path)
        cells = ordered_cells(nb2)
        @test !cells[1].folded
        @test cells[2].folded

        rm(path; force=true)
    end

    @testset "E2E: Context menu — open and close" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test app.mode == :normal
        @test app.context_menu === nothing

        # '.' opens context menu
        Tachikoma.update!(app, Tachikoma.KeyEvent('.'))
        @test app.mode == :context_menu
        @test app.context_menu !== nothing

        # Escape closes it
        Tachikoma.update!(app, Tachikoma.KeyEvent(:escape))
        @test app.mode == :normal
        @test app.context_menu === nothing
    end

    @testset "E2E: Context menu — navigate and render" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        Tachikoma.update!(app, Tachikoma.KeyEvent('.'))
        @test app.context_menu.selected == 1

        Tachikoma.update!(app, Tachikoma.KeyEvent(:down))
        @test app.context_menu.selected == 2

        Tachikoma.update!(app, Tachikoma.KeyEvent(:up))
        @test app.context_menu.selected == 1

        # Can't go above 1
        Tachikoma.update!(app, Tachikoma.KeyEvent(:up))
        @test app.context_menu.selected == 1

        # Render shows menu items
        tb = render_app(app)
        @test Tachikoma.find_text(tb, "Run Cell") !== nothing
        @test Tachikoma.find_text(tb, "Delete Cell") !== nothing
        @test Tachikoma.find_text(tb, "Move Up") !== nothing
    end

    @testset "E2E: Context menu — Run Cell action" begin
        nb = Notebook()
        c1 = add_cell!(nb, "ctx_run = 42")
        app = Sessions.SessionsApp(nb)

        Tachikoma.update!(app, Tachikoma.KeyEvent('.'))
        # "Run Cell" is item 1 — select and enter
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter))

        @test app.mode == :normal
        @test c1.state == cell_done
        @test c1.output.result == 42
    end

    @testset "E2E: Context menu — Delete Cell action" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        app = Sessions.SessionsApp(nb)
        @test length(nb) == 2

        Tachikoma.update!(app, Tachikoma.KeyEvent('.'))
        # Navigate to "Delete Cell" (item 2)
        Tachikoma.update!(app, Tachikoma.KeyEvent(:down))
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter))

        @test app.mode == :normal
        @test length(nb) == 1
    end

    @testset "E2E: Context menu — Fold action" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        Tachikoma.update!(app, Tachikoma.KeyEvent('.'))
        # Navigate to "Fold/Unfold" (item 3)
        Tachikoma.update!(app, Tachikoma.KeyEvent(:down))
        Tachikoma.update!(app, Tachikoma.KeyEvent(:down))
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter))

        @test c1.folded
        @test app.mode == :normal
    end

    @testset "E2E: Context menu — Disable action" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        Tachikoma.update!(app, Tachikoma.KeyEvent('.'))
        # Navigate to "Disable/Enable" (item 4)
        for _ in 1:3
            Tachikoma.update!(app, Tachikoma.KeyEvent(:down))
        end
        Tachikoma.update!(app, Tachikoma.KeyEvent(:enter))

        @test c1.disabled
        @test app.mode == :normal
    end

    @testset "E2E: Context menu — does not open in insert mode" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert

        Tachikoma.update!(app, Tachikoma.KeyEvent('.'))
        @test app.mode == :insert  # stayed in insert
        @test app.context_menu === nothing
    end

    @testset "E2E: Delete cell with Ctrl+D" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        app = Sessions.SessionsApp(nb)

        @test length(nb) == 2
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'd'))
        @test length(nb) == 1
        # Should store in undo buffer
        @test length(app.undo_buffer) == 1
        @test contains(app.message, "undo")
    end

    @testset "E2E: Undo delete with Ctrl+Z" begin
        nb = Notebook()
        c1 = add_cell!(nb, "undo_a = 1")
        c2 = add_cell!(nb, "undo_b = 2")
        c3 = add_cell!(nb, "undo_c = 3")
        app = Sessions.SessionsApp(nb)

        # Delete first cell
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'd'))
        @test length(nb) == 2

        # Undo — should restore at position 1
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'z'))
        @test length(nb) == 3
        @test ordered_cells(nb)[1] === c1
        @test app.notebook_view.focused_idx == 1
        @test contains(app.message, "Restored")
    end

    @testset "E2E: Multiple undo (LIFO)" begin
        nb = Notebook()
        c1 = add_cell!(nb, "lifo_a = 1")
        c2 = add_cell!(nb, "lifo_b = 2")
        c3 = add_cell!(nb, "lifo_c = 3")
        app = Sessions.SessionsApp(nb)

        # Delete first cell
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'd'))
        # Delete next (now first)
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'd'))
        @test length(nb) == 1

        # Undo twice — LIFO order
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'z'))
        @test length(nb) == 2

        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'z'))
        @test length(nb) == 3
    end

    @testset "E2E: Undo with empty buffer is no-op" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test isempty(app.undo_buffer)
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'z'))
        @test length(nb) == 1  # nothing changed
    end

    @testset "E2E: Click in gap inserts new cell" begin
        nb = Notebook()
        c1 = add_cell!(nb, "gap_a = 1")
        c2 = add_cell!(nb, "gap_b = 2")
        app = Sessions.SessionsApp(nb)

        # Render first to establish viewport
        render_app(app)
        @test length(nb) == 2

        # Cell 1: height=3 (1 line + 2 border), starts at viewport.y=2
        # Output: 0, Gap at y = 2+3 = 5 (content y=3)
        # Click in gap between cell 1 and cell 2
        gap_y = app.notebook_view.viewport.y + 3  # after cell 1 (3 lines)
        evt = Tachikoma.MouseEvent(5, gap_y, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false)
        Tachikoma.update!(app, evt)

        @test length(nb) == 3
        # New cell inserted between c1 and c2
        cells = ordered_cells(nb)
        @test cells[1] === c1
        @test cells[3] === c2
        @test cells[2].code == ""  # new empty cell
        @test app.notebook_view.focused_idx == 2
    end

    @testset "E2E: Click below last cell inserts at end" begin
        nb = Notebook()
        add_cell!(nb, "last = 1")
        app = Sessions.SessionsApp(nb)

        render_app(app; height=40)

        # Click well below the last cell
        evt = Tachikoma.MouseEvent(5, 35, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false)
        Tachikoma.update!(app, evt)

        @test length(nb) == 2
        @test app.notebook_view.focused_idx == 2
    end

    @testset "E2E: gap_at_y returns nothing for clicks inside cells" begin
        nb = Notebook()
        add_cell!(nb, "inside = 1")
        app = Sessions.SessionsApp(nb)

        render_app(app)

        # Click inside cell body (y = viewport.y + 1, which is inside the cell)
        inside_y = app.notebook_view.viewport.y + 1
        @test Sessions.gap_at_y(app.notebook_view, inside_y) === nothing
        @test Sessions.cell_at_y(app.notebook_view, inside_y) == 1
    end

    @testset "E2E: Click indicator runs cell" begin
        nb = Notebook()
        c1 = add_cell!(nb, "ind_run = 42")
        app = Sessions.SessionsApp(nb)

        render_app(app)
        @test c1.state == cell_idle

        # Click on indicator area (x=1, inside cell y)
        cell_y = app.notebook_view.viewport.y + 1  # inside cell 1
        evt = Tachikoma.MouseEvent(1, cell_y, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false)
        Tachikoma.update!(app, evt)

        @test c1.state == cell_done
        @test c1.output.result == 42
    end

    @testset "E2E: Click indicator runs non-focused cell" begin
        nb = Notebook()
        c1 = add_cell!(nb, "ind_a = 10")
        c2 = add_cell!(nb, "ind_b = 20")
        app = Sessions.SessionsApp(nb)

        render_app(app)
        @test app.notebook_view.focused_idx == 1

        # Click indicator on cell 2 (y = viewport.y + cell1_height + gap)
        cell2_y = app.notebook_view.viewport.y + 3 + 1  # after cell1 (3) + gap (1)
        evt = Tachikoma.MouseEvent(2, cell2_y, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false)
        Tachikoma.update!(app, evt)

        @test c2.state == cell_done
        @test c2.output.result == 20
    end

    @testset "E2E: Click body focuses cell (not run)" begin
        nb = Notebook()
        c1 = add_cell!(nb, "no_run = 1")
        c2 = add_cell!(nb, "no_run2 = 2")
        app = Sessions.SessionsApp(nb)

        render_app(app)

        # Click on cell 2 body (x=10, well past indicator area)
        cell2_y = app.notebook_view.viewport.y + 3 + 1
        evt = Tachikoma.MouseEvent(10, cell2_y, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false)
        Tachikoma.update!(app, evt)

        # Should focus but not run
        @test app.notebook_view.focused_idx == 2
        @test c2.state == cell_idle
    end

    @testset "E2E: Split cell at cursor" begin
        nb = Notebook()
        c1 = add_cell!(nb, "line1\nline2\nline3")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert

        # Set cursor to middle of line 2 (after "li" on line 2)
        editor = Sessions.focused_widget(app.notebook_view).editor
        editor.cursor_row = 2
        editor.cursor_col = 2

        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl_shift_s))

        @test length(nb) == 2
        cells = ordered_cells(nb)
        @test cells[1].code == "line1\nli"
        @test cells[2].code == "ne2\nline3"
        @test app.notebook_view.focused_idx == 2
    end

    @testset "E2E: Split cell at start" begin
        nb = Notebook()
        add_cell!(nb, "all code here")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert

        editor = Sessions.focused_widget(app.notebook_view).editor
        editor.cursor_row = 1
        editor.cursor_col = 0

        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl_shift_s))

        @test length(nb) == 2
        cells = ordered_cells(nb)
        @test cells[1].code == ""
        @test cells[2].code == "all code here"
    end

    @testset "E2E: Split cell at end" begin
        nb = Notebook()
        add_cell!(nb, "code")
        app = Sessions.SessionsApp(nb)
        app.mode = :insert

        editor = Sessions.focused_widget(app.notebook_view).editor
        editor.cursor_row = 1
        editor.cursor_col = 4

        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl_shift_s))

        @test length(nb) == 2
        cells = ordered_cells(nb)
        @test cells[1].code == "code"
        @test cells[2].code == ""
    end

    @testset "E2E: Merge cells" begin
        nb = Notebook()
        c1 = add_cell!(nb, "first")
        c2 = add_cell!(nb, "second")
        app = Sessions.SessionsApp(nb)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl_shift_m))

        @test length(nb) == 1
        @test ordered_cells(nb)[1].code == "first\nsecond"
        @test app.notebook_view.focused_idx == 1
    end

    @testset "E2E: Merge — can't merge last cell" begin
        nb = Notebook()
        add_cell!(nb, "only")
        app = Sessions.SessionsApp(nb)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl_shift_m))
        @test length(nb) == 1  # no change
    end

    @testset "E2E: Split does nothing in normal mode" begin
        nb = Notebook()
        add_cell!(nb, "no split")
        app = Sessions.SessionsApp(nb)
        # mode is :normal by default

        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl_shift_s))
        @test length(nb) == 1  # no change
    end

    @testset "E2E: Quit with Ctrl+Q" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test !Tachikoma.should_quit(app)
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'q'))
        @test Tachikoma.should_quit(app)
    end

    @testset "E2E: Error handling — bad code shows error" begin
        nb = Notebook()
        c1 = add_cell!(nb, "error(\"e2e boom\")")
        app = Sessions.SessionsApp(nb)

        Sessions.run_focused_cell!(app)
        @test c1.state == cell_errored
        @test c1.output.error !== nothing

        # Error should be visible
        @test find_in_render(app, "boom")
    end

    @testset "E2E: Error formatting" begin
        nb = Notebook()
        c1 = add_cell!(nb, "undefined_e2e_var + 1")
        app = Sessions.SessionsApp(nb)

        Sessions.run_focused_cell!(app)
        @test c1.state == cell_errored

        msg = format_cell_error(c1.output)
        @test contains(msg, "UndefVarError")
        @test contains(msg, "undefined_e2e_var")
    end

    @testset "E2E: DataTable output" begin
        nb = Notebook()
        c1 = add_cell!(nb, "[(a=1, b=2), (a=3, b=4)]")
        app = Sessions.SessionsApp(nb)

        Sessions.run_focused_cell!(app)
        @test c1.state == cell_done
        @test c1.output.output_type == :dataframe

        tb = render_app(app)
        @test Tachikoma.find_text(tb, "a") !== nothing
        @test Tachikoma.find_text(tb, "b") !== nothing
    end

    @testset "E2E: Markdown output" begin
        nb = Notebook()
        c1 = add_cell!(nb, "using Markdown; md\"# Hello E2E\"")
        app = Sessions.SessionsApp(nb)

        # Execute in workspace (md string literal needs Markdown loaded)
        # Use direct classification instead
        c1.state = cell_done
        c1.output.result = md"# Hello E2E"
        c1.output.output_type = classify_output(c1.output.result)
        mark_executed!(c1)

        @test c1.output.output_type == :markdown
        @test find_in_render(app, "Hello")
    end

    @testset "E2E: State indicators in render" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        # Never-run → dim dotted circle ◌
        char, _ = Sessions.state_indicator(c1)
        @test char == "◌"

        Sessions.run_focused_cell!(app)
        char, _ = Sessions.state_indicator(c1)
        @test char == "●"  # done → solid green

        c1.code = "x = 2"
        char, _ = Sessions.state_indicator(c1)
        @test char == "○"  # stale → hollow yellow
    end

    @testset "E2E: File save/load roundtrip" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "roundtrip_x = 42")
        c2 = add_cell!(nb, "roundtrip_y = roundtrip_x + 1")
        app = Sessions.SessionsApp(nb)

        Sessions.run_all_cells!(app)
        save_notebook(nb)

        # Load back
        nb2 = load_notebook(path)
        @test length(nb2) == 2
        cells = ordered_cells(nb2)
        @test cells[1].code == "roundtrip_x = 42"
        @test cells[2].code == "roundtrip_y = roundtrip_x + 1"

        rm(path; force=true)
    end

    @testset "E2E: Hot reload — external file edit" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "reload_x = 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        execute_cell!(app.workspace, c1)
        @test !is_stale(c1)

        # External edit
        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "reload_x = 999"
        save_notebook(nb_ext, path)

        diff = Sessions.reload_notebook!(nb)
        @test length(diff.changed) == 1
        @test c1.code == "reload_x = 999"
        @test is_stale(c1)

        rm(path; force=true)
    end

    @testset "E2E: Async execution basics" begin
        nb = Notebook()
        c1 = add_cell!(nb, "async_e2e = 77")
        app = Sessions.SessionsApp(nb)

        @test app.tq isa Tachikoma.TaskQueue
        Sessions.run_focused_cell_async!(app)
        sleep(0.5)
        @test c1.state == cell_done
        @test c1.output.result == 77
    end

    @testset "E2E: Navigation during async execution" begin
        nb = Notebook()
        add_cell!(nb, "na = 1")
        add_cell!(nb, "nb_val = 2")
        add_cell!(nb, "nc = 3")
        app = Sessions.SessionsApp(nb)

        Sessions.run_all_cells_async!(app)

        # Navigate while executing
        Tachikoma.update!(app, Tachikoma.KeyEvent(:tab))
        @test app.notebook_view.focused_idx == 2

        sleep(0.5)
    end

    @testset "E2E: Cycle detection" begin
        nb = Notebook()
        c1 = add_cell!(nb, "cycle_a = cycle_b + 1")
        c2 = add_cell!(nb, "cycle_b = cycle_a + 1")
        app = Sessions.SessionsApp(nb)

        Sessions.run_all_cells!(app)
        @test c1.state == cell_errored
        @test c2.state == cell_errored
    end

    @testset "E2E: Output widget shows correct types" begin
        # Text output
        cell_text = Cell("42")
        cell_text.state = cell_done
        cell_text.output.result = 42
        cell_text.output.output_type = :text
        ow_text = Sessions.OutputWidget(cell_text)
        @test Sessions.output_height(ow_text) > 0

        # Nothing output (idle)
        cell_idle = Cell("")
        ow_idle = Sessions.OutputWidget(cell_idle)
        @test Sessions.output_height(ow_idle) == 0

        # Collapsed output
        cell_coll = Cell("1")
        cell_coll.state = cell_done
        cell_coll.output.result = 1
        ow_coll = Sessions.OutputWidget(cell_coll)
        ow_coll.collapsed = true
        @test Sessions.output_height(ow_coll) == 0
    end

    @testset "E2E: Full workflow sequence" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "workflow_x = 10")
        c2 = add_cell!(nb, "workflow_y = workflow_x * 2")
        app = Sessions.SessionsApp(nb)

        # 1. Initial render
        @test find_in_render(app, "workflow_x")
        @test find_in_render(app, "workflow_y")

        # 2. Execute all
        Sessions.run_all_cells!(app)
        @test c1.output.result == 10
        @test c2.output.result == 20
        app.message = ""
        @test find_in_render(app, "2/2 cells")

        # 3. Edit cell 1
        c1.code = "workflow_x = 100"
        Sessions.sync_from_cell!(app.notebook_view.cell_widgets[1])
        @test is_stale(c1)

        # 4. Run stale
        Sessions.run_stale_cells!(app)
        @test c1.output.result == 100
        @test c2.output.result == 200
        @test !is_stale(c1)

        # 5. Save
        save_notebook(nb)
        @test isfile(path)

        # 6. Add cell
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'n'))
        @test length(nb) == 3

        # 7. Delete cell
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'd'))
        @test length(nb) == 2

        # 8. Quit
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'q'))
        @test app.quit

        rm(path; force=true)
    end
end
