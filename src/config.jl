# Configuration types and configure() function

"""
    LogfireConfig

Configuration options for Logfire SDK.

# Fields
- `token::Union{String, Nothing}`: Logfire write token
- `service_name::String`: Service name for telemetry
- `service_version::Union{String, Nothing}`: Service version
- `environment::String`: Deployment environment (development, staging, production)
- `send_to_logfire::Symbol`: Export control (:if_token_present, :always, :never)
- `endpoint::String`: OTLP endpoint URL
- `console::Bool`: Print spans to console
- `scrubbing::Bool`: Enable data scrubbing
- `auto_record_exceptions::Bool`: Automatically record exceptions in spans (default: true)
"""
Base.@kwdef mutable struct LogfireConfig
    # Core settings
    token::Union{String, Nothing} = nothing
    service_name::String = DEFAULT_SERVICE_NAME
    service_version::Union{String, Nothing} = nothing
    environment::String = DEFAULT_ENVIRONMENT

    # Export settings
    send_to_logfire::Symbol = :if_token_present  # :always, :never, :if_token_present
    endpoint::String = LOGFIRE_US_ENDPOINT

    # Telemetry options
    console::Bool = false
    scrubbing::Bool = false
    auto_record_exceptions::Bool = true  # Automatically catch and record exceptions in spans

    # Internal state
    _configured::Bool = false
    _tracer_provider::Any = nothing
    _meter_provider::Any = nothing
end

# Global configuration instance
const GLOBAL_CONFIG = LogfireConfig()

"""
    is_configured() -> Bool

Check if Logfire has been configured.
"""
is_configured() = GLOBAL_CONFIG._configured

"""
    get_config() -> LogfireConfig

Get the current global configuration.
"""
get_config() = GLOBAL_CONFIG

"""
    should_send_to_logfire(cfg::LogfireConfig) -> Bool

Determine if telemetry should be sent to Logfire based on configuration.
"""
function should_send_to_logfire(cfg::LogfireConfig = GLOBAL_CONFIG)::Bool
    if cfg.send_to_logfire === :always
        return true
    elseif cfg.send_to_logfire === :never
        return false
    elseif cfg.send_to_logfire === :if_token_present
        return cfg.token !== nothing && !isempty(cfg.token)
    end
    return false
end

"""
    configure(; kwargs...)

Initialize Logfire SDK with the specified options.

# Keywords
- `token::String`: Logfire write token (or use LOGFIRE_TOKEN env var)
- `service_name::String`: Name of the service (default: "julia-app")
- `service_version::String`: Version of the service
- `environment::String`: Deployment environment (default: "development")
- `send_to_logfire::Symbol`: Export control (:if_token_present, :always, :never)
- `endpoint::String`: Custom OTLP endpoint (default: Logfire US)
- `scrubbing::Bool`: Enable data scrubbing (default: false)
- `console::Bool`: Print spans to console (default: false)
- `auto_record_exceptions::Bool`: Automatically record exceptions in spans (default: true)

# Example
```julia
using Logfire

Logfire.configure(
    service_name = "my-llm-app",
    environment = "production",
    auto_record_exceptions = true  # Automatically capture exceptions in spans
)
```
"""
function configure(;
        token::Union{String, Nothing} = nothing,
        service_name::Union{String, Nothing} = nothing,
        service_version::Union{String, Nothing} = nothing,
        environment::Union{String, Nothing} = nothing,
        send_to_logfire::Union{Symbol, Nothing} = nothing,
        endpoint::Union{String, Nothing} = nothing,
        console::Union{Bool, Nothing} = nothing,
        scrubbing::Union{Bool, Nothing} = nothing,
        auto_record_exceptions::Union{Bool, Nothing} = nothing
)
    # Load .env file if present
    try
        DotEnv.config()
    catch e
        # .env file not found or error, continue silently
    end

    cfg = GLOBAL_CONFIG

    # Apply configuration with ENV fallbacks
    cfg.token = something(
        token,
        get(ENV, "LOGFIRE_TOKEN", nothing),
        Some(nothing)  # Token is optional
    )

    cfg.service_name = something(
        service_name,
        get(ENV, "LOGFIRE_SERVICE_NAME", nothing),
        Some(DEFAULT_SERVICE_NAME)
    )

    cfg.service_version = something(
        service_version,
        get(ENV, "LOGFIRE_SERVICE_VERSION", nothing),
        Some(nothing)
    )

    cfg.environment = something(
        environment,
        get(ENV, "LOGFIRE_ENVIRONMENT", nothing),
        Some(DEFAULT_ENVIRONMENT)
    )

    # Parse send_to_logfire from ENV if needed
    if send_to_logfire !== nothing
        cfg.send_to_logfire = send_to_logfire
    else
        env_val = get(ENV, "LOGFIRE_SEND_TO_LOGFIRE", nothing)
        if env_val !== nothing
            env_lower = lowercase(env_val)
            if env_lower == "true" || env_lower == "always"
                cfg.send_to_logfire = :always
            elseif env_lower == "false" || env_lower == "never"
                cfg.send_to_logfire = :never
            else
                cfg.send_to_logfire = :if_token_present
            end
        end
    end

    cfg.endpoint = something(
        endpoint,
        get(ENV, "LOGFIRE_ENDPOINT", nothing),
        get(ENV, "OTEL_EXPORTER_OTLP_ENDPOINT", nothing),
        Some(LOGFIRE_US_ENDPOINT)
    )

    cfg.console = something(console, Some(false))
    cfg.scrubbing = something(scrubbing, Some(false))

    # Parse auto_record_exceptions from ENV if needed
    if auto_record_exceptions !== nothing
        cfg.auto_record_exceptions = auto_record_exceptions
    else
        env_val = get(ENV, "LOGFIRE_AUTO_RECORD_EXCEPTIONS", nothing)
        if env_val !== nothing
            cfg.auto_record_exceptions = lowercase(env_val) == "true"
        end
    end

    # Initialize OTel providers
    _setup_providers!(cfg)

    cfg._configured = true

    # Log configuration status
    if should_send_to_logfire(cfg)
        @info "Logfire configured" service_name=cfg.service_name environment=cfg.environment endpoint=cfg.endpoint
    else
        @info "Logfire configured (local only, not sending to Logfire)" service_name=cfg.service_name
    end

    return cfg
end

"""
    shutdown!()

Gracefully shutdown the Logfire SDK, flushing any pending telemetry.
Note: With SimpleSpanProcessor, spans are exported immediately when they end,
so shutdown is mainly for cleanup. For BatchSpanProcessor, this would flush pending spans.
"""
function shutdown!()
    cfg = GLOBAL_CONFIG
    if cfg._tracer_provider !== nothing
        # Try to flush if using BatchSpanProcessor
        # SimpleSpanProcessor exports immediately, so this is mainly for cleanup
        try
            # Access the span processor and try to flush if it's a BatchSpanProcessor
            sp = cfg._tracer_provider.span_processor
            if sp isa OpenTelemetrySDK.BatchSpanProcessor
                # BatchSpanProcessor may have internal flush mechanism
                # For now, we just mark as closed - spans should already be exported
                # Note: OpenTelemetrySDK doesn't expose flush! directly
            end
        catch e
            # Ignore errors - SimpleSpanProcessor doesn't need explicit flushing
        end
        cfg._tracer_provider = nothing
    end
    cfg._configured = false
    @info "Logfire shutdown complete"
end

"""
    flush!()

Force flush any pending telemetry data.
Note: With SimpleSpanProcessor, spans are exported immediately when they end.
This function is mainly useful for BatchSpanProcessor, but OpenTelemetrySDK doesn't
expose a direct flush API. Spans will be exported automatically.
"""
function flush!()
    cfg = GLOBAL_CONFIG
    if cfg._tracer_provider !== nothing
        # SimpleSpanProcessor exports immediately, so no flush needed
        # BatchSpanProcessor batches spans and exports them automatically
        # OpenTelemetrySDK doesn't expose a direct flush! method
        # Spans will be exported when the batch is full or after a timeout
        @debug "Flush requested - spans are exported automatically by the span processor"
    end
end
