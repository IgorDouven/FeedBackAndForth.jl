# ─────────────────────────────────────────────────────────────────────
# API Calling Functions
# ─────────────────────────────────────────────────────────────────────

"""
    call_llm(provider, system_prompt, user_message; retries=3) -> (response_text, token_info)

Send a message to an LLM provider and return the response text plus
a NamedTuple of token usage: `(input=..., output=...)`.
Retries on transient network errors with exponential backoff.
"""
function call_llm(provider::Provider, system_prompt::String, user_message::String;
                  retries::Int=3)
    api_key = if isempty(provider.api_key_env)
        ""  # local models don't need a key
    else
        get(ENV, provider.api_key_env, "")
    end

    if !isempty(provider.api_key_env) && isempty(api_key)
        error("API key not found for $(provider.name). Set $(provider.api_key_env).")
    end

    local last_err
    for attempt in 1:retries
        try
            if provider.format == :anthropic
                return _call_anthropic(provider, system_prompt, user_message, api_key)
            elseif provider.format == :openai
                return _call_openai(provider, system_prompt, user_message, api_key)
            elseif provider.format == :google
                return _call_google(provider, system_prompt, user_message, api_key)
            else
                error("Unknown provider format: $(provider.format)")
            end
        catch e
            last_err = e
            # Only retry on transient network errors, not auth/API errors
            if _is_transient(e) && attempt < retries
                wait_time = 2^attempt + rand()  # exponential backoff with jitter
                @warn "$(provider.name) attempt $attempt/$retries failed ($(typeof(e))), " *
                      "retrying in $(round(wait_time; digits=1))s..."
                sleep(wait_time)
            else
                rethrow(e)
            end
        end
    end
    throw(last_err)  # unreachable, but keeps the compiler happy
end

# Classify whether an error is transient (worth retrying)
function _is_transient(e)
    e isa HTTP.RequestError && return true
    e isa Base.IOError && return true
    e isa EOFError && return true
    if e isa TaskFailedException
        return true  # usually wraps a connection error
    end
    # HTTP 429 (rate limit), 500, 502, 503, 504, 529 (overloaded) are transient
    if e isa ErrorException
        msg = e.msg
        for code in ("429", "500", "502", "503", "504", "529")
            contains(msg, code) && return true
        end
    end
    return false
end

function _call_anthropic(provider::Provider, system::String, user::String, key::String)
    headers = [
        "x-api-key" => key,
        "anthropic-version" => "2023-06-01",
        "content-type" => "application/json",
    ]
    body = JSON3.write(Dict(
        "model" => provider.model,
        "max_tokens" => provider.max_tokens,
        "system" => system,
        "messages" => [Dict("role" => "user", "content" => user)]
    ))
    resp = HTTP.post(provider.endpoint, headers, body;
                     status_exception=false, connect_timeout=30, readtimeout=600)
    if resp.status != 200
        error("Anthropic API error ($(resp.status)): $(String(resp.body))")
    end
    data = JSON3.read(String(resp.body))
    text = data.content[1].text
    tokens = (
        input  = _get_nested(data, :usage, :input_tokens, 0),
        output = _get_nested(data, :usage, :output_tokens, 0)
    )
    return text, tokens
end

function _call_openai(provider::Provider, system::String, user::String, key::String)
    headers = ["Content-Type" => "application/json"]
    if !isempty(key)
        push!(headers, "Authorization" => "Bearer $key")
    end
    body = JSON3.write(Dict(
        "model" => provider.model,
        "max_tokens" => provider.max_tokens,
        "messages" => [
            Dict("role" => "system", "content" => system),
            Dict("role" => "user", "content" => user),
        ]
    ))
    resp = HTTP.post(provider.endpoint, headers, body;
                     status_exception=false, connect_timeout=30, readtimeout=600)
    if resp.status != 200
        error("$(provider.name) API error ($(resp.status)): $(String(resp.body))")
    end
    data = JSON3.read(String(resp.body))
    text = data.choices[1].message.content
    tokens = (
        input  = _get_nested(data, :usage, :prompt_tokens, 0),
        output = _get_nested(data, :usage, :completion_tokens, 0)
    )
    return text, tokens
end

function _call_google(provider::Provider, system::String, user::String, key::String)
    url = "$(provider.endpoint)/$(provider.model):generateContent?key=$key"
    headers = ["Content-Type" => "application/json"]
    body = JSON3.write(Dict(
        "system_instruction" => Dict("parts" => [Dict("text" => system)]),
        "contents" => [Dict("parts" => [Dict("text" => user)])],
        "generationConfig" => Dict("maxOutputTokens" => provider.max_tokens)
    ))
    resp = HTTP.post(url, headers, body;
                     status_exception=false, connect_timeout=30, readtimeout=600)
    if resp.status != 200
        error("Google API error ($(resp.status)): $(String(resp.body))")
    end
    data = JSON3.read(String(resp.body))
    text = data.candidates[1].content.parts[1].text
    tokens = (
        input  = _get_nested(data, :usageMetadata, :promptTokenCount, 0),
        output = _get_nested(data, :usageMetadata, :candidatesTokenCount, 0)
    )
    return text, tokens
end

# Helper to safely navigate nested JSON
function _get_nested(data, keys::Symbol...; default=0)
    current = data
    for k in keys[1:end]
        if current isa AbstractDict || applicable(getproperty, current, k)
            try
                current = getproperty(current, k)
            catch
                return default
            end
        else
            return default
        end
    end
    return current
end

function _get_nested(data, k1::Symbol, k2::Symbol, default)
    try
        return getproperty(getproperty(data, k1), k2)
    catch
        return default
    end
end
