using OpenRouter
using OpenRouterCLIProxyAPI

println("=" ^ 60)
println("TEST 1: BEFORE MUTATE INJECT")
println("anthropic:anthropic/claude-sonnet-4.5 -> direct Anthropic API")
println("=" ^ 60)

response1 = aigen("Say 'Hello from before mutate' in exactly those words.",
    "anthropic:anthropic/claude-sonnet-4.5";
    streamcallback=HttpStreamCallback(; out=stdout, verbose=true))

println("\n\nResponse: ", response1.content)

println("\n" * "=" ^ 60)
println("APPLYING MUTATE INJECT...")
println("=" ^ 60)

setup_cli_proxy!(; mutate=true)

println("\n" * "=" ^ 60)
println("TEST 2: AFTER MUTATE INJECT (anthropic: prefix)")
println("anthropic:anthropic/claude-sonnet-4.5 -> now routes to cli_proxy_api")
println("=" ^ 60)

response2 = aigen("Say 'Hello from after mutate' in exactly those words.",
    "anthropic:anthropic/claude-sonnet-4.5";
    streamcallback=HttpStreamCallback(; out=stdout, verbose=true))

println("\n\nResponse: ", response2.content)
