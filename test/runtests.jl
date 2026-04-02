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
end
