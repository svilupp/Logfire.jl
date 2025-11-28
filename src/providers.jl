# OpenTelemetry TracerProvider and MeterProvider setup

"""
    _setup_providers!(cfg::LogfireConfig)

Initialize OpenTelemetry tracer and meter providers based on configuration.
"""
function _setup_providers!(cfg::LogfireConfig)
    resource = create_resource(cfg)

    # Create span processor based on configuration
    # Note: TracerProvider only accepts a single span_processor, so we prioritize:
    # 1. Logfire exporter (if enabled) - main purpose
    # 2. Console exporter (if enabled and logfire not enabled) - for debugging
    # 3. In-memory exporter (if nothing enabled) - fallback

    local span_processor

    if should_send_to_logfire(cfg)
        exporter = create_logfire_exporter(cfg)
        # Use SimpleSpanProcessor for immediate export
        # For production, consider BatchSpanProcessor for better performance
        span_processor = OpenTelemetrySDK.SimpleSpanProcessor(exporter)
    elseif cfg.console
        # Use console exporter for debugging
        console_exporter = OpenTelemetrySDK.ConsoleExporter()
        span_processor = OpenTelemetrySDK.SimpleSpanProcessor(console_exporter)
    else
        # Use a dummy/in-memory exporter when nothing is configured
        dummy_exporter = OpenTelemetrySDK.InMemoryExporter()
        span_processor = OpenTelemetrySDK.SimpleSpanProcessor(dummy_exporter)
        @debug "No exporters configured, spans will be stored in memory only"
    end

    # Create tracer provider
    provider = OpenTelemetrySDK.TracerProvider(;
        resource = resource,
        span_processor = span_processor
    )

    # Set as global tracer provider
    OpenTelemetryAPI.global_tracer_provider(provider)
    cfg._tracer_provider = provider

    return provider
end

"""
    tracer(name::String = "logfire") -> Tracer

Get a tracer instance for creating spans.
"""
function tracer(name::String = "logfire")
    scope = OpenTelemetryAPI.InstrumentationScope(; name = name)
    return OpenTelemetryAPI.Tracer(; instrumentation_scope = scope)
end
