# PromptingTools Integration - Tool Calling Example
#
# This example demonstrates tracing multi-turn conversations with tool execution.
# Tool calling is a powerful pattern where the LLM can request to call functions,
# and you execute them and return results for the LLM to process.
#
# ENVIRONMENT VARIABLES
# =====================
# Create a `.env` file with:
#
#   LOGFIRE_TOKEN=your-write-token     # From https://logfire.pydantic.dev
#   OPENAI_API_KEY=your-openai-key     # Required for OpenAI models
#
# Run: julia --project=. examples/03_promptingtools_tools.jl

using DotEnv
DotEnv.load!()

using Logfire
using PromptingTools
import PromptingTools as PT

# =============================================================================
# Setup
# =============================================================================

Logfire.configure(service_name = "promptingtools-tools-example")
Logfire.instrument_promptingtools!()

# =============================================================================
# Define Tools
# =============================================================================
# Tools are regular Julia functions with docstrings. PromptingTools converts
# them to the format expected by the LLM.

"Get the current weather for a city. Returns temperature and conditions."
get_weather(city::String) = city == "Paris" ? "18°C, partly cloudy" : "25°C, sunny"

"Get the current local time for a city."
get_time(city::String) = city == "Paris" ? "2:30 PM" : "9:30 PM"

# Create tool registry
tools = [get_weather, get_time]
tool_map = PT.tool_call_signature(tools)

# =============================================================================
# Helper: Execute tool calls
# =============================================================================

function execute_tools!(conv, tool_map)
    msg = conv[end]
    msg isa PT.AIToolRequest || return conv
    for tc in msg.tool_calls
        result = PT.execute_tool(tool_map, tc)
        tc.content = string(result)
        push!(conv, tc)
    end
    return conv
end

# =============================================================================
# Multi-Turn Conversation with Tools
# =============================================================================
println("="^60)
println("Multi-Turn Tool Calling Conversation")
println("="^60)
println()

# Turn 1: Ask about Paris weather
println("User: What's the weather in Paris?")
conv = aitools("What's the weather in Paris?";
    tools = tools,
    model = "gpt4om",
    return_all = true)

# Execute any tool calls and get final response
execute_tools!(conv, tool_map)
response = aigenerate(conv; model = "gpt4om")
push!(conv, response)
println("Assistant: ", response.content)
println()

# In Logfire you'll see:
#   1. Span: "chat gpt-4o-mini" - tool request with get_weather tool call
#   2. Span: "chat gpt-4o-mini" - final response using tool result

# Turn 2: Follow-up question (conversation continues)
println("User: What time is it there?")
conv = aitools("What time is it there?";
    tools = tools,
    model = "gpt4om",
    conversation = conv,  # Continue the conversation
    return_all = true)

execute_tools!(conv, tool_map)
response = aigenerate(conv; model = "gpt4om")
push!(conv, response)
println("Assistant: ", response.content)
println()

# Turn 3: Compare with another city (may trigger multiple tools)
println("User: How does that compare to Tokyo?")
conv = aitools("How does that compare to Tokyo's weather and time?";
    tools = tools,
    model = "gpt4om",
    conversation = conv,
    return_all = true)

execute_tools!(conv, tool_map)
response = aigenerate(conv; model = "gpt4om")
push!(conv, response)
println("Assistant: ", response.content)
println()

# =============================================================================
# Conversation Summary
# =============================================================================
println("="^60)
println("Conversation Summary: $(length(conv)) messages")
println("="^60)
for (i, m) in enumerate(conv)
    type_name = nameof(typeof(m))
    content = if m isa PT.AIToolRequest
        tools_called = join([tc.name for tc in m.tool_calls], ", ")
        "Tools: $tools_called"
    elseif m isa PT.ToolMessage
        "Result: $(first(m.content, 30))..."
    else
        first(string(m.content), 50) * "..."
    end
    println("  $i. $type_name: $content")
end

# =============================================================================
# Cleanup
# =============================================================================
println()
println("Shutting down...")
sleep(1)  # Allow time for spans to export
Logfire.shutdown!()

println("\nDone! Check your Logfire dashboard to see:")
println("  - Each LLM call as a separate span")
println("  - Tool calls with function names and arguments")
println("  - Tool results fed back to the model")
println("  - Full conversation history at each turn")
println("  - Parent-child relationships in trace view")
