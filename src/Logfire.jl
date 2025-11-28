module Logfire

using DotEnv
using HTTP
using JSON3
using OpenTelemetryAPI
using OpenTelemetrySDK
using OpenTelemetryExporterOtlpProtoHttp

# Include source files in order
include("constants.jl")
include("types.jl")
include("config.jl")
include("resource.jl")
include("exporter.jl")
include("providers.jl")
include("spans.jl")
include("logfire_schema.jl")
include("otel_genai.jl")
include("instrumentation/promptingtools.jl")
include("query.jl")

# Export public API
export configure,
       shutdown!,
       flush!,
       is_configured,
       get_config,
# Span utilities
       with_span,
       with_llm_span,
       set_span_attribute!,
       set_span_status_error!,
       record_exception!,
       record_token_usage!,
       add_prompt_attribute!,
       add_response_attribute!,
       tracer,
# Instrumentation
       LogfireSchema,
       wrap,
       instrument_promptingtools!,
       instrument_promptingtools_model!,
       uninstrument_promptingtools!,
# OTEL GenAI Types - Enums
       Role, ROLE_SYSTEM, ROLE_USER, ROLE_ASSISTANT, ROLE_TOOL,
       role_to_string, string_to_role,
       FinishReason, FINISH_STOP, FINISH_LENGTH, FINISH_CONTENT_FILTER, FINISH_TOOL_CALL,
       FINISH_ERROR,
       finish_reason_to_string, string_to_finish_reason,
       Modality, MODALITY_IMAGE, MODALITY_VIDEO, MODALITY_AUDIO,
       modality_to_string, string_to_modality,
       OperationName, OP_CHAT, OP_CREATE_AGENT, OP_EMBEDDINGS, OP_EXECUTE_TOOL,
       OP_GENERATE_CONTENT, OP_INVOKE_AGENT, OP_TEXT_COMPLETION,
       operation_name_to_string, string_to_operation_name,
       OutputType, OUTPUT_TEXT, OUTPUT_JSON, OUTPUT_IMAGE, OUTPUT_SPEECH,
       output_type_to_string, string_to_output_type,
       ERROR_TYPE_OTHER,
# OTEL GenAI Types - Message Parts
       AbstractMessagePart, TextPart, ToolCallRequestPart, ToolCallResponsePart,
       BlobPart, UriPart, FilePart, ReasoningPart, GenericPart,
# OTEL GenAI Types - Messages
       InputMessage, OutputMessage, ToolDefinition,
       to_dict, part_to_dict, messages_to_json, system_instructions_to_json,
       tool_definitions_to_json,
# OTEL GenAI Utilities
       pt_message_to_input, pt_message_to_output, pt_conversation_to_otel,
       tool_definitions_from_pt, tool_definitions_from_functions,
       set_genai_messages!, set_tool_definitions!,
# Query API
       LogfireQueryClient, query_json, query_csv,
       QUERY_ENDPOINT_US, QUERY_ENDPOINT_EU

end # module Logfire
