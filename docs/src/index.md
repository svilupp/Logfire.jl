```@meta
CurrentModule = Logfire
```

# Logfire.jl

Julia client for [Pydantic Logfire](https://pydantic.dev/logfire) - OpenTelemetry-based observability for LLM applications.

## Features

- **OpenTelemetry Integration** - Full OTEL support for tracing LLM calls
- **PromptingTools.jl Support** - Automatic instrumentation of `aigenerate`, `aitools`, `aiextract`
- **GenAI Semantic Conventions** - Compliant with OTEL GenAI specs
- **Query API** - Download your telemetry data using SQL
- **Alternative Backends** - Send data to Jaeger, Langfuse, or any OTEL-compatible backend
- **Exception Tracking** - Automatic exception capture with full stacktraces

## Quick Start

```julia
using DotEnv
DotEnv.load!()  # Load .env file (must call explicitly)

using Logfire
using PromptingTools

# Configure Logfire (uses LOGFIRE_TOKEN from environment)
Logfire.configure(service_name="my-app")

# Instrument PromptingTools
Logfire.instrument_promptingtools!()

# All LLM calls are now traced
response = aigenerate("What is 2+2?")
```

### Manual Schema Wrapping (No Auto-Instrumentation)

If you prefer not to use auto-instrumentation, you can explicitly wrap any PromptingTools schema:

```julia
using Logfire, PromptingTools

Logfire.configure(service_name = "my-app")

# Wrap the schema you want to trace
schema = PromptingTools.OpenAISchema() |> Logfire.LogfireSchema

# Use it directly - no instrument_promptingtools!() needed
aigenerate(schema, "Hello!"; model = "gpt-5-mini")
```

This gives you fine-grained control over which calls are traced.

## Authentication

Set your Logfire token via one of:
- `.env` file with `LOGFIRE_TOKEN=...` (call `DotEnv.load!()` first)
- Environment variable: `ENV["LOGFIRE_TOKEN"] = "..."`
- Direct argument: `Logfire.configure(token="...")`

## What Gets Captured

- **Request params**: model, temperature, top_p, max_tokens, stop, penalties
- **Usage**: input/output/total tokens, latency, cost
- **Provider metadata**: model returned, status, finish_reason, response_id
- **Tool/function calls**: count + full payload
- **Conversation**: roles + content for all messages
- **Exceptions**: type, message, and full stacktrace

## Configuration Options

```julia
Logfire.configure(
    token = "...",                    # Logfire write token (or use LOGFIRE_TOKEN env)
    service_name = "my-app",          # Service name for telemetry
    service_version = "1.0.0",        # Service version
    environment = "production",       # Deployment environment
    send_to_logfire = :if_token_present,  # :always, :never, or :if_token_present
    endpoint = "...",                 # Custom OTLP endpoint
    auto_record_exceptions = true     # Automatic exception capture
)
```

## Manual Spans

```julia
# Generic span
with_span("my-operation") do span
    set_span_attribute!(span, "custom.key", "value")
    # do work...
end

# LLM-specific span
with_llm_span("chat"; system="openai", model="gpt-4o") do span
    # do LLM work...
    record_token_usage!(span, 100, 50)
end
```

## Exception Handling

```julia
# Automatic (default)
with_span("risky-operation") do span
    error("Oops!")  # Automatically captured
end

# Manual
try
    risky_operation()
catch e
    record_exception!(span, e; backtrace=catch_backtrace())
    rethrow()
end
```

## Documentation

- **[Query API](@ref)** - Download telemetry data using SQL queries
- **[Alternative Backends](@ref)** - Use Jaeger, Langfuse, or other OTEL backends
- **[OTEL GenAI Semantic Conventions](@ref)** - Message formats and span attributes

## API Reference

```@index
```

```@autodocs
Modules = [Logfire]
```
