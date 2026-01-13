#=
Mutation Injection Test
========================

This example demonstrates routing Anthropic API calls through CLIProxyAPI
before and after applying the mutation injection.

## Prerequisites

### 1. Install CLIProxyAPI
```bash
curl -fsSL https://raw.githubusercontent.com/brokechubb/cliproxyapi-installer/refs/heads/master/cliproxyapi-installer | bash
```

### 2. Login to providers (one-time setup)
```bash
cd ~/cliproxyapi

# Login commands (prints URL, use --no-browser to avoid auto-open):
./cli-proxy-api --claude-login --no-browser    # Claude/Anthropic
./cli-proxy-api --codex-login --no-browser     # OpenAI/Codex
./cli-proxy-api --login --no-browser           # Gemini/Google
./cli-proxy-api --qwen-login --no-browser      # Qwen
./cli-proxy-api --iflow-login --no-browser     # iFlow
```

### 3. Start the proxy server
```bash
# Manual:
cd ~/cliproxyapi && ./cli-proxy-api

# Or via systemd:
systemctl --user enable cliproxyapi.service
systemctl --user start cliproxyapi.service
systemctl --user status cliproxyapi.service
```

### 4. Set API key environment variable
The API key is stored in `~/cliproxyapi/config.yaml` under the `api-keys:` key.
Export the first key:
```bash
export CLIPROXYAPI_API_KEY="your-api-key-from-config.yaml"
```

Or add to your shell profile (~/.bashrc, ~/.zshrc, etc.):
```bash
echo 'export CLIPROXYAPI_API_KEY="your-api-key"' >> ~/.bashrc
```

## Troubleshooting

- **Model not found after mutate**: CLIProxyAPI not logged in for that provider.
  Run the appropriate login command above.
- **Connection refused**: Proxy server not running. Start it with `./cli-proxy-api`.
- **401 Unauthorized**: CLIPROXYAPI_API_KEY not set or incorrect.

## Default endpoint
CLIProxyAPI runs on `http://localhost:8317/v1` (OpenAI-compatible API).
=#

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
