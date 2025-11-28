module LogfirePromptingToolsExt

import PromptingTools as PT
using Logfire
using OpenTelemetryAPI

# Extend PromptingTools tracer hooks using the LogfireSchema defined in core

# Resolve model alias to full model ID using PT.MODEL_ALIASES
function _resolve_model_id(model::AbstractString)
    isempty(model) && return model
    return get(PT.MODEL_ALIASES, model, model)
end

function PT.initialize_tracer(s::Logfire.LogfireSchema;
        model::AbstractString = "",
        prompt = nothing,
        api_kwargs = NamedTuple(),
        tracer_kwargs = NamedTuple(),
        kwargs...)
    span = OpenTelemetryAPI.create_span("gen_ai.chat", Logfire.tracer("logfire.genai"))

    # Resolve alias to full model ID (e.g., "gpt4om" -> "gpt-4o-mini")
    model_id = _resolve_model_id(model)

    Logfire.set_span_attribute!(span, "gen_ai.operation.name", "chat")
    Logfire._set_if_some(span, "gen_ai.system", Logfire._detect_system(s.schema))
    Logfire._set_if_some(span, "gen_ai.request.model", model_id)
    Logfire._record_request_params!(span, api_kwargs)

    # Capture tool definitions if tools are provided (aitools/aiextract)
    tools = get(kwargs, :tools, nothing)
    if tools !== nothing && !isempty(tools)
        Logfire.set_tool_definitions!(span, tools)
    end

    return (; span, time_sent = time(), model = model_id, tracer_kwargs)
end

function PT.finalize_tracer(s::Logfire.LogfireSchema,
        tracer_state::Union{NamedTuple, AbstractDict},
        msg_or_conv::Union{PT.AbstractMessage, AbstractVector{<:PT.AbstractMessage}};
        model::AbstractString = "",
        tracer_kwargs::NamedTuple = NamedTuple(),
        kwargs...)
    span = get(tracer_state, :span, nothing)
    span === nothing && return msg_or_conv

    # Resolve alias to full model ID
    model_id = _resolve_model_id(model)

    try
        conv = msg_or_conv isa AbstractVector ? msg_or_conv : [msg_or_conv]
        ai_msg = Logfire._find_ai_message(conv)

        # Record token usage and response metadata
        Logfire._record_usage!(span, ai_msg)
        Logfire._record_response_attrs!(span, ai_msg, model_id)
        Logfire._record_cache_attrs!(span, ai_msg)
        Logfire._record_streaming_attrs!(span, ai_msg)
        Logfire._record_tool_calls!(span, ai_msg)

        # Record messages as span attributes for Logfire UI message previews
        # This uses PT's render() for proper role mapping and image/tool support
        Logfire._record_messages_as_attributes!(span, conv)

        # Note: Events are skipped because PydanticAI doesn't use them (otel_events: [])
        # and the Julia OTel library has serialization issues with event attributes.
        # The span attributes above are sufficient for Logfire to render messages.
    catch e
        Logfire.record_exception!(span, e)
    finally
        OpenTelemetryAPI.end_span!(span)
    end

    return msg_or_conv
end

end # module
