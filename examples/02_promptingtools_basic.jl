# PromptingTools Integration - Basic Example
#
# This example shows how to trace LLM calls made with PromptingTools.
# All AI operations are automatically traced with full observability.
#
# ENVIRONMENT VARIABLES
# =====================
# Create a `.env` file in your project root with:
#
#   LOGFIRE_TOKEN=your-write-token     # From https://logfire.pydantic.dev
#   OPENAI_API_KEY=your-openai-key     # Required for OpenAI models
#
# Run: julia --project=. examples/02_promptingtools_basic.jl

using DotEnv
DotEnv.load!()

using Logfire
using PromptingTools

# =============================================================================
# Setup (3 steps)
# =============================================================================

# 1. Configure Logfire (automatically loads .env)
Logfire.configure(service_name = "promptingtools-basic-example")

# 2. Instrument PromptingTools - this wraps all registered models with tracing
Logfire.instrument_promptingtools!()

# 3. Use PromptingTools as normal - traces are automatic!

# =============================================================================
# Example 1: Simple text generation
# =============================================================================
println("Example 1: Simple text generation")
println("-"^50)

response = aigenerate("What is 2 + 2? Reply in one word."; model = "gpt5m")
println("Response: ", response.content)
println()

# What gets traced:
#   - Span: "chat gpt-4o-mini" with timing
#   - Input messages (your prompt)
#   - Output messages (model response)
#   - Token usage (input/output tokens)
#   - Model parameters (temperature, etc.)
#   - Cost estimate

# =============================================================================
# Example 2: With system prompt and parameters
# =============================================================================
println("Example 2: With system prompt and parameters")
println("-"^50)

response = aigenerate(
    "Translate 'Hello, world!' to French.";
    system = "You are a helpful translator. Be concise.",
    model = "gpt41m",
    api_kwargs = (; temperature = 0.3)
)
println("Response: ", response.content)
println()

# Additional attributes traced:
#   - System instructions (shown separately in Logfire UI)
#   - gen_ai.request.temperature = 0.3

# =============================================================================
# Example 3: Structured extraction with aiextract
# =============================================================================
println("Example 3: Structured extraction")
println("-"^50)

# Define a struct for extraction
@kwdef struct City
    name::String
    country::String
    population::Int
end

result = aiextract(
    "Paris is the capital of France with about 2.1 million people.";
    return_type = City,
    model = "gpt5m"
)
println("Extracted: ", result.content)
println()

# Traces include:
#   - The extraction schema/return type
#   - Successful parsing confirmation

# =============================================================================
# Example 4: Multi-turn conversation
# =============================================================================
println("Example 4: Multi-turn conversation")
println("-"^50)

# Using the OpenAI Responses Schema
schema = PromptingTools.OpenAIResponseSchema()
# First turn
msg = aigenerate(schema, "My name is Alice."; model = "gpt-5-mini")
println("Turn 1: ", msg.content)

# Continue the conversation
msg = aigenerate(schema,
    "What's my name?"; model = "gpt-5-mini", previous_response_id = msg.extras[:response_id])
println("Turn 2: ", msg.content)
println()

# Each turn creates a separate span with:
#   - Full conversation history in gen_ai.input.messages
#   - Parent-child relationship visible in trace view

# =============================================================================
# Cleanup
# =============================================================================
println("Shutting down...")
Logfire.shutdown!()

println("\nDone! Check your Logfire dashboard to see:")
println("  - 'chat gpt-4o-mini' spans for each AI call")
println("  - Input/output messages with full content")
println("  - Token usage and cost estimates")
println("  - Latency measurements for each call")
println("  - Conversation history for multi-turn chats")
