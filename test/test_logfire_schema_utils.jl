using Test
using Logfire
import PromptingTools as PT

# Mock span for testing schema utilities
mutable struct SchemaTestSpan
    attributes::Dict{String, Any}
    SchemaTestSpan() = new(Dict{String, Any}())
end

@testset "LogfireSchema Utilities" begin
    @testset "_set_if_some" begin
        span = SchemaTestSpan()

        # String value - should set
        Logfire._set_if_some(span, "key1", "value")
        @test span.attributes["key1"] == "value"

        # Nothing - should not set
        Logfire._set_if_some(span, "key2", nothing)
        @test !haskey(span.attributes, "key2")

        # Missing - should not set
        Logfire._set_if_some(span, "key3", missing)
        @test !haskey(span.attributes, "key3")

        # Empty string - should not set
        Logfire._set_if_some(span, "key4", "")
        @test !haskey(span.attributes, "key4")

        # Number - should set
        Logfire._set_if_some(span, "key5", 42)
        @test span.attributes["key5"] == 42
    end

    @testset "_getfield_or" begin
        # Dict access
        d = Dict(:foo => "bar", :num => 42)
        @test Logfire._getfield_or(d, :foo, "default") == "bar"
        @test Logfire._getfield_or(d, :missing, "default") == "default"

        # NamedTuple access
        nt = (foo = "bar", num = 42)
        @test Logfire._getfield_or(nt, :foo, "default") == "bar"
        @test Logfire._getfield_or(nt, :missing, "default") == "default"

        # Struct access
        struct TestStruct
            foo::String
        end
        ts = TestStruct("bar")
        @test Logfire._getfield_or(ts, :foo, "default") == "bar"
        @test Logfire._getfield_or(ts, :missing, "default") == "default"
    end

    @testset "_getextras" begin
        # Message with extras
        msg_with_extras = (content = "test", extras = Dict{Symbol, Any}(:key => "value"))
        extras = Logfire._getextras(msg_with_extras)
        @test extras[:key] == "value"

        # Message without extras
        msg_without_extras = (content = "test",)
        extras = Logfire._getextras(msg_without_extras)
        @test isempty(extras)
    end

    @testset "_message_role" begin
        # Dict with string key
        @test Logfire._message_role(Dict("role" => "user")) == "user"
        @test Logfire._message_role(Dict("role" => "assistant")) == "assistant"

        # Dict with symbol key
        @test Logfire._message_role(Dict(:role => "system")) == "system"

        # PT messages
        @test Logfire._message_role(PT.SystemMessage("test")) == "system"
        @test Logfire._message_role(PT.UserMessage("test")) == "user"
        @test Logfire._message_role(PT.AIMessage("test")) == "assistant"
    end

    @testset "_message_content" begin
        # Dict with string key
        @test Logfire._message_content(Dict("content" => "hello")) == "hello"

        # Dict with symbol key
        @test Logfire._message_content(Dict(:content => "world")) == "world"

        # PT messages
        @test Logfire._message_content(PT.UserMessage("test content")) == "test content"

        # Empty/missing
        @test Logfire._message_content(Dict()) == ""
    end

    @testset "_find_ai_message" begin
        # Conversation with AI message at end
        conv = [
            PT.UserMessage("Hello"),
            PT.AIMessage("Hi there!")
        ]
        ai_msg = Logfire._find_ai_message(conv)
        @test ai_msg isa PT.AIMessage
        @test ai_msg.content == "Hi there!"

        # Conversation with user message at end (still finds AI)
        conv2 = [
            PT.UserMessage("Hello"),
            PT.AIMessage("Response"),
            PT.UserMessage("Follow up")
        ]
        ai_msg2 = Logfire._find_ai_message(conv2)
        @test ai_msg2 isa PT.AIMessage
        @test ai_msg2.content == "Response"

        # Empty conversation
        @test Logfire._find_ai_message([]) === nothing
    end

    @testset "_detect_system" begin
        @test Logfire._detect_system(PT.OpenAISchema()) == "openai"
        @test Logfire._detect_system(PT.AnthropicSchema()) == "anthropic"
        @test Logfire._detect_system(PT.OllamaSchema()) == "ollama"

        # Unknown schema
        struct UnknownSchema <: PT.AbstractPromptSchema end
        @test Logfire._detect_system(UnknownSchema()) == "unknown"
    end

    @testset "_safe_json" begin
        # Serializable
        @test Logfire._safe_json(Dict("key" => "value")) == "{\"key\":\"value\"}"
        @test Logfire._safe_json([1, 2, 3]) == "[1,2,3]"

        # Falls back to string representation
        @test Logfire._safe_json("plain string") == "\"plain string\""
    end

    @testset "_extract_tool_call_data" begin
        # Dict-based tool call
        tool_calls = [
            Dict("id" => "call_1", "name" => "get_weather", "arguments" => "{\"city\":\"Paris\"}")
        ]
        result = Logfire._extract_tool_call_data(tool_calls)
        @test length(result) == 1
        @test result[1]["id"] == "call_1"
        @test result[1]["name"] == "get_weather"

        # Empty list
        @test isempty(Logfire._extract_tool_call_data([]))
    end

    @testset "_record_detailed_usage!" begin
        @testset "with unified keys (preferred)" begin
            span = SchemaTestSpan()
            msg = (
                content = "test",
                extras = Dict{Symbol, Any}(
                    :cache_read_tokens => 50,
                    :cache_write_tokens => 100,
                    :cache_write_1h_tokens => 25,
                    :cache_write_5m_tokens => 10,
                    :reasoning_tokens => 200,
                    :audio_input_tokens => 30,
                    :audio_output_tokens => 40,
                    :accepted_prediction_tokens => 15,
                    :rejected_prediction_tokens => 5,
                    :service_tier => "default",
                    :web_search_requests => 2
                )
            )

            Logfire._record_detailed_usage!(span, msg)

            @test span.attributes["gen_ai.usage.cache_read_tokens"] == 50
            @test span.attributes["gen_ai.usage.cache_write_tokens"] == 100
            @test span.attributes["gen_ai.usage.cache_write_1h_tokens"] == 25
            @test span.attributes["gen_ai.usage.cache_write_5m_tokens"] == 10
            @test span.attributes["gen_ai.usage.reasoning_tokens"] == 200
            @test span.attributes["gen_ai.usage.audio_input_tokens"] == 30
            @test span.attributes["gen_ai.usage.audio_output_tokens"] == 40
            @test span.attributes["gen_ai.usage.accepted_prediction_tokens"] == 15
            @test span.attributes["gen_ai.usage.rejected_prediction_tokens"] == 5
            @test span.attributes["gen_ai.service_tier"] == "default"
            @test span.attributes["gen_ai.usage.web_search_requests"] == 2
        end

        @testset "with OpenAI raw dict fallback" begin
            span = SchemaTestSpan()
            # Simulate older PromptingTools format with raw dicts only
            msg = (
                content = "test",
                extras = Dict{Symbol, Any}(
                    :prompt_tokens_details => Dict{Symbol, Any}(
                        :cached_tokens => 50,
                        :audio_tokens => 10
                    ),
                    :completion_tokens_details => Dict{Symbol, Any}(
                        :reasoning_tokens => 100,
                        :audio_tokens => 20,
                        :accepted_prediction_tokens => 5,
                        :rejected_prediction_tokens => 2
                    )
                )
            )

            Logfire._record_detailed_usage!(span, msg)

            @test span.attributes["gen_ai.usage.cache_read_tokens"] == 50
            @test span.attributes["gen_ai.usage.audio_input_tokens"] == 10
            @test span.attributes["gen_ai.usage.reasoning_tokens"] == 100
            @test span.attributes["gen_ai.usage.audio_output_tokens"] == 20
            @test span.attributes["gen_ai.usage.accepted_prediction_tokens"] == 5
            @test span.attributes["gen_ai.usage.rejected_prediction_tokens"] == 2
        end

        @testset "with Anthropic legacy keys fallback" begin
            span = SchemaTestSpan()
            # Simulate older Anthropic format with legacy keys
            msg = (
                content = "test",
                extras = Dict{Symbol, Any}(
                    :cache_read_input_tokens => 500,
                    :cache_creation_input_tokens => 1000
                )
            )

            Logfire._record_detailed_usage!(span, msg)

            @test span.attributes["gen_ai.usage.cache_read_tokens"] == 500
            @test span.attributes["gen_ai.usage.cache_write_tokens"] == 1000
        end

        @testset "unified keys take precedence over fallbacks" begin
            span = SchemaTestSpan()
            # Both unified keys and fallback dicts present
            msg = (
                content = "test",
                extras = Dict{Symbol, Any}(
                    :cache_read_tokens => 100,  # unified key
                    :cache_read_input_tokens => 500,  # should be ignored
                    :prompt_tokens_details => Dict{Symbol, Any}(
                        :cached_tokens => 999  # should be ignored
                    )
                )
            )

            Logfire._record_detailed_usage!(span, msg)

            @test span.attributes["gen_ai.usage.cache_read_tokens"] == 100
        end

        @testset "handles nothing message" begin
            span = SchemaTestSpan()
            Logfire._record_detailed_usage!(span, nothing)
            @test isempty(span.attributes)
        end

        @testset "handles empty extras" begin
            span = SchemaTestSpan()
            msg = (content = "test", extras = Dict{Symbol, Any}())
            Logfire._record_detailed_usage!(span, msg)
            @test isempty(span.attributes)
        end

        @testset "handles message without extras" begin
            span = SchemaTestSpan()
            msg = (content = "test",)
            Logfire._record_detailed_usage!(span, msg)
            @test isempty(span.attributes)
        end
    end
end
