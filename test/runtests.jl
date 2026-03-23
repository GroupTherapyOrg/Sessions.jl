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
    include("test_session.jl")
    include("test_watcher.jl")
    include("test_e2e.jl")
    include("test_pluto_compat.jl")
    include("test_structured_error.jl")

    # TUI-dependent tests — removed (TUI + Tachikoma deleted)
    # These tested TUI rendering, cell widgets, file editor, REPL panel,
    # image pipeline, scrollbar, LSP popups, etc. via Tachikoma.TestBackend.
    # Web equivalents should be added as Playwright E2E tests.
    #
    # Removed: test_tui.jl, test_cli.jl, test_file_editor_parity.jl,
    # test_auto_indent.jl, test_auto_close_brackets.jl, test_bracket_matching.jl,
    # test_lsp_completion.jl, test_completion_popup.jl, test_hover.jl,
    # test_goto_definition.jl, test_signature_help.jl, test_scrollbar.jl,
    # test_rename.jl, test_e2e_editing.jl, test_image_pipeline.jl,
    # test_png_decoder.jl, test_output_cache.jl, test_encoded_cache.jl,
    # test_aspect_sizing.jl, test_resize_cache.jl, test_jpeg_decoder.jl,
    # test_svg_fallback.jl, test_image_interact.jl, test_repl_parity.jl,
    # test_inline_diagnostics.jl, test_formatting.jl
end
