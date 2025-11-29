# Logfire.jl

[![CI](https://github.com/svilupp/Logfire.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/svilupp/Logfire.jl/actions/workflows/CI.yml)
[![Documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://svilupp.github.io/Logfire.jl/dev)

Unofficial Julia client for [Pydantic Logfire](https://pydantic.dev/logfire) - OpenTelemetry-based observability for LLM applications.

## Quick start (PromptingTools)
```julia
using DotEnv
DotEnv.load!() # Load .env file if present

using Logfire, PromptingTools

Logfire.configure(service_name = "my-app")  # sets up OTLP exporter to Logfire cloud if env vars present
Logfire.instrument_promptingtools!()        # instruments all registered models

aigenerate("hello"; model = "gpt-5-mini")       # spans with tokens, cost, messages, tool-calls, cache info
```

### Authentication
- Copy `.env.example` to `.env` and fill in your tokens
- Or provide via `Logfire.configure(token = "...")` or `ENV["LOGFIRE_TOKEN"]`

### Instrument a single model (alias or full name)
```julia
Logfire.instrument_promptingtools_model!("my-local-llm")
```
This reuses the model's registered PromptingTools schema when available, so provider-specific behavior is preserved.

### Manual schema wrapping (no auto-instrumentation)
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

## Manual spans (non-PT code)
```julia
with_llm_span("chat"; system = "custom", model = "my-model") do span
    # do work...
    # exceptions automatically set span status = error and propagate
end
```
`with_llm_span` and `with_span` mark errors automatically via `set_span_status_error!`, so failures show up clearly in tracing backends.

## What gets captured
- Request params: model, temperature, top_p, max_tokens, stop, penalties (best-effort).
- Usage: input/output/total tokens, latency, cost.
- Provider metadata: model returned, status, finish_reason, response_id/system_fingerprint.
- Cache + streaming flags, chunk counts.
- Tool/function calls (count + payload event).
- Full conversation (roles + content) and completion event.
- Exceptions: span status set to error with message; span ends safely even if fields are missing.

## Query API - Download Your Data

Query your telemetry data using SQL via the Logfire Query API.

### Setup
1. Create a read token at [logfire.pydantic.dev](https://logfire.pydantic.dev) → Settings → Read tokens
2. Set `LOGFIRE_READ_TOKEN` in your environment or `.env` file

### Usage
```julia
using Logfire

client = LogfireQueryClient()  # uses LOGFIRE_READ_TOKEN from env

# Row-oriented results (Vector{Dict})
rows = query_json(client, "SELECT span_name, duration FROM records LIMIT 10")
for row in rows
    println("$(row["span_name"]): $(row["duration"])s")
end

# Column-oriented results (Dict{String,Vector})
cols = query_json(client, "SELECT span_name, duration FROM records"; row_oriented=false)

# CSV export
csv_data = query_csv(client, "SELECT * FROM records LIMIT 100")
```

### Example Queries
```sql
-- Most common operations
SELECT COUNT() AS count, span_name FROM records GROUP BY span_name ORDER BY count DESC

-- Recent exceptions
SELECT exception_type, exception_message FROM records WHERE is_exception LIMIT 20

-- P95 latency by operation
SELECT approx_percentile_cont(0.95) WITHIN GROUP (ORDER BY duration) as P95, span_name
FROM records WHERE duration IS NOT NULL GROUP BY span_name ORDER BY P95 DESC

-- Slowest traces
SELECT trace_id, duration, message FROM records ORDER BY duration DESC LIMIT 10
```

## Alternative Backends

Send telemetry to local collectors instead of Logfire cloud using standard OpenTelemetry environment variables.

### Environment Variables
| Variable | Purpose |
|----------|---------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Backend URL (e.g., `http://localhost:4318`) |
| `OTEL_EXPORTER_OTLP_HEADERS` | Custom headers (e.g., `Authorization=Bearer token`) |

### Local Development with Jaeger
```bash
# Start Jaeger
docker run --rm -p 16686:16686 -p 4318:4318 jaegertracing/all-in-one:latest
```

```julia
using Logfire

ENV["OTEL_EXPORTER_OTLP_ENDPOINT"] = "http://localhost:4318"

Logfire.configure(
    service_name = "my-app",
    send_to_logfire = :always  # Export even without Logfire token
)

with_span("my-operation") do
    # your code
end
```

View traces at: http://localhost:16686

### Using with Langfuse
```julia
ENV["OTEL_EXPORTER_OTLP_ENDPOINT"] = "https://cloud.langfuse.com/api/public/otel"
ENV["OTEL_EXPORTER_OTLP_HEADERS"] = "Authorization=Basic <base64-credentials>"

Logfire.configure(service_name = "my-llm-app", send_to_logfire = :always)
```

## Exception Handling

Exceptions are automatically captured and recorded using OpenTelemetry semantic conventions.

### Automatic Capture (Default)
```julia
# Exceptions automatically recorded with full stacktrace
with_span("risky-operation") do span
    error("Something went wrong!")  # Automatically captured
end
```

### Manual Recording
```julia
try
    risky_operation()
catch e
    bt = catch_backtrace()
    record_exception!(span, e; backtrace=bt)
    rethrow()
end
```

### Configuration
```julia
# Disable automatic exception capture if needed
Logfire.configure(auto_record_exceptions = false)

# Or via environment variable
ENV["LOGFIRE_AUTO_RECORD_EXCEPTIONS"] = "false"
```

Captured exceptions appear in Logfire's UI with:
- `exception.type` - Exception type name
- `exception.message` - Error message
- `exception.stacktrace` - Full formatted stacktrace

