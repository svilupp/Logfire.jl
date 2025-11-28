# OpenTelemetry GenAI Semantic Conventions

Logfire.jl implements the [OpenTelemetry GenAI Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/) for tracing LLM operations, with specific adaptations for [Logfire](https://logfire.pydantic.dev/) compatibility. This document describes the attributes and formats used.

## Logfire-Specific Deviations from OTEL Standard

While Logfire.jl follows the OTEL GenAI semantic conventions, it uses **Logfire's message format** which differs from the standard in several ways. These deviations ensure proper rendering in the Logfire UI.

### Tool Call Responses

The OTEL specification defines `ToolCallResponsePart` with a `response` field and `role: "tool"` for tool result messages. However, Logfire expects:

| Aspect | OTEL Standard | Logfire Format |
|--------|---------------|----------------|
| Field name | `response` | `result` |
| Message role | `tool` | `user` |
| Tool name | Not specified | `name` field included |

**OTEL Standard format:**
```json
{
  "role": "tool",
  "parts": [{"type": "tool_call_response", "id": "call_123", "response": "22°C"}]
}
```

**Logfire format (what this library produces):**
```json
{
  "role": "user",
  "parts": [{"type": "tool_call_response", "id": "call_123", "name": "get_weather", "result": "22°C"}]
}
```

### Why These Deviations?

Logfire's UI has specific expectations for how tool results are displayed. Using the standard OTEL format results in tool responses being marked as "Unrecognised" in the Logfire dashboard. The Logfire format ensures:

1. **Proper visualization** - Tool results render correctly in the conversation view
2. **Tool identification** - The `name` field allows Logfire to associate results with their corresponding tool calls
3. **Role consistency** - Using `role: "user"` matches how Logfire processes tool results internally

### Reference Specifications

- **OTEL GenAI Semantic Conventions**: [opentelemetry.io/docs/specs/semconv/gen-ai/](https://opentelemetry.io/docs/specs/semconv/gen-ai/)
- **OTEL GenAI Attributes Registry**: [opentelemetry.io/docs/specs/semconv/registry/attributes/gen-ai/](https://opentelemetry.io/docs/specs/semconv/registry/attributes/gen-ai/)
- **Logfire Documentation**: [logfire.pydantic.dev/](https://logfire.pydantic.dev/)

## References

- [GenAI Spans](https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-spans/)
- [GenAI Agent Spans](https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-agent-spans/)
- [GenAI Events](https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-events/)

## Operation Types

The `gen_ai.operation.name` attribute identifies the type of GenAI operation:

| Value | Description | Example |
|-------|-------------|---------|
| `chat` | Chat completion | OpenAI Chat API, `aigenerate` |
| `create_agent` | Create GenAI agent | Agent initialization |
| `embeddings` | Embeddings operation | `aiembed` |
| `execute_tool` | Execute a tool | Tool execution spans |
| `generate_content` | Multimodal content generation | Gemini Generate Content |
| `invoke_agent` | Invoke GenAI agent | Agent invocation |
| `text_completion` | Text completions (legacy) | Legacy completions API |

## Span Attributes

### Required Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `gen_ai.operation.name` | string | Operation type (see above) |
| `gen_ai.provider.name` | string | Provider identifier (e.g., "openai", "anthropic") |

### Request Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `gen_ai.request.model` | string | Model requested (e.g., "gpt-4o-mini") |
| `gen_ai.request.temperature` | double | Temperature setting |
| `gen_ai.request.max_tokens` | int | Maximum tokens for response |
| `gen_ai.request.top_p` | double | Top-p sampling setting |
| `gen_ai.request.frequency_penalty` | double | Frequency penalty |
| `gen_ai.request.presence_penalty` | double | Presence penalty |
| `gen_ai.request.stop_sequences` | string[] | Stop sequences |
| `gen_ai.request.seed` | int | Random seed if used |

### Response Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `gen_ai.response.model` | string | Model that generated response |
| `gen_ai.response.id` | string | Completion identifier |
| `gen_ai.response.finish_reasons` | string[] | Why model stopped generating |
| `gen_ai.usage.input_tokens` | int | Tokens in prompt |
| `gen_ai.usage.output_tokens` | int | Tokens in response |

### Output Type

The `gen_ai.output.type` attribute describes the output format:

| Value | Description |
|-------|-------------|
| `text` | Plain text |
| `json` | JSON object (known or unknown schema) |
| `image` | Image |
| `speech` | Speech |

## Message Formats

Messages follow a parts-based format with the following structure.

### Input Messages (`gen_ai.input.messages`)

Array of messages sent to the model:

```json
[
  {
    "role": "user",
    "parts": [{"type": "text", "content": "What's the weather?"}]
  },
  {
    "role": "assistant",
    "parts": [
      {"type": "tool_call", "id": "call_123", "name": "get_weather", "arguments": {"city": "Paris"}}
    ]
  },
  {
    "role": "user",
    "parts": [
      {"type": "tool_call_response", "id": "call_123", "name": "get_weather", "result": "22°C, sunny"}
    ]
  }
]
```

> **Note:** Tool call responses use `role: "user"` and `result` field for Logfire compatibility. See [Logfire-Specific Deviations](#logfire-specific-deviations-from-otel-standard) for details.

### Output Messages (`gen_ai.output.messages`)

Array of messages returned by the model (includes `finish_reason`):

```json
[
  {
    "role": "assistant",
    "parts": [{"type": "text", "content": "The weather in Paris is 22°C and sunny."}],
    "finish_reason": "stop"
  }
]
```

### System Instructions (`gen_ai.system_instructions`)

System prompt separate from chat history:

```json
[
  {"type": "text", "content": "You are a helpful weather assistant."}
]
```

## Message Roles

| Role | Description |
|------|-------------|
| `system` | System instructions |
| `user` | User input (also used for tool execution results in Logfire format) |
| `assistant` | Model response |

> **Note:** The OTEL standard defines a `tool` role, but Logfire expects tool results to use `role: "user"`. See [Logfire-Specific Deviations](#logfire-specific-deviations-from-otel-standard).

## Message Part Types

### TextPart

Plain text content:

```json
{"type": "text", "content": "Hello, world!"}
```

### ToolCallRequestPart

Tool call requested by the model:

```json
{
  "type": "tool_call",
  "id": "call_abc123",
  "name": "get_weather",
  "arguments": {"city": "Paris", "unit": "celsius"}
}
```

### ToolCallResponsePart

Tool execution result (Logfire format):

```json
{
  "type": "tool_call_response",
  "id": "call_abc123",
  "name": "get_weather",
  "result": "22°C, sunny"
}
```

> **Note:** Uses `result` (not `response`) and includes `name` for Logfire compatibility.

### BlobPart

Inline binary data (base64-encoded):

```json
{
  "type": "blob",
  "modality": "image",
  "mime_type": "image/png",
  "content": "iVBORw0KGgoAAAANSUhEUgAA..."
}
```

### UriPart

External file by URI:

```json
{
  "type": "uri",
  "modality": "image",
  "uri": "https://example.com/image.png"
}
```

### FilePart

Pre-uploaded file by ID:

```json
{
  "type": "file",
  "modality": "image",
  "file_id": "file-abc123"
}
```

### ReasoningPart

Model reasoning/thinking content:

```json
{"type": "reasoning", "content": "Let me think about this..."}
```

## Finish Reasons

| Value | Description |
|-------|-------------|
| `stop` | Natural completion |
| `length` | Max tokens reached |
| `content_filter` | Content filtered |
| `tool_call` | Model requested tool execution |
| `error` | Error occurred |

## Tool Definitions (`gen_ai.tool.definitions`)

Array of available tools in OpenAI function format:

```json
[
  {
    "type": "function",
    "name": "get_weather",
    "description": "Get current weather for a city",
    "parameters": {
      "type": "object",
      "properties": {
        "city": {"type": "string", "description": "City name"},
        "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
      },
      "required": ["city"]
    }
  }
]
```

## Error Handling

When an error occurs, set `error.type`:

| Value | Description |
|-------|-------------|
| `_OTHER` | Fallback error value |
| Custom | Specific error type (e.g., "rate_limit", "invalid_api_key") |

## Julia Types

Logfire.jl provides Julia types for all message formats in `src/types.jl`:

```julia
using Logfire: TextPart, ToolCallRequestPart, ToolCallResponsePart
using Logfire: InputMessage, OutputMessage
using Logfire: ROLE_USER, ROLE_ASSISTANT, FINISH_STOP

# Create a text message
msg = InputMessage(ROLE_USER, [TextPart("Hello!")])

# Create a tool call response
response = OutputMessage(
    ROLE_ASSISTANT,
    [TextPart("The weather is sunny.")],
    FINISH_STOP
)
```

## Usage with PromptingTools

When using the `LogfireSchema` wrapper, messages are automatically converted:

```julia
using DotEnv
DotEnv.load!()  # Load .env file (must call explicitly)

using Logfire
using PromptingTools

Logfire.configure()
Logfire.instrument_promptingtools!()

# Messages are automatically traced with OTEL GenAI attributes
response = aigenerate("What is 2+2?")
```

The tracer extracts:
- System messages → `gen_ai.system_instructions`
- Conversation history → `gen_ai.input.messages`
- Model response → `gen_ai.output.messages`
- Tool definitions (if using `aitools`) → `gen_ai.tool.definitions`

### Tool Calls Example

```julia
using DotEnv
DotEnv.load!()

using Logfire
using PromptingTools
import PromptingTools as PT

Logfire.configure()
Logfire.instrument_promptingtools!()

# Define tools
"Get weather for a city"
get_weather(city::String) = "22°C, sunny"

"Get current time for a city"
get_time(city::String) = "3:45 PM"

tools = [get_weather, get_time]
tool_map = PT.tool_call_signature(tools)

# Multi-turn conversation with tools
conv = aitools("What's the weather in Paris?"; tools, model="gpt4om", return_all=true)

# Execute tool calls
if conv[end] isa PT.AIToolRequest
    for tc in conv[end].tool_calls
        tc.content = string(PT.execute_tool(tool_map, tc))
        push!(conv, tc)
    end
end

# Get final response
resp = aigenerate(conv; model="gpt4om")
push!(conv, resp)
```

## Julia API Reference

### Creating Messages Manually

```julia
using Logfire

# Create a user message with text
user_msg = InputMessage(ROLE_USER, [TextPart("What's the weather?")])

# Create an assistant response with tool call
assistant_msg = InputMessage(ROLE_ASSISTANT, [
    ToolCallRequestPart("get_weather"; id="call_123", arguments=Dict("city" => "Paris"))
])

# Create a tool response (uses ROLE_USER for Logfire compatibility)
tool_msg = InputMessage(ROLE_USER, [
    ToolCallResponsePart("22°C, sunny"; id="call_123", name="get_weather")
])

# Create output message with finish reason
output = OutputMessage(ROLE_ASSISTANT, [TextPart("The weather is sunny.")], FINISH_STOP)

# Serialize to JSON
json_input = messages_to_json([user_msg, assistant_msg, tool_msg])
json_output = messages_to_json([output])
```

### Creating Tool Definitions

```julia
using Logfire

# Create tool definition manually
tool = ToolDefinition(
    "get_weather";
    description="Get current weather for a city",
    parameters=Dict{String,Any}(
        "type" => "object",
        "properties" => Dict(
            "city" => Dict("type" => "string", "description" => "City name"),
            "unit" => Dict("type" => "string", "enum" => ["celsius", "fahrenheit"])
        ),
        "required" => ["city"]
    )
)

# Serialize to JSON
json = tool_definitions_to_json([tool])
```

### Converting PromptingTools Messages

```julia
using Logfire
using PromptingTools as PT

# Convert a PT conversation to OTEL format
conv = [
    PT.SystemMessage("You are helpful"),
    PT.UserMessage("Hello"),
    PT.AIMessage("Hi there!")
]

# Convert with system message extraction
result = pt_conversation_to_otel(conv; separate_system=true)

# Access converted messages
println(result.system_instructions)  # Array of TextPart
println(result.input_messages)       # Array of InputMessage
println(result.output_messages)      # Array of OutputMessage
```

### Setting Span Attributes

```julia
using Logfire
using OpenTelemetryAPI

# Create a span
span = create_span("gen_ai.chat", tracer("myapp"))

# Set messages from a PT conversation
set_genai_messages!(span, conv)

# Set tool definitions
set_tool_definitions!(span, tool_map)

# End span
end_span!(span)
```
