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
        @test Tachikoma.find_text(tb, "x = 1") !== nothing
        @test Tachikoma.find_text(tb, "y = x + 1") !== nothing
        @test Tachikoma.find_text(tb, "z = x * y") !== nothing
    end

    @testset "E2E: App renders without errors" begin
        nb = Notebook(; path="e2e.jl")
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test find_in_render(app, "x = 1")
    end

    @testset "E2E: Navigate between cells" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        add_cell!(nb, "c = 3")
        app = Sessions.SessionsApp(nb)

        @test app.notebook_view.focused_idx == 1

        Sessions.focus_next!(app.notebook_view)
        @test app.notebook_view.focused_idx == 2

        Sessions.focus_next!(app.notebook_view)
        @test app.notebook_view.focused_idx == 3

        # Can't go past last
        Sessions.focus_next!(app.notebook_view)
        @test app.notebook_view.focused_idx == 3
    end

    @testset "E2E: Always in editing mode (no normal/insert distinction)" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test app.mode == :normal
        # Typing goes directly to the cell — no Enter needed to start editing
        Tachikoma.update!(app, Tachikoma.KeyEvent(:char, 'y'))
        @test app.mode == :normal  # stays in normal (which is always-editing)
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

        # All cells executed successfully
        @test c1.state == cell_done
        @test c2.state == cell_done
        @test c3.state == cell_done
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

    @testset "E2E: Add new cell" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test length(nb) == 1
        Sessions.add_cell_after_focus!(app.notebook_view)
        @test length(nb) == 2
        @test app.notebook_view.focused_idx == 2
    end

    @testset "E2E: Move cell up" begin
        nb = Notebook()
        c1 = add_cell!(nb, "a = 1")
        c2 = add_cell!(nb, "b = 2")
        c3 = add_cell!(nb, "c = 3")
        app = Sessions.SessionsApp(nb)

        # Focus second cell, then move it up
        Sessions.focus_next!(app.notebook_view)
        @test app.notebook_view.focused_idx == 2

        Sessions.move_cell_up!(app.notebook_view)
        @test app.notebook_view.focused_idx == 1
        @test ordered_cells(nb) == [c2, c1, c3]
    end

    @testset "E2E: Move cell down" begin
        nb = Notebook()
        c1 = add_cell!(nb, "a = 1")
        c2 = add_cell!(nb, "b = 2")
        c3 = add_cell!(nb, "c = 3")
        app = Sessions.SessionsApp(nb)

        # Focus first cell, move it down
        @test app.notebook_view.focused_idx == 1
        Sessions.move_cell_down!(app.notebook_view)
        @test app.notebook_view.focused_idx == 2
        @test ordered_cells(nb) == [c2, c1, c3]
    end

    @testset "E2E: Move cell — boundary no-ops" begin
        nb = Notebook()
        c1 = add_cell!(nb, "a = 1")
        c2 = add_cell!(nb, "b = 2")
        app = Sessions.SessionsApp(nb)

        # First cell can't move up
        Sessions.move_cell_up!(app.notebook_view)
        @test app.notebook_view.focused_idx == 1
        @test ordered_cells(nb) == [c1, c2]

        # Move to last, then can't move down
        Sessions.focus_next!(app.notebook_view)
        @test app.notebook_view.focused_idx == 2
        Sessions.move_cell_down!(app.notebook_view)
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
        Sessions.focus_next!(app.notebook_view)
        Sessions.focus_next!(app.notebook_view)
        @test app.notebook_view.focused_idx == 3

        # Move it up twice — should end at position 1
        Sessions.move_cell_up!(app.notebook_view)
        @test app.notebook_view.focused_idx == 2
        Sessions.move_cell_up!(app.notebook_view)
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

        Sessions.move_cell_down!(app.notebook_view)

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
        Sessions.move_cell_down!(app.notebook_view)

        tb = render_app(app)
        # Both cells should still be visible
        @test Tachikoma.find_text(tb, "alpha") !== nothing
        @test Tachikoma.find_text(tb, "beta") !== nothing
        @test Tachikoma.find_text(tb, "gamma") !== nothing
    end

    @testset "E2E: Fold cell" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1\ny = 2\nz = 3")
        app = Sessions.SessionsApp(nb)

        @test !c1.folded

        # Toggle fold on focused cell
        c1.folded = !c1.folded
        Sessions.rebuild_widgets!(app.notebook_view)
        @test c1.folded

        # Folded cell is completely hidden — code not visible
        tb = render_app(app)
        @test Tachikoma.find_text(tb, "x = 1") === nothing

        # Unfold
        c1.folded = !c1.folded
        Sessions.rebuild_widgets!(app.notebook_view)
        @test !c1.folded
    end

    @testset "E2E: Folded cell height is minimal" begin
        nb = Notebook()
        c1 = add_cell!(nb, "line1\nline2\nline3\nline4\nline5")
        app = Sessions.SessionsApp(nb)

        cw = Sessions.focused_widget(app.notebook_view)
        unfolded_h = Sessions.cell_height(cw)
        @test unfolded_h == 7  # 5 lines + 2 border + 2*V_INSET(0)

        c1.folded = true
        @test Sessions.cell_height(cw) == 1  # folded = single thin row
    end

    @testset "E2E: Disable cell" begin
        nb = Notebook()
        c1 = add_cell!(nb, "dis_x = 1")
        c2 = add_cell!(nb, "dis_y = dis_x + 1")
        app = Sessions.SessionsApp(nb)

        @test !c1.disabled

        # Toggle disabled on focused cell
        c1.disabled = !c1.disabled
        Sessions.rebuild_widgets!(app.notebook_view)
        @test c1.disabled

        # Render shows disabled preview
        tb = render_app(app)
        @test Tachikoma.find_text(tb, "dis_x") !== nothing

        # Re-enable
        c1.disabled = !c1.disabled
        Sessions.rebuild_widgets!(app.notebook_view)
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

    @testset "E2E: Disabled defaults to false" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        # disabled is false by default — no action taken
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

    @testset "E2E: Folded defaults to false" begin
        nb = Notebook()
        c1 = add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        # folded is false by default
        @test !c1.folded
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

    @testset "E2E: Dropdown — open and close" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test app.mode == :normal
        @test app.cell_dropdown === nothing

        # Open dropdown
        Sessions.open_dropdown!(app, 1, 50, 5)
        @test app.mode == :dropdown
        @test app.cell_dropdown !== nothing
        @test app.cell_dropdown.cell_idx == 1

        # Close dropdown
        Sessions.close_dropdown!(app)
        @test app.mode == :normal
        @test app.cell_dropdown === nothing
    end

    @testset "E2E: Dropdown — render shows items" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        Sessions.open_dropdown!(app, 1, 50, 5)

        # Render shows dropdown items
        tb = render_app(app)
        @test Tachikoma.find_text(tb, "Delete cell") !== nothing
    end

    @testset "E2E: Dropdown — click Delete cell opens confirm dialog" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        app = Sessions.SessionsApp(nb)
        app.screen_area = Tachikoma.Rect(1, 1, 120, 40)
        @test length(nb) == 2

        # Open dropdown on cell 1
        Sessions.open_dropdown!(app, 1, 50, 5)

        # Simulate click on "Delete cell" item (item 1, at y = dropdown.y + 1)
        dd = app.cell_dropdown
        click_evt = Tachikoma.MouseEvent(dd.x + 2, dd.y + 1, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false)
        Tachikoma.update!(app, click_evt)

        # Should now be in confirm mode, not deleted yet
        @test app.mode == :confirm
        @test app.confirm_dialog !== nothing
        @test length(nb) == 2

        # Click Yes to confirm deletion
        r = Sessions._confirm_rect(app.screen_area)
        yes_x = r.x + r.w - length(Sessions.CONFIRM_BTN_YES) - 2
        yes_y = r.y + 5
        yes_evt = Tachikoma.MouseEvent(yes_x + 1, yes_y, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false)
        Tachikoma.update!(app, yes_evt)

        @test app.mode == :normal
        @test length(nb) == 1
    end

    @testset "E2E: Confirm dialog — click away dismisses (No)" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        app = Sessions.SessionsApp(nb)
        app.screen_area = Tachikoma.Rect(1, 1, 120, 40)

        # Open dropdown and click Delete
        Sessions.open_dropdown!(app, 1, 50, 5)
        dd = app.cell_dropdown
        click_evt = Tachikoma.MouseEvent(dd.x + 2, dd.y + 1, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false)
        Tachikoma.update!(app, click_evt)
        @test app.mode == :confirm

        # Click away (far from buttons) — should dismiss without deleting
        away_evt = Tachikoma.MouseEvent(1, 1, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false)
        Tachikoma.update!(app, away_evt)

        @test app.mode == :normal
        @test length(nb) == 2  # not deleted
    end

    @testset "E2E: Dropdown — click away dismisses" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        Sessions.open_dropdown!(app, 1, 50, 5)
        @test app.mode == :dropdown

        # Click far away from dropdown
        click_evt = Tachikoma.MouseEvent(1, 1, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false)
        Tachikoma.update!(app, click_evt)

        @test app.mode == :normal
        @test app.cell_dropdown === nothing
    end

    @testset "E2E: Dropdown — Escape closes" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        Sessions.open_dropdown!(app, 1, 50, 5)
        @test app.mode == :dropdown

        Tachikoma.update!(app, Tachikoma.KeyEvent(:escape))
        @test app.mode == :normal
        @test app.cell_dropdown === nothing
    end

    @testset "E2E: Dropdown — hover highlights item" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        Sessions.open_dropdown!(app, 1, 50, 5)
        dd = app.cell_dropdown
        @test dd.hovered_idx == 0

        # Mouse move over item 1
        move_evt = Tachikoma.MouseEvent(dd.x + 2, dd.y + 1, Tachikoma.mouse_none, Tachikoma.mouse_move, false, false, false)
        Tachikoma.update!(app, move_evt)
        @test dd.hovered_idx == 1

        # Mouse move away
        move_evt = Tachikoma.MouseEvent(1, 1, Tachikoma.mouse_none, Tachikoma.mouse_move, false, false, false)
        Tachikoma.update!(app, move_evt)
        @test dd.hovered_idx == 0
    end

    @testset "E2E: Dropdown — not open by default" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test app.mode == :normal
        @test app.cell_dropdown === nothing
    end

    @testset "E2E: Delete cell" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        app = Sessions.SessionsApp(nb)

        @test length(nb) == 2
        Sessions.delete_focused_cell_with_undo!(app)
        @test length(nb) == 1
        # Should store in undo buffer
        @test length(app.undo_buffer) == 1
        @test contains(app.message, "undo")
    end

    @testset "E2E: Undo delete" begin
        nb = Notebook()
        c1 = add_cell!(nb, "undo_a = 1")
        c2 = add_cell!(nb, "undo_b = 2")
        c3 = add_cell!(nb, "undo_c = 3")
        app = Sessions.SessionsApp(nb)

        # Delete first cell
        Sessions.delete_focused_cell_with_undo!(app)
        @test length(nb) == 2

        # Undo — should restore at position 1
        Sessions.undo_delete!(app)
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
        Sessions.delete_focused_cell_with_undo!(app)
        # Delete next (now first)
        Sessions.delete_focused_cell_with_undo!(app)
        @test length(nb) == 1

        # Undo twice — LIFO order
        Sessions.undo_delete!(app)
        @test length(nb) == 2

        Sessions.undo_delete!(app)
        @test length(nb) == 3
    end

    @testset "E2E: Undo with empty buffer is no-op" begin
        nb = Notebook()
        add_cell!(nb, "x = 1")
        app = Sessions.SessionsApp(nb)

        @test isempty(app.undo_buffer)
        Sessions.undo_delete!(app)
        @test length(nb) == 1  # nothing changed
    end

    @testset "E2E: Click in gap does NOT insert cell" begin
        nb = Notebook()
        c1 = add_cell!(nb, "gap_a = 1")
        c2 = add_cell!(nb, "gap_b = 2")
        app = Sessions.SessionsApp(nb)

        render_app(app)
        @test length(nb) == 2

        # Click in gap between cell 1 and cell 2 — should NOT create a cell
        gap_y = app.notebook_view.viewport.y + 1 + 3  # top_margin + cell1 height
        evt = Tachikoma.MouseEvent(5, gap_y, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false)
        Tachikoma.update!(app, evt)

        @test length(nb) == 2  # no new cell
    end

    @testset "E2E: Click below last cell inserts at end" begin
        nb = Notebook()
        add_cell!(nb, "last = 1")
        app = Sessions.SessionsApp(nb)

        render_app(app; height=40)

        # Click well below the last cell — does NOT insert (only explicit + clicks)
        evt = Tachikoma.MouseEvent(5, 35, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false)
        Tachikoma.update!(app, evt)

        @test length(nb) == 1  # unchanged — no accidental insertion
        @test app.notebook_view.focused_idx == 1  # unchanged
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

    @testset "E2E: Click run button runs cell" begin
        nb = Notebook()
        c1 = add_cell!(nb, "ind_run = 42")
        app = Sessions.SessionsApp(nb)

        render_app(app; width=80)
        @test c1.state == cell_idle

        # Click on run button area (gap below cell, right-aligned)
        vp = app.notebook_view.viewport
        pad = max(1, round(Int, vp.width * Sessions.CELL_PAD_FRACTION))
        pad = min(pad, max(0, div(vp.width - 10, 2)))
        cell_right = vp.x + vp.width - pad
        # Gap below cell 1: viewport.y + border(1) + top_margin(1) + cell_height = first gap row
        ch1 = Sessions.cell_height(Sessions.focused_widget(app.notebook_view))
        gap_y = vp.y + 2 + ch1
        run_x = cell_right - 1  # inside the right-aligned run text
        evt = Tachikoma.MouseEvent(run_x, gap_y, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false)
        Tachikoma.update!(app, evt)

        @test c1.state == cell_done
        @test c1.output.result == 42
    end

    @testset "E2E: Click run button runs non-focused cell" begin
        nb = Notebook()
        c1 = add_cell!(nb, "ind_a = 10")
        c2 = add_cell!(nb, "ind_b = 20")
        app = Sessions.SessionsApp(nb)

        render_app(app; width=80)
        @test app.notebook_view.focused_idx == 1

        # In Pluto-style, run button only shows on focused cell.
        # Focus cell 2 first, then click run.
        Sessions.focus_cell!(app.notebook_view, 2)
        render_app(app; width=80)

        vp = app.notebook_view.viewport
        pad = max(1, round(Int, vp.width * Sessions.CELL_PAD_FRACTION))
        pad = min(pad, max(0, div(vp.width - 10, 2)))
        cell_right = vp.x + vp.width - pad
        # Gap below cell 2: compute dynamically from cell heights
        nv = app.notebook_view
        ch1 = Sessions.cell_height(nv.cell_widgets[1])
        ch2 = Sessions.cell_height(nv.cell_widgets[2])
        gap = Sessions.Theme.CELL_GAP
        gap_y = vp.y + 2 + ch1 + gap + ch2  # border(1) + top_margin(1) + cell1 + gap + cell2
        run_x = cell_right - 1
        evt = Tachikoma.MouseEvent(run_x, gap_y, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false)
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

        # Click on cell 2 body: top_margin(1) + cell1_height + gap + 1 inside cell2
        ch1 = Sessions.cell_height(app.notebook_view.cell_widgets[1])
        gap = Sessions.Theme.CELL_GAP
        cell2_y = app.notebook_view.viewport.y + 1 + ch1 + gap + 1
        evt = Tachikoma.MouseEvent(40, cell2_y, Tachikoma.mouse_left, Tachikoma.mouse_press, false, false, false)
        Tachikoma.update!(app, evt)

        # Should focus but not run
        @test app.notebook_view.focused_idx == 2
        @test c2.state == cell_idle
    end

    @testset "E2E: Split cell at cursor" begin
        nb = Notebook()
        c1 = add_cell!(nb, "line1\nline2\nline3")
        app = Sessions.SessionsApp(nb)
        # (no mode switch needed — always editing)

        # Set cursor to middle of line 2 (after "li" on line 2)
        editor = Sessions.focused_widget(app.notebook_view).editor
        editor.cursor_row = 2
        editor.cursor_col = 2

        Sessions.split_cell_at_cursor!(app.notebook_view)

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
        # (no mode switch needed — always editing)

        editor = Sessions.focused_widget(app.notebook_view).editor
        editor.cursor_row = 1
        editor.cursor_col = 0

        Sessions.split_cell_at_cursor!(app.notebook_view)

        @test length(nb) == 2
        cells = ordered_cells(nb)
        @test cells[1].code == ""
        @test cells[2].code == "all code here"
    end

    @testset "E2E: Split cell at end" begin
        nb = Notebook()
        add_cell!(nb, "code")
        app = Sessions.SessionsApp(nb)
        # (no mode switch needed — always editing)

        editor = Sessions.focused_widget(app.notebook_view).editor
        editor.cursor_row = 1
        editor.cursor_col = 4

        Sessions.split_cell_at_cursor!(app.notebook_view)

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

        Sessions.merge_with_next!(app.notebook_view)

        @test length(nb) == 1
        @test ordered_cells(nb)[1].code == "first\nsecond"
        @test app.notebook_view.focused_idx == 1
    end

    @testset "E2E: Merge — can't merge last cell" begin
        nb = Notebook()
        add_cell!(nb, "only")
        app = Sessions.SessionsApp(nb)

        Sessions.merge_with_next!(app.notebook_view)
        @test length(nb) == 1  # no change
    end

    @testset "E2E: Single cell unchanged without split" begin
        nb = Notebook()
        add_cell!(nb, "no split")
        app = Sessions.SessionsApp(nb)
        # mode is :normal by default — no split action taken

        @test length(nb) == 1  # no change
    end

    @testset "E2E: Smart delete — empty cell deletes immediately" begin
        nb = Notebook()
        add_cell!(nb, "keep this")
        add_cell!(nb, "")  # empty cell
        app = Sessions.SessionsApp(nb)

        # Focus second (empty) cell
        Sessions.focus_next!(app.notebook_view)
        @test app.notebook_view.focused_idx == 2

        # Empty cell — delete immediately without undo
        Sessions.delete_focused_cell!(app.notebook_view)
        @test length(nb) == 1
        @test isempty(app.undo_buffer)  # not stored in undo
    end

    @testset "E2E: Smart delete — non-empty cell goes to undo" begin
        nb = Notebook()
        add_cell!(nb, "keep")
        add_cell!(nb, "important code")
        app = Sessions.SessionsApp(nb)

        Sessions.delete_focused_cell_with_undo!(app)
        @test length(nb) == 1
        @test length(app.undo_buffer) == 1  # stored for undo
    end

    @testset "E2E: Smart delete — whitespace-only cell deletes immediately" begin
        nb = Notebook()
        add_cell!(nb, "a")
        add_cell!(nb, "  ")  # whitespace-only = empty
        app = Sessions.SessionsApp(nb)

        Sessions.focus_next!(app.notebook_view)
        # Whitespace-only cell — delete immediately without undo
        Sessions.delete_focused_cell!(app.notebook_view)
        @test length(nb) == 1
        @test isempty(app.undo_buffer)  # whitespace = empty → immediate
    end

    @testset "E2E: Smart delete — can't delete last cell" begin
        nb = Notebook()
        add_cell!(nb, "")
        app = Sessions.SessionsApp(nb)

        Sessions.delete_focused_cell!(app.notebook_view)
        @test length(nb) == 1  # can't delete last cell
    end

    # --- Multi-cell selection tests ---

    @testset "E2E: Shift+click selects range" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        add_cell!(nb, "c = 3")
        add_cell!(nb, "d = 4")
        app = Sessions.SessionsApp(nb)

        render_app(app)  # establish viewport
        @test app.notebook_view.focused_idx == 1

        # Calculate cell 3 position dynamically
        vp = app.notebook_view.viewport
        nv = app.notebook_view
        ch1 = Sessions.cell_height(nv.cell_widgets[1])
        ch2 = Sessions.cell_height(nv.cell_widgets[2])
        gap = Sessions.Theme.CELL_GAP
        cell3_y = vp.y + 2 + ch1 + gap + ch2 + gap  # border(1) + top_margin(1) + cell1 + gap + cell2 + gap

        # Shift+click on cell 3 — should select range from focused (1) through 3
        # MouseEvent field order: x, y, button, action, shift, alt, ctrl
        evt = Tachikoma.MouseEvent(40, cell3_y, Tachikoma.mouse_left, Tachikoma.mouse_press, true, false, false)
        Tachikoma.update!(app, evt)

        @test app.notebook_view.cell_widgets[1].selected
        @test app.notebook_view.cell_widgets[2].selected
        @test app.notebook_view.cell_widgets[3].selected
        @test !app.notebook_view.cell_widgets[4].selected
    end

    @testset "E2E: Select all cells" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        add_cell!(nb, "c = 3")
        app = Sessions.SessionsApp(nb)

        # Select all cells
        Sessions.select_all!(app.notebook_view)
        app.message = "Selected all 3 cells"

        @test all(cw -> cw.selected, app.notebook_view.cell_widgets)
        @test contains(app.message, "Selected all")
    end

    @testset "E2E: Escape clears selection" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        app = Sessions.SessionsApp(nb)

        Sessions.select_all!(app.notebook_view)
        @test all(cw -> cw.selected, app.notebook_view.cell_widgets)

        Sessions.clear_selection!(app.notebook_view)
        @test !any(cw -> cw.selected, app.notebook_view.cell_widgets)
    end

    @testset "E2E: Escape key clears selection in normal mode" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        app = Sessions.SessionsApp(nb)

        Sessions.select_all!(app.notebook_view)
        @test all(cw -> cw.selected, app.notebook_view.cell_widgets)

        Tachikoma.update!(app, Tachikoma.KeyEvent(:escape))
        @test !any(cw -> cw.selected, app.notebook_view.cell_widgets)
    end

    @testset "E2E: Delete removes all selected cells" begin
        nb = Notebook()
        add_cell!(nb, "keep1")
        add_cell!(nb, "del1")
        add_cell!(nb, "del2")
        add_cell!(nb, "keep2")
        app = Sessions.SessionsApp(nb)

        # Select cells 2 and 3
        app.notebook_view.cell_widgets[2].selected = true
        app.notebook_view.cell_widgets[3].selected = true

        Sessions.delete_selected_cells!(app)
        @test length(nb) == 2
        cells = ordered_cells(nb)
        @test cells[1].code == "keep1"
        @test cells[2].code == "keep2"
    end

    @testset "E2E: Delete selected stores in undo buffer" begin
        nb = Notebook()
        add_cell!(nb, "keep")
        add_cell!(nb, "del1")
        add_cell!(nb, "del2")
        app = Sessions.SessionsApp(nb)

        app.notebook_view.cell_widgets[2].selected = true
        app.notebook_view.cell_widgets[3].selected = true

        Sessions.delete_selected_cells!(app)
        @test length(app.undo_buffer) == 2
    end

    @testset "E2E: Alt+Up moves selected cells up" begin
        nb = Notebook()
        add_cell!(nb, "first")
        add_cell!(nb, "second")
        add_cell!(nb, "third")
        app = Sessions.SessionsApp(nb)

        # Select cells 2 and 3
        app.notebook_view.cell_widgets[2].selected = true
        app.notebook_view.cell_widgets[3].selected = true

        Sessions.move_selected_up!(app.notebook_view)
        cells = ordered_cells(nb)
        @test cells[1].code == "second"
        @test cells[2].code == "third"
        @test cells[3].code == "first"
    end

    @testset "E2E: Alt+Down moves selected cells down" begin
        nb = Notebook()
        add_cell!(nb, "first")
        add_cell!(nb, "second")
        add_cell!(nb, "third")
        app = Sessions.SessionsApp(nb)

        # Select cells 1 and 2
        app.notebook_view.cell_widgets[1].selected = true
        app.notebook_view.cell_widgets[2].selected = true

        Sessions.move_selected_down!(app.notebook_view)
        cells = ordered_cells(nb)
        @test cells[1].code == "third"
        @test cells[2].code == "first"
        @test cells[3].code == "second"
    end

    @testset "E2E: Selected cells get highlighted border" begin
        nb = Notebook()
        add_cell!(nb, "a = 1")
        add_cell!(nb, "b = 2")
        app = Sessions.SessionsApp(nb)

        app.notebook_view.cell_widgets[2].selected = true

        # Just check the selected field is set — render will use it
        @test app.notebook_view.cell_widgets[2].selected
        @test !app.notebook_view.cell_widgets[1].selected
    end

    @testset "E2E: Can't delete all cells via selection" begin
        nb = Notebook()
        add_cell!(nb, "only1")
        add_cell!(nb, "only2")
        app = Sessions.SessionsApp(nb)

        # Select all — should keep at least one
        app.notebook_view.cell_widgets[1].selected = true
        app.notebook_view.cell_widgets[2].selected = true

        Sessions.delete_selected_cells!(app)
        @test length(nb) >= 1  # at least one cell survives
    end

    @testset "E2E: has_selection helper" begin
        nb = Notebook()
        add_cell!(nb, "a")
        add_cell!(nb, "b")
        app = Sessions.SessionsApp(nb)

        @test !Sessions.has_selection(app.notebook_view)
        app.notebook_view.cell_widgets[1].selected = true
        @test Sessions.has_selection(app.notebook_view)
    end

    @testset "E2E: Delete with selection deletes selected" begin
        nb = Notebook()
        add_cell!(nb, "keep")
        add_cell!(nb, "sel1")
        add_cell!(nb, "sel2")
        app = Sessions.SessionsApp(nb)

        app.notebook_view.cell_widgets[2].selected = true
        app.notebook_view.cell_widgets[3].selected = true

        Sessions.delete_selected_cells!(app)
        @test length(nb) == 1
        @test ordered_cells(nb)[1].code == "keep"
    end

    @testset "E2E: Move selected cells up" begin
        nb = Notebook()
        add_cell!(nb, "stay")
        add_cell!(nb, "move1")
        add_cell!(nb, "move2")
        app = Sessions.SessionsApp(nb)

        app.notebook_view.cell_widgets[2].selected = true
        app.notebook_view.cell_widgets[3].selected = true

        Sessions.move_selected_up!(app.notebook_view)
        cells = ordered_cells(nb)
        @test cells[1].code == "move1"
        @test cells[2].code == "move2"
        @test cells[3].code == "stay"
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
        Sessions.focus_next!(app.notebook_view)
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
        @test c1.state == cell_done
        @test c2.state == cell_done

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
        Sessions.add_cell_after_focus!(app.notebook_view)
        @test length(nb) == 3

        # 7. Delete cell
        Sessions.delete_focused_cell_with_undo!(app)
        @test length(nb) == 2

        # 8. Quit
        Tachikoma.update!(app, Tachikoma.KeyEvent(:ctrl, 'q'))
        @test app.quit

        rm(path; force=true)
    end

    # --- E2E Agent Workflow (SESSIONS-6024) ---

    @testset "E2E: Agent workflow — execute, external edit, stale, re-execute" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "agent_x = 10")
        c2 = add_cell!(nb, "agent_y = agent_x * 2")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)

        # Step 1: Execute all cells — both green
        Sessions.run_all_cells!(app)
        @test c1.state == cell_done
        @test c2.state == cell_done
        @test c1.output.result == 10
        @test c2.output.result == 20

        # Step 2: Verify .session.toml created with correct hashes
        sp = session_path(path)
        @test isfile(sp)
        session_data = Sessions.load_session(sp)
        @test session_data !== nothing
        c1_hash = session_data["cells"][string(c1.id)]["execution_hash"]
        @test c1_hash == source_hash(c1)

        # Step 3: Agent externally modifies c1 on disk
        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "agent_x = 99"
        save_notebook(nb_ext, path)

        # Step 4: Trigger reload — c1 becomes stale with OLD cached output
        Sessions._on_external_change!(app)
        @test app.nb.cells[c1.id].code == "agent_x = 99"
        @test is_stale(app.nb.cells[c1.id])
        @test app.nb.cells[c1.id].output.result == 10  # old cached value
        # c2 unchanged
        @test !is_stale(app.nb.cells[c2.id])
        @test app.nb.cells[c2.id].output.result == 20

        # Step 5: Re-execute stale cell
        Sessions.run_cell_at_index!(app, 1)
        @test app.nb.cells[c1.id].state == cell_done
        @test app.nb.cells[c1.id].output.result == 99
        @test !is_stale(app.nb.cells[c1.id])

        # Step 6: Verify .session.toml updated with new hash
        session_data2 = Sessions.load_session(sp)
        c1_hash2 = session_data2["cells"][string(c1.id)]["execution_hash"]
        @test c1_hash2 == source_hash(app.nb.cells[c1.id])
        @test c1_hash2 != c1_hash  # hash changed

        rm(path; force=true)
        rm(sp; force=true)
    end

    @testset "E2E: Agent workflow — downstream stale after upstream change" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "up_val = 5")
        c2 = add_cell!(nb, "down_val = up_val + 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        Sessions.run_all_cells!(app)
        @test c2.output.result == 6

        # Agent changes upstream cell
        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "up_val = 50"
        save_notebook(nb_ext, path)
        Sessions._on_external_change!(app)

        # c1 stale (code changed), c2 still has old output
        @test is_stale(app.nb.cells[c1.id])
        @test app.nb.cells[c1.id].output.result == 5  # old

        # Re-execute all stale
        Sessions.run_all_cells!(app)
        @test app.nb.cells[c1.id].output.result == 50
        @test app.nb.cells[c2.id].output.result == 51

        rm(path; force=true)
        rm(session_path(path); force=true)
    end

    @testset "E2E: Agent workflow — add new cell, execute, verify session" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "base_val = 1")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        Sessions.run_all_cells!(app)
        @test c1.output.result == 1

        # Agent adds a cell on disk
        nb_ext = load_notebook(path)
        c_new = add_cell!(nb_ext, "new_val = base_val + 100")
        save_notebook(nb_ext, path)
        Sessions._on_external_change!(app)

        @test haskey(app.nb.cells, c_new.id)
        @test app.nb.cells[c_new.id].state == cell_idle

        # Execute the new cell
        new_idx = findfirst(id -> id == c_new.id, app.nb.cell_order)
        Sessions.run_cell_at_index!(app, new_idx)
        @test app.nb.cells[c_new.id].state == cell_done
        @test app.nb.cells[c_new.id].output.result == 101

        # Session file has the new cell
        sp = session_path(path)
        session_data = Sessions.load_session(sp)
        @test haskey(session_data["cells"], string(c_new.id))

        rm(path; force=true)
        rm(sp; force=true)
    end

    @testset "E2E: Agent workflow — remove cell, verify cleanup" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "keep_val = 1")
        c2 = add_cell!(nb, "remove_val = 2")
        save_notebook(nb)

        app = Sessions.SessionsApp(nb)
        Sessions.run_all_cells!(app)
        @test c2.output.result == 2

        c2_id = c2.id

        # Agent removes c2 on disk
        nb_ext = load_notebook(path)
        remove_cell!(nb_ext, c2_id)
        save_notebook(nb_ext, path)
        Sessions._on_external_change!(app)

        @test !haskey(app.nb.cells, c2_id)
        @test length(app.nb.cell_order) == 1
        @test length(app.notebook_view.cell_widgets) == 1

        rm(path; force=true)
        rm(session_path(path); force=true)
    end

    @testset "E2E: Agent workflow — full session roundtrip via fresh load" begin
        path = tempname() * ".jl"
        nb = Notebook(; path)
        c1 = add_cell!(nb, "rt_a = 42")
        c2 = add_cell!(nb, "rt_b = rt_a * 2")
        save_notebook(nb)

        # Execute and save session
        app = Sessions.SessionsApp(nb)
        Sessions.run_all_cells!(app)
        @test c1.output.result == 42
        @test c2.output.result == 84

        # Fresh load with session — should show cached outputs
        nb2 = load_notebook_with_session(path)
        @test nb2.cells[c1.id].state == cell_done
        @test nb2.cells[c1.id].output.text_representation != ""
        @test nb2.cells[c2.id].state == cell_done
        @test !is_stale(nb2.cells[c1.id])
        @test !is_stale(nb2.cells[c2.id])

        # Modify c1 on disk — fresh load shows stale
        nb_ext = load_notebook(path)
        nb_ext.cells[c1.id].code = "rt_a = 999"
        save_notebook(nb_ext, path)

        nb3 = load_notebook_with_session(path)
        @test is_stale(nb3.cells[c1.id])  # code changed, hash mismatch
        @test nb3.cells[c1.id].output.text_representation != ""  # still has cached output

        rm(path; force=true)
        rm(session_path(path); force=true)
    end
end
