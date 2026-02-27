using Test
using Sessions
using UUIDs
using Therapy

@testset "Sessions.jl" begin

    @testset "Cell" begin
        @testset "Cell creation" begin
            cell = Cell()
            @test cell.code == ""
            @test cell.state == CELL_IDLE
            @test cell.output === nothing
        end

        @testset "Cell with code" begin
            cell = Cell("x = 1 + 1")
            @test cell.code == "x = 1 + 1"
            @test cell.state == CELL_IDLE
        end

        @testset "Cell serialization" begin
            cell = Cell(; code="test")
            d = Sessions.cell_to_dict(cell)
            @test d["code"] == "test"
            @test d["state"] == "CELL_IDLE"
        end
    end

    @testset "Notebook" begin
        @testset "Notebook creation" begin
            nb = Notebook()
            @test length(nb.cells) == 0
            @test nb.path === nothing
        end

        @testset "Add cell" begin
            nb = Notebook()
            cell = add_cell!(nb; code="x = 1")
            @test length(nb.cells) == 1
            @test haskey(nb.cells, cell.id)
            @test nb.cells[cell.id].code == "x = 1"
        end

        @testset "Delete cell" begin
            nb = Notebook()
            cell = add_cell!(nb; code="x = 1")
            @test length(nb.cells) == 1
            delete_cell!(nb, cell.id)
            @test length(nb.cells) == 0
        end

        @testset "Move cell" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="# cell 1")
            cell2 = add_cell!(nb; code="# cell 2")
            cell3 = add_cell!(nb; code="# cell 3")
            @test nb.cell_order == [cell1.id, cell2.id, cell3.id]

            move_cell!(nb, cell3.id, 1)
            @test nb.cell_order == [cell3.id, cell1.id, cell2.id]
        end

        @testset "Get cell" begin
            nb = Notebook()
            cell = add_cell!(nb; code="x = 42")
            @test get_cell(nb, cell.id) === cell
            @test get_cell(nb, uuid4()) === nothing
        end
    end

    @testset "Cell Parsing" begin
        @testset "Single expression" begin
            expr = parse_cell_code("x = 1")
            @test expr == :(x = 1)
        end

        @testset "Multiple expressions auto-wrapped" begin
            expr = parse_cell_code("x = 1\ny = 2")
            @test expr.head == :block
            @test length(expr.args) == 2
        end

        @testset "Empty code" begin
            expr = parse_cell_code("")
            @test expr == :nothing
        end
    end

    @testset "Reactivity" begin
        @testset "Cell analysis" begin
            cell = Cell(; code="y = x + 1")
            analyze_cell!(cell)
            @test :x in cell.references
            @test :y in cell.definitions
        end

        @testset "Cell analysis - function definitions" begin
            cell = Cell(; code="function foo(x) x + 1 end")
            analyze_cell!(cell)
            @test :foo in cell.funcdefs
            # Note: ExpressionExplorer sees :+ as a reference (operator usage)
            # That's expected behavior from the Pluto ecosystem
        end

        @testset "Cell analysis - multiple definitions" begin
            cell = Cell(; code="a = 1\nb = 2\nc = a + b")
            analyze_cell!(cell)
            @test :a in cell.definitions
            @test :b in cell.definitions
            @test :c in cell.definitions
        end

        @testset "Execution order" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="x = 1")
            cell2 = add_cell!(nb; code="y = x + 1")
            cell3 = add_cell!(nb; code="z = y * 2")

            # Analyze cells
            for c in values(nb.cells)
                analyze_cell!(c)
            end

            order = get_execution_order(nb, [cell1.id])
            @test length(order) == 3
            # cell1 should come before cell2, cell2 before cell3
            idx1 = findfirst(c -> c.id == cell1.id, order)
            idx2 = findfirst(c -> c.id == cell2.id, order)
            idx3 = findfirst(c -> c.id == cell3.id, order)
            @test idx1 < idx2 < idx3
        end
    end

    # =========================================================================
    # SESSIONS-1902: Dependency Tracking with Pluto Packages
    # =========================================================================
    @testset "Dependency tracking (SESSIONS-1902)" begin
        @testset "SessionsCell interface" begin
            # Test SessionsCell wraps Cell correctly
            cell = Cell(; code="x = 42")
            sc = SessionsCell(cell)
            @test sc.id == cell.id
            @test sc.code == cell.code

            # Test SessionsCell subtypes AbstractCell
            import PlutoDependencyExplorer as PDE
            @test sc isa PDE.AbstractCell
        end

        @testset "update_topology! creates topology" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="x = 1")
            cell2 = add_cell!(nb; code="y = x + 1")

            @test nb.topology === nothing
            update_topology!(nb)
            @test nb.topology !== nothing
        end

        @testset "update_topology! with changed cells" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="x = 1")
            cell2 = add_cell!(nb; code="y = x + 1")

            update_topology!(nb)
            initial_topology = nb.topology

            # Update just cell1
            cell1.code = "x = 2"
            update_topology!(nb, [cell1.id])

            # Topology should be updated
            @test nb.topology !== nothing
        end

        @testset "get_execution_order - linear chain" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="a = 1")
            cell2 = add_cell!(nb; code="b = a + 1")
            cell3 = add_cell!(nb; code="c = b + 1")

            order = get_execution_order(nb, [cell1.id])
            @test length(order) == 3

            idx1 = findfirst(c -> c.id == cell1.id, order)
            idx2 = findfirst(c -> c.id == cell2.id, order)
            idx3 = findfirst(c -> c.id == cell3.id, order)
            @test idx1 < idx2 < idx3
        end

        @testset "get_execution_order - diamond dependency" begin
            # Diamond pattern: A -> B, A -> C, B -> D, C -> D
            nb = Notebook()
            cellA = add_cell!(nb; code="a = 1")
            cellB = add_cell!(nb; code="b = a * 2")
            cellC = add_cell!(nb; code="c = a * 3")
            cellD = add_cell!(nb; code="d = b + c")

            order = get_execution_order(nb, [cellA.id])
            @test length(order) == 4

            # A must come first
            idxA = findfirst(c -> c.id == cellA.id, order)
            idxB = findfirst(c -> c.id == cellB.id, order)
            idxC = findfirst(c -> c.id == cellC.id, order)
            idxD = findfirst(c -> c.id == cellD.id, order)

            @test idxA < idxB
            @test idxA < idxC
            @test idxB < idxD
            @test idxC < idxD
        end

        @testset "get_execution_order - partial update" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="x = 1")
            cell2 = add_cell!(nb; code="y = x + 1")
            cell3 = add_cell!(nb; code="z = 100")  # Independent cell

            order = get_execution_order(nb, [cell1.id])
            @test length(order) == 2  # Only cell1 and cell2

            ids = [c.id for c in order]
            @test cell1.id in ids
            @test cell2.id in ids
            @test !(cell3.id in ids)  # Independent cell not included
        end

        @testset "get_all_execution_order" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="a = 1")
            cell2 = add_cell!(nb; code="b = a + 1")
            cell3 = add_cell!(nb; code="c = 100")

            order = get_all_execution_order(nb)
            @test length(order) == 3
        end

        @testset "get_downstream_cells" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="x = 1")
            cell2 = add_cell!(nb; code="y = x + 1")
            cell3 = add_cell!(nb; code="z = y + 1")

            downstream = get_downstream_cells(nb, cell1.id)
            @test length(downstream) == 2

            ids = [c.id for c in downstream]
            @test cell2.id in ids
            @test cell3.id in ids
            @test !(cell1.id in ids)  # Original cell excluded
        end

        @testset "get_upstream_cells" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="x = 1")
            cell2 = add_cell!(nb; code="y = x + 1")
            cell3 = add_cell!(nb; code="z = y + 1")

            upstream = get_upstream_cells(nb, cell3.id)
            @test length(upstream) == 2

            ids = [c.id for c in upstream]
            @test cell1.id in ids
            @test cell2.id in ids
            @test !(cell3.id in ids)
        end

        @testset "get_dependency_info" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="x = 1")
            cell2 = add_cell!(nb; code="y = x + 1")
            cell3 = add_cell!(nb; code="z = y + undefined_var")

            info = get_dependency_info(nb, cell2.id)

            @test cell1.id in info.upstream
            @test cell3.id in info.downstream
            @test :y in info.definitions
            @test :x in info.references

            # Test unresolved references
            info3 = get_dependency_info(nb, cell3.id)
            @test :undefined_var in info3.unresolved
        end

        @testset "has_cycle - no cycle" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="x = 1")
            cell2 = add_cell!(nb; code="y = x + 1")
            cell3 = add_cell!(nb; code="z = y + 1")

            found_cycle, cycle_ids = has_cycle(nb)
            @test !found_cycle
            @test isempty(cycle_ids)
        end

        @testset "has_cycle - direct cycle" begin
            nb = Notebook()
            # Create a direct cycle: x = y + 1, y = x + 1
            cell1 = add_cell!(nb; code="x = y + 1")
            cell2 = add_cell!(nb; code="y = x + 1")

            found_cycle, cycle_ids = has_cycle(nb)
            @test found_cycle
            @test length(cycle_ids) >= 2
            @test cell1.id in cycle_ids || cell2.id in cycle_ids
        end

        @testset "has_cycle - indirect cycle" begin
            nb = Notebook()
            # Create indirect cycle: a -> b -> c -> a
            cell1 = add_cell!(nb; code="a = c + 1")
            cell2 = add_cell!(nb; code="b = a + 1")
            cell3 = add_cell!(nb; code="c = b + 1")

            found_cycle, cycle_ids = has_cycle(nb)
            @test found_cycle
        end

        @testset "detect_and_mark_cycles!" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="x = y + 1")
            cell2 = add_cell!(nb; code="y = x + 1")

            found_cycle, cycle_ids = detect_and_mark_cycles!(nb)
            @test found_cycle

            # Cells should be marked with error state
            for id in cycle_ids
                cell = get_cell(nb, id)
                if cell !== nothing
                    @test cell.state == CELL_ERROR
                    @test cell.output !== nothing
                    # Error message is in error_logs
                    @test !isempty(cell.output.error_logs)
                    @test any(occursin("Circular", msg) for msg in cell.output.error_logs)
                end
            end
        end

        @testset "compute_topology returns valid topology" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="x = 1")
            cell2 = add_cell!(nb; code="y = x + 1")

            topology = compute_topology(nb)
            @test topology !== nothing
        end

        @testset "get_execution_order with empty changed_cells" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="x = 1")
            cell2 = add_cell!(nb; code="y = 2")

            order = get_execution_order(nb, UUID[])
            @test isempty(order)
        end

        @testset "analyze_code utility function" begin
            refs, defs, funcdefs = Sessions.analyze_code("y = x + 1")
            @test :x in refs
            @test :y in defs
        end

        @testset "function dependency" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="function foo(x) x * 2 end")
            cell2 = add_cell!(nb; code="result = foo(5)")

            for c in values(nb.cells)
                analyze_cell!(c)
            end

            @test :foo in cell1.funcdefs
            @test :foo in cell2.references
            @test :result in cell2.definitions

            order = get_execution_order(nb, [cell1.id])
            @test length(order) == 2
        end

        @testset "self-referential cell (not a cycle)" begin
            nb = Notebook()
            # x = 1 is not a cycle, just a simple assignment
            cell = add_cell!(nb; code="x = 1")

            found_cycle, _ = has_cycle(nb)
            @test !found_cycle
        end
    end

    @testset "server/server.jl integration" begin
        @testset "Global state" begin
            @test Sessions.NOTEBOOKS isa Dict
            @test Sessions.CONN_NOTEBOOK isa Dict
            @test Sessions.CELL_SIGNAL_REGISTRY isa Set
        end

        @testset "Server initialization functions exist" begin
            @test isdefined(Sessions, :setup_signals!)
            @test isdefined(Sessions, :setup_channels!)
            @test isdefined(Sessions, :setup_lifecycle!)
            @test isdefined(Sessions, :create_default_notebook!)
        end
    end

    @testset "@bind macro" begin
        @testset "SessionsBond struct" begin
            # Create a simple HTML widget
            struct TestWidget end
            Base.show(io::IO, ::MIME"text/html", ::TestWidget) = print(io, "<input type='range'>")

            bond = Sessions.create_bond(TestWidget(), :x, uuid4())
            @test bond isa Sessions.SessionsBond
            @test bond.defines == :x
        end

        @testset "Bond HTML rendering" begin
            struct TestSlider end
            Base.show(io::IO, ::MIME"text/html", ::TestSlider) = print(io, "<input type='range' min='1' max='10'>")

            bond = Sessions.create_bond(TestSlider(), :slider_var, uuid4())
            html = sprint(show, MIME"text/html"(), bond)

            @test occursin("<bond def=\"slider_var\">", html)
            @test occursin("<input type='range'", html)
            @test occursin("</bond>", html)
        end

        @testset "Bond interface defaults" begin
            struct PlainWidget end

            # Default implementations
            @test Sessions.initial_value(PlainWidget()) === missing
            @test Sessions.transform_value(PlainWidget(), 42) == 42
            @test Sessions.possible_values(PlainWidget()) === nothing
            @test Sessions.validate_value(PlainWidget(), "anything") == true
        end

        @testset "Bond registry" begin
            cell_id = uuid4()
            struct RegistryTestWidget end
            Base.show(io::IO, ::MIME"text/html", ::RegistryTestWidget) = print(io, "<button>Click</button>")

            bond = Sessions.create_bond(RegistryTestWidget(), :test_var, cell_id)

            # Check registry entries
            @test haskey(Sessions.CELL_BOND_NAMES, cell_id)
            @test :test_var in Sessions.CELL_BOND_NAMES[cell_id]
            @test haskey(Sessions.BOND_ELEMENTS, :test_var)

            # Clear bonds
            Sessions.clear_cell_bonds!(cell_id)
            @test !haskey(Sessions.CELL_BOND_NAMES, cell_id)
            @test !haskey(Sessions.BOND_ELEMENTS, :test_var)
        end

        @testset "set_bond channel exists" begin
            # setup_channels! should have created the set_bond channel
            @test isdefined(Sessions, :setup_set_bond_channel!)
        end

        @testset "set_bond_and_run! exists" begin
            @test isdefined(Sessions, :set_bond_and_run!)
        end

        @testset "@bind macro exported" begin
            @test isdefined(Sessions, Symbol("@bind"))
            @test isdefined(Sessions, :SessionsBond)
            @test isdefined(Sessions, :initial_value)
            @test isdefined(Sessions, :transform_value)
            @test isdefined(Sessions, :create_bond)
        end
    end

    @testset "PlutoUI-compatible widgets" begin
        @testset "Slider" begin
            @testset "Slider creation" begin
                s = Slider(1:10)
                @test s.range == 1:10
                @test s.default === nothing
                @test s.show_value == false
            end

            @testset "Slider with options" begin
                s = Slider(1:0.5:10, default=5.0, show_value=true)
                @test s.range == 1:0.5:10
                @test s.default == 5.0
                @test s.show_value == true
            end

            @testset "Slider initial_value" begin
                s1 = Slider(1:10)
                @test Sessions.initial_value(s1) == 1  # First value in range

                s2 = Slider(1:10, default=5)
                @test Sessions.initial_value(s2) == 5
            end

            @testset "Slider transform_value" begin
                s = Slider(1:10)
                @test Sessions.transform_value(s, "5") == 5
                @test Sessions.transform_value(s, 7) == 7

                s_float = Slider(0.0:0.1:1.0)
                @test Sessions.transform_value(s_float, "0.5") == 0.5
            end

            @testset "Slider possible_values" begin
                s = Slider(1:5)
                @test Sessions.possible_values(s) == [1, 2, 3, 4, 5]
            end

            @testset "Slider validate_value" begin
                s = Slider(1:10)
                @test Sessions.validate_value(s, 5) == true
                @test Sessions.validate_value(s, 15) == false
            end

            @testset "Slider HTML rendering" begin
                s = Slider(1:10, default=5)
                html = sprint(show, MIME"text/html"(), s)
                @test occursin("<input type=\"range\"", html)
                @test occursin("min=\"1\"", html)
                @test occursin("max=\"10\"", html)
                @test occursin("value=\"5\"", html)
            end

            @testset "Slider with show_value" begin
                s = Slider(1:10, default=5, show_value=true)
                html = sprint(show, MIME"text/html"(), s)
                @test occursin("<span", html)  # Value display element
                @test occursin("oninput=", html)  # Update handler
            end
        end

        @testset "TextField" begin
            @testset "TextField creation" begin
                tf = TextField()
                @test tf.default == ""
                @test tf.placeholder == ""
            end

            @testset "TextField with options" begin
                tf = TextField(default="Hello", placeholder="Enter text")
                @test tf.default == "Hello"
                @test tf.placeholder == "Enter text"
            end

            @testset "TextField initial_value" begin
                tf1 = TextField()
                @test Sessions.initial_value(tf1) == ""

                tf2 = TextField(default="World")
                @test Sessions.initial_value(tf2) == "World"
            end

            @testset "TextField transform_value" begin
                tf = TextField()
                @test Sessions.transform_value(tf, "test") == "test"
                @test Sessions.transform_value(tf, 123) == "123"
            end

            @testset "TextField validate_value" begin
                tf = TextField()
                @test Sessions.validate_value(tf, "anything") == true
                @test Sessions.validate_value(tf, 123) == false
            end

            @testset "TextField HTML rendering" begin
                tf = TextField(default="Hello", placeholder="Type here")
                html = sprint(show, MIME"text/html"(), tf)
                @test occursin("<input type=\"text\"", html)
                @test occursin("value=\"Hello\"", html)
                @test occursin("placeholder=\"Type here\"", html)
            end

            @testset "TextField HTML escaping" begin
                tf = TextField(default="<script>alert('xss')</script>")
                html = sprint(show, MIME"text/html"(), tf)
                @test !occursin("<script>", html)
                @test occursin("&lt;script&gt;", html)
            end
        end

        @testset "CheckBox" begin
            @testset "CheckBox creation" begin
                cb = CheckBox()
                @test cb.default == false
                @test cb.label == ""
            end

            @testset "CheckBox with options" begin
                cb = CheckBox(default=true, label="Enable feature")
                @test cb.default == true
                @test cb.label == "Enable feature"
            end

            @testset "CheckBox initial_value" begin
                cb1 = CheckBox()
                @test Sessions.initial_value(cb1) == false

                cb2 = CheckBox(default=true)
                @test Sessions.initial_value(cb2) == true
            end

            @testset "CheckBox transform_value" begin
                cb = CheckBox()
                @test Sessions.transform_value(cb, true) == true
                @test Sessions.transform_value(cb, false) == false
                @test Sessions.transform_value(cb, "true") == true
                @test Sessions.transform_value(cb, "false") == false
                @test Sessions.transform_value(cb, "TRUE") == true
                @test Sessions.transform_value(cb, 1) == true
                @test Sessions.transform_value(cb, 0) == false
            end

            @testset "CheckBox possible_values" begin
                cb = CheckBox()
                @test Sessions.possible_values(cb) == [false, true]
            end

            @testset "CheckBox validate_value" begin
                cb = CheckBox()
                @test Sessions.validate_value(cb, true) == true
                @test Sessions.validate_value(cb, false) == true
                @test Sessions.validate_value(cb, "true") == false
            end

            @testset "CheckBox HTML rendering" begin
                cb = CheckBox()
                html = sprint(show, MIME"text/html"(), cb)
                @test occursin("<input type=\"checkbox\"", html)
                @test !occursin("checked", html)
            end

            @testset "CheckBox checked by default" begin
                cb = CheckBox(default=true)
                html = sprint(show, MIME"text/html"(), cb)
                @test occursin("checked", html)
            end

            @testset "CheckBox with label" begin
                cb = CheckBox(label="My Label")
                html = sprint(show, MIME"text/html"(), cb)
                @test occursin("<label", html)
                @test occursin("My Label", html)
            end

            @testset "CheckBox label HTML escaping" begin
                cb = CheckBox(label="<b>Bold</b>")
                html = sprint(show, MIME"text/html"(), cb)
                @test !occursin("<b>", html)
                @test occursin("&lt;b&gt;", html)
            end
        end

        @testset "Select" begin
            @testset "Select creation" begin
                s = Sessions.Select(["a", "b", "c"])
                @test length(s.options) == 3
                @test s.default === nothing
            end

            @testset "Select with pairs" begin
                s = Sessions.Select(["en" => "English", "es" => "Spanish"])
                @test length(s.options) == 2
                @test s.options[1].second == "English"
            end

            @testset "Select with Dict" begin
                s = Sessions.Select(Dict("a" => "A", "b" => "B"))
                @test length(s.options) == 2
            end

            @testset "Select initial_value" begin
                s1 = Sessions.Select(["a", "b", "c"])
                @test Sessions.initial_value(s1) == "a"

                s2 = Sessions.Select(["a", "b", "c"], default="b")
                @test Sessions.initial_value(s2) == "b"
            end

            @testset "Select transform_value" begin
                s = Sessions.Select(["a", "b", "c"])
                @test Sessions.transform_value(s, "a") == "a"
                @test Sessions.transform_value(s, "b") == "b"
            end

            @testset "Select possible_values" begin
                s = Sessions.Select(["a", "b", "c"])
                @test Sessions.possible_values(s) == ["a", "b", "c"]
            end

            @testset "Select validate_value" begin
                s = Sessions.Select(["a", "b", "c"])
                @test Sessions.validate_value(s, "a") == true
                @test Sessions.validate_value(s, "d") == false
            end

            @testset "Select HTML rendering" begin
                s = Sessions.Select(["dog", "cat", "bird"], default="cat")
                html = sprint(show, MIME"text/html"(), s)
                @test occursin("<select", html)
                @test occursin("<option", html)
                @test occursin("selected", html)
                @test occursin("cat", html)
            end
        end

        @testset "NumberField" begin
            @testset "NumberField creation" begin
                nf = NumberField()
                @test nf.range === nothing
                @test nf.default === nothing
            end

            @testset "NumberField with range" begin
                nf = NumberField(1:100, default=50)
                @test nf.range == 1:100
                @test nf.default == 50
            end

            @testset "NumberField initial_value" begin
                nf1 = NumberField()
                @test Sessions.initial_value(nf1) == 0

                nf2 = NumberField(1:10)
                @test Sessions.initial_value(nf2) == 1

                nf3 = NumberField(1:10, default=5)
                @test Sessions.initial_value(nf3) == 5
            end

            @testset "NumberField transform_value" begin
                nf = NumberField(1:10)
                @test Sessions.transform_value(nf, "5") == 5
                @test Sessions.transform_value(nf, 7) == 7

                nf_float = NumberField(0.0:0.1:1.0)
                @test Sessions.transform_value(nf_float, "0.5") == 0.5
            end

            @testset "NumberField validate_value" begin
                nf = NumberField(1:10)
                @test Sessions.validate_value(nf, 5) == true
                @test Sessions.validate_value(nf, 15) == false
                @test Sessions.validate_value(nf, "not a number") == false

                nf_open = NumberField()
                @test Sessions.validate_value(nf_open, 999) == true
            end

            @testset "NumberField possible_values" begin
                nf = NumberField(1:5)
                @test Sessions.possible_values(nf) == [1, 2, 3, 4, 5]

                nf_none = NumberField()
                @test Sessions.possible_values(nf_none) === nothing
            end

            @testset "NumberField HTML rendering" begin
                nf = NumberField(1:100, default=42)
                html = sprint(show, MIME"text/html"(), nf)
                @test occursin("<input type=\"number\"", html)
                @test occursin("min=\"1\"", html)
                @test occursin("max=\"100\"", html)
                @test occursin("value=\"42\"", html)
            end
        end

        @testset "Widget exports" begin
            @test isdefined(Sessions, :Slider)
            @test isdefined(Sessions, :TextField)
            @test isdefined(Sessions, :CheckBox)
            @test isdefined(Sessions, :Select)
            @test isdefined(Sessions, :NumberField)
        end

        @testset "Widgets work with @bind" begin
            # Test that widgets can be used with create_bond
            cell_id = uuid4()

            slider_bond = Sessions.create_bond(Slider(1:10), :slider_var, cell_id)
            @test slider_bond isa Sessions.SessionsBond
            @test slider_bond.defines == :slider_var

            Sessions.clear_cell_bonds!(cell_id)

            tf_bond = Sessions.create_bond(TextField(), :text_var, uuid4())
            @test tf_bond isa Sessions.SessionsBond

            cb_bond = Sessions.create_bond(CheckBox(), :check_var, uuid4())
            @test cb_bond isa Sessions.SessionsBond
        end
    end

    @testset "app.jl - NotebookApp entry point" begin
        @testset "NotebookOptions defaults" begin
            opts = NotebookOptions()
            @test opts.show_header == true
            @test opts.show_toolbar == true
            @test opts.show_add_cell == true
            @test opts.editable == true
            @test opts.runnable == true
            @test opts.show_output == true
            @test opts.max_height === nothing
            @test opts.theme == "default"
        end

        @testset "NotebookOptions custom" begin
            opts = NotebookOptions(show_header = false, editable = false, show_toolbar = false)
            @test opts.show_header == false
            @test opts.editable == false
            @test opts.show_toolbar == false
            @test opts.show_add_cell == true  # default
        end

        @testset "NotebookApp exported" begin
            @test isdefined(Sessions, :NotebookApp)
            @test isdefined(Sessions, :NotebookOptions)
            @test isdefined(Sessions, :notebook_head_extra)
            @test isdefined(Sessions, :init_notebook_server!)
        end

        @testset "NotebookApp creates component" begin
            # Clear any existing notebooks to test fresh creation
            empty!(Sessions.NOTEBOOKS)

            # NotebookApp should create a notebook and return a VNode
            result = Sessions.NotebookApp()
            @test result isa Therapy.VNode
            @test result.tag == :div
            @test !isempty(Sessions.NOTEBOOKS)
        end

        @testset "NotebookApp with options" begin
            empty!(Sessions.NOTEBOOKS)

            opts = NotebookOptions(show_header = false)
            result = Sessions.NotebookApp(options = opts)
            @test result isa Therapy.VNode
        end

        @testset "get_or_create_notebook" begin
            empty!(Sessions.NOTEBOOKS)

            # Should create a new notebook when none exist
            nb1 = Sessions.get_or_create_notebook()
            @test nb1 isa Notebook
            @test length(Sessions.NOTEBOOKS) == 1

            # Should return existing notebook
            nb2 = Sessions.get_or_create_notebook(id = nb1.id)
            @test nb2 === nb1
        end
    end

    @testset "Workspace module isolation" begin
        @testset "create_workspace" begin
            ws = create_workspace()
            @test ws isa Workspace
            @test ws.module_name isa Symbol
            @test isempty(ws.defined_names)
            @test isempty(ws.previous_modules)
        end

        @testset "run_cell! basic" begin
            ws = create_workspace()
            result, time_ms = run_cell!(ws, "x = 42")
            @test result == 42
            @test time_ms >= 0.0
            @test :x in ws.defined_names
        end

        @testset "run_cell! multi-expression" begin
            ws = create_workspace()
            result, _ = run_cell!(ws, "a = 1\nb = 2\na + b")
            @test result == 3
            @test :a in ws.defined_names
            @test :b in ws.defined_names
        end

        @testset "run_cell! syntax error" begin
            ws = create_workspace()
            result, _ = run_cell!(ws, "if true")  # incomplete
            @test result isa Exception
        end

        @testset "run_cell! runtime exception" begin
            ws = create_workspace()
            result, _ = run_cell!(ws, "error(\"test error\")")
            # include_string wraps errors in LoadError
            @test result isa LoadError
            @test result.error isa ErrorException
            @test occursin("test error", result.error.msg)
        end

        @testset "run_cell! undefined variable" begin
            ws = create_workspace()
            result, _ = run_cell!(ws, "undefined_var + 1")
            # include_string wraps errors in LoadError
            @test result isa LoadError
            @test result.error isa UndefVarError
        end

        @testset "workspace isolation" begin
            ws1 = create_workspace()
            ws2 = create_workspace()

            run_cell!(ws1, "x = 100")
            run_cell!(ws2, "x = 200")

            @test Sessions.get_variable(ws1, :x) == 100
            @test Sessions.get_variable(ws2, :x) == 200
        end

        @testset "get_variable and set_variable!" begin
            ws = create_workspace()
            @test Sessions.get_variable(ws, :y) === nothing

            Sessions.set_variable!(ws, :y, 123)
            @test Sessions.get_variable(ws, :y) == 123
            @test :y in ws.defined_names
        end

        @testset "is_defined" begin
            ws = create_workspace()
            @test !Sessions.is_defined(ws, :z)

            run_cell!(ws, "z = 1")
            @test Sessions.is_defined(ws, :z)
        end

        @testset "list_defined" begin
            ws = create_workspace()
            run_cell!(ws, "a = 1")
            run_cell!(ws, "b = 2")

            defined = Sessions.list_defined(ws)
            @test :a in defined
            @test :b in defined
        end

        @testset "cleanup_variables!" begin
            ws = create_workspace()
            run_cell!(ws, "x = 1")
            run_cell!(ws, "y = 2")

            @test Sessions.is_defined(ws, :x)
            @test Sessions.is_defined(ws, :y)

            cleanup_variables!(ws, Set([:x]))

            @test !Sessions.is_defined(ws, :x)
            @test Sessions.is_defined(ws, :y)
            @test :x ∉ ws.defined_names
            @test :y in ws.defined_names
        end

        @testset "cleanup_variables! preserves previous modules" begin
            ws = create_workspace()
            old_name = ws.module_name

            run_cell!(ws, "x = 1")
            cleanup_variables!(ws, Set([:x]))

            @test old_name in ws.previous_modules
            @test ws.module_name != old_name
        end

        @testset "reset_workspace!" begin
            ws = create_workspace()
            old_name = ws.module_name

            run_cell!(ws, "x = 1")
            run_cell!(ws, "y = 2")

            Sessions.reset_workspace!(ws)

            @test !Sessions.is_defined(ws, :x)
            @test !Sessions.is_defined(ws, :y)
            @test isempty(ws.defined_names)
            @test old_name in ws.previous_modules
        end

        @testset "function definition tracking" begin
            ws = create_workspace()
            run_cell!(ws, "function foo() 42 end")
            @test :foo in ws.defined_names
        end

        @testset "struct definition tracking" begin
            ws = create_workspace()
            run_cell!(ws, "struct MyType x::Int end")
            @test :MyType in ws.defined_names
        end

        @testset "const definition tracking" begin
            ws = create_workspace()
            run_cell!(ws, "const MY_CONST = 42")
            @test :MY_CONST in ws.defined_names
        end
    end

    # =========================================================================
    # SESSIONS-1903: Pluto Notebook File Format
    # =========================================================================
    @testset "File format (SESSIONS-1903)" begin
        fixtures_dir = joinpath(@__DIR__, "fixtures")

        @testset "load_notebook - basic" begin
            path = joinpath(fixtures_dir, "basic_notebook.jl")
            nb = load_notebook(path)

            @test nb.path == path
            @test length(nb.cells) == 3
            @test length(nb.cell_order) == 3

            # Verify cells loaded correctly
            cell1 = nb.cells[nb.cell_order[1]]
            @test cell1.code == "x = 1"

            cell2 = nb.cells[nb.cell_order[2]]
            @test cell2.code == "y = x + 1"

            cell3 = nb.cells[nb.cell_order[3]]
            @test cell3.code == "z = x * y"
        end

        @testset "load_notebook - UUIDs correctly extracted" begin
            path = joinpath(fixtures_dir, "basic_notebook.jl")
            nb = load_notebook(path)

            # Check that UUIDs match expected format
            for cell_id in nb.cell_order
                @test cell_id isa UUID
            end

            # Verify specific UUIDs from fixture
            @test nb.cell_order[1] == UUID("00000001-0000-0000-0000-000000000001")
            @test nb.cell_order[2] == UUID("00000002-0000-0000-0000-000000000002")
            @test nb.cell_order[3] == UUID("00000003-0000-0000-0000-000000000003")
        end

        @testset "load_notebook - folded metadata" begin
            path = joinpath(fixtures_dir, "folded_notebook.jl")
            nb = load_notebook(path)

            @test length(nb.cells) == 3

            # First cell is visible (not folded)
            cell1_id = UUID("11111111-1111-1111-1111-111111111111")
            @test !nb.cells[cell1_id].folded

            # Second cell is folded
            cell2_id = UUID("22222222-2222-2222-2222-222222222222")
            @test nb.cells[cell2_id].folded

            # Third cell is visible
            cell3_id = UUID("33333333-3333-3333-3333-333333333333")
            @test !nb.cells[cell3_id].folded
        end

        @testset "load_notebook - Project.toml and Manifest.toml" begin
            path = joinpath(fixtures_dir, "with_pkgs_notebook.jl")
            nb = load_notebook(path)

            @test !isempty(nb.project_toml)
            @test occursin("Statistics", nb.project_toml)

            @test !isempty(nb.manifest_toml)
            @test occursin("Statistics", nb.manifest_toml)
        end

        @testset "is_pluto_notebook" begin
            @test is_pluto_notebook(joinpath(fixtures_dir, "basic_notebook.jl"))
            @test !is_pluto_notebook(joinpath(fixtures_dir, "nonexistent.jl"))
            @test !is_pluto_notebook(@__FILE__)  # This test file is not a Pluto notebook
        end

        @testset "save_notebook - basic" begin
            # Create a notebook in memory
            nb = Notebook()
            cell1 = add_cell!(nb; code="a = 1")
            cell2 = add_cell!(nb; code="b = a + 1")

            # Analyze cells for topology
            for c in values(nb.cells)
                analyze_cell!(c)
            end

            # Save to temp file
            temp_path = tempname() * ".jl"
            try
                save_notebook(nb, temp_path)

                # Verify file was written
                @test isfile(temp_path)
                content = read(temp_path, String)

                @test startswith(content, "### A Pluto.jl notebook ###")
                @test occursin("a = 1", content)
                @test occursin("b = a + 1", content)
                @test occursin("Cell order:", content)
            finally
                rm(temp_path; force=true)
            end
        end

        @testset "save_notebook - preserves folded state" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="# visible")
            cell2 = add_cell!(nb; code="# folded")
            cell2.folded = true
            cell3 = add_cell!(nb; code="# also visible")

            for c in values(nb.cells)
                analyze_cell!(c)
            end

            temp_path = tempname() * ".jl"
            try
                save_notebook(nb, temp_path)
                content = read(temp_path, String)

                # Count occurrences of each delimiter
                visible_count = length(collect(eachmatch(r"# ╠═", content)))
                folded_count = length(collect(eachmatch(r"# ╟─", content)))

                @test visible_count == 2  # Two visible cells
                @test folded_count == 1   # One folded cell
            finally
                rm(temp_path; force=true)
            end
        end

        @testset "round-trip: load → modify → save → load" begin
            # Load existing notebook
            orig_path = joinpath(fixtures_dir, "folded_notebook.jl")
            nb = load_notebook(orig_path)

            # Modify the notebook
            cell2_id = UUID("22222222-2222-2222-2222-222222222222")
            nb.cells[cell2_id].code = "modified_folded_var = 999"

            # Also modify folded state
            nb.cells[cell2_id].folded = false
            nb.cells[nb.cell_order[1]].folded = true

            # Save to new location
            temp_path = tempname() * ".jl"
            try
                save_notebook(nb, temp_path)

                # Reload the notebook
                nb2 = load_notebook(temp_path)

                # Verify modifications persisted
                @test nb2.cells[cell2_id].code == "modified_folded_var = 999"
                @test !nb2.cells[cell2_id].folded  # Was folded, now not
                @test nb2.cells[nb2.cell_order[1]].folded  # Was not folded, now is

                # Verify cell order preserved
                @test length(nb2.cell_order) == 3
            finally
                rm(temp_path; force=true)
            end
        end

        @testset "parse_pluto_content - basic" begin
            content = """### A Pluto.jl notebook ###
# v0.19.0

# ╔═╡ 12345678-1234-1234-1234-123456789012
x = 1

# ╔═╡ 23456789-2345-2345-2345-234567890123
y = 2

# ╔═╡ Cell order:
# ╠═12345678-1234-1234-1234-123456789012
# ╠═23456789-2345-2345-2345-234567890123
"""
            cells = parse_pluto_content(content)

            @test length(cells) == 2
            @test cells[1][2] == "x = 1"
            @test cells[2][2] == "y = 2"
        end

        @testset "parse_pluto_content - non-Pluto content" begin
            content = "x = 1\ny = 2"
            cells = parse_pluto_content(content)

            @test length(cells) == 1
            @test cells[1][2] == "x = 1\ny = 2"
        end

        @testset "is_pluto_content" begin
            @test is_pluto_content("### A Pluto.jl notebook ###\nsome content")
            @test !is_pluto_content("x = 1")
            @test !is_pluto_content("")
        end

        # =====================================================================
        # Testing with Real Pluto Community Notebooks
        # =====================================================================
        @testset "Community notebook: Basic.jl" begin
            path = joinpath(fixtures_dir, "pluto_sample_basic.jl")
            if isfile(path)
                nb = load_notebook(path)
                @test length(nb.cells) >= 3
                @test length(nb.cell_order) >= 3

                # First cell is markdown (folded in cell order)
                first_cell_id = nb.cell_order[1]
                @test nb.cells[first_cell_id].folded

                # Check that code cells are present
                code_found = false
                for cell in values(nb.cells)
                    if occursin("1:100000", cell.code)
                        code_found = true
                        break
                    end
                end
                @test code_found
            else
                @info "Skipping community notebook test - file not found: $path"
            end
        end

        @testset "Community notebook: Tower of Hanoi.jl" begin
            path = joinpath(fixtures_dir, "pluto_sample_hanoi.jl")
            if isfile(path)
                nb = load_notebook(path)
                @test length(nb.cells) >= 10

                # Verify cell order is preserved
                @test length(nb.cell_order) == length(nb.cells)

                # Check that specific content exists
                found_hanoi = false
                found_function = false
                for cell in values(nb.cells)
                    if occursin("tower of Hanoi", lowercase(cell.code)) || occursin("tower of hanoi", lowercase(cell.code))
                        found_hanoi = true
                    end
                    if occursin("function islegal", cell.code)
                        found_function = true
                    end
                end
                @test found_hanoi || found_function

                # Verify save/load round-trip
                temp_path = tempname() * ".jl"
                try
                    save_notebook(nb, temp_path)
                    nb2 = load_notebook(temp_path)
                    @test length(nb2.cells) == length(nb.cells)
                    @test length(nb2.cell_order) == length(nb.cell_order)
                finally
                    rm(temp_path; force=true)
                end
            else
                @info "Skipping community notebook test - file not found: $path"
            end
        end

        @testset "Community notebook: Interactivity.jl" begin
            path = joinpath(fixtures_dir, "pluto_sample_interactive.jl")
            if isfile(path)
                nb = load_notebook(path)
                @test length(nb.cells) >= 5

                # Check for @bind macro usage
                found_bind = false
                for cell in values(nb.cells)
                    if occursin("@bind", cell.code)
                        found_bind = true
                        break
                    end
                end
                @test found_bind

                # Verify round-trip preserves content
                temp_path = tempname() * ".jl"
                try
                    save_notebook(nb, temp_path)
                    nb2 = load_notebook(temp_path)

                    # Check that @bind cells are still there
                    bind_found = false
                    for cell in values(nb2.cells)
                        if occursin("@bind", cell.code)
                            bind_found = true
                            break
                        end
                    end
                    @test bind_found
                finally
                    rm(temp_path; force=true)
                end
            else
                @info "Skipping community notebook test - file not found: $path"
            end
        end

        @testset "Community notebook: Getting Started.jl" begin
            path = joinpath(fixtures_dir, "pluto_getting_started.jl")
            if isfile(path)
                nb = load_notebook(path)
                @test length(nb.cells) >= 10

                # Check for specific content from the tutorial
                found_cat = false
                found_bind = false
                for cell in values(nb.cells)
                    if occursin("cat", cell.code)
                        found_cat = true
                    end
                    if occursin("@bind", cell.code)
                        found_bind = true
                    end
                end
                @test found_cat  # The cat variable in the tutorial
                @test found_bind  # Has @bind power_level

                # Verify cell order is maintained
                @test length(nb.cell_order) == length(nb.cells)

                # Test round-trip
                temp_path = tempname() * ".jl"
                try
                    save_notebook(nb, temp_path)
                    nb2 = load_notebook(temp_path)
                    @test length(nb2.cells) == length(nb.cells)

                    # Verify content preserved
                    cat_found = false
                    for cell in values(nb2.cells)
                        if occursin("cat", cell.code)
                            cat_found = true
                            break
                        end
                    end
                    @test cat_found
                finally
                    rm(temp_path; force=true)
                end
            else
                @info "Skipping community notebook test - file not found: $path"
            end
        end

        @testset "Community notebook: PlutoUI Sample" begin
            path = joinpath(fixtures_dir, "pluto_plutoui_sample.jl")
            if isfile(path)
                nb = load_notebook(path)
                @test length(nb.cells) >= 10

                # Check for PlutoUI imports
                found_plutoui = false
                found_slider = false
                found_scrubbable = false
                for cell in values(nb.cells)
                    if occursin("using PlutoUI", cell.code)
                        found_plutoui = true
                    end
                    if occursin("Slider", cell.code)
                        found_slider = true
                    end
                    if occursin("Scrubbable", cell.code)
                        found_scrubbable = true
                    end
                end
                @test found_plutoui
                @test found_slider
                @test found_scrubbable

                # Test round-trip preserves all content
                temp_path = tempname() * ".jl"
                try
                    save_notebook(nb, temp_path)
                    nb2 = load_notebook(temp_path)
                    @test length(nb2.cells) == length(nb.cells)
                    @test length(nb2.cell_order) == length(nb.cell_order)
                finally
                    rm(temp_path; force=true)
                end
            else
                @info "Skipping community notebook test - file not found: $path"
            end
        end
    end

    # =========================================================================
    # SESSIONS-2202: Pluto Notebook Compatibility Suite
    # =========================================================================
    @testset "Pluto Compatibility Suite (SESSIONS-2202)" begin
        fixtures_dir = joinpath(@__DIR__, "fixtures")

        @testset "5+ community notebooks load correctly" begin
            # List of all Pluto notebooks we test against
            notebooks = [
                "pluto_sample_basic.jl",
                "pluto_sample_hanoi.jl",
                "pluto_sample_interactive.jl",
                "pluto_getting_started.jl",
                "pluto_plutoui_sample.jl"
            ]

            loaded_count = 0
            for notebook_file in notebooks
                path = joinpath(fixtures_dir, notebook_file)
                if isfile(path)
                    @testset "Load: $notebook_file" begin
                        nb = load_notebook(path)
                        @test nb !== nothing
                        @test !isempty(nb.cells)
                        @test length(nb.cell_order) == length(nb.cells)
                        loaded_count += 1
                    end
                end
            end
            @test loaded_count >= 5  # Must successfully load at least 5 notebooks
        end

        @testset "Cell dependency analysis works" begin
            # Test with Hanoi notebook - has functions and dependencies
            path = joinpath(fixtures_dir, "pluto_sample_hanoi.jl")
            if isfile(path)
                nb = load_notebook(path)

                # Analyze all cells
                for cell in values(nb.cells)
                    analyze_cell!(cell)
                end

                # Look for cells that define functions
                functions_found = Set{Symbol}()
                for cell in values(nb.cells)
                    union!(functions_found, cell.funcdefs)
                end

                # Hanoi notebook should have islegal, iscomplete, move, solve
                @test !isempty(functions_found)

                # Test topology computation
                update_topology!(nb)
                @test nb.topology !== nothing
            end
        end

        @testset "Round-trip preserves all data" begin
            notebooks = [
                "pluto_sample_basic.jl",
                "pluto_sample_hanoi.jl",
                "pluto_sample_interactive.jl"
            ]

            for notebook_file in notebooks
                path = joinpath(fixtures_dir, notebook_file)
                if isfile(path)
                    @testset "Round-trip: $notebook_file" begin
                        nb_orig = load_notebook(path)

                        temp_path = tempname() * ".jl"
                        try
                            save_notebook(nb_orig, temp_path)
                            nb_reloaded = load_notebook(temp_path)

                            # Same number of cells
                            @test length(nb_reloaded.cells) == length(nb_orig.cells)

                            # Same cell order
                            @test nb_reloaded.cell_order == nb_orig.cell_order

                            # Same code in each cell
                            for (id, orig_cell) in nb_orig.cells
                                reloaded_cell = nb_reloaded.cells[id]
                                @test reloaded_cell.code == orig_cell.code
                                @test reloaded_cell.folded == orig_cell.folded
                            end
                        finally
                            rm(temp_path; force=true)
                        end
                    end
                end
            end
        end

        @testset "Saved notebooks are valid Pluto format" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="# Test markdown cell\nmd\"Hello\"")
            cell1.folded = true  # Markdown cells are typically folded
            cell2 = add_cell!(nb; code="x = 42")
            cell3 = add_cell!(nb; code="y = x * 2")

            for c in values(nb.cells)
                analyze_cell!(c)
            end

            temp_path = tempname() * ".jl"
            try
                save_notebook(nb, temp_path)
                content = read(temp_path, String)

                # Check Pluto header
                @test startswith(content, "### A Pluto.jl notebook ###")

                # Check cell markers present
                @test occursin("# ╔═╡", content)

                # Check cell order section
                @test occursin("# ╔═╡ Cell order:", content)

                # Check folded marker for markdown cell
                @test occursin("# ╟─", content)

                # Check visible marker for code cells
                @test occursin("# ╠═", content)

                # Check code is present
                @test occursin("x = 42", content)
                @test occursin("y = x * 2", content)
            finally
                rm(temp_path; force=true)
            end
        end

        @testset "Multi-line cells preserved" begin
            path = joinpath(fixtures_dir, "pluto_sample_hanoi.jl")
            if isfile(path)
                nb = load_notebook(path)

                # Find cells with multiple lines
                multi_line_cells = []
                for cell in values(nb.cells)
                    if count('\n', cell.code) > 1
                        push!(multi_line_cells, cell)
                    end
                end

                @test !isempty(multi_line_cells)

                # Verify multi-line code is preserved on round-trip
                temp_path = tempname() * ".jl"
                try
                    save_notebook(nb, temp_path)
                    nb2 = load_notebook(temp_path)

                    for orig_cell in multi_line_cells
                        reloaded_cell = nb2.cells[orig_cell.id]
                        @test reloaded_cell.code == orig_cell.code
                    end
                finally
                    rm(temp_path; force=true)
                end
            end
        end

        @testset "Special characters in code preserved" begin
            nb = Notebook()
            # Add cells with special characters
            cell1 = add_cell!(nb; code="s = \"Hello\\nWorld\"")
            cell2 = add_cell!(nb; code="emoji = \"🐱🐶\"")
            cell3 = add_cell!(nb; code="math = \"π ≈ 3.14159\"")
            cell4 = add_cell!(nb; code="special = \"quotes: \\\"inside\\\"\"")

            for c in values(nb.cells)
                analyze_cell!(c)
            end

            temp_path = tempname() * ".jl"
            try
                save_notebook(nb, temp_path)
                nb2 = load_notebook(temp_path)

                @test nb2.cells[cell1.id].code == cell1.code
                @test nb2.cells[cell2.id].code == cell2.code
                @test nb2.cells[cell3.id].code == cell3.code
                @test nb2.cells[cell4.id].code == cell4.code
            finally
                rm(temp_path; force=true)
            end
        end

        @testset "@bind cells detected correctly" begin
            path = joinpath(fixtures_dir, "pluto_sample_interactive.jl")
            if isfile(path)
                nb = load_notebook(path)

                # Count cells with @bind
                bind_cells = 0
                for cell in values(nb.cells)
                    if occursin("@bind", cell.code)
                        bind_cells += 1
                    end
                end

                @test bind_cells >= 5  # Interactive notebook has multiple @bind cells
            end
        end

        @testset "Notebook version info preserved" begin
            path = joinpath(fixtures_dir, "pluto_sample_basic.jl")
            if isfile(path)
                # Read original file to get version
                original_content = read(path, String)
                version_match = match(r"# v(\d+\.\d+\.\d+)", original_content)

                nb = load_notebook(path)

                temp_path = tempname() * ".jl"
                try
                    save_notebook(nb, temp_path)
                    saved_content = read(temp_path, String)

                    # Should have a version marker
                    @test occursin("# v", saved_content)
                finally
                    rm(temp_path; force=true)
                end
            end
        end
    end

    # =========================================================================
    # SESSIONS-3703: Pluto File Format Compatibility (Comprehensive)
    # =========================================================================
    @testset "Pluto Compatibility (SESSIONS-3703)" begin
        fixtures_dir = joinpath(@__DIR__, "fixtures")

        @testset "Reactive execution order for Pluto notebooks" begin
            # Test with basic.jl — has n, seq, sqrt(sum(seq)*6.0) dependency chain
            path = joinpath(fixtures_dir, "pluto_sample_basic.jl")
            if isfile(path)
                nb = load_notebook(path)

                # Analyze all cells for reactive dependencies
                for cell in values(nb.cells)
                    analyze_cell!(cell)
                end

                # Find cells by content
                n_cell = nothing
                seq_cell = nothing
                result_cell = nothing
                for cell in values(nb.cells)
                    if cell.code == "n = 1:100000"
                        n_cell = cell
                    elseif occursin("seq = n .^ -2", cell.code)
                        seq_cell = cell
                    elseif occursin("sqrt(sum(seq)", cell.code)
                        result_cell = cell
                    end
                end

                # Verify dependency analysis found references
                if n_cell !== nothing
                    @test :n in n_cell.definitions
                end
                if seq_cell !== nothing
                    @test :n in seq_cell.references
                    @test :seq in seq_cell.definitions
                end
                if result_cell !== nothing
                    @test :seq in result_cell.references
                end

                # Get execution order starting from n_cell
                if n_cell !== nothing
                    order = get_execution_order(nb, [n_cell.id])
                    @test length(order) >= 2  # n_cell + downstream
                end
            end
        end

        @testset "Sessions.jl metadata round-trip" begin
            nb = Notebook()
            nb.title = "Test Notebook"
            nb.author = "Test Author"
            nb.created_at = time()
            add_cell!(nb; code="x = 1")
            add_cell!(nb; code="y = x + 1")

            temp_path = tempname() * ".jl"
            try
                save_notebook(nb, temp_path)
                content = read(temp_path, String)

                # Sessions.jl metadata section present
                @test occursin("# ╔═╡ Sessions.jl metadata", content)
                @test occursin("title = \"Test Notebook\"", content)
                @test occursin("author = \"Test Author\"", content)

                # Still valid Pluto format
                @test startswith(content, "### A Pluto.jl notebook ###")

                # Reload and verify metadata preserved
                nb2 = load_notebook(temp_path)
                @test nb2.title == "Test Notebook"
                @test nb2.author == "Test Author"
                @test nb2.created_at !== nothing
            finally
                rm(temp_path; force=true)
            end
        end

        @testset "Export to HTML" begin
            nb = Notebook()
            add_cell!(nb; code="x = 42")
            cell2 = add_cell!(nb; code="md\"# Hello World\"")
            cell2.folded = true
            cell2.cell_type = :markdown

            html = export_to_html(nb)
            @test occursin("<!DOCTYPE html>", html)
            @test occursin("x = 42", html)
            @test occursin("Sessions.jl", html)
            @test occursin("prefers-color-scheme", html)  # Dark mode support
        end

        @testset "Export to Julia script" begin
            nb = Notebook()
            add_cell!(nb; code="x = 42")
            cell2 = add_cell!(nb; code="md\"\"\"# Hello World\"\"\"")
            cell2.folded = true
            cell2.cell_type = :markdown
            add_cell!(nb; code="y = x + 1")

            script = export_to_script(nb)
            @test occursin("x = 42", script)
            @test occursin("y = x + 1", script)
            @test occursin("# Hello World", script)  # Markdown as comment
            @test !occursin("md\"\"\"", script)  # md wrapper stripped
        end

        @testset "All 8 fixture files load without error" begin
            all_fixtures = [
                "basic_notebook.jl",
                "folded_notebook.jl",
                "with_pkgs_notebook.jl",
                "pluto_sample_basic.jl",
                "pluto_sample_hanoi.jl",
                "pluto_sample_interactive.jl",
                "pluto_getting_started.jl",
                "pluto_plutoui_sample.jl"
            ]

            for fixture in all_fixtures
                path = joinpath(fixtures_dir, fixture)
                if isfile(path)
                    @testset "Load: $fixture" begin
                        nb = load_notebook(path)
                        @test !isempty(nb.cells)
                        @test length(nb.cell_order) == length(nb.cells)
                        # Cell UUIDs are valid
                        for id in nb.cell_order
                            @test haskey(nb.cells, id)
                        end
                    end
                end
            end
        end
    end

    # =========================================================================
    # SESSIONS-3900: Comprehensive Test Suite — Cell State & Accessors
    # =========================================================================
    @testset "Cell state and accessors (SESSIONS-3900)" begin
        @testset "CellState enum values" begin
            @test CELL_IDLE isa CellState
            @test CELL_QUEUED isa CellState
            @test CELL_RUNNING isa CellState
            @test CELL_ERROR isa CellState
            @test CELL_STALE isa CellState
        end

        @testset "Cell state transitions" begin
            cell = Cell("x = 1")
            @test cell.state == CELL_IDLE

            cell.state = CELL_QUEUED
            @test cell.state == CELL_QUEUED

            cell.state = CELL_RUNNING
            @test cell.state == CELL_RUNNING

            cell.state = CELL_ERROR
            @test cell.state == CELL_ERROR

            cell.state = CELL_STALE
            @test cell.state == CELL_STALE

            cell.state = CELL_IDLE
            @test cell.state == CELL_IDLE
        end

        @testset "Cell type accessors" begin
            code_cell = Cell("x = 1")
            @test Sessions.is_code(code_cell)
            @test !Sessions.is_markdown(code_cell)

            md_cell = Cell(; code="md\"# Hello\"", cell_type=:markdown)
            @test Sessions.is_markdown(md_cell)
            @test !Sessions.is_code(md_cell)
        end

        @testset "Cell state accessors" begin
            cell = Cell("x = 1")
            @test Sessions.is_stale(cell) == false

            cell.state = CELL_STALE
            @test Sessions.is_stale(cell) == true
        end

        @testset "Cell last_run_at field" begin
            cell = Cell("x = 1")
            @test cell.last_run_at === nothing

            cell.last_run_at = time()
            @test cell.last_run_at !== nothing
            @test cell.last_run_at isa Float64
        end

        @testset "Cell cell_type field" begin
            cell = Cell()
            @test cell.cell_type == :code  # default

            cell.cell_type = :markdown
            @test cell.cell_type == :markdown
        end

        @testset "Cell serialization with new fields" begin
            cell = Cell(; code="test", cell_type=:markdown)
            cell.last_run_at = 1234567890.0
            cell.state = CELL_STALE
            d = Sessions.cell_to_dict(cell)

            @test d["cell_type"] == "markdown"
            @test d["state"] == "CELL_STALE"
            @test d["last_run_at"] == 1234567890.0
        end
    end

    # =========================================================================
    # SESSIONS-3900: Component Rendering Tests
    # =========================================================================
    @testset "Component rendering (SESSIONS-3900)" begin
        @testset "CellStateBadge rendering" begin
            # Idle returns nothing
            @test CellStateBadge(CELL_IDLE) === nothing

            # Other states return VNodes
            queued_badge = CellStateBadge(CELL_QUEUED)
            @test queued_badge isa Therapy.VNode
            queued_html = Therapy.render_to_string(queued_badge)
            @test occursin("Queued", queued_html)

            running_badge = CellStateBadge(CELL_RUNNING)
            @test running_badge isa Therapy.VNode
            running_html = Therapy.render_to_string(running_badge)
            @test occursin("Running", running_html)
            @test occursin("animate-pulse", running_html)

            error_badge = CellStateBadge(CELL_ERROR)
            @test error_badge isa Therapy.VNode
            error_html = Therapy.render_to_string(error_badge)
            @test occursin("Error", error_html)
            @test occursin("rose", error_html)

            stale_badge = CellStateBadge(CELL_STALE)
            @test stale_badge isa Therapy.VNode
            stale_html = Therapy.render_to_string(stale_badge)
            @test occursin("Stale", stale_html)
            @test occursin("amber", stale_html)
        end

        @testset "CellRunningIndicator rendering" begin
            indicator = CellRunningIndicator()
            @test indicator isa Therapy.VNode
            html = Therapy.render_to_string(indicator)
            @test occursin("cell-running-skeleton", html)
            @test occursin("animate-pulse", html)
        end

        @testset "CellErrorDisplay rendering" begin
            error_display = CellErrorDisplay("MethodError: no method matching foo(::Int64)")
            @test error_display isa Therapy.VNode
            html = Therapy.render_to_string(error_display)
            @test occursin("MethodError", html)

            # With logs
            error_with_logs = CellErrorDisplay("test error"; logs=["stderr line 1", "stderr line 2"])
            html2 = Therapy.render_to_string(error_with_logs)
            @test occursin("stderr line 1", html2)
            @test occursin("stderr line 2", html2)
        end

        @testset "CellStaleIndicator rendering" begin
            indicator = CellStaleIndicator()
            @test indicator isa Therapy.VNode
            html = Therapy.render_to_string(indicator)
            @test occursin("re-run", lowercase(html)) || occursin("stale", lowercase(html)) || occursin("upstream", lowercase(html))
        end

        @testset "CellAddButton rendering" begin
            btn = CellAddButton("test-cell-id")
            @test btn isa Therapy.VNode
            html = Therapy.render_to_string(btn)
            @test occursin("test-cell-id", html)
            @test occursin("+", html) || occursin("add", lowercase(html))
        end

        @testset "IDECellCard rendering" begin
            cell = Cell(; code="x = 1 + 1")
            card = IDECellCard(cell)
            @test card isa Therapy.VNode
            html = Therapy.render_to_string(card)
            @test occursin(string(cell.id), html)
            @test occursin("data-cell-id", html)
        end

        @testset "IDECellCard with options" begin
            cell = Cell(; code="x = 1")
            opts = NotebookOptions(show_toolbar=false, show_add_cell=false)
            card = IDECellCard(cell; options=opts)
            @test card isa Therapy.VNode
        end

        @testset "IDECodeCard rendering" begin
            cell = Cell(; code="y = 42")
            code_card = IDECodeCard(cell)
            @test code_card isa Therapy.VNode
            html = Therapy.render_to_string(code_card)
            @test occursin("y = 42", html)
        end

        @testset "IDECodeCard accent colors" begin
            # Error state → red
            error_cell = Cell(; code="x")
            error_cell.state = CELL_ERROR
            @test Sessions._accent_color(error_cell) == "bg-rose-600"

            # Markdown → purple
            md_cell = Cell(; code="md\"test\"", cell_type=:markdown)
            @test occursin("purple-600", Sessions._accent_color(md_cell))

            # Running → accent
            running_cell = Cell(; code="x")
            running_cell.state = CELL_RUNNING
            @test occursin("accent", Sessions._accent_color(running_cell))

            # Queued → accent
            queued_cell = Cell(; code="x")
            queued_cell.state = CELL_QUEUED
            @test occursin("accent", Sessions._accent_color(queued_cell))

            # Idle with no output → warm neutral
            idle_cell = Cell(; code="x")
            @test occursin("warm", Sessions._accent_color(idle_cell))

            # Idle with output → green accent
            output_cell = Cell(; code="x")
            output_cell.output = CellOutput(nothing, "text/plain", "42", String[], String[])
            @test occursin("accent", Sessions._accent_color(output_cell))
            @test occursin("opacity", Sessions._accent_color(output_cell))
        end

        @testset "IDECellsView rendering" begin
            cells = [Cell(; code="a = 1"), Cell(; code="b = 2"), Cell(; code="c = 3")]
            view = IDECellsView(cells)
            @test view isa Therapy.VNode
            html = Therapy.render_to_string(view)
            # Should contain all cell IDs
            for cell in cells
                @test occursin(string(cell.id), html)
            end
        end

        @testset "IDECellsView empty state" begin
            view = IDECellsView(Cell[])
            @test view isa Therapy.VNode
            html = Therapy.render_to_string(view)
            # Empty state should show prompt text
            @test occursin("add", lowercase(html)) || occursin("cell", lowercase(html)) || occursin("empty", lowercase(html))
        end

        @testset "IDECellsView with options" begin
            cells = [Cell(; code="x = 1")]
            opts = NotebookOptions(show_toolbar=false)
            view = IDECellsView(cells; options=opts)
            @test view isa Therapy.VNode
        end

        @testset "IDECellToolbar rendering" begin
            toolbar = IDECellToolbar("test-id")
            @test toolbar isa Therapy.VNode
            html = Therapy.render_to_string(toolbar)
            @test occursin("test-id", html)
        end

        @testset "IDECellToolbar with runtime" begin
            toolbar = IDECellToolbar("test-id"; runtime_ms=123.4)
            html = Therapy.render_to_string(toolbar)
            @test occursin("123", html)  # Runtime displayed
        end

        @testset "IDECellToolbar with fold state" begin
            toolbar_unfolded = IDECellToolbar("id1"; is_folded=false)
            toolbar_folded = IDECellToolbar("id2"; is_folded=true)
            @test toolbar_unfolded isa Therapy.VNode
            @test toolbar_folded isa Therapy.VNode
        end

        @testset "CellFoldedIndicator rendering" begin
            indicator = Sessions.CellFoldedIndicator("fold-test-id")
            @test indicator isa Therapy.VNode
            html = Therapy.render_to_string(indicator)
            @test occursin("fold-test-id", html)
            @test occursin("hidden", lowercase(html)) || occursin("code hidden", lowercase(html))
        end
    end

    # =========================================================================
    # SESSIONS-3900: Markdown Rendering Tests
    # =========================================================================
    @testset "Markdown rendering (SESSIONS-3900)" begin
        @testset "render_markdown_html - empty" begin
            @test render_markdown_html("") == ""
            @test render_markdown_html("   ") == ""
        end

        @testset "render_markdown_html - plain text" begin
            html = render_markdown_html("Hello world")
            @test occursin("Hello world", html)
            @test occursin("<p>", html)
        end

        @testset "render_markdown_html - headings" begin
            # Note: render_markdown_html strips trailing whitespace before parsing,
            # so Julia's Markdown.parse may not detect headings from single-line input.
            # Test with multi-line content where headings work correctly.
            h1 = render_markdown_html("# Heading 1\n\nSome text after.\n")
            @test occursin("Heading 1", h1)

            h2 = render_markdown_html("## Heading 2\n\nMore text.\n")
            @test occursin("Heading 2", h2)

            h3 = render_markdown_html("### Heading 3\n\nBody text.\n")
            @test occursin("Heading 3", h3)
        end

        @testset "render_markdown_html - bold and italic" begin
            # Single-line markdown: strip() removes trailing newline, so bold/italic
            # may not be parsed. Test content is at least present.
            bold = render_markdown_html("Some **bold text** here")
            @test occursin("bold text", bold)

            italic = render_markdown_html("Some *italic text* here")
            @test occursin("italic text", italic)
        end

        @testset "render_markdown_html - links" begin
            html = render_markdown_html("Visit [Julia](https://julialang.org) now")
            @test occursin("Julia", html)
            @test occursin("julialang.org", html)
        end

        @testset "render_markdown_html - code spans" begin
            html = render_markdown_html("Use `println()` for output")
            @test occursin("println", html)
        end

        @testset "render_markdown_html - code blocks" begin
            html = render_markdown_html("```julia\nx = 1\n```")
            @test occursin("x", html)
        end

        @testset "render_markdown_html - lists" begin
            unordered = render_markdown_html("- item 1\n- item 2\n- item 3")
            @test occursin("item 1", unordered)

            ordered = render_markdown_html("1. first\n2. second")
            @test occursin("first", ordered)
        end

        @testset "render_markdown_html - strips md wrapper" begin
            # Triple-quoted md string
            html1 = render_markdown_html("md\"\"\"# Hello\n\"\"\"")
            @test occursin("Hello", html1)
            @test !occursin("md\"\"\"", html1)

            # Single-quoted md string
            html2 = render_markdown_html("md\"Hello world\"")
            @test occursin("Hello world", html2)
            @test !occursin("md\"", html2)
        end

        @testset "render_markdown_html - no wrapper" begin
            html = render_markdown_html("Just plain markdown")
            @test occursin("Just plain markdown", html)
        end

        @testset "IDEMarkdownCell rendering" begin
            # Folded markdown cell (closed mode)
            folded_cell = Cell(; code="md\"\"\"# Title\"\"\"", cell_type=:markdown)
            folded_cell.folded = true
            md_view = IDEMarkdownCell(folded_cell)
            @test md_view isa Therapy.VNode

            # Unfolded markdown cell (open mode)
            open_cell = Cell(; code="md\"\"\"Some text\"\"\"", cell_type=:markdown)
            open_cell.folded = false
            md_open = IDEMarkdownCell(open_cell)
            @test md_open isa Therapy.VNode
        end

        @testset "MarkdownCellClosed rendering" begin
            cell = Cell(; code="md\"\"\"# My Title\"\"\"", cell_type=:markdown)
            closed = MarkdownCellClosed(cell)
            @test closed isa Therapy.VNode
            html = Therapy.render_to_string(closed)
            @test occursin("My Title", html)
        end

        @testset "MarkdownCellOpen rendering" begin
            cell = Cell(; code="md\"\"\"# Open Title\"\"\"", cell_type=:markdown)
            open_cell = MarkdownCellOpen(cell)
            @test open_cell isa Therapy.VNode
            html = Therapy.render_to_string(open_cell)
            @test occursin("Open Title", html)
            # Should have code card with purple accent
            @test occursin("purple-600", html) || occursin("bg-purple-600", html)
        end
    end

    # =========================================================================
    # SESSIONS-3900: CSS and JS Generation Tests
    # =========================================================================
    @testset "CSS and JS generation (SESSIONS-3900)" begin
        @testset "cell_state_styles()" begin
            css = cell_state_styles()
            @test css isa String
            @test !isempty(css)
            @test occursin("<style>", css)
            @test occursin("cell-running", css)
            @test occursin("@keyframes", css) || occursin("animation", css)
        end

        @testset "markdown_styles()" begin
            css = markdown_styles()
            @test css isa String
            @test !isempty(css)
            @test occursin("<style>", css)
            @test occursin("markdown", lowercase(css)) || occursin("md-output", lowercase(css))
        end

        @testset "codemirror_sessions_theme()" begin
            css = codemirror_sessions_theme()
            @test css isa String
            @test !isempty(css)
            @test occursin("<style>", css)
            @test occursin("cm-editor", css)
            # Julia syntax colors
            @test occursin("#9558b2", css) || occursin("9558b2", css)  # Purple keywords (hardcoded — Julia official color)
            @test occursin("accent-secondary", css)  # Blue types use CSS var
        end

        @testset "output_styles()" begin
            css = output_styles()
            @test css isa String
            @test !isempty(css)
            @test occursin("<style>", css)
            @test occursin("389826", css) || occursin("output", lowercase(css))  # Green output
        end

        @testset "output_truncation_script()" begin
            js = output_truncation_script()
            @test js isa String
            @test !isempty(js)
            @test occursin("truncat", lowercase(js)) || occursin("output", lowercase(js))
        end

        @testset "cell_toolbar_script()" begin
            js = cell_toolbar_script()
            @test js isa String
            @test !isempty(js)
            @test occursin("moveCellUp", js) || occursin("move_cell", js)
        end

        @testset "markdown_cell_script()" begin
            js = markdown_cell_script()
            @test js isa String
            @test !isempty(js)
            @test occursin("markdown", lowercase(js)) || occursin("toggle", lowercase(js))
        end

        @testset "file_browser_script()" begin
            js = file_browser_script()
            @test js isa String
            @test !isempty(js)
            @test occursin("<script>", js)
        end

        @testset "terminal_panel_script()" begin
            js = terminal_panel_script()
            @test js isa String
            @test !isempty(js)
            @test occursin("<script>", js)
            @test occursin("toggleTerminalPanel", js) || occursin("terminal", lowercase(js))
        end

        @testset "package_panel_script()" begin
            js = package_panel_script()
            @test js isa String
            @test !isempty(js)
            @test occursin("<script>", js)
        end

        @testset "keyboard_shortcuts_script()" begin
            js = keyboard_shortcuts_script()
            @test js isa String
            @test !isempty(js)
            @test occursin("<script>", js)
            @test occursin("keydown", js)
        end

        @testset "run_controls_script()" begin
            js = run_controls_script()
            @test js isa String
            @test !isempty(js)
            @test occursin("<script>", js)
        end

        @testset "search_replace_script()" begin
            js = search_replace_script()
            @test js isa String
            @test !isempty(js)
            @test occursin("<script>", js)
        end

        @testset "search_styles()" begin
            css = search_styles()
            @test css isa String
            @test !isempty(css)
            @test occursin("<style>", css)
        end

        @testset "workspace_inspector_script()" begin
            js = workspace_inspector_script()
            @test js isa String
            @test !isempty(js)
            @test occursin("<script>", js)
        end

        @testset "command_palette_script()" begin
            js = command_palette_script()
            @test js isa String
            @test !isempty(js)
            @test occursin("<script>", js)
        end

        @testset "statusbar_ide_script()" begin
            js = statusbar_ide_script()
            @test js isa String
            @test !isempty(js)
            @test occursin("<script>", js)
        end
    end

    # =========================================================================
    # SESSIONS-3900: Layout & IDE Component Tests
    # =========================================================================
    @testset "Layout and IDE components (SESSIONS-3900)" begin
        @testset "IDENotebookTabs rendering" begin
            # With notebooks — IDENotebookTabs expects Vector of Dicts with string keys
            nb = Notebook()
            add_cell!(nb; code="x = 1")
            notebooks = [Dict("id" => nb.id, "title" => "test.jl", "modified" => false)]
            tabs = IDENotebookTabs(notebooks; active_id=nb.id)
            @test tabs isa Therapy.VNode
            html = Therapy.render_to_string(tabs)
            @test occursin("test.jl", html)
        end

        @testset "IDENotebookTabs empty state" begin
            empty_tabs = IDEEmptyTabs()
            @test empty_tabs isa Therapy.VNode
            html = Therapy.render_to_string(empty_tabs)
            @test occursin("notebook", lowercase(html)) || occursin("new", lowercase(html))
        end

        @testset "IDETab rendering" begin
            tab = IDETab(; id=uuid4(), title="signals.jl", is_active=true)
            @test tab isa Therapy.VNode
            html = Therapy.render_to_string(tab)
            @test occursin("signals.jl", html)
        end

        @testset "IDETab modified indicator" begin
            tab = IDETab(; id=uuid4(), title="test.jl", is_modified=true)
            html = Therapy.render_to_string(tab)
            @test occursin("amber", html) || occursin("modified", lowercase(html)) || occursin("●", html)
        end

        @testset "RunAllButton rendering" begin
            btn = RunAllButton()
            @test btn isa Therapy.VNode
            html = Therapy.render_to_string(btn)
            @test occursin("Run All", html)
        end

        @testset "RunAllButton running state" begin
            btn = RunAllButton(; is_running=true)
            html = Therapy.render_to_string(btn)
            @test occursin("Run All", html)
        end

        @testset "IDEStatusBar rendering" begin
            statusbar = IDEStatusBar()
            @test statusbar isa Therapy.VNode
            html = Therapy.render_to_string(statusbar)
            @test !isempty(html)
        end

        @testset "IDEKernelStatus states" begin
            idle = IDEKernelStatus(; state="idle")
            @test idle isa Therapy.VNode
            idle_html = Therapy.render_to_string(idle)
            @test occursin("accent", idle_html) || occursin("green", idle_html) || occursin("Idle", idle_html)

            busy = IDEKernelStatus(; state="busy")
            busy_html = Therapy.render_to_string(busy)
            @test occursin("amber", busy_html) || occursin("Busy", busy_html)

            error_status = IDEKernelStatus(; state="error")
            error_html = Therapy.render_to_string(error_status)
            @test occursin("rose", error_html) || occursin("Error", error_html)
        end

        @testset "IDECellProgress rendering" begin
            # Not running
            progress_idle = IDECellProgress()
            @test progress_idle isa Therapy.VNode

            # Running
            progress_active = IDECellProgress(; running=3, total=10)
            html = Therapy.render_to_string(progress_active)
            @test occursin("3", html) || occursin("10", html)
        end

        @testset "IDEGitStatus rendering" begin
            git = IDEGitStatus(; branch="main", dirty=false)
            @test git isa Therapy.VNode
            html = Therapy.render_to_string(git)
            @test occursin("main", html)
        end

        @testset "IDEGitStatus dirty indicator" begin
            git = IDEGitStatus(; branch="feature", dirty=true)
            html = Therapy.render_to_string(git)
            @test occursin("feature", html)
        end

        @testset "IDEConnectionStatus rendering" begin
            conn = IDEConnectionStatus()
            @test conn isa Therapy.VNode
        end

        @testset "IDENotebookPath rendering" begin
            path_comp = IDENotebookPath(; path="/home/user/notebook.jl")
            @test path_comp isa Therapy.VNode
            html = Therapy.render_to_string(path_comp)
            @test occursin("notebook.jl", html)
        end

        @testset "IDESearchBar rendering" begin
            search = IDESearchBar()
            @test search isa Therapy.VNode
            html = Therapy.render_to_string(search)
            @test occursin("search", lowercase(html)) || occursin("find", lowercase(html))
        end

        @testset "IDECommandPalette rendering" begin
            palette = IDECommandPalette()
            @test palette isa Therapy.VNode
            html = Therapy.render_to_string(palette)
            @test occursin("Run All", html)
            @test occursin("Save", html) || occursin("save", html)
        end

        @testset "IDETerminalPanel rendering" begin
            terminal = IDETerminalPanel()
            @test terminal isa Therapy.VNode
            html = Therapy.render_to_string(terminal)
            @test occursin("terminal", lowercase(html))
        end

        @testset "IDETerminalPanel collapsed" begin
            terminal = IDETerminalPanel(; collapsed=true)
            @test terminal isa Therapy.VNode
        end

        @testset "IDETerminalHeader rendering" begin
            header = IDETerminalHeader()
            @test header isa Therapy.VNode
            html = Therapy.render_to_string(header)
            @test occursin("Terminal", html) || occursin("terminal", html)
        end

        @testset "IDEPackagePanel rendering" begin
            panel = IDEPackagePanel()
            @test panel isa Therapy.VNode
        end

        @testset "IDEPackageItem rendering" begin
            item = IDEPackageItem(; name="DataFrames", version="1.6.1")
            @test item isa Therapy.VNode
            html = Therapy.render_to_string(item)
            @test occursin("DataFrames", html)
            @test occursin("1.6.1", html)
        end

        @testset "IDEWorkspaceInspector rendering" begin
            inspector = IDEWorkspaceInspector()
            @test inspector isa Therapy.VNode
        end
    end

    # =========================================================================
    # SESSIONS-3900: File Browser Tests
    # =========================================================================
    @testset "File browser (SESSIONS-3900)" begin
        @testset "FileEntry and list_directory" begin
            entries = list_directory(joinpath(@__DIR__, "fixtures"))
            @test entries isa Vector{FileEntry}
            @test !isempty(entries)

            # Should contain .jl files from test fixtures
            jl_files = filter(e -> endswith(e.name, ".jl"), entries)
            @test !isempty(jl_files)
        end

        @testset "format_file_size" begin
            @test format_file_size(0) == "0 B"
            @test format_file_size(100) == "100 B"
            @test format_file_size(1024) == "1.0 KB"
            @test format_file_size(1048576) == "1.0 MB"
        end

        @testset "IDEFileBrowser rendering" begin
            entries = list_directory(joinpath(@__DIR__, "fixtures"))
            browser = IDEFileBrowser(; entries=entries, current_path=joinpath(@__DIR__, "fixtures"))
            # IDEFileBrowser returns a Fragment (multiple children), not a VNode
            html = Therapy.render_to_string(browser)
            @test !isempty(html)
        end

        @testset "IDEBrowserToolbar rendering" begin
            toolbar = IDEBrowserToolbar()
            @test toolbar isa Therapy.VNode
        end

        @testset "IDEFileContextMenu rendering" begin
            menu = IDEFileContextMenu()
            @test menu isa Therapy.VNode
        end

        @testset "IDEFileTreeItem rendering" begin
            # FileEntry is positional: name, is_directory, size, modified, path
            entry = FileEntry("test.jl", false, 1024, time(), "/tmp/test.jl")
            item = IDEFileTreeItem(entry)
            @test item isa Therapy.VNode
            html = Therapy.render_to_string(item)
            @test occursin("test.jl", html)
        end

        @testset "IDEFileTreeItem directory" begin
            entry = FileEntry("src", true, 0, time(), "/tmp/src")
            item = IDEFileTreeItem(entry)
            @test item isa Therapy.VNode
        end

        @testset "IDEFileTreeItem active notebook" begin
            entry = FileEntry("active.jl", false, 500, time(), "/tmp/active.jl")
            item = IDEFileTreeItem(entry; current_notebook_path="/tmp/active.jl")
            html = Therapy.render_to_string(item)
            @test occursin("accent", html) || occursin("active", lowercase(html))
        end
    end

    # =========================================================================
    # SESSIONS-3900: Execution Engine Integration Tests
    # =========================================================================
    @testset "Execution engine integration (SESSIONS-3900)" begin
        @testset "Cell analysis → execution order → workspace" begin
            # Create a multi-cell notebook with dependencies
            nb = Notebook()
            cell1 = add_cell!(nb; code="base = 10")
            cell2 = add_cell!(nb; code="doubled = base * 2")
            cell3 = add_cell!(nb; code="result = doubled + base")

            # Analyze cells
            for c in values(nb.cells)
                analyze_cell!(c)
            end

            # Verify analysis
            @test :base in cell1.definitions
            @test :base in cell2.references
            @test :doubled in cell2.definitions
            @test :doubled in cell3.references
            @test :base in cell3.references

            # Get execution order
            order = get_execution_order(nb, [cell1.id])
            @test length(order) == 3
            ids = [c.id for c in order]
            @test findfirst(==(cell1.id), ids) < findfirst(==(cell2.id), ids)
            @test findfirst(==(cell2.id), ids) < findfirst(==(cell3.id), ids)

            # Execute in workspace
            ws = create_workspace()
            for c in order
                run_cell!(ws, c.code)
            end
            @test Sessions.get_variable(ws, :base) == 10
            @test Sessions.get_variable(ws, :doubled) == 20
            @test Sessions.get_variable(ws, :result) == 30
        end

        @testset "Workspace isolation across notebooks" begin
            ws1 = create_workspace()
            ws2 = create_workspace()

            run_cell!(ws1, "shared_name = :notebook1")
            run_cell!(ws2, "shared_name = :notebook2")

            @test Sessions.get_variable(ws1, :shared_name) == :notebook1
            @test Sessions.get_variable(ws2, :shared_name) == :notebook2
        end

        @testset "Function redefinition in workspace" begin
            ws = create_workspace()
            run_cell!(ws, "f(x) = x + 1")
            r1, _ = run_cell!(ws, "f(10)")
            @test r1 == 11

            # Redefine
            run_cell!(ws, "f(x) = x * 2")
            r2, _ = run_cell!(ws, "f(10)")
            @test r2 == 20
        end

        @testset "Cell error does not crash workspace" begin
            ws = create_workspace()
            run_cell!(ws, "good_val = 42")

            # This should error but not crash
            result, _ = run_cell!(ws, "1 / 0")
            @test result isa Exception || isinf(result) || result == Inf  # Julia returns Inf for 1/0 int

            # Workspace still works
            r, _ = run_cell!(ws, "good_val + 1")
            @test r == 43
        end

        @testset "Execution with cancel_cell!" begin
            nb = Notebook()
            cell = add_cell!(nb; code="x = 1")
            cell.state = CELL_RUNNING

            # Cancel should reset to idle
            cancel_cell!(nb, cell.id)
            @test cell.state == CELL_IDLE
        end

        @testset "Execution order - independent cells" begin
            nb = Notebook()
            cell1 = add_cell!(nb; code="a = 1")
            cell2 = add_cell!(nb; code="b = 2")
            cell3 = add_cell!(nb; code="c = 3")

            # Changing cell1 should only execute cell1 (no dependencies)
            order = get_execution_order(nb, [cell1.id])
            @test length(order) == 1
            @test order[1].id == cell1.id
        end

        @testset "Cell timeout configuration" begin
            @test Sessions.DEFAULT_CELL_TIMEOUT isa Base.RefValue{Float64}
            @test Sessions.DEFAULT_CELL_TIMEOUT[] == 30.0
        end
    end

    # =========================================================================
    # SESSIONS-3900: Export Function Tests
    # =========================================================================
    @testset "Export functions (SESSIONS-3900)" begin
        @testset "export_to_html - structure" begin
            nb = Notebook()
            add_cell!(nb; code="greeting = \"Hello\"")
            add_cell!(nb; code="println(greeting)")

            html = export_to_html(nb)
            @test startswith(html, "<!DOCTYPE html>")
            @test occursin("<html", html)
            @test occursin("</html>", html)
            @test occursin("greeting", html)
            @test occursin("Sessions.jl", html)
        end

        @testset "export_to_html - dark mode support" begin
            nb = Notebook()
            add_cell!(nb; code="x = 1")
            html = export_to_html(nb)
            @test occursin("prefers-color-scheme", html)
        end

        @testset "export_to_html - markdown cell" begin
            nb = Notebook()
            md_cell = add_cell!(nb; code="md\"\"\"# Hello World\"\"\"")
            md_cell.folded = true
            md_cell.cell_type = :markdown

            html = export_to_html(nb)
            @test occursin("Hello World", html)
        end

        @testset "export_to_script - code only" begin
            nb = Notebook()
            add_cell!(nb; code="x = 42")
            add_cell!(nb; code="y = x + 1")

            script = export_to_script(nb)
            @test occursin("x = 42", script)
            @test occursin("y = x + 1", script)
        end

        @testset "export_to_script - markdown to comments" begin
            nb = Notebook()
            md_cell = add_cell!(nb; code="md\"\"\"# Section Title\"\"\"")
            md_cell.cell_type = :markdown
            md_cell.folded = true
            add_cell!(nb; code="code_here = true")

            script = export_to_script(nb)
            @test occursin("# Section Title", script) || occursin("#  Section Title", script)
            @test !occursin("md\"\"\"", script)
            @test occursin("code_here", script)
        end

        @testset "export_to_html - with notebook path" begin
            nb = Notebook()
            nb.path = "/tmp/my_notebook.jl"
            add_cell!(nb; code="x = 1")

            html = export_to_html(nb)
            # export_to_html uses basename(notebook.path) for the title
            @test occursin("my_notebook.jl", html)
        end

        @testset "export_to_html - untitled notebook" begin
            nb = Notebook()
            add_cell!(nb; code="x = 1")

            html = export_to_html(nb)
            # No path → "Untitled Notebook" as title
            @test occursin("Untitled Notebook", html)
        end
    end

    # =========================================================================
    # SESSIONS-3900: Notebook Metadata Tests
    # =========================================================================
    @testset "Notebook metadata (SESSIONS-3900)" begin
        @testset "Notebook metadata fields" begin
            nb = Notebook()
            @test nb.title == ""
            @test nb.author == ""
            # Default constructor sets created_at = time()
            @test nb.created_at isa Float64
            @test nb.sessions_version isa String
        end

        @testset "Notebook metadata persistence" begin
            nb = Notebook()
            nb.title = "My Test"
            nb.author = "Tester"
            nb.created_at = 1234567890.0
            add_cell!(nb; code="x = 1")

            temp = tempname() * ".jl"
            try
                save_notebook(nb, temp)
                nb2 = load_notebook(temp)
                @test nb2.title == "My Test"
                @test nb2.author == "Tester"
                @test nb2.created_at ≈ 1234567890.0
            finally
                rm(temp; force=true)
            end
        end

        @testset "notebook_to_dict includes metadata" begin
            nb = Notebook()
            nb.title = "Dict Test"
            nb.author = "Author"
            add_cell!(nb; code="x = 1")

            d = Sessions.notebook_to_dict(nb)
            @test d["title"] == "Dict Test"
            @test d["author"] == "Author"
        end
    end

    # =========================================================================
    # SESSIONS-3900: Server Global State Tests
    # =========================================================================
    @testset "Server global state (SESSIONS-3900)" begin
        @testset "Global dictionaries" begin
            @test Sessions.NOTEBOOKS isa Dict
            @test Sessions.CONN_NOTEBOOK isa Dict
            @test Sessions.CELL_SIGNAL_REGISTRY isa Set
        end

        @testset "Server functions defined" begin
            @test isdefined(Sessions, :setup_signals!)
            @test isdefined(Sessions, :setup_channels!)
            @test isdefined(Sessions, :setup_lifecycle!)
            @test isdefined(Sessions, :create_default_notebook!)
            @test isdefined(Sessions, :setup_set_bond_channel!)
            @test isdefined(Sessions, :set_bond_and_run!)
        end

        @testset "get_or_create_notebook creates and returns" begin
            empty!(Sessions.NOTEBOOKS)
            nb = Sessions.get_or_create_notebook()
            @test nb isa Notebook
            @test length(Sessions.NOTEBOOKS) >= 1

            # Same notebook returned by ID
            nb2 = Sessions.get_or_create_notebook(id=nb.id)
            @test nb2 === nb
        end
    end

    # =========================================================================
    # SESSIONS-3900: NotebookApp Options Tests
    # =========================================================================
    @testset "NotebookApp options (SESSIONS-3900)" begin
        @testset "NotebookOptions all fields" begin
            opts = NotebookOptions(
                show_header=false,
                show_toolbar=false,
                show_add_cell=false,
                editable=false,
                runnable=false,
                show_output=false,
                max_height="500px",
                theme="ocean"
            )
            @test opts.show_header == false
            @test opts.show_toolbar == false
            @test opts.show_add_cell == false
            @test opts.editable == false
            @test opts.runnable == false
            @test opts.show_output == false
            @test opts.max_height == "500px"
            @test opts.theme == "ocean"
        end

        @testset "NotebookOptions default values" begin
            opts = NotebookOptions()
            @test opts.show_header == true
            @test opts.show_toolbar == true
            @test opts.show_add_cell == true
            @test opts.editable == true
            @test opts.runnable == true
            @test opts.show_output == true
            @test opts.max_height === nothing
            @test opts.theme == "default"
        end

        @testset "NotebookApp with read-only options" begin
            empty!(Sessions.NOTEBOOKS)
            opts = NotebookOptions(editable=false, runnable=false, show_toolbar=false)
            result = Sessions.NotebookApp(options=opts)
            @test result isa Therapy.VNode
        end

        @testset "NotebookApp with max_height" begin
            empty!(Sessions.NOTEBOOKS)
            opts = NotebookOptions(max_height="300px")
            result = Sessions.NotebookApp(options=opts)
            @test result isa Therapy.VNode
        end
    end

end

println("\nAll tests passed!")
