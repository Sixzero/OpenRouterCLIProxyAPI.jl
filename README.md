# OpenRouterCLIProxyAPI.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://sixzero.github.io/OpenRouterCLIProxyAPI.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://sixzero.github.io/OpenRouterCLIProxyAPI.jl/dev/)
[![Build Status](https://github.com/sixzero/OpenRouterCLIProxyAPI.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/sixzero/OpenRouterCLIProxyAPI.jl/actions/workflows/CI.yml?query=branch%3Amaster)

Unofficial OAuth session support for Claude, OpenAI, and Gemini models via [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI).

This package extends [OpenRouter.jl](https://github.com/sixzero/OpenRouter.jl) to route requests through CLIProxyAPI, a local proxy that provides API endpoints using OAuth authentication from your existing subscriptions.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/sixzero/OpenRouterCLIProxyAPI.jl")
```

## Prerequisites

1. Install and run [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)
2. Authenticate with your provider (Claude, OpenAI, Gemini, etc.)

## Usage

```julia
using OpenRouter
using OpenRouterCLIProxyAPI

# One-time setup (registers provider + injects endpoints)
setup_cli_proxy!()

response = aigen("Hello!", "cli_proxy_api:anthropic/claude-opus-4.5")
```

### Custom Configuration

```julia
setup_cli_proxy!(
    base_url = "http://localhost:8317/v1",
    api_key_env_var = "CLIPROXYAPI_API_KEY",
    provider_name = "cli_proxy_api",
    mutate = false  # true = overwrite existing endpoints
)
```

## Supported Models

**Anthropic:** claude-opus-4.5, claude-sonnet-4.5, claude-haiku-4.5, claude-opus-4.1, claude-opus-4, claude-sonnet-4, claude-3.7-sonnet, claude-3.5-haiku

**OpenAI:** gpt-5, gpt-5.1, gpt-5.2, gpt-5-codex, gpt-5.1-codex, gpt-5.1-codex-mini, gpt-5.1-codex-max

## Related

- [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)
- [OpenRouter.jl](https://github.com/sixzero/OpenRouter.jl)
