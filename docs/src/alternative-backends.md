# Alternative Backends

Logfire.jl uses OpenTelemetry under the hood, which means you can send telemetry to any backend that supports the OTLP protocol. This allows you to:

- Develop locally without sending data to Logfire cloud
- Use self-hosted observability platforms
- Integrate with existing infrastructure (Jaeger, Grafana, Datadog, etc.)
- Avoid vendor lock-in

## Environment Variables

Configure alternative backends using standard OpenTelemetry environment variables:

| Variable | Purpose | Example |
|----------|---------|---------|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Base URL for the OTLP endpoint | `http://localhost:4318` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Custom headers (authentication) | `Authorization=Bearer token` |
| `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | Traces-specific endpoint | `http://localhost:4318/v1/traces` |
| `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT` | Metrics-specific endpoint | `http://localhost:4318/v1/metrics` |

**Note:** Data is sent using Protobuf over HTTP (not gRPC). Ensure your backend supports this format.

## Local Development with Jaeger

[Jaeger](https://www.jaegertracing.io/) is an open-source distributed tracing platform that's perfect for local development.

### 1. Start Jaeger

```bash
docker run --rm \
  -p 16686:16686 \
  -p 4318:4318 \
  jaegertracing/all-in-one:latest
```

Ports:
- `16686`: Jaeger UI
- `4318`: OTLP HTTP receiver

### 2. Configure Logfire.jl

```julia
using Logfire

ENV["OTEL_EXPORTER_OTLP_ENDPOINT"] = "http://localhost:4318"

Logfire.configure(
    service_name = "my-julia-app",
    send_to_logfire = :always  # Force export even without Logfire token
)
```

### 3. Create Traces

```julia
with_span("main-operation") do
    println("Doing work...")

    with_span("sub-task-1") do
        sleep(0.1)
    end

    with_span("sub-task-2") do
        sleep(0.2)
    end
end

Logfire.flush!()
```

### 4. View in Jaeger

Open http://localhost:16686 and select your service from the dropdown.

## Using with Langfuse

[Langfuse](https://langfuse.com) is an open-source LLM observability platform with OTEL support.

### Cloud (langfuse.com)

```julia
using Logfire

# Get your credentials from Langfuse dashboard
ENV["OTEL_EXPORTER_OTLP_ENDPOINT"] = "https://cloud.langfuse.com/api/public/otel"
ENV["OTEL_EXPORTER_OTLP_HEADERS"] = "Authorization=Basic $(base64encode("public-key:secret-key"))"

Logfire.configure(
    service_name = "my-llm-app",
    send_to_logfire = :always
)
```

### Self-Hosted Langfuse

```julia
ENV["OTEL_EXPORTER_OTLP_ENDPOINT"] = "http://localhost:3000/api/public/otel"
ENV["OTEL_EXPORTER_OTLP_HEADERS"] = "Authorization=Basic $(base64encode("pk-...:sk-..."))"
```

## OpenTelemetry Collector

The [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/) is a vendor-agnostic proxy that can receive, process, and export telemetry data to multiple backends.

### 1. Create Collector Config

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318

exporters:
  debug:
    verbosity: detailed
  # Add your backends here:
  # jaeger:
  #   endpoint: jaeger:14250
  # prometheus:
  #   endpoint: "0.0.0.0:8889"

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [debug]
    metrics:
      receivers: [otlp]
      exporters: [debug]
```

### 2. Run Collector

```bash
docker run --rm \
  -p 4318:4318 \
  -v $(pwd)/otel-collector-config.yaml:/etc/otelcol/config.yaml \
  otel/opentelemetry-collector:latest
```

### 3. Configure Logfire.jl

```julia
ENV["OTEL_EXPORTER_OTLP_ENDPOINT"] = "http://localhost:4318"
Logfire.configure(service_name = "my-app", send_to_logfire = :always)
```

## Grafana Cloud

```julia
ENV["OTEL_EXPORTER_OTLP_ENDPOINT"] = "https://otlp-gateway-prod-us-central-0.grafana.net/otlp"
ENV["OTEL_EXPORTER_OTLP_HEADERS"] = "Authorization=Basic $(base64encode("instance-id:api-key"))"

Logfire.configure(service_name = "my-app", send_to_logfire = :always)
```

## Dual Export (Logfire + Local)

To send data to both Logfire cloud and a local collector, use an OpenTelemetry Collector as a fanout proxy:

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318

exporters:
  otlphttp/logfire:
    endpoint: https://logfire-us.pydantic.dev
    headers:
      Authorization: "Bearer ${LOGFIRE_TOKEN}"
  otlphttp/jaeger:
    endpoint: http://jaeger:4318

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [otlphttp/logfire, otlphttp/jaeger]
```

Then point your Julia app at the collector:

```julia
ENV["OTEL_EXPORTER_OTLP_ENDPOINT"] = "http://localhost:4318"
Logfire.configure(service_name = "my-app", send_to_logfire = :always)
```

## Disabling Cloud Export

To use only local backends without any cloud export:

```julia
Logfire.configure(
    service_name = "my-app",
    send_to_logfire = :never  # Never send to Logfire cloud
)
```

Or set the environment variable:

```bash
LOGFIRE_SEND_TO_LOGFIRE=never
```

## Troubleshooting

### No traces appearing

1. Check that your backend is running and accessible
2. Verify the endpoint URL is correct (include `/v1/traces` if using specific endpoint vars)
3. Ensure `send_to_logfire = :always` is set when no Logfire token is present
4. Call `Logfire.flush!()` before your program exits

### Authentication errors

Check that headers are formatted correctly:
```julia
# Correct
ENV["OTEL_EXPORTER_OTLP_HEADERS"] = "Authorization=Bearer mytoken"

# Wrong (no spaces around =)
ENV["OTEL_EXPORTER_OTLP_HEADERS"] = "Authorization = Bearer mytoken"
```

### Protocol mismatch

Logfire.jl sends data using HTTP/Protobuf. If your backend only supports gRPC, you'll need to use an OpenTelemetry Collector as a protocol converter.
