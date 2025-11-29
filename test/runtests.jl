using Logfire
using Test
using Aqua

@testset "Logfire.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        # Skip compat test for test extras (Aqua, Test, JSON3)
        Aqua.test_all(Logfire; deps_compat = (check_extras = false,))
    end

    include("test_otel_genai.jl")
    include("test_config.jl")
    include("test_spans.jl")
    include("test_logfire_schema_utils.jl")
    include("test_query.jl")
end
