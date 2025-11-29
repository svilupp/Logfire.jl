# PromptingTools tracer schema for Logfire

import PromptingTools as PT

# -- Public wrapper ------------------------------------------------------------

"""
    LogfireSchema(inner::PT.AbstractPromptSchema)

Tracer schema that wraps any PromptingTools prompt schema and emits OpenTelemetry
GenAI spans. Works with all `ai*` APIs in PromptingTools.
"""
struct LogfireSchema <: PT.AbstractTracerSchema
    schema::PT.AbstractPromptSchema
end

"""
    wrap(schema::PT.AbstractPromptSchema) -> LogfireSchema

Convenience helper to wrap an existing PromptingTools schema.
"""
wrap(schema::PT.AbstractPromptSchema) = LogfireSchema(schema)

# -- Internals -----------------------------------------------------------------

function _set_if_some(span, key::String, value)
    (isempty(string(value)) ? nothing : set_span_attribute!(span, key, value))
end
_set_if_some(span, key::String, value::Nothing) = nothing
_set_if_some(span, key::String, ::Missing) = nothing

function _record_request_params!(span, api_kwargs)
    for k in
        (:temperature, :top_p, :max_tokens, :stop, :presence_penalty, :frequency_penalty)
        if hasproperty(api_kwargs, k)
            _set_if_some(span, "gen_ai.request.$(k)", getproperty(api_kwargs, k))
        elseif api_kwargs isa AbstractDict && haskey(api_kwargs, k)
            _set_if_some(span, "gen_ai.request.$(k)", api_kwargs[k])
        end
    end
end

function _getfield_or(dictlike, key, default)
    dictlike isa AbstractDict ? get(dictlike, key, default) :
    (hasproperty(dictlike, key) ? getproperty(dictlike, key) : default)
end

_getextras(msg) = _getfield_or(msg, :extras, Dict{Symbol, Any}())

function _find_ai_message(conv)
    for m in reverse(conv)
        role = lowercase(String(_message_role(m)))
        if occursin("assistant", role) || occursin("model", role) || occursin("ai", role)
            return m
        end
    end
    return isempty(conv) ? nothing : conv[end]
end

"""
Get the role of a message, using PT's role4render when available.
"""
function _message_role(msg)
    # Handle Dict messages (already rendered)
    if msg isa AbstractDict
        return get(msg, "role", get(msg, :role, "unknown"))
    end

    # Use PT's role4render for proper message type mapping
    try
        return PT.role4render(PT.OpenAISchema(), msg)
    catch
        # Fallback: detect by type name
        type_name = lowercase(string(typeof(msg).name.name))
        if occursin("system", type_name)
            return "system"
        elseif occursin("user", type_name)
            return "user"
        elseif occursin("ai", type_name) || occursin("assistant", type_name)
            return "assistant"
        elseif occursin("tool", type_name)
            return "tool"
        end
    end

    # Last fallback
    if hasproperty(msg, :role)
        return string(getproperty(msg, :role))
    end
    return "unknown"
end

function _message_content(msg)
    msg isa AbstractDict ? get(msg, "content", get(msg, :content, "")) :
    (hasproperty(msg, :content) ? getproperty(msg, :content) : "")
end

# -- Message attribute recording -----------------------------------------------

"""
Record messages as span attributes using OTEL GenAI semantic conventions.

Sets the following attributes:
- gen_ai.input.messages: Chat history (all messages except final response)
- gen_ai.output.messages: Model response with finish_reason
- gen_ai.system_instructions: System prompt (extracted from conversation)

Uses typed constructs from types.jl for proper JSON serialization.
"""
function _record_messages_as_attributes!(span, conv)
    # Use the new OTEL GenAI utilities for proper format
    set_genai_messages!(span, conv; separate_system = true)

    # Also record JSON schema so Logfire knows how to parse these attributes
    schema_properties = Dict{String, Any}(
        "gen_ai.input.messages" => Dict("type" => "array"),
        "gen_ai.output.messages" => Dict("type" => "array"),
        "gen_ai.system_instructions" => Dict("type" => "array")
    )
    json_schema = Dict{String, Any}(
        "type" => "object",
        "properties" => schema_properties
    )
    set_span_attribute!(span, "logfire.json_schema", JSON3.write(json_schema))
end

# -- Token and response recording ----------------------------------------------

function _record_usage!(span, ai_msg)
    ai_msg === nothing && return
    tokens = _getfield_or(ai_msg, :tokens, (0, 0))
    input_tokens = (tokens isa Tuple || tokens isa AbstractVector) && length(tokens) >= 1 ?
                   tokens[1] : 0
    output_tokens = (tokens isa Tuple || tokens isa AbstractVector) && length(tokens) >= 2 ?
                    tokens[2] : 0
    record_token_usage!(span, input_tokens, output_tokens)
end

function _record_response_attrs!(span, ai_msg, requested_model::AbstractString)
    ai_msg === nothing && return
    extras = _getextras(ai_msg)

    _set_if_some(span, "gen_ai.response.model", get(extras, :model, requested_model))
    _set_if_some(span, "gen_ai.response.finish_reasons", _getfield_or(ai_msg, :finish_reason, nothing))
    latency = _getfield_or(ai_msg, :elapsed, nothing)
    latency !== nothing && _set_if_some(span, "gen_ai.latency_ms", latency * 1000)
    _set_if_some(span, "gen_ai.cost", _getfield_or(ai_msg, :cost, nothing))
    _set_if_some(span, "gen_ai.response.id", get(extras, :response_id, get(extras, :id, nothing)))
    _set_if_some(span, "gen_ai.system.fingerprint", get(extras, :system_fingerprint, nothing))
    _set_if_some(span, "gen_ai.response.status",
        _getfield_or(ai_msg, :status, get(extras, :status, nothing)))
    _set_if_some(span, "gen_ai.response.run_id",
        _getfield_or(ai_msg, :run_id, get(extras, :run_id, nothing)))

    # Record detailed usage statistics
    _record_detailed_usage!(span, ai_msg)
end

"""
    _record_detailed_usage!(span, ai_msg)

Record detailed usage statistics from extras to OTEL GenAI attributes.

Reads unified keys first, falls back to raw provider dicts for backwards compatibility
with older PromptingTools versions.

# Unified keys supported:
- `:cache_read_tokens`, `:cache_write_tokens` - cache token usage
- `:cache_write_1h_tokens`, `:cache_write_5m_tokens` - Anthropic ephemeral cache
- `:reasoning_tokens` - chain-of-thought tokens
- `:audio_input_tokens`, `:audio_output_tokens` - audio tokens
- `:accepted_prediction_tokens`, `:rejected_prediction_tokens` - prediction tokens
- `:service_tier` - provider service tier
- `:web_search_requests` - Anthropic server tool usage

# Fallback dicts:
- `:prompt_tokens_details` - OpenAI prompt token details
- `:completion_tokens_details` - OpenAI completion token details
- `:cache_read_input_tokens`, `:cache_creation_input_tokens` - Anthropic legacy keys
"""
function _record_detailed_usage!(span, ai_msg)
    ai_msg === nothing && return
    extras = _getextras(ai_msg)
    isempty(extras) && return

    # === Unified Keys (preferred) ===

    # Cache tokens
    _set_if_some(span, "gen_ai.usage.cache_read_tokens", get(extras, :cache_read_tokens, nothing))
    _set_if_some(span, "gen_ai.usage.cache_write_tokens", get(extras, :cache_write_tokens, nothing))
    _set_if_some(span, "gen_ai.usage.cache_write_1h_tokens", get(extras, :cache_write_1h_tokens, nothing))
    _set_if_some(span, "gen_ai.usage.cache_write_5m_tokens", get(extras, :cache_write_5m_tokens, nothing))

    # Reasoning/audio tokens
    _set_if_some(span, "gen_ai.usage.reasoning_tokens", get(extras, :reasoning_tokens, nothing))
    _set_if_some(span, "gen_ai.usage.audio_input_tokens", get(extras, :audio_input_tokens, nothing))
    _set_if_some(span, "gen_ai.usage.audio_output_tokens", get(extras, :audio_output_tokens, nothing))

    # Prediction tokens
    _set_if_some(span, "gen_ai.usage.accepted_prediction_tokens",
        get(extras, :accepted_prediction_tokens, nothing))
    _set_if_some(span, "gen_ai.usage.rejected_prediction_tokens",
        get(extras, :rejected_prediction_tokens, nothing))

    # Service tier
    _set_if_some(span, "gen_ai.service_tier", get(extras, :service_tier, nothing))

    # Anthropic server tools
    _set_if_some(span, "gen_ai.usage.web_search_requests", get(extras, :web_search_requests, nothing))

    # === Fallback to Raw Dicts (for older PromptingTools versions) ===

    # OpenAI prompt_tokens_details fallback
    if !haskey(extras, :cache_read_tokens) && haskey(extras, :prompt_tokens_details)
        details = extras[:prompt_tokens_details]
        if details isa AbstractDict
            _set_if_some(span, "gen_ai.usage.cache_read_tokens", get(details, :cached_tokens, nothing))
            _set_if_some(span, "gen_ai.usage.audio_input_tokens", get(details, :audio_tokens, nothing))
        end
    end

    # OpenAI completion_tokens_details fallback
    if !haskey(extras, :reasoning_tokens) && haskey(extras, :completion_tokens_details)
        details = extras[:completion_tokens_details]
        if details isa AbstractDict
            _set_if_some(span, "gen_ai.usage.reasoning_tokens", get(details, :reasoning_tokens, nothing))
            _set_if_some(span, "gen_ai.usage.audio_output_tokens", get(details, :audio_tokens, nothing))
            _set_if_some(span, "gen_ai.usage.accepted_prediction_tokens",
                get(details, :accepted_prediction_tokens, nothing))
            _set_if_some(span, "gen_ai.usage.rejected_prediction_tokens",
                get(details, :rejected_prediction_tokens, nothing))
        end
    end

    # Anthropic cache fallback (original keys)
    if !haskey(extras, :cache_read_tokens)
        _set_if_some(span, "gen_ai.usage.cache_read_tokens", get(extras, :cache_read_input_tokens, nothing))
    end
    if !haskey(extras, :cache_write_tokens)
        _set_if_some(span, "gen_ai.usage.cache_write_tokens",
            get(extras, :cache_creation_input_tokens, nothing))
    end
end

function _record_cache_attrs!(span, ai_msg)
    ai_msg === nothing && return
    extras = _getextras(ai_msg)
    _set_if_some(span, "gen_ai.cache.status", get(extras, :cache_status, get(extras, :cache_hit, nothing)))
    _set_if_some(span, "gen_ai.cache.key", get(extras, :cache_key, nothing))
end

function _record_streaming_attrs!(span, ai_msg)
    ai_msg === nothing && return
    extras = _getextras(ai_msg)
    _set_if_some(span, "gen_ai.response.streamed", get(extras, :streamed, nothing))
    _set_if_some(span, "gen_ai.response.num_chunks", get(extras, :num_chunks, nothing))
end

"""
Record tool calls from AIToolRequest or AIMessage.

Handles both:
- `AIToolRequest.tool_calls` (direct field with Vector{ToolMessage})
- `extras[:tool_calls]` (fallback for AIMessage with tool calls in extras)
"""
function _record_tool_calls!(span, ai_msg)
    ai_msg === nothing && return

    # Check direct field first (AIToolRequest.tool_calls)
    tool_calls = if hasproperty(ai_msg, :tool_calls)
        tc = getproperty(ai_msg, :tool_calls)
        # Ensure it's not nothing and not empty
        (tc !== nothing && !isempty(tc)) ? tc : nothing
    else
        # Fallback to extras for AIMessage with tool calls in extras
        extras = _getextras(ai_msg)
        get(extras, :tool_calls, get(extras, :function_calls, nothing))
    end

    tool_calls === nothing && return

    # Record count
    count = try
        length(tool_calls)
    catch
        nothing
    end
    _set_if_some(span, "gen_ai.response.tool_calls.count", count)

    # Extract structured data from ToolMessage objects
    tool_call_data = _extract_tool_call_data(tool_calls)

    if !isempty(tool_call_data)
        # Store as span attribute (JSON string) for Logfire UI
        set_span_attribute!(span, "gen_ai.tool_calls", JSON3.write(tool_call_data))
    end
end

"""
Extract structured tool call data from a vector of tool calls.
Handles both ToolMessage objects and Dict representations.
"""
function _extract_tool_call_data(tool_calls)
    result = Dict{String, Any}[]

    for tc in tool_calls
        try
            data = if hasproperty(tc, :tool_call_id)
                # ToolMessage from PromptingTools
                Dict{String, Any}(
                    "id" => string(getproperty(tc, :tool_call_id)),
                    "name" => string(something(getproperty(tc, :name), "unknown")),
                    "arguments" => string(getproperty(tc, :raw))
                )
            elseif tc isa AbstractDict
                # Dict representation (from extras or rendered)
                # Handle OpenAI format where name/arguments are nested under "function"
                func = get(tc, "function", get(tc, :function, Dict()))
                name = get(func, "name", get(func, :name,
                    get(tc, "name", get(tc, :name, "unknown"))))
                args = get(func, "arguments",
                    get(func, :arguments,
                        get(tc, "arguments", get(tc, :arguments, "{}"))))
                Dict{String, Any}(
                    "id" => string(get(tc, :id, get(tc, "id", ""))),
                    "name" => string(name),
                    "arguments" => args isa AbstractString ? args : JSON3.write(args)
                )
            else
                # Fallback: serialize the whole thing
                Dict{String, Any}("raw" => _safe_json(tc))
            end
            push!(result, data)
        catch e
            @debug "Failed to extract tool call data" exception = e
            push!(result, Dict{String, Any}("raw" => _safe_json(tc)))
        end
    end

    return result
end

_safe_json(x) =
    try
        JSON3.write(x)
    catch
        try
            JSON3.write(string(x))
        catch
            "unserializable"
        end
    end

function _detect_system(schema)
    s = string(typeof(schema))
    if occursin("OpenAI", s)
        return "openai"
    elseif occursin("Anthropic", s)
        return "anthropic"
    elseif occursin("Google", s) || occursin("Vertex", s)
        return "google"
    elseif occursin("Ollama", s)
        return "ollama"
    else
        return "unknown"
    end
end
