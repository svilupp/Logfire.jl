# Span utilities and GenAI semantic conventions

"""
    set_span_attribute!(span, key::String, value)

Set an attribute on a span.
"""
function set_span_attribute!(span, key::String, value)
    span.attributes[key] = value
end

"""
    set_span_status_error!(span, message::String)

Set span status to error with a message.
"""
function set_span_status_error!(span, message::String)
    OpenTelemetryAPI.span_status!(span, OpenTelemetryAPI.SPAN_STATUS_ERROR, message)
end

"""
    record_exception!(span, exception; backtrace=nothing, escaped=false)

Record an exception on a span following OpenTelemetry semantic conventions.

This function sets the standard OpenTelemetry exception attributes that Logfire recognizes
for its specialized exception view:
- `exception.type`: The exception type name
- `exception.message`: The exception message
- `exception.stacktrace`: The full stack trace

It also sets the span status to error and the log level to 'error'.

# Arguments
- `span`: The span to record the exception on
- `exception`: The exception object to record
- `backtrace`: Optional backtrace. If not provided, attempts to use `catch_backtrace()` 
  if called within a catch block. Pass the backtrace explicitly for best results.
- `escaped`: Whether the exception message should be escaped (default: false, reserved for future use)

# Example
```julia
try
    error("Something went wrong")
catch e
    bt = catch_backtrace()
    record_exception!(span, e; backtrace=bt)
    rethrow()
end
```

Or more simply, if called within the catch block:
```julia
try
    error("Something went wrong")
catch e
    record_exception!(span, e)  # Will attempt to get backtrace automatically
    rethrow()
end
```

This is equivalent to Python's `logfire.exception()` or `span.record_exception()`.
"""
function record_exception!(span, exception; backtrace = nothing, escaped = false)
    # Get exception type name
    exception_type = string(typeof(exception).name.name)

    # Get exception message
    exception_msg = string(exception)

    # Get stacktrace
    if backtrace === nothing
        # Try to get current backtrace if available (only works if called within catch block)
        try
            # catch_backtrace() must be called in the context where exception was caught
            backtrace = Base.catch_backtrace()
        catch
            backtrace = nothing
        end
    end

    # Format stacktrace
    stacktrace_str = ""
    if backtrace !== nothing
        try
            stacktrace_str = sprint(showerror, exception, backtrace)
        catch
            # Fallback to just the exception message if stacktrace formatting fails
            stacktrace_str = exception_msg
        end
    else
        # If no backtrace available, use just the exception message
        stacktrace_str = exception_msg
    end

    # Truncate stacktrace if too long (OpenTelemetry recommends reasonable limits)
    # Logfire can handle large stacktraces, but we'll truncate at 50KB to be safe
    max_stacktrace_length = 50_000
    if length(stacktrace_str) > max_stacktrace_length
        stacktrace_str = stacktrace_str[1:max_stacktrace_length] * "... [truncated]"
    end

    # Set OpenTelemetry semantic convention attributes
    # These are the standard attribute names that Logfire recognizes
    set_span_attribute!(span, "exception.type", exception_type)
    set_span_attribute!(span, "exception.message", exception_msg)
    set_span_attribute!(span, "exception.stacktrace", stacktrace_str)

    # Set span status to error
    set_span_status_error!(span, exception_msg)

    # Set log level to 'error' (Logfire uses this for filtering and display)
    # This matches Python's logfire.exception() behavior
    set_span_attribute!(span, "log.level", "error")

    return nothing
end

"""
    with_span(f, name::String; attrs...)

Create a span with the given name and execute the function within it.
The function `f` receives the span as an argument.

If `auto_record_exceptions` is enabled in configuration (default: true),
exceptions thrown within the span will be automatically recorded using
OpenTelemetry semantic conventions before being rethrown.

# Example
```julia
# With auto_record_exceptions enabled (default)
Logfire.with_span("my-operation") do span
    error("This will be automatically recorded!")  # Exception automatically captured
end

# Manual exception handling (still works)
Logfire.with_span("my-operation") do span
    try
        risky_operation()
    catch e
        Logfire.record_exception!(span, e)
        # Handle exception...
    end
end
```
"""
function with_span(f, name::String; attrs...)
    t = tracer()
    cfg = get_config()

    OpenTelemetryAPI.with_span(name, t) do
        span = OpenTelemetryAPI.current_span()
        # Set any additional attributes
        for (k, v) in attrs
            set_span_attribute!(span, string(k), v)
        end

        # Automatically catch and record exceptions if enabled
        if cfg.auto_record_exceptions
            try
                return f(span)
            catch e
                # Record exception using OpenTelemetry semantic conventions
                # Get backtrace for the caught exception
                bt = Base.catch_backtrace()
                try
                    record_exception!(span, e; backtrace = bt)
                catch record_err
                    # If recording fails, at least set span status to error
                    # This ensures the span is marked as failed even if recording fails
                    try
                        set_span_status_error!(span, string(e))
                        set_span_attribute!(
                            span, "exception.type", string(typeof(e).name.name))
                        set_span_attribute!(span, "exception.message", string(e))
                    catch
                        # If even basic error recording fails, just continue
                    end
                end
                # Rethrow the exception so callers can handle it
                rethrow()
            end
        else
            # If auto-recording is disabled, just execute normally
            return f(span)
        end
    end
end

"""
    with_llm_span(f, operation::String; system="openai", model="", kwargs...)

Create a span for an LLM operation with GenAI semantic convention attributes.

# Arguments
- `f`: Function to execute within the span
- `operation`: The operation name (e.g., "chat", "embed", "completion")
- `system`: The AI system/provider (e.g., "openai", "anthropic")
- `model`: The model name/ID
- `kwargs`: Additional attributes to set on the span
"""
function with_llm_span(f, operation::String;
        system::String = "openai",
        model::String = "",
        kwargs...)
    span_name = "gen_ai.$operation"
    t = tracer("logfire.genai")

    OpenTelemetryAPI.with_span(span_name, t) do
        span = OpenTelemetryAPI.current_span()

        # Set GenAI semantic convention attributes
        set_span_attribute!(span, "gen_ai.operation.name", operation)
        set_span_attribute!(span, "gen_ai.system", system)

        if !isempty(model)
            set_span_attribute!(span, "gen_ai.request.model", model)
        end

        # Set any additional attributes
        for (k, v) in kwargs
            set_span_attribute!(span, string(k), v)
        end

        try
            result = f(span)
            return result
        catch e
            record_exception!(span, e)
            rethrow()
        end
    end
end

"""
    record_token_usage!(span, input_tokens::Int, output_tokens::Int; model::String="")

Record token usage on a span following GenAI semantic conventions.
"""
function record_token_usage!(
        span, input_tokens::Int, output_tokens::Int; model::String = "")
    set_span_attribute!(span, "gen_ai.usage.input_tokens", input_tokens)
    set_span_attribute!(span, "gen_ai.usage.output_tokens", output_tokens)
    set_span_attribute!(span, "gen_ai.usage.total_tokens", input_tokens + output_tokens)

    if !isempty(model)
        set_span_attribute!(span, "gen_ai.response.model", model)
    end
end

"""
    add_prompt_attribute!(span, messages::Vector)

Add prompt messages as span attributes.
"""
function add_prompt_attribute!(span, messages::Vector)
    # Store messages as JSON string in attributes
    try
        messages_json = JSON3.write(messages)
        set_span_attribute!(span, "gen_ai.prompt.messages", _maybe_truncate(messages_json))
    catch
        # If JSON fails, store as string
        set_span_attribute!(
            span, "gen_ai.prompt.messages", _maybe_truncate(string(messages)))
    end
end

"""
    add_response_attribute!(span, content::AbstractString)

Add response content as a span attribute.
"""
function add_response_attribute!(span, content::AbstractString)
    set_span_attribute!(span, "gen_ai.response.content", _maybe_truncate(content))
end

# Helper functions

function _maybe_truncate(content::AbstractString, max_length::Int = 10000)
    if length(content) > max_length
        return content[1:max_length] * "... [truncated]"
    end
    return content
end
