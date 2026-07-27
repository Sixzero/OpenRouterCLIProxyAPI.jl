using OpenRouterCLIProxyAPI
using Test
using Aqua
using OpenRouter
using OpenRouter: AnthropicSchema, ChatCompletionSchema, build_payload, get_provider_info, set_provider!

function restore_provider!(name::String, info)
    set_provider!(
        name,
        info.base_url,
        info.auth_header_format,
        info.api_key_env_var,
        copy(info.default_headers),
        info.model_name_transform,
        info.schema,
        info.notes,
    )
end

@testset "OpenRouterCLIProxyAPI.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        # Aqua.test_all(OpenRouterCLIProxyAPI)
    end

    @testset "mutate keeps Anthropic native request shape for caching" begin
        original = Dict(name => get_provider_info(name) for name in ("anthropic", "openai", "google-ai-studio"))

        try
            setup_cli_proxy!(; mutate=true, base_url="http://localhost:8317/v1")

            anthropic = get_provider_info("anthropic")
            openai = get_provider_info("openai")

            @test anthropic.schema isa AnthropicSchema
            @test anthropic.base_url == "http://localhost:8317"
            @test openai.schema isa ChatCompletionSchema
            @test openai.base_url == "http://localhost:8317/v1"
            @test build_payload(anthropic.schema, "hello", "claude-3-5-haiku-20241022", nothing, false; cache=:last)["messages"][1]["content"][1]["cache_control"] == Dict("type" => "ephemeral")
        finally
            for (name, info) in original
                set_provider!(name, info.base_url, info.auth_header_format, info.api_key_env_var,
                    copy(info.default_headers), info.model_name_transform, info.schema, info.notes)
            end
        end
    end

    @testset "transforms live GPT-5.6 proxy models to native names" begin
        @test cli_proxy_model_transform("openai/gpt-5.6-sol") == "gpt-5.6-sol"
        @test cli_proxy_model_transform("openai/gpt-5.6-terra") == "gpt-5.6-terra"
    end

    @testset "derives OpenRouter slugs from native model IDs" begin
        # Anthropic drops the release date and dots the version.
        @test MODEL_MAP["claude-opus-4-5-20251101"] == "anthropic/claude-opus-4.5"
        @test MODEL_MAP["claude-3-5-haiku-20241022"] == "anthropic/claude-3.5-haiku"
        # No date, no version pair: passed through under the vendor prefix.
        @test MODEL_MAP["claude-opus-5"] == "anthropic/claude-opus-5"
        @test MODEL_MAP["gpt-5.4-mini"] == "openai/gpt-5.4-mini"
        @test MODEL_MAP["gemini-2.5-pro"] == "google/gemini-2.5-pro"
    end

    @testset "reverse map resolves shared slugs to the canonical native ID" begin
        # The reasoning-effort variants map onto one slug, which carries no hint of the
        # effort — so the slug has to resolve back to the plain model, not to -low/-high.
        @test cli_proxy_model_transform("google/gemini-3-pro-preview") == "gemini-3-pro-preview"
        @test cli_proxy_model_transform("google/gemini-3.1-pro-preview") == "gemini-3.1-pro-preview"
        # An alias is the only native ID for its slug, so it stays reachable.
        @test cli_proxy_model_transform("google/gemini-3.1-flash-image-preview") == "gemini-3.1-flash-image"
        @test cli_proxy_model_transform("anthropic/claude-opus-5") == "claude-opus-5"
        # Unknown models pass through untouched for the OpenRouter fallback.
        @test cli_proxy_model_transform("moonshotai/kimi-k2") == "moonshotai/kimi-k2"
    end

    @testset "every mapping round-trips" begin
        @test all(haskey(MODEL_MAP_REVERSE, slug) for slug in values(MODEL_MAP))
        @test all(haskey(MODEL_MAP, native) for native in values(MODEL_MAP_REVERSE))
    end

    @testset "mutate routes xAI/Grok through the proxy with native model names" begin
        original = Dict(name => get_provider_info(name) for name in ("anthropic", "openai", "google-ai-studio", "xai"))

        try
            setup_cli_proxy!(; mutate=true, base_url="http://localhost:8317/v1")

            xai = get_provider_info("xai")
            # xai must now hit the local proxy, not api.x.ai (region-locked, no creds).
            @test xai.base_url == "http://localhost:8317/v1"
            @test xai.schema isa ChatCompletionSchema
            # The `x-ai/` prefix must be stripped to the proxy's native model name.
            @test xai.model_name_transform("x-ai/grok-4.5") == "grok-4.5"
            @test xai.model_name_transform("x-ai/grok-build-0.1") == "grok-build-0.1"
        finally
            for (name, info) in original
                set_provider!(name, info.base_url, info.auth_header_format, info.api_key_env_var,
                    copy(info.default_headers), info.model_name_transform, info.schema, info.notes)
            end
        end
    end
end
