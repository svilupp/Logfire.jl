# PromptingTools tracer-based instrumentation (no method pirating)

const _DEFAULT_MODELS = [
    "gpt-4o",
    "gpt-4o-mini",
    "gpt-4",
    "gpt-3.5-turbo"
]

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
    names = String[]
    # Try MODEL_REGISTRY first (most reliable)
    try
        if hasproperty(PromptingTools, :MODEL_REGISTRY)
            reg = getproperty(PromptingTools, :MODEL_REGISTRY)
            if reg isa AbstractDict && !isempty(reg)
                append!(names, string.(keys(reg)))
            end
        end
    catch
    end

    # Try function-based discovery methods
    for fname in (:registered_models, :list_registered_models, :available_models, :models)
        try
            if hasproperty(PromptingTools, fname)
                f = getproperty(PromptingTools, fname)
                if f isa Function
                    vals = f()
                    if vals isa AbstractDict && !isempty(vals)
                        append!(names, string.(keys(vals)))
                    elseif vals isa AbstractVector && !isempty(vals)
                        append!(names, string.(vals))
                    end
                end
            end
        catch
        end
    end

    unique!(names)
    return names
end

"""
    instrument_promptingtools!(; models=nothing, base_schema=PromptingTools.OpenAISchema())

Register Logfire's `LogfireSchema` tracer for the given model names. If `models`
is `nothing`, all models currently registered in PromptingTools are instrumented;
if none are registered, falls back to `_DEFAULT_MODELS`. This wraps each model's
existing schema when available.
"""
function instrument_promptingtools!(; models = nothing,
        base_schema = PromptingTools.OpenAISchema())
    was_auto = models === nothing
    selected_models = models === nothing ? _registered_model_names() : models
    isempty(selected_models) && (selected_models = _DEFAULT_MODELS)

    for name in selected_models
        instrument_promptingtools_model!(name; base_schema)
    end

    # Only print full list if explicitly provided models, otherwise just count
    if was_auto
        @debug "PromptingTools registered with Logfire tracer schema" count=length(selected_models)
    else
        @debug "PromptingTools registered with Logfire tracer schema" models=selected_models
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
