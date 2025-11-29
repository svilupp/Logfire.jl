# PromptingTools tracer-based instrumentation (no method pirating)

using PromptingTools

# -- shared helpers -----------------------------------------------------------

function _schema_for_model(name; base_schema = PromptingTools.OpenAISchema())
    # Try PromptingTools helpers to fetch the registered schema, fallback to base_schema
    for fname in (:get_schema, :schema_for, :get_prompt_schema, :get_model_schema)
        try
            if hasproperty(PromptingTools, fname)
                f = getproperty(PromptingTools, fname)
                if f isa Function
                    sch = f(name)
                    sch isa PromptingTools.AbstractPromptSchema && return sch
                end
            end
        catch
        end
    end
    return base_schema
end

function _registered_model_names()
    # MODEL_REGISTRY is a ModelRegistry type that supports keys()
    reg = PromptingTools.MODEL_REGISTRY
    return collect(string.(keys(reg)))
end

"""
    instrument_promptingtools!(; models=nothing, base_schema=PromptingTools.OpenAISchema())

Register Logfire's `LogfireSchema` tracer for the given model names. If `models`
is `nothing`, all models currently registered in PromptingTools are instrumented.
Throws an error if no models are provided and none can be discovered.
"""
function instrument_promptingtools!(; models = nothing,
        base_schema = PromptingTools.OpenAISchema())
    was_auto = models === nothing
    selected_models = models === nothing ? _registered_model_names() : models

    if isempty(selected_models)
        error("No models to instrument. Either pass `models` explicitly or ensure " *
              "PromptingTools has registered models (check PromptingTools.MODEL_REGISTRY).")
    end

    for name in selected_models
        instrument_promptingtools_model!(name; base_schema)
    end

    # Only print full list if explicitly provided models, otherwise just count
    if was_auto
        @info "PromptingTools auto-instrumented with Logfire tracer schema for $(length(selected_models)) models"
    else
        @info "PromptingTools manually instrumented with Logfire tracer schema for $(length(selected_models)) models" models=selected_models
    end
    return selected_models
end

"""
    instrument_promptingtools_model!(name; base_schema=PromptingTools.OpenAISchema())

Register Logfire tracing for a single model name or alias. Uses the already
registered PromptingTools schema when available; otherwise falls back to
`base_schema`. Safe to call multiple times.
"""
function instrument_promptingtools_model!(name;
        base_schema = PromptingTools.OpenAISchema())
    model_name = string(name)
    schema = LogfireSchema(_schema_for_model(model_name; base_schema))
    try
        # Suppress stdout/stderr to avoid "already registered" warnings from PromptingTools
        # This is expected behavior when re-registering models
        devnull = Base.DevNull()
        redirect_stdout(devnull) do
            redirect_stderr(devnull) do
                PromptingTools.register_model!(; name = model_name, schema)
            end
        end
        @debug "PromptingTools model registered for Logfire tracing" model=model_name
    catch e
        @warn "Failed to register PromptingTools model for Logfire tracing" model=model_name exception=(
            e, catch_backtrace())
    end
    return schema
end

"""
    uninstrument_promptingtools!()

Best-effort removal. Since PromptingTools does not expose a deregistration hook,
this currently logs a warning and leaves registrations intact.
"""
function uninstrument_promptingtools!()
    @warn "PromptingTools does not support deregistering schemas; restart your session to fully remove Logfire tracer registrations."
end
