# ─────────────────────────────────────────────────────────────────────
# Provider Registry
# ─────────────────────────────────────────────────────────────────────

const PROVIDER_REGISTRY = Dict{String, Provider}()

function _init_providers!()
    defaults = [
        "claude" => Provider(
            "Claude (Anthropic)", "ANTHROPIC_API_KEY",
            "https://api.anthropic.com/v1/messages",
            "claude-sonnet-4-20250514", :anthropic, 8192,
            0.003, 0.015
        ),
        "openai" => Provider(
            "GPT-4o (OpenAI)", "OPENAI_API_KEY",
            "https://api.openai.com/v1/chat/completions",
            "gpt-4o", :openai, 8192,
            0.0025, 0.010
        ),
        "gemini" => Provider(
            "Gemini (Google)", "GOOGLE_API_KEY",
            "https://generativelanguage.googleapis.com/v1beta/models",
            "gemini-2.0-flash", :google, 8192,
            0.0001, 0.0004
        ),
        "deepseek" => Provider(
            "DeepSeek", "DEEPSEEK_API_KEY",
            "https://api.deepseek.com/v1/chat/completions",
            "deepseek-chat", :openai, 8192,
            0.00014, 0.00028
        ),
        "mistral" => Provider(
            "Mistral", "MISTRAL_API_KEY",
            "https://api.mistral.ai/v1/chat/completions",
            "mistral-large-latest", :openai, 8192,
            0.002, 0.006
        ),
    ]
    for (key, prov) in defaults
        PROVIDER_REGISTRY[key] = prov
    end
end

"""
    add_provider!(key; endpoint, model, name="", api_key_env="",
                  format=:openai, max_tokens=4096,
                  cost_per_1k_input=0.0, cost_per_1k_output=0.0)

Register a custom provider. Especially useful for local models served
via Ollama, LM Studio, llama.cpp, vLLM, or any OpenAI-compatible API.

# Examples

```julia
# Ollama (default port 11434)
add_provider!("local_qwen",
    endpoint = "http://localhost:11434/v1/chat/completions",
    model = "qwen2.5:72b",
    name = "Qwen 2.5 72B (local)"
)

# LM Studio (default port 1234)
add_provider!("local_llama",
    endpoint = "http://localhost:1234/v1/chat/completions",
    model = "meta-llama-3.1-70b",
    name = "LLaMA 3.1 70B (local)"
)

# vLLM server
add_provider!("vllm_mistral",
    endpoint = "http://localhost:8000/v1/chat/completions",
    model = "mistralai/Mistral-Large-Instruct-2411",
    name = "Mistral Large (vLLM)"
)
```

Local providers don't require an API key by default. Set `api_key_env`
if your server requires authentication.
"""
function add_provider!(key::AbstractString;
                       endpoint::String,
                       model::String,
                       name::String = "",
                       api_key_env::String = "",
                       format::Symbol = :openai,
                       max_tokens::Int = 4096,
                       cost_per_1k_input::Float64 = 0.0,
                       cost_per_1k_output::Float64 = 0.0)
    if isempty(name)
        name = "$model (custom)"
    end
    PROVIDER_REGISTRY[string(key)] = Provider(
        name, api_key_env, endpoint, model, format, max_tokens,
        cost_per_1k_input, cost_per_1k_output
    )
    @info "Registered provider '$(key)': $(name) at $(endpoint)"
    return nothing
end

"""
    remove_provider!(key)

Remove a provider from the registry.
"""
function remove_provider!(key::AbstractString)
    delete!(PROVIDER_REGISTRY, string(key))
end

"""
    list_providers() -> Dict{String, Provider}

Return all registered providers.
"""
list_providers() = copy(PROVIDER_REGISTRY)

"""
    available_providers() -> Vector{Tuple{String, Provider}}

Return providers for which API keys are set (or which need no key, e.g. local).
"""
function available_providers(requested::Vector{String} = String[])
    candidates = isempty(requested) ? collect(keys(PROVIDER_REGISTRY)) : requested
    result = Tuple{String, Provider}[]
    for key in candidates
        key = lowercase(strip(key))
        if !haskey(PROVIDER_REGISTRY, key)
            @warn "Unknown provider '$key', skipping."
            continue
        end
        p = PROVIDER_REGISTRY[key]
        # Local providers (empty api_key_env) are always available
        if isempty(p.api_key_env) || !isempty(get(ENV, p.api_key_env, ""))
            push!(result, (key, p))
        else
            @warn "No API key for $(p.name) ($(p.api_key_env) not set), skipping."
        end
    end
    return result
end

# Detect if a provider is local (no API key required)
is_local(p::Provider) = isempty(p.api_key_env)

# Initialize defaults on module load
function __init__()
    _init_providers!()
end
