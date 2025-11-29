using Test
using JSON3
using Logfire

@testset "OTEL GenAI Types" begin
    @testset "Role enum" begin
        @test role_to_string(ROLE_SYSTEM) == "system"
        @test role_to_string(ROLE_USER) == "user"
        @test role_to_string(ROLE_ASSISTANT) == "assistant"
        @test role_to_string(ROLE_TOOL) == "tool"

        @test string_to_role("system") == ROLE_SYSTEM
        @test string_to_role("user") == ROLE_USER
        @test string_to_role("assistant") == ROLE_ASSISTANT
        @test string_to_role("tool") == ROLE_TOOL
        @test string_to_role("SYSTEM") == ROLE_SYSTEM  # case insensitive
        @test string_to_role("unknown") == ROLE_USER  # default
    end

    @testset "FinishReason enum" begin
        @test finish_reason_to_string(FINISH_STOP) == "stop"
        @test finish_reason_to_string(FINISH_LENGTH) == "length"
        @test finish_reason_to_string(FINISH_CONTENT_FILTER) == "content_filter"
        @test finish_reason_to_string(FINISH_TOOL_CALL) == "tool_call"
        @test finish_reason_to_string(FINISH_ERROR) == "error"

        @test string_to_finish_reason("stop") == FINISH_STOP
        @test string_to_finish_reason("tool_call") == FINISH_TOOL_CALL
    end

    @testset "Modality enum" begin
        @test modality_to_string(MODALITY_IMAGE) == "image"
        @test modality_to_string(MODALITY_VIDEO) == "video"
        @test modality_to_string(MODALITY_AUDIO) == "audio"

        @test string_to_modality("image") == MODALITY_IMAGE
        @test string_to_modality("video") == MODALITY_VIDEO
    end

    @testset "OperationName enum" begin
        @test operation_name_to_string(OP_CHAT) == "chat"
        @test operation_name_to_string(OP_EMBEDDINGS) == "embeddings"
        @test operation_name_to_string(OP_EXECUTE_TOOL) == "execute_tool"
        @test operation_name_to_string(OP_INVOKE_AGENT) == "invoke_agent"

        @test string_to_operation_name("chat") == OP_CHAT
        @test string_to_operation_name("embeddings") == OP_EMBEDDINGS
    end

    @testset "OutputType enum" begin
        @test output_type_to_string(OUTPUT_TEXT) == "text"
        @test output_type_to_string(OUTPUT_JSON) == "json"
        @test output_type_to_string(OUTPUT_IMAGE) == "image"
        @test output_type_to_string(OUTPUT_SPEECH) == "speech"

        @test string_to_output_type("text") == OUTPUT_TEXT
        @test string_to_output_type("json") == OUTPUT_JSON
    end
end

@testset "Message Part Types" begin
    @testset "TextPart" begin
        p = TextPart("Hello, world!")
        @test p.content == "Hello, world!"
        @test p isa AbstractMessagePart

        d = part_to_dict(p)
        @test d["type"] == "text"
        @test d["content"] == "Hello, world!"
    end

    @testset "ToolCallRequestPart" begin
        p = ToolCallRequestPart("get_weather"; id = "call_123", arguments = Dict("city" => "Paris"))
        @test p.name == "get_weather"
        @test p.id == "call_123"
        @test p.arguments["city"] == "Paris"

        d = part_to_dict(p)
        @test d["type"] == "tool_call"
        @test d["name"] == "get_weather"
        @test d["id"] == "call_123"
        @test d["arguments"]["city"] == "Paris"

        # Without optional fields
        p2 = ToolCallRequestPart("simple_tool")
        d2 = part_to_dict(p2)
        @test d2["type"] == "tool_call"
        @test d2["name"] == "simple_tool"
        @test !haskey(d2, "id")
        @test !haskey(d2, "arguments")
    end

    @testset "ToolCallResponsePart" begin
        # With id and name (Logfire format)
        p = ToolCallResponsePart("22°C, sunny"; id = "call_123", name = "get_weather")
        @test p.response == "22°C, sunny"
        @test p.id == "call_123"
        @test p.name == "get_weather"

        d = part_to_dict(p)
        @test d["type"] == "tool_call_response"
        @test d["result"] == "22°C, sunny"  # Logfire uses "result" not "response"
        @test d["id"] == "call_123"
        @test d["name"] == "get_weather"

        # Without id and name
        p2 = ToolCallResponsePart("some result")
        d2 = part_to_dict(p2)
        @test d2["type"] == "tool_call_response"
        @test d2["result"] == "some result"
        @test !haskey(d2, "id")
        @test !haskey(d2, "name")
    end

    @testset "BlobPart" begin
        p = BlobPart(MODALITY_IMAGE, "base64data"; mime_type = "image/png")
        @test p.modality == MODALITY_IMAGE
        @test p.content == "base64data"
        @test p.mime_type == "image/png"

        d = part_to_dict(p)
        @test d["type"] == "blob"
        @test d["modality"] == "image"
        @test d["content"] == "base64data"
        @test d["mime_type"] == "image/png"
    end

    @testset "UriPart" begin
        p = UriPart(MODALITY_IMAGE, "https://example.com/image.png")
        @test p.modality == MODALITY_IMAGE
        @test p.uri == "https://example.com/image.png"
        @test p.mime_type === nothing

        d = part_to_dict(p)
        @test d["type"] == "uri"
        @test d["modality"] == "image"
        @test d["uri"] == "https://example.com/image.png"
        @test !haskey(d, "mime_type")
    end

    @testset "FilePart" begin
        p = FilePart(MODALITY_IMAGE, "file-abc123"; mime_type = "image/jpeg")
        d = part_to_dict(p)
        @test d["type"] == "file"
        @test d["modality"] == "image"
        @test d["file_id"] == "file-abc123"
        @test d["mime_type"] == "image/jpeg"
    end

    @testset "ReasoningPart" begin
        p = ReasoningPart("Let me think about this...")
        d = part_to_dict(p)
        @test d["type"] == "reasoning"
        @test d["content"] == "Let me think about this..."
    end

    @testset "GenericPart" begin
        p = GenericPart("custom"; properties = Dict{String, Any}("foo" => "bar"))
        d = part_to_dict(p)
        @test d["type"] == "custom"
        @test d["foo"] == "bar"
    end
end

@testset "Message Types" begin
    @testset "InputMessage" begin
        msg = InputMessage(ROLE_USER, [TextPart("Hello")])
        @test msg.role == ROLE_USER
        @test length(msg.parts) == 1
        @test msg.parts[1].content == "Hello"
        @test msg.name === nothing

        d = to_dict(msg)
        @test d["role"] == "user"
        @test length(d["parts"]) == 1
        @test d["parts"][1]["type"] == "text"
        @test d["parts"][1]["content"] == "Hello"
        @test !haskey(d, "name")

        # With name
        msg2 = InputMessage(ROLE_USER, [TextPart("Hi")]; name = "Alice")
        d2 = to_dict(msg2)
        @test d2["name"] == "Alice"

        # String role constructor
        msg3 = InputMessage("assistant", [TextPart("Response")])
        @test msg3.role == ROLE_ASSISTANT
    end

    @testset "OutputMessage" begin
        msg = OutputMessage(ROLE_ASSISTANT, [TextPart("Response")], FINISH_STOP)
        @test msg.role == ROLE_ASSISTANT
        @test msg.finish_reason == FINISH_STOP
        @test length(msg.parts) == 1

        d = to_dict(msg)
        @test d["role"] == "assistant"
        @test d["finish_reason"] == "stop"
        @test d["parts"][1]["content"] == "Response"

        # With tool call
        msg2 = OutputMessage(
            ROLE_ASSISTANT,
            [ToolCallRequestPart("get_weather"; id = "call_1")],
            FINISH_TOOL_CALL
        )
        d2 = to_dict(msg2)
        @test d2["finish_reason"] == "tool_call"
        @test d2["parts"][1]["type"] == "tool_call"
    end

    @testset "messages_to_json" begin
        msgs = [
            InputMessage(ROLE_USER, [TextPart("What's the weather?")]),
            InputMessage(ROLE_ASSISTANT, [ToolCallRequestPart("get_weather"; id = "c1")])
        ]
        json = messages_to_json(msgs)
        parsed = JSON3.read(json)
        @test length(parsed) == 2
        @test parsed[1]["role"] == "user"
        @test parsed[2]["role"] == "assistant"
        @test parsed[2]["parts"][1]["type"] == "tool_call"
    end

    @testset "system_instructions_to_json" begin
        parts = [TextPart("You are a helpful assistant.")]
        json = system_instructions_to_json(parts)
        parsed = JSON3.read(json)
        @test length(parsed) == 1
        @test parsed[1]["type"] == "text"
        @test parsed[1]["content"] == "You are a helpful assistant."
    end
end

@testset "ToolDefinition" begin
    @testset "Basic construction" begin
        td = ToolDefinition("get_weather"; description = "Get weather for a city")
        @test td.name == "get_weather"
        @test td.description == "Get weather for a city"
        @test isempty(td.parameters)

        d = to_dict(td)
        @test d["type"] == "function"
        @test d["name"] == "get_weather"
        @test d["description"] == "Get weather for a city"
    end

    @testset "With parameters" begin
        params = Dict{String, Any}(
            "type" => "object",
            "properties" => Dict(
                "city" => Dict("type" => "string", "description" => "City name")
            ),
            "required" => ["city"]
        )
        td = ToolDefinition("get_weather"; description = "Get weather", parameters = params)
        d = to_dict(td)
        @test d["parameters"]["type"] == "object"
        @test d["parameters"]["required"] == ["city"]
    end

    @testset "tool_definitions_to_json" begin
        tools = [
            ToolDefinition("tool1"; description = "First tool"),
            ToolDefinition("tool2"; description = "Second tool")
        ]
        json = tool_definitions_to_json(tools)
        parsed = JSON3.read(json)
        @test length(parsed) == 2
        @test parsed[1]["name"] == "tool1"
        @test parsed[2]["name"] == "tool2"
    end
end

@testset "PromptingTools Conversion" begin
    using PromptingTools
    import PromptingTools as PT

    @testset "pt_message_to_input - SystemMessage" begin
        msg = PT.SystemMessage("You are helpful")
        input = pt_message_to_input(msg)
        @test input.role == ROLE_SYSTEM
        @test length(input.parts) == 1
        @test input.parts[1] isa TextPart
        @test input.parts[1].content == "You are helpful"
    end

    @testset "pt_message_to_input - UserMessage" begin
        msg = PT.UserMessage("Hello!")
        input = pt_message_to_input(msg)
        @test input.role == ROLE_USER
        @test input.parts[1].content == "Hello!"
    end

    @testset "pt_message_to_input - AIMessage" begin
        msg = PT.AIMessage("Response")
        input = pt_message_to_input(msg)
        @test input.role == ROLE_ASSISTANT
        @test input.parts[1].content == "Response"
    end

    @testset "pt_conversation_to_otel" begin
        conv = [
            PT.SystemMessage("You are helpful"),
            PT.UserMessage("Hello"),
            PT.AIMessage("Hi there!")
        ]
        result = pt_conversation_to_otel(conv; separate_system = true)

        @test result.system_instructions !== nothing
        @test length(result.system_instructions) == 1
        @test result.system_instructions[1].content == "You are helpful"

        @test length(result.input_messages) == 1  # User message only
        @test result.input_messages[1].role == ROLE_USER

        @test length(result.output_messages) == 1  # AI message as output
        @test result.output_messages[1].role == ROLE_ASSISTANT
        @test result.output_messages[1].finish_reason == FINISH_STOP
    end

    @testset "pt_conversation_to_otel - separate_system=false" begin
        conv = [
            PT.SystemMessage("You are helpful"),
            PT.UserMessage("Hello"),
            PT.AIMessage("Hi!")
        ]
        result = pt_conversation_to_otel(conv; separate_system = false)

        @test result.system_instructions === nothing
        @test length(result.input_messages) == 2  # System + User
        @test result.input_messages[1].role == ROLE_SYSTEM
    end

    @testset "tool_definitions_from_pt" begin
        # Use pre-built tool map instead of functions (PT requires Main-scope functions)
        tool_map = Dict(
            "get_weather" => (
                parameters = Dict{String, Any}(
                    "type" => "object",
                    "properties" => Dict("city" => Dict("type" => "string"))
                ),
                description = "Get weather for a city"
            ),
            "get_time" => (
                parameters = Dict{String, Any}("type" => "object"),
                description = "Get current time"
            )
        )

        defs = tool_definitions_from_pt(tool_map)

        @test length(defs) == 2
        names = [d.name for d in defs]
        @test "get_weather" in names
        @test "get_time" in names
    end
end

@testset "JSON Schema Compliance" begin
    @testset "Input message schema" begin
        msg = InputMessage(ROLE_USER,
            [
                TextPart("What's the weather?"),
                UriPart(MODALITY_IMAGE, "https://example.com/image.png")
            ])
        d = to_dict(msg)

        # Required fields
        @test haskey(d, "role")
        @test haskey(d, "parts")
        @test d["role"] isa String
        @test d["parts"] isa Vector

        # Parts have required type field
        for part in d["parts"]
            @test haskey(part, "type")
        end
    end

    @testset "Output message schema" begin
        msg = OutputMessage(ROLE_ASSISTANT, [TextPart("Response")], FINISH_STOP)
        d = to_dict(msg)

        # Required fields
        @test haskey(d, "role")
        @test haskey(d, "parts")
        @test haskey(d, "finish_reason")
        @test d["finish_reason"] in [
            "stop", "length", "content_filter", "tool_call", "error"]
    end

    @testset "Tool definition schema" begin
        td = ToolDefinition("test"; description = "Test",
            parameters = Dict{String, Any}(
                "type" => "object",
                "properties" => Dict()
            ))
        d = to_dict(td)

        @test d["type"] == "function"
        @test haskey(d, "name")
        @test haskey(d, "description")
        @test haskey(d, "parameters")
    end
end
