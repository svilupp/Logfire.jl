using Test
using Logfire

# Mock span for testing (simple Dict-based mock)
mutable struct MockSpan
    attributes::Dict{String, Any}
    status::Union{Nothing, Tuple{Symbol, String}}
    events::Vector{Any}

    MockSpan() = new(Dict{String, Any}(), nothing, [])
end

# Make MockSpan compatible with span operations
Base.push!(s::MockSpan, event) = push!(s.events, event)

@testset "Span Utilities" begin
    @testset "set_span_attribute!" begin
        span = MockSpan()
        Logfire.set_span_attribute!(span, "test.key", "test-value")
        @test span.attributes["test.key"] == "test-value"

        Logfire.set_span_attribute!(span, "test.number", 42)
        @test span.attributes["test.number"] == 42

        Logfire.set_span_attribute!(span, "test.bool", true)
        @test span.attributes["test.bool"] == true
    end

    @testset "record_token_usage!" begin
        span = MockSpan()
        Logfire.record_token_usage!(span, 100, 50)
        @test span.attributes["gen_ai.usage.input_tokens"] == 100
        @test span.attributes["gen_ai.usage.output_tokens"] == 50
        @test span.attributes["gen_ai.usage.total_tokens"] == 150

        # With model
        span2 = MockSpan()
        Logfire.record_token_usage!(span2, 200, 100; model = "gpt-4")
        @test span2.attributes["gen_ai.response.model"] == "gpt-4"
    end

    @testset "add_prompt_attribute!" begin
        span = MockSpan()
        messages = [Dict("role" => "user", "content" => "Hello")]
        Logfire.add_prompt_attribute!(span, messages)
        @test haskey(span.attributes, "gen_ai.prompt.messages")
        @test occursin("Hello", span.attributes["gen_ai.prompt.messages"])
    end

    @testset "add_response_attribute!" begin
        span = MockSpan()
        Logfire.add_response_attribute!(span, "This is a response")
        @test span.attributes["gen_ai.response.content"] == "This is a response"
    end

    @testset "_maybe_truncate" begin
        # Short content - no truncation
        short = "Hello, world!"
        @test Logfire._maybe_truncate(short) == short

        # Long content - should truncate
        long = repeat("x", 15000)
        truncated = Logfire._maybe_truncate(long)
        @test length(truncated) < length(long)
        @test endswith(truncated, "... [truncated]")

        # Custom max length
        custom = Logfire._maybe_truncate("Hello, world!", 5)
        @test custom == "Hello... [truncated]"
    end
end
