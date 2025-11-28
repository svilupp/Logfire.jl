# OpenTelemetry Resource construction

"""
    create_resource(cfg::LogfireConfig) -> Resource

Create an OpenTelemetry Resource with Logfire-compatible attributes.
"""
function create_resource(cfg::LogfireConfig)
    # Build attributes as NamedTuple
    if cfg.service_version !== nothing
        return OpenTelemetryAPI.Resource((;
            var"service.name" = cfg.service_name,
            var"service.version" = cfg.service_version,
            var"deployment.environment.name" = cfg.environment,
            var"telemetry.sdk.language" = "julia",
            var"telemetry.sdk.name" = SDK_NAME,
            var"telemetry.sdk.version" = SDK_VERSION
        ))
    else
        return OpenTelemetryAPI.Resource((;
            var"service.name" = cfg.service_name,
            var"deployment.environment.name" = cfg.environment,
            var"telemetry.sdk.language" = "julia",
            var"telemetry.sdk.name" = SDK_NAME,
            var"telemetry.sdk.version" = SDK_VERSION
        ))
    end
end
