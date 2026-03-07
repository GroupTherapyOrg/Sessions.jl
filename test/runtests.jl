using Test
using Sessions

@testset "Sessions.jl v2" begin
    @testset "Module loads" begin
        @test true  # Sessions loaded successfully
    end

    include("test_types.jl")
    include("test_format.jl")
    include("test_analysis.jl")
    include("test_kernel.jl")
    include("test_output.jl")
    include("test_run.jl")
    include("test_tui.jl")
    include("test_cli.jl")
    include("test_session.jl")
    include("test_watcher.jl")
    include("test_e2e.jl")
    include("test_pluto_compat.jl")
    include("test_formatting.jl")
    include("test_inline_diagnostics.jl")
    include("test_file_editor_parity.jl")
    include("test_auto_indent.jl")
    include("test_auto_close_brackets.jl")
    include("test_bracket_matching.jl")
    include("test_lsp_completion.jl")
    include("test_completion_popup.jl")
    include("test_hover.jl")
    include("test_goto_definition.jl")
    include("test_signature_help.jl")
    include("test_scrollbar.jl")
end
