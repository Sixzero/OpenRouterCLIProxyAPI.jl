module OpenRouterCLIProxyAPI

using OpenRouter
using OpenRouter: add_provider, set_provider!, ChatCompletionSchema, ChatCompletionAnthropicSchema,
                  AnthropicSchema, ProviderEndpoint, get_global_cache, Pricing, ZERO_PRICING

export inject_cli_proxy_endpoints!, cli_proxy_model_transform, setup_cli_proxy!
export MODEL_MAP, MODEL_MAP_REVERSE

# ============ Model Mappings ============
# Native proxy model ID => OpenRouter model ID

const MODEL_MAP_ANTHROPIC = Dict{String,String}(
    "claude-3-5-haiku-20241022" => "anthropic/claude-3.5-haiku",
    "claude-3-7-sonnet-20250219" => "anthropic/claude-3.7-sonnet",
    "claude-sonnet-4-20250514" => "anthropic/claude-sonnet-4",
    "claude-opus-4-20250514" => "anthropic/claude-opus-4",
    "claude-opus-4-1-20250805" => "anthropic/claude-opus-4.1",
    "claude-sonnet-4-5-20250929" => "anthropic/claude-sonnet-4.5",
    "claude-haiku-4-5-20251001" => "anthropic/claude-haiku-4.5",
    "claude-opus-4-5-20251101" => "anthropic/claude-opus-4.5",
    "claude-opus-4-6" => "anthropic/claude-opus-4.6",
)

const MODEL_MAP_OPENAI = Dict{String,String}(
    "gpt-5" => "openai/gpt-5",
    "gpt-5-codex" => "openai/gpt-5-codex",
    "gpt-5.1" => "openai/gpt-5.1",
    "gpt-5.1-codex" => "openai/gpt-5.1-codex",
    "gpt-5.1-codex-mini" => "openai/gpt-5.1-codex-mini",
    "gpt-5.1-codex-max" => "openai/gpt-5.1-codex-max",
    "gpt-5.2" => "openai/gpt-5.2",
)

const MODEL_MAP = merge(MODEL_MAP_ANTHROPIC, MODEL_MAP_OPENAI)
const MODEL_MAP_REVERSE = Dict(v => k for (k, v) in MODEL_MAP)

# ============ Transform Function ============

"""
    cli_proxy_model_transform(model_id::AbstractString)

Converts OpenRouter model ID to native proxy model ID.
E.g., "anthropic/claude-opus-4.5" → "claude-opus-4-5-20251101"
"""
cli_proxy_model_transform(model_id::AbstractString) = get(MODEL_MAP_REVERSE, model_id, model_id)

# ============ Endpoint Injection ============

"""
    inject_cli_proxy_endpoints!(provider_name::String="cli_proxy_api")

Inject cli_proxy_api endpoints into cached models (adds new endpoint, preserves originals).
"""
function inject_cli_proxy_endpoints!(provider_name::String="cli_proxy_api")
    cache = get_global_cache()
    count = 0

    for (native_id, or_model_id) in MODEL_MAP
        cached = get(cache.models, or_model_id, nothing)

        if cached === nothing || cached.endpoints === nothing
            @warn "Model not found in cache (skipping)" or_model_id
            continue
        end

        # Add new endpoint without overwriting
        existing = findfirst(ep -> ep.provider_name == provider_name, cached.endpoints.endpoints)
        if existing !== nothing
            continue
        end

        base_pricing = if !isempty(cached.endpoints.endpoints)
            cached.endpoints.endpoints[1].pricing
        else
            ZERO_PRICING
        end

        new_endpoint = ProviderEndpoint(;
            name = native_id,
            model_name = native_id,
            context_length = cached.model.context_length,
            pricing = base_pricing,
            provider_name = provider_name,
            tag = provider_name,
            quantization = nothing,
            max_completion_tokens = nothing,
            max_prompt_tokens = nothing,
            supported_parameters = nothing,
            uptime_last_30m = nothing,
            supports_implicit_caching = nothing,
            status = nothing
        )

        push!(cached.endpoints.endpoints, new_endpoint)
        count += 1
    end

    @info "Injected $count cli_proxy_api endpoints"
    return count
end

# ============ Provider Override ============

"""
    override_providers!(base_url, api_key_env_var)

Override anthropic and openai providers to route through cli_proxy_api.
"""
function override_providers!(base_url::String, api_key_env_var::String)
    schemas = Dict("anthropic" => ChatCompletionAnthropicSchema(), "openai" => ChatCompletionSchema())
    for name in ("anthropic", "openai")
        set_provider!(
            name,
            base_url,
            "Bearer",
            api_key_env_var,
            Dict{String,String}(),
            cli_proxy_model_transform,
            schemas[name],
            "$name (overridden to cli_proxy_api)"
        )
    end
    @info "Overrode anthropic and openai providers to route through cli_proxy_api"
end

# ============ Setup ============

"""
    setup_cli_proxy!(;
        base_url::String="http://localhost:8317/v1",
        api_key_env_var::String="CLIPROXYAPI_API_KEY",
        provider_name::String="cli_proxy_api",
        mutate::Bool=false
    )

Complete setup for CLI proxy:
1. Register the cli_proxy_api provider
2. Inject endpoints into all mapped models

Set `mutate=true` to override original providers (anthropic, openai) to route through cli_proxy_api.
This allows `anthropic:anthropic/claude-sonnet-4.5` to transparently route through the proxy.
"""
function setup_cli_proxy!(;
    base_url::String = "http://localhost:8317/v1",
    api_key_env_var::String = "CLIPROXYAPI_API_KEY",
    provider_name::String = "cli_proxy_api",
    mutate::Bool = false
)
    # Always register cli_proxy_api provider
    add_provider(
        provider_name,
        base_url,
        "Bearer",
        api_key_env_var,
        Dict{String,String}(),
        cli_proxy_model_transform,
        ChatCompletionSchema(),
        "CLI Proxy API - routes to local proxy"
    )

    if mutate
        override_providers!(base_url, api_key_env_var)
    end

    count = mutate ? 0 : inject_cli_proxy_endpoints!(provider_name)

    @info "CLI Proxy setup complete" provider_name base_url mutate
    return count
end

end # module
