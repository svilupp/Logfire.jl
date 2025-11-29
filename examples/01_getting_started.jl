# Getting Started with Logfire.jl
#
# Logfire is an observability platform for tracing and monitoring your Julia applications.
# This example shows how to configure Logfire and create basic traces.
#
# ENVIRONMENT VARIABLES
# =====================
# Logfire uses environment variables for configuration. Create a `.env` file in your
# project root or set these variables in your shell:
#
#   LOGFIRE_TOKEN        - Your write token from https://logfire.pydantic.dev (required to send data)
#   LOGFIRE_SERVICE_NAME - Name of your service (optional, default: "julia-app")
#   LOGFIRE_ENVIRONMENT  - Environment name (optional, default: "development")
#
# Without LOGFIRE_TOKEN, traces are created locally but not sent to Logfire.
#
# Run: julia --project=. examples/01_getting_started.jl

using DotEnv
DotEnv.load!()

using Logfire

# =============================================================================
# Configuration
# =============================================================================
# configure() automatically loads .env files and reads environment variables.
# You can also pass options directly:

Logfire.configure(
    service_name = "logfire-getting-started",
    service_version = "1.0.0",
    environment = "development"
)

# Check if we're sending to Logfire
cfg = Logfire.get_config()
if !Logfire.should_send_to_logfire(cfg)
    println("Note: LOGFIRE_TOKEN not set. Traces will be created but not sent to Logfire.")
    println("      Set LOGFIRE_TOKEN in your .env file to see traces in the dashboard.\n")
end

# =============================================================================
# Basic Spans
# =============================================================================
# A span represents a unit of work. Use with_span to trace operations:

println("Creating basic spans...")

Logfire.with_span("process-data"; user_id = 123) do span
    # Add attributes to provide context
    Logfire.set_span_attribute!(span, "records.count", 50)
    Logfire.set_span_attribute!(span, "source", "database")

    sleep(0.05)  # Simulate work
    println("  Processed 50 records")
end

# =============================================================================
# Nested Spans
# =============================================================================
# Spans automatically form parent-child relationships when nested:

println("\nCreating nested spans...")

Logfire.with_span("api-request"; endpoint = "/users") do parent
    Logfire.set_span_attribute!(parent, "http.method", "GET")

    # Child span: database query
    Logfire.with_span("db-query"; table = "users") do child
        Logfire.set_span_attribute!(child, "db.rows", 10)
        sleep(0.02)
        println("  Database query completed")
    end

    # Child span: format response
    Logfire.with_span("format-response") do child
        sleep(0.01)
        println("  Response formatted")
    end

    println("  API request completed")
end

# =============================================================================
# Error Handling
# =============================================================================
# Exceptions are automatically captured and recorded in spans:

println("\nDemonstrating error capture...")

try
    Logfire.with_span("risky-operation") do span
        Logfire.set_span_attribute!(span, "operation", "file-upload")
        error("File too large")  # This exception is auto-captured
    end
catch e
    println("  Error captured: $(e.msg)")
end

# =============================================================================
# Cleanup
# =============================================================================
# Always call shutdown! to ensure all spans are exported:

println("\nShutting down...")
Logfire.shutdown!()

println("\nDone! If LOGFIRE_TOKEN was set, check your dashboard at https://logfire.pydantic.dev")
println("You should see:")
println("  - A 'process-data' span with user_id and records.count attributes")
println("  - An 'api-request' span with nested 'db-query' and 'format-response' children")
println("  - A 'risky-operation' span marked as error with exception details")
