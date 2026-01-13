#=
CLI Proxy API Provider Example
==============================

This example shows two approaches for using the CLI proxy:

1. **Recommended**: Use OpenRouterCLIProxyAPI.jl package (adds endpoint, preserves originals)
2. **Legacy**: Override endpoints directly (overwrites originals)

Usage with package:
  using OpenRouterCLIProxyAPI
  setup_cli_proxy!()
  response = aigen("Hello", "cli_proxy_api:anthropic/claude-opus-4.5")

The original provider still works:
  response = aigen("Hello", "anthropic:anthropic/claude-opus-4.5")  # Direct Anthropic API
=#

using OpenRouter
using OpenRouter: add_provider, ChatCompletionSchema, ProviderEndpoint, get_global_cache

# ============ Approach 1: Using OpenRouterCLIProxyAPI package ============
# This is the recommended approach - adds endpoints without overwriting

# using OpenRouterCLIProxyAPI
# setup_cli_proxy!()  # Registers provider + injects endpoints

# ============ Approach 2: Manual setup (legacy - overwrites endpoints) ============

# Model Mappings: Native proxy model ID => OpenRouter model ID
const MODEL_MAP_ANTHROPIC = Dict{String,String}(
    "claude-3-5-haiku-20241022" => "anthropic/claude-3.5-haiku",
    "claude-3-7-sonnet-20250219" => "anthropic/claude-3.7-sonnet",
    "claude-sonnet-4-20250514" => "anthropic/claude-sonnet-4",
    "claude-opus-4-20250514" => "anthropic/claude-opus-4",
    "claude-opus-4-1-20250805" => "anthropic/claude-opus-4.1",
    "claude-sonnet-4-5-20250929" => "anthropic/claude-sonnet-4.5",
    "claude-haiku-4-5-20251001" => "anthropic/claude-haiku-4.5",
    "claude-opus-4-5-20251101" => "anthropic/claude-opus-4.5",
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

cli_proxy_model_transform(model_id::AbstractString) = get(MODEL_MAP_REVERSE, model_id, model_id)

"""
Override all endpoints to point to cli_proxy_api provider.
WARNING: This overwrites existing endpoints. Use OpenRouterCLIProxyAPI.jl instead
for non-destructive endpoint injection.
"""
function override_endpoints_to_cli_proxy!(provider_name::String = "cli_proxy_api")
    cache = get_global_cache()
    for (native_id, or_model_id) in MODEL_MAP
        cached = get(cache.models, or_model_id, nothing)

        if cached === nothing || cached.endpoints === nothing
            @warn "Model not found in cache (skipping)" or_model_id
            continue
        end

        # Override all endpoints to point to cli_proxy_api
        for ep in cached.endpoints.endpoints
            ep.provider_name = provider_name
            ep.tag = "$(ep.tag)>$(provider_name)"  # encode override in tag
            ep.name = native_id
            ep.model_name = native_id
        end
    end
end

# ============ Example Usage ============

# Setup provider (required for both approaches)
# add_provider("cli_proxy_api", "http://localhost:8317/v1", "Bearer", "CLIPROXYAPI_API_KEY",
#     Dict{String,String}(), cli_proxy_model_transform, ChatCompletionSchema())

# For legacy override approach:
# override_endpoints_to_cli_proxy!()

# Example tool definition
READ_TOOL = [Dict(
    "type" => "function",
    "function" => Dict(
        "name" => "read_file",
        "description" => "Read the contents of a file at the given path",
        "parameters" => Dict(
            "type" => "object",
            "properties" => Dict(
                "path" => Dict("type" => "string", "description" => "The file path to read")
            ),
            "required" => ["path"]
        )
    )
)]

# With package approach (recommended):
# response = aigen("Hello", "cli_proxy_api:anthropic/claude-opus-4.5")

# With legacy override:
# response = aigen("Hello", "anthropic:anthropic/claude-opus-4.5")

response = aigen("Use the Read tool to read /tmp/example.txt file, but first welcome me.",
    "anthropic:anthropic/claude-sonnet-4.5";
    tools=READ_TOOL,
    streamcallback=HttpStreamCallback(; out=stdout, verbose=true))

println(response.content)
