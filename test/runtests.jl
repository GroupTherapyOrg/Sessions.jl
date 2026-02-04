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

        @testset "Widget exports" begin
            @test isdefined(Sessions, :Slider)
            @test isdefined(Sessions, :TextField)
            @test isdefined(Sessions, :CheckBox)
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
            @test opts.show_add_first_cell == true
            @test opts.editable == true
            @test opts.runnable == true
        end

        @testset "NotebookOptions custom" begin
            opts = NotebookOptions(show_header = false, editable = false)
            @test opts.show_header == false
            @test opts.editable == false
            @test opts.show_add_first_cell == true  # default
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

end

println("\nAll tests passed!")
