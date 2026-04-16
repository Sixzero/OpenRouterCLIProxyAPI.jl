module OpenRouterCLIProxyAPI

using Dates: now
using OpenRouter
using OpenRouter: add_provider, set_provider!, ChatCompletionSchema, ChatCompletionAnthropicSchema,
                  AnthropicSchema, ProviderEndpoint, get_global_cache, Pricing, ZERO_PRICING,
                  OpenRouterModel, CachedModel, ModelProviders

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
    "claude-opus-4-7" => "anthropic/claude-opus-4.7",
    "claude-opus-4-6" => "anthropic/claude-opus-4.6",
    "claude-sonnet-4-6" => "anthropic/claude-sonnet-4.6",
)

const MODEL_MAP_OPENAI = Dict{String,String}(
    "gpt-5" => "openai/gpt-5",
    "gpt-5-codex" => "openai/gpt-5-codex",
    "gpt-5.1" => "openai/gpt-5.1",
    "gpt-5.1-codex" => "openai/gpt-5.1-codex",
    "gpt-5.1-codex-mini" => "openai/gpt-5.1-codex-mini",
    "gpt-5.1-codex-max" => "openai/gpt-5.1-codex-max",
    "gpt-5.2" => "openai/gpt-5.2",
    "gpt-5.2-codex" => "openai/gpt-5.2-codex",
    "gpt-5.3-codex" => "openai/gpt-5.3-codex",
    "gpt-5.3-codex-spark" => "openai/gpt-5.3-codex-spark",
    "gpt-5.4" => "openai/gpt-5.4",
    "gpt-5.4-mini" => "openai/gpt-5.4-mini",
)

# Pricing matching gpt-5.3-codex (best estimate — no public pricing for spark yet)
const CODEX_SPARK_PRICING = Pricing(
    prompt = "0.00000175",
    completion = "0.000014",
    request = nothing,
    image = nothing,
    web_search = nothing,
    internal_reasoning = nothing,
    image_output = nothing,
    audio = nothing,
    input_audio_cache = nothing,
    input_cache_read = "0.000000175",
    input_cache_write = nothing,
    discount = nothing,
)

# Models only on CLI proxy (not on OpenRouter) — need synthetic cache entries
const PROXY_ONLY_MODELS = Dict{String,@NamedTuple{name::String, context_length::Int, pricing::Pricing}}(
    "openai/gpt-5.3-codex-spark" => (name = "GPT 5.3 Codex Spark", context_length = 128000, pricing = CODEX_SPARK_PRICING),
)

const MODEL_MAP_GEMINI = Dict{String,String}(
    "gemini-2.5-flash"              => "google/gemini-2.5-flash",
    "gemini-2.5-flash-lite"         => "google/gemini-2.5-flash-lite",
    "gemini-2.5-pro"                => "google/gemini-2.5-pro",
    "gemini-3-flash"                => "google/gemini-3-flash-preview",
    "gemini-3-flash-preview"        => "google/gemini-3-flash-preview",
    "gemini-3-pro-preview"          => "google/gemini-3-pro-image-preview",
    "gemini-3-pro-low"              => "google/gemini-3-pro-image-preview",
    "gemini-3-pro-high"             => "google/gemini-3-pro-image-preview",
    "gemini-3.1-flash-image"        => "google/gemini-3.1-flash-image-preview",
    "gemini-3.1-flash-lite-preview" => "google/gemini-3.1-flash-lite-preview",
    "gemini-3.1-pro-preview"        => "google/gemini-3.1-pro-preview",
    "gemini-3.1-pro-low"            => "google/gemini-3.1-pro-preview",
    "gemini-3.1-pro-high"           => "google/gemini-3.1-pro-preview",
)

const MODEL_MAP = merge(MODEL_MAP_ANTHROPIC, MODEL_MAP_OPENAI, MODEL_MAP_GEMINI)
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

    # Register proxy-only models as synthetic cache entries
    for (or_model_id, meta) in PROXY_ONLY_MODELS
        haskey(cache.models, or_model_id) && continue
        native_id = get(MODEL_MAP_REVERSE, or_model_id, or_model_id)
        # Derive original provider from model ID (e.g. "openai" from "openai/gpt-5.3-codex-spark")
        orig_provider = split(or_model_id, "/")[1]
        endpoints = ProviderEndpoint[]
        for (pname, ptag) in [(orig_provider, orig_provider), (provider_name, provider_name)]
            push!(endpoints, ProviderEndpoint(;
                name = native_id,
                model_name = native_id,
                context_length = meta.context_length,
                pricing = meta.pricing,
                provider_name = pname,
                tag = ptag,
                quantization = nothing,
                max_completion_tokens = meta.context_length,
                max_prompt_tokens = nothing,
                supported_parameters = nothing,
                uptime_last_30m = nothing,
                supports_implicit_caching = nothing,
                status = nothing
            ))
        end
        model = OpenRouterModel(or_model_id, meta.name, "CLI proxy only model", meta.context_length, meta.pricing, nothing, nothing)
        providers = ModelProviders(or_model_id, meta.name, nothing, nothing, nothing, endpoints)
        cache.models[or_model_id] = CachedModel(model, providers, now(), true)
        count += 1
    end

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
    override_providers!(base_url, api_key_env_var; gemini, verbose)

Override providers to route through cli_proxy_api.
Set `gemini=true` to also override google-ai-studio.
"""
function override_providers!(base_url::String, api_key_env_var::String;
                             gemini::Bool=false, verbose::Bool=false)
    anthropic_base_url = replace(base_url, r"/v1/?$" => "")
    set_provider!(
        "anthropic",
        anthropic_base_url,
        "Bearer",
        api_key_env_var,
        Dict{String,String}(),
        cli_proxy_model_transform,
        AnthropicSchema(),
        "anthropic (overridden to cli_proxy_api)"
    )
    set_provider!(
        "openai",
        base_url,
        "Bearer",
        api_key_env_var,
        Dict{String,String}(),
        cli_proxy_model_transform,
        ChatCompletionSchema(),
        "openai (overridden to cli_proxy_api)"
    )

    if gemini
        google_proxy_transform(id::AbstractString) = replace(id, r"^google/" => "")
        set_provider!(
            "google-ai-studio",
            base_url,
            "Bearer",
            api_key_env_var,
            Dict{String,String}(),
            google_proxy_transform,
            ChatCompletionSchema(),
            "google-ai-studio (overridden to cli_proxy_api)"
        )
    end

    verbose && @info "Overrode providers to route through cli_proxy_api" gemini
end

# ============ Setup ============

"""
    setup_cli_proxy!(;
        base_url::String="http://localhost:8317/v1",
        api_key_env_var::String="CLIPROXYAPI_API_KEY",
        provider_name::String="cli_proxy_api",
        mutate::Bool=false,
        gemini::Bool=false
    )

Complete setup for CLI proxy:
1. Register the cli_proxy_api provider
2. Inject endpoints into all mapped models

Set `mutate=true` to override anthropic and openai providers to route through cli_proxy_api.
Set `gemini=true` to also override google-ai-studio.
Set `verbose=true` to log setup details.
"""
function setup_cli_proxy!(;
    base_url::String = "http://localhost:8317/v1",
    api_key_env_var::String = "CLIPROXYAPI_API_KEY",
    provider_name::String = "cli_proxy_api",
    mutate::Bool = false,
    gemini::Bool = false,
    verbose::Bool = false
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

    # Always register proxy-only models + inject endpoints (even in mutate mode)
    count = inject_cli_proxy_endpoints!(provider_name)

    if mutate
        override_providers!(base_url, api_key_env_var; gemini, verbose)
    end

    verbose && @info "CLI Proxy setup complete" provider_name base_url mutate
    return count
end

end # module
