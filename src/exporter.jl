# OTLP HTTP Exporter configuration for Logfire

"""
    create_logfire_exporter(cfg::LogfireConfig) -> OtlpHttpTracesExporter

Create an OTLP HTTP exporter configured for Logfire backend.
"""
function create_logfire_exporter(cfg::LogfireConfig)
    # OtlpHttpTracesExporter automatically appends /v1/traces to the URL
    # So we just pass the base endpoint
    endpoint = cfg.endpoint

    # Headers must be Vector{Pair{String, String}}
    headers = [
        "Authorization" => cfg.token,
    ]

    return OpenTelemetryExporterOtlpProtoHttp.OtlpHttpTracesExporter(;
        url = endpoint,
        headers = headers
    )
end
