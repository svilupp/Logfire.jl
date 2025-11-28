# OpenTelemetry GenAI Utilities
#
# High-level utilities for converting PromptingTools messages to OTEL-compliant format.
# Uses typed constructs from types.jl for strong typing and validation.
#
# Reference: https://opentelemetry.io/docs/specs/semconv/gen-ai/

import PromptingTools as PT

# =============================================================================
# PromptingTools Message Conversion
# =============================================================================

"""
    pt_message_to_input(msg) -> InputMessage

Convert a PromptingTools message to an OTEL InputMessage.

Handles:
- SystemMessage → role=ROLE_SYSTEM
- UserMessage → role=ROLE_USER
- UserMessageWithImages → role=ROLE_USER with BlobPart/UriPart
- AIMessage → role=ROLE_ASSISTANT
- AIToolRequest → role=ROLE_ASSISTANT with ToolCallRequestPart
- ToolMessage → role=ROLE_USER with ToolCallResponsePart
"""
function pt_message_to_input(msg)::InputMessage
    # Handle Dict messages (already rendered)
    if msg isa AbstractDict
        return _dict_to_input_message(msg)
    end

    # Detect message type from PT
    type_name = lowercase(string(typeof(msg).name.name))

    if occursin("system", type_name)
        return InputMessage(ROLE_SYSTEM, [TextPart(_get_content(msg))])

    elseif occursin("usermessagewithimage", type_name)
        parts = AbstractMessagePart[TextPart(_get_content(msg))]
        if hasproperty(msg, :image_url) && msg.image_url !== nothing
            for img in (msg.image_url isa Vector ? msg.image_url : [msg.image_url])
                push!(parts, _image_to_part(img))
            end
        end
        return InputMessage(ROLE_USER, parts)

    elseif occursin("user", type_name)
        return InputMessage(ROLE_USER, [TextPart(_get_content(msg))])

    elseif occursin("aitoolrequest", type_name)
        tool_calls = hasproperty(msg, :tool_calls) ? msg.tool_calls : []
        parts = AbstractMessagePart[]

        content = _get_content(msg)
        if !isempty(content)
            push!(parts, TextPart(content))
        end

        for tc in tool_calls
            push!(parts, _tool_message_to_part(tc))
        end

        return InputMessage(ROLE_ASSISTANT, isempty(parts) ? [TextPart("")] : parts)

    elseif occursin("tool", type_name) && !occursin("request", type_name)
        tool_call_id = hasproperty(msg, :tool_call_id) ? msg.tool_call_id : nothing
        tool_name = hasproperty(msg, :name) ? msg.name : nothing
        response = _get_content(msg)
        # Use ROLE_USER for tool responses (Logfire expects this format)
        return InputMessage(ROLE_USER,
            [ToolCallResponsePart(
                response;
                id = tool_call_id !== nothing ? string(tool_call_id) : nothing,
                name = tool_name !== nothing ? string(tool_name) : nothing
            )])

    elseif occursin("ai", type_name) || occursin("assistant", type_name)
        return InputMessage(ROLE_ASSISTANT, [TextPart(_get_content(msg))])

    elseif occursin("data", type_name)
        # DataMessage from aiextract - contains extracted struct in content
        content = _get_content(msg)
        return InputMessage(ROLE_ASSISTANT, [TextPart(content)])

    else
        return InputMessage(ROLE_USER, [TextPart(_get_content(msg))])
    end
end

"""
    pt_message_to_output(msg; finish_reason=nothing) -> OutputMessage

Convert a PromptingTools message to an OTEL OutputMessage.
Automatically detects finish_reason if not provided.
"""
function pt_message_to_output(msg; finish_reason::Union{
        FinishReason, Nothing} = nothing)::OutputMessage
    input = pt_message_to_input(msg)

    # Auto-detect finish reason
    if finish_reason === nothing
        finish_reason = _detect_finish_reason(input)
    end

    return OutputMessage(input.role, input.parts, finish_reason; name = input.name)
end

"""
    pt_conversation_to_otel(conv; separate_system=true) -> NamedTuple

Convert a PromptingTools conversation to OTEL format.

Returns `(; input_messages, output_messages, system_instructions)`.

If `separate_system=true`, system messages are extracted to `system_instructions`.
"""
function pt_conversation_to_otel(conv::AbstractVector; separate_system::Bool = true)
    input_msgs = InputMessage[]
    system_parts = AbstractMessagePart[]

    for msg in conv
        input_msg = pt_message_to_input(msg)

        if separate_system && input_msg.role == ROLE_SYSTEM
            append!(system_parts, input_msg.parts)
        else
            push!(input_msgs, input_msg)
        end
    end

    # Last assistant message becomes output (with finish_reason)
    output_msgs = OutputMessage[]
    if !isempty(input_msgs) && input_msgs[end].role == ROLE_ASSISTANT
        last_msg = pop!(input_msgs)
        finish_reason = _detect_finish_reason(last_msg)
        push!(output_msgs,
            OutputMessage(last_msg.role, last_msg.parts, finish_reason; name = last_msg.name))
    end

    return (
        input_messages = input_msgs,
        output_messages = output_msgs,
        system_instructions = isempty(system_parts) ? nothing : system_parts
    )
end

# =============================================================================
# Tool Definitions from PromptingTools
# =============================================================================

"""
    tool_definitions_from_pt(tool_map) -> Vector{ToolDefinition}

Convert PromptingTools tool signatures to OTEL tool definitions.

# Example
```julia
get_weather(city::String) = "sunny"
tools = [get_weather]
tool_map = PT.tool_call_signature(tools)
defs = tool_definitions_from_pt(tool_map)
```
"""
function tool_definitions_from_pt(tool_map::AbstractDict)::Vector{ToolDefinition}
    definitions = ToolDefinition[]

    for (name, tool) in tool_map
        # Extract schema from PT tool signature
        if hasproperty(tool, :parameters) ||
           (tool isa AbstractDict && haskey(tool, :parameters))
            schema = tool isa AbstractDict ? get(tool, :parameters, Dict()) :
                     (hasproperty(tool, :parameters) ? tool.parameters : Dict())
            desc = _get_tool_description(tool)
            push!(definitions,
                ToolDefinition(
                    string(name);
                    description = desc,
                    parameters = schema isa AbstractDict ?
                                 Dict{String, Any}(string(k) => v for (k, v) in schema) :
                                 Dict{String, Any}()
                ))
        else
            push!(definitions, ToolDefinition(string(name)))
        end
    end

    return definitions
end

"""
    tool_definitions_from_functions(tools::Vector) -> Vector{ToolDefinition}

Create tool definitions from a vector of functions using PT.tool_call_signature.
"""
function tool_definitions_from_functions(tools::Vector)::Vector{ToolDefinition}
    tool_map = PT.tool_call_signature(tools)
    return tool_definitions_from_pt(tool_map)
end

# =============================================================================
# Span Attribute Setters
# =============================================================================

"""
    set_genai_messages!(span, conv; separate_system=true)

Set gen_ai.input.messages, gen_ai.output.messages, and gen_ai.system_instructions
on a span from a PromptingTools conversation.
"""
function set_genai_messages!(span, conv::AbstractVector; separate_system::Bool = true)
    result = pt_conversation_to_otel(conv; separate_system)

    if !isempty(result.input_messages)
        set_span_attribute!(span, "gen_ai.input.messages", messages_to_json(result.input_messages))
    end

    if !isempty(result.output_messages)
        set_span_attribute!(span, "gen_ai.output.messages", messages_to_json(result.output_messages))
    end

    if result.system_instructions !== nothing
        set_span_attribute!(span, "gen_ai.system_instructions",
            system_instructions_to_json(result.system_instructions))
    end
end

"""
    set_tool_definitions!(span, tool_map)

Set gen_ai.tool.definitions on a span from PromptingTools tool signatures.
"""
function set_tool_definitions!(span, tool_map::AbstractDict)
    definitions = tool_definitions_from_pt(tool_map)
    if !isempty(definitions)
        set_span_attribute!(span, "gen_ai.tool.definitions", tool_definitions_to_json(definitions))
    end
end

"""
    set_tool_definitions!(span, tools::Vector)

Set gen_ai.tool.definitions on a span from a vector of functions.
"""
function set_tool_definitions!(span, tools::Vector)
    definitions = tool_definitions_from_functions(tools)
    if !isempty(definitions)
        set_span_attribute!(span, "gen_ai.tool.definitions", tool_definitions_to_json(definitions))
    end
end

# =============================================================================
# Internal Helpers
# =============================================================================

_get_content(msg) = hasproperty(msg, :content) ? string(something(msg.content, "")) : ""

function _get_tool_description(tool)
    if tool isa AbstractDict
        return string(get(tool, :description, get(tool, "description", "")))
    elseif hasproperty(tool, :description)
        return string(something(tool.description, ""))
    end
    return ""
end

function _dict_to_input_message(msg::AbstractDict)::InputMessage
    role_str = string(get(msg, "role", get(msg, :role, "user")))
    role = string_to_role(role_str)
    content = get(msg, "content", get(msg, :content, ""))
    tool_calls = get(msg, "tool_calls", get(msg, :tool_calls, nothing))
    tool_call_id = get(msg, "tool_call_id", get(msg, :tool_call_id, nothing))
    tool_name = get(msg, "name", get(msg, :name, nothing))

    parts = if tool_calls !== nothing && !isempty(tool_calls)
        AbstractMessagePart[_dict_tool_call_to_part(tc) for tc in tool_calls]
    elseif tool_call_id !== nothing
        # Tool responses should use ROLE_USER for Logfire compatibility
        role = ROLE_USER
        [ToolCallResponsePart(content; id = string(tool_call_id),
            name = tool_name !== nothing ? string(tool_name) : nothing)]
    else
        [TextPart(string(content))]
    end

    return InputMessage(role, parts)
end

function _tool_message_to_part(tc)::ToolCallRequestPart
    id = hasproperty(tc, :tool_call_id) ? tc.tool_call_id : nothing
    name = hasproperty(tc, :name) ? tc.name : "unknown"
    args = hasproperty(tc, :raw) ? tc.raw : nothing

    arguments = if args isa AbstractString && !isempty(args)
        try
            JSON3.read(args, Dict{String, Any})
        catch
            args
        end
    else
        args
    end

    ToolCallRequestPart(string(name); id = id !== nothing ? string(id) : nothing, arguments = arguments)
end

function _dict_tool_call_to_part(tc::AbstractDict)::ToolCallRequestPart
    func = get(tc, "function", get(tc, :function, Dict()))
    ToolCallRequestPart(
        string(get(func, "name", get(tc, "name", get(tc, :name, "unknown")))),
        id = get(tc, "id", get(tc, :id, nothing)),
        arguments = get(func, "arguments", get(tc, "arguments", get(tc, :arguments, nothing)))
    )
end

function _image_to_part(img)::AbstractMessagePart
    if startswith(img, "data:")
        BlobPart(MODALITY_IMAGE, img)
    else
        UriPart(MODALITY_IMAGE, img)
    end
end

function _detect_finish_reason(msg::InputMessage)::FinishReason
    for part in msg.parts
        if part isa ToolCallRequestPart
            return FINISH_TOOL_CALL
        end
    end
    return FINISH_STOP
end
