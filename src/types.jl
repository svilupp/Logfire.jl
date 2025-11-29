# OpenTelemetry GenAI Semantic Convention Types
#
# Julia types matching the OTEL GenAI message schemas for strong typing and validation.
# Reference: https://opentelemetry.io/docs/specs/semconv/gen-ai/

using JSON3

# =============================================================================
# Enums
# =============================================================================

"""
Role of the entity that created the message.
"""
@enum Role begin
    ROLE_SYSTEM = 1
    ROLE_USER = 2
    ROLE_ASSISTANT = 3
    ROLE_TOOL = 4
end

const ROLE_STRING_MAP = Dict{Role, String}(
    ROLE_SYSTEM => "system",
    ROLE_USER => "user",
    ROLE_ASSISTANT => "assistant",
    ROLE_TOOL => "tool"
)

const STRING_ROLE_MAP = Dict{String, Role}(v => k for (k, v) in ROLE_STRING_MAP)

role_to_string(r::Role) = ROLE_STRING_MAP[r]
string_to_role(s::AbstractString) = get(STRING_ROLE_MAP, lowercase(s), ROLE_USER)

"""
Reason for finishing the generation.
"""
@enum FinishReason begin
    FINISH_STOP = 1
    FINISH_LENGTH = 2
    FINISH_CONTENT_FILTER = 3
    FINISH_TOOL_CALL = 4
    FINISH_ERROR = 5
end

const FINISH_REASON_STRING_MAP = Dict{FinishReason, String}(
    FINISH_STOP => "stop",
    FINISH_LENGTH => "length",
    FINISH_CONTENT_FILTER => "content_filter",
    FINISH_TOOL_CALL => "tool_call",
    FINISH_ERROR => "error"
)

const STRING_FINISH_REASON_MAP = Dict{String, FinishReason}(v => k
for (k, v) in FINISH_REASON_STRING_MAP)

finish_reason_to_string(fr::FinishReason) = FINISH_REASON_STRING_MAP[fr]
function string_to_finish_reason(s::AbstractString)
    get(STRING_FINISH_REASON_MAP, lowercase(s), FINISH_STOP)
end

"""
Modality of media content.
"""
@enum Modality begin
    MODALITY_IMAGE = 1
    MODALITY_VIDEO = 2
    MODALITY_AUDIO = 3
end

const MODALITY_STRING_MAP = Dict{Modality, String}(
    MODALITY_IMAGE => "image",
    MODALITY_VIDEO => "video",
    MODALITY_AUDIO => "audio"
)

const STRING_MODALITY_MAP = Dict{String, Modality}(v => k for (k, v) in MODALITY_STRING_MAP)

modality_to_string(m::Modality) = MODALITY_STRING_MAP[m]
function string_to_modality(s::AbstractString)
    get(STRING_MODALITY_MAP, lowercase(s), MODALITY_IMAGE)
end

"""
GenAI operation type.

Well-known values from OTEL semantic conventions:
- `chat`: Chat completion (e.g., OpenAI Chat API)
- `create_agent`: Create GenAI agent
- `embeddings`: Embeddings operation
- `execute_tool`: Execute a tool
- `generate_content`: Multimodal content generation (e.g., Gemini)
- `invoke_agent`: Invoke GenAI agent
- `text_completion`: Text completions (legacy)
"""
@enum OperationName begin
    OP_CHAT = 1
    OP_CREATE_AGENT = 2
    OP_EMBEDDINGS = 3
    OP_EXECUTE_TOOL = 4
    OP_GENERATE_CONTENT = 5
    OP_INVOKE_AGENT = 6
    OP_TEXT_COMPLETION = 7
end

const OPERATION_NAME_STRING_MAP = Dict{OperationName, String}(
    OP_CHAT => "chat",
    OP_CREATE_AGENT => "create_agent",
    OP_EMBEDDINGS => "embeddings",
    OP_EXECUTE_TOOL => "execute_tool",
    OP_GENERATE_CONTENT => "generate_content",
    OP_INVOKE_AGENT => "invoke_agent",
    OP_TEXT_COMPLETION => "text_completion"
)

const STRING_OPERATION_NAME_MAP = Dict{String, OperationName}(v => k
for (k, v) in OPERATION_NAME_STRING_MAP)

operation_name_to_string(op::OperationName) = OPERATION_NAME_STRING_MAP[op]
function string_to_operation_name(s::AbstractString)
    get(STRING_OPERATION_NAME_MAP, lowercase(s), OP_CHAT)
end

"""
GenAI output type.

Well-known values from OTEL semantic conventions:
- `text`: Plain text
- `json`: JSON object with known or unknown schema
- `image`: Image
- `speech`: Speech
"""
@enum OutputType begin
    OUTPUT_TEXT = 1
    OUTPUT_JSON = 2
    OUTPUT_IMAGE = 3
    OUTPUT_SPEECH = 4
end

const OUTPUT_TYPE_STRING_MAP = Dict{OutputType, String}(
    OUTPUT_TEXT => "text",
    OUTPUT_JSON => "json",
    OUTPUT_IMAGE => "image",
    OUTPUT_SPEECH => "speech"
)

const STRING_OUTPUT_TYPE_MAP = Dict{String, OutputType}(v => k
for (k, v) in OUTPUT_TYPE_STRING_MAP)

output_type_to_string(ot::OutputType) = OUTPUT_TYPE_STRING_MAP[ot]
function string_to_output_type(s::AbstractString)
    get(STRING_OUTPUT_TYPE_MAP, lowercase(s), OUTPUT_TEXT)
end

"""
Error type for GenAI operations.

Well-known value from OTEL semantic conventions:
- `_OTHER`: Fallback error value when no custom value is defined

Custom values may be used for specific error types.
"""
const ERROR_TYPE_OTHER = "_OTHER"

# =============================================================================
# Abstract Types
# =============================================================================

"""
Abstract base type for all message parts.
"""
abstract type AbstractMessagePart end

# =============================================================================
# Message Part Types
# =============================================================================

"""
    TextPart

Represents text content sent to or received from the model.

# Fields
- `content::String`: Text content
"""
struct TextPart <: AbstractMessagePart
    content::String
end

"""
    ToolCallRequestPart

Represents a tool call requested by the model.

# Fields
- `name::String`: Name of the tool
- `id::Union{String,Nothing}`: Unique identifier for the tool call
- `arguments::Any`: Arguments for the tool call (Dict, String, or nothing)
"""
struct ToolCallRequestPart <: AbstractMessagePart
    name::String
    id::Union{String, Nothing}
    arguments::Any

    function ToolCallRequestPart(name::String; id = nothing, arguments = nothing)
        new(name, id, arguments)
    end
end

"""
    ToolCallResponsePart

Represents a tool call result sent to the model.

# Fields
- `response::Any`: Tool call response
- `id::Union{String,Nothing}`: Unique tool call identifier
- `name::Union{String,Nothing}`: Name of the tool that was called
"""
struct ToolCallResponsePart <: AbstractMessagePart
    response::Any
    id::Union{String, Nothing}
    name::Union{String, Nothing}

    ToolCallResponsePart(response; id = nothing, name = nothing) = new(response, id, name)
end

"""
    BlobPart

Represents blob binary data sent inline to the model.

# Fields
- `modality::Modality`: The general modality (image, video, audio)
- `content::String`: Base64-encoded binary content
- `mime_type::Union{String,Nothing}`: IANA MIME type
"""
struct BlobPart <: AbstractMessagePart
    modality::Modality
    content::String
    mime_type::Union{String, Nothing}

    function BlobPart(modality::Modality, content::String; mime_type = nothing)
        new(modality, content, mime_type)
    end
end

"""
    UriPart

Represents an external referenced file sent to the model by URI.

# Fields
- `modality::Modality`: The general modality (image, video, audio)
- `uri::String`: URI referencing the data
- `mime_type::Union{String,Nothing}`: IANA MIME type
"""
struct UriPart <: AbstractMessagePart
    modality::Modality
    uri::String
    mime_type::Union{String, Nothing}

    function UriPart(modality::Modality, uri::String; mime_type = nothing)
        new(modality, uri, mime_type)
    end
end

"""
    FilePart

Represents an external referenced file sent to the model by file ID.

# Fields
- `modality::Modality`: The general modality (image, video, audio)
- `file_id::String`: Identifier referencing a pre-uploaded file
- `mime_type::Union{String,Nothing}`: IANA MIME type
"""
struct FilePart <: AbstractMessagePart
    modality::Modality
    file_id::String
    mime_type::Union{String, Nothing}

    function FilePart(modality::Modality, file_id::String; mime_type = nothing)
        new(modality, file_id, mime_type)
    end
end

"""
    ReasoningPart

Represents reasoning/thinking content received from the model.

# Fields
- `content::String`: Reasoning/thinking content
"""
struct ReasoningPart <: AbstractMessagePart
    content::String
end

"""
    GenericPart

Represents an arbitrary message part with custom type.
Allows extensibility with custom message part types.

# Fields
- `type::String`: The type identifier
- `properties::Dict{String,Any}`: Additional properties
"""
struct GenericPart <: AbstractMessagePart
    type::String
    properties::Dict{String, Any}

    GenericPart(type::String; properties = Dict{String, Any}()) = new(type, properties)
end

# =============================================================================
# Message Types
# =============================================================================

"""
    InputMessage

Represents an input message sent to the model.

# Fields
- `role::Role`: Role of the entity that created the message
- `parts::Vector{AbstractMessagePart}`: List of message parts
- `name::Union{String,Nothing}`: Optional participant name
"""
struct InputMessage
    role::Role
    parts::Vector{<:AbstractMessagePart}
    name::Union{String, Nothing}

    function InputMessage(role::Role, parts::Vector{<:AbstractMessagePart}; name = nothing)
        new(role, parts, name)
    end
    function InputMessage(role::String, parts::Vector{<:AbstractMessagePart}; name = nothing)
        new(string_to_role(role), parts, name)
    end
end

function to_dict(msg::InputMessage)
    d = Dict{String, Any}(
        "role" => role_to_string(msg.role),
        "parts" => [part_to_dict(p) for p in msg.parts]
    )
    msg.name !== nothing && (d["name"] = msg.name)
    return d
end

"""
    OutputMessage

Represents an output message generated by the model.

# Fields
- `role::Role`: Role of the entity that created the message
- `parts::Vector{AbstractMessagePart}`: List of message parts
- `finish_reason::FinishReason`: Reason for finishing generation
- `name::Union{String,Nothing}`: Optional participant name
"""
struct OutputMessage
    role::Role
    parts::Vector{<:AbstractMessagePart}
    finish_reason::FinishReason
    name::Union{String, Nothing}

    function OutputMessage(role::Role, parts::Vector{<:AbstractMessagePart},
            finish_reason::FinishReason; name = nothing)
        new(role, parts, finish_reason, name)
    end
    function OutputMessage(role::String, parts::Vector{<:AbstractMessagePart},
            finish_reason::String; name = nothing)
        new(string_to_role(role), parts, string_to_finish_reason(finish_reason), name)
    end
end

function to_dict(msg::OutputMessage)
    d = Dict{String, Any}(
        "role" => role_to_string(msg.role),
        "parts" => [part_to_dict(p) for p in msg.parts],
        "finish_reason" => finish_reason_to_string(msg.finish_reason)
    )
    msg.name !== nothing && (d["name"] = msg.name)
    return d
end

# =============================================================================
# Helper Functions for Serialization
# =============================================================================

"""
Convert any message part to a Dict for JSON serialization.
"""
function part_to_dict(p::TextPart)
    Dict{String, Any}("type" => "text", "content" => p.content)
end

function part_to_dict(p::ToolCallRequestPart)
    d = Dict{String, Any}("type" => "tool_call", "name" => p.name)
    p.id !== nothing && (d["id"] = p.id)
    p.arguments !== nothing && (d["arguments"] = p.arguments)
    return d
end

function part_to_dict(p::ToolCallResponsePart)
    d = Dict{String, Any}("type" => "tool_call_response", "result" => p.response)
    p.id !== nothing && (d["id"] = p.id)
    p.name !== nothing && (d["name"] = p.name)
    return d
end

function part_to_dict(p::BlobPart)
    d = Dict{String, Any}(
        "type" => "blob",
        "modality" => modality_to_string(p.modality),
        "content" => p.content
    )
    p.mime_type !== nothing && (d["mime_type"] = p.mime_type)
    return d
end

function part_to_dict(p::UriPart)
    d = Dict{String, Any}(
        "type" => "uri",
        "modality" => modality_to_string(p.modality),
        "uri" => p.uri
    )
    p.mime_type !== nothing && (d["mime_type"] = p.mime_type)
    return d
end

function part_to_dict(p::FilePart)
    d = Dict{String, Any}(
        "type" => "file",
        "modality" => modality_to_string(p.modality),
        "file_id" => p.file_id
    )
    p.mime_type !== nothing && (d["mime_type"] = p.mime_type)
    return d
end

function part_to_dict(p::ReasoningPart)
    Dict{String, Any}("type" => "reasoning", "content" => p.content)
end

function part_to_dict(p::GenericPart)
    d = Dict{String, Any}("type" => p.type)
    merge!(d, p.properties)
    return d
end

# =============================================================================
# Top-Level Serialization
# =============================================================================

"""
    messages_to_json(messages::Vector{InputMessage}) -> String

Serialize input messages to JSON string for gen_ai.input.messages attribute.
"""
function messages_to_json(messages::Vector{<:InputMessage})
    JSON3.write([to_dict(m) for m in messages])
end

"""
    messages_to_json(messages::Vector{OutputMessage}) -> String

Serialize output messages to JSON string for gen_ai.output.messages attribute.
"""
function messages_to_json(messages::Vector{<:OutputMessage})
    JSON3.write([to_dict(m) for m in messages])
end

"""
    system_instructions_to_json(parts::Vector{<:AbstractMessagePart}) -> String

Serialize system instructions to JSON string for gen_ai.system_instructions attribute.
"""
function system_instructions_to_json(parts::Vector{<:AbstractMessagePart})
    JSON3.write([part_to_dict(p) for p in parts])
end

# =============================================================================
# Tool Definition Type
# =============================================================================

"""
    ToolDefinition

Represents a tool definition in OpenAI function format.

# Fields
- `name::String`: Tool name
- `description::String`: Tool description
- `parameters::Dict{String,Any}`: JSON Schema for parameters
"""
struct ToolDefinition
    name::String
    description::String
    parameters::Dict{String, Any}

    function ToolDefinition(name::String; description = "", parameters = Dict{String, Any}())
        new(name, description, parameters)
    end
end

function to_dict(td::ToolDefinition)
    Dict{String, Any}(
        "type" => "function",
        "name" => td.name,
        "description" => td.description,
        "parameters" => td.parameters
    )
end

"""
    tool_definitions_to_json(tools::Vector{ToolDefinition}) -> String

Serialize tool definitions to JSON string for gen_ai.tool.definitions attribute.
"""
function tool_definitions_to_json(tools::Vector{ToolDefinition})
    JSON3.write([to_dict(t) for t in tools])
end
