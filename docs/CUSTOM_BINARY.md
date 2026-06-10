# Building and deploying a custom CLIProxyAPI binary

When a new model (e.g. `claude-opus-4.7`) is released before the upstream
[`router-for-me/CLIProxyAPI`](https://github.com/router-for-me/CLIProxyAPI) ships it,
you can build your own binary with the model added.

## Where the model list lives

CLIProxyAPI resolves its model catalog in this order:

1. **Remote** (wins on startup):
   `https://raw.githubusercontent.com/router-for-me/models/refs/heads/main/models.json`
   and `https://models.router-for.me/models.json`.
   URLs are hard-coded in `internal/registry/model_updater.go` (`modelsURLs`).
2. **Embedded fallback**: `internal/registry/models/models.json`
   (embedded into the binary via `//go:embed`).

Because the remote list overrides the embedded one, **adding a model to the embedded
JSON alone is not enough** — you must either:

- Get the model merged into [`router-for-me/models`](https://github.com/router-for-me/models), **or**
- Point `modelsURLs` at your own fork.

## Deploy location

On our dev box the binary lives at:

```
~/cliproxyapi/cli-proxy-api
```

and is run via the user systemd unit `cliproxyapi.service`
(`~/.config/systemd/user/cliproxyapi.service`), listening on port `8317`
(see `~/cliproxyapi/config.yaml`).

## Procedure for adding a new model

### 1. Fork + update `router-for-me/models`

```bash
cd ~/repo/awesome
git clone https://github.com/router-for-me/models.git        # if not already cloned
cd models
gh repo fork --remote=true   # creates Sixzero/models, sets origin to the fork
git checkout -b add-<model-id>
```

Add the new entry to `models.json` (mirror the closest existing model, e.g. copy the
`claude-opus-4-6` block and adjust `id`, `display_name`, `created`):

```json
{
  "id": "claude-opus-4-7",
  "object": "model",
  "created": 1776643200,
  "owned_by": "anthropic",
  "type": "claude",
  "display_name": "Claude 4.7 Opus",
  "description": "Premium model combining maximum intelligence with practical performance",
  "context_length": 1000000,
  "max_completion_tokens": 128000,
  "thinking": {
    "min": 1024, "max": 128000, "zero_allowed": true,
    "levels": ["low", "medium", "high", "max"]
  }
}
```

Then:

```bash
git commit -am "Add <model-id>"
git push origin add-<model-id>
gh pr create --repo router-for-me/models --title "Add <model-id>" \
  --body "Mirrors the previous entry." --head Sixzero:add-<model-id>
```

Once the PR is merged, CLIProxyAPI will pick the new model up on its next refresh
(every 3 hours) or on restart — no rebuild needed.

### 2. (Until the PR merges) Build a custom binary pointing at your fork

```bash
cd ~/repo/awesome/CLIProxyAPI
git pull
```

Edit `internal/registry/model_updater.go` and prepend your fork URL to `modelsURLs`:

```go
var modelsURLs = []string{
    "https://raw.githubusercontent.com/Sixzero/models/refs/heads/add-<model-id>/models.json",
    "https://raw.githubusercontent.com/router-for-me/models/refs/heads/main/models.json",
    "https://models.router-for.me/models.json",
}
```

Optional: also add the model to the embedded fallback
(`internal/registry/models/models.json`) so offline startups work.

Build:

```bash
go build -o ~/cliproxyapi/cli-proxy-api-new ./cmd/server/
```

### 3. Swap and restart

```bash
# Back up the current binary
cp ~/cliproxyapi/cli-proxy-api ~/cliproxyapi/cli-proxy-api.bak

# Install the new one
mv ~/cliproxyapi/cli-proxy-api-new ~/cliproxyapi/cli-proxy-api

# Restart the service
systemctl --user restart cliproxyapi.service
sleep 3
systemctl --user status cliproxyapi.service --no-pager
```

### 4. Verify the model is listed

```bash
curl -s http://localhost:8317/v1/models \
  -H "Authorization: Bearer $CLIPROXYAPI_API_KEY" \
  | python3 -c "import sys,json; [print(m['id']) for m in json.load(sys.stdin).get('data',[])]" \
  | grep <model-id>
```

Startup log should contain:

```
model_updater.go:134 startup model refresh completed from https://raw.githubusercontent.com/Sixzero/models/...
```

### 5. Add the OpenRouter model mapping

In `OpenRouterCLIProxyAPI.jl/src/OpenRouterCLIProxyAPI.jl`, add the mapping so the
package can translate `anthropic/<model>` (OpenRouter-style) to the proxy's
native ID:

```julia
const MODEL_MAP_ANTHROPIC = Dict{String,String}(
    ...
    "claude-opus-4-7" => "anthropic/claude-opus-4.7",  # LATEST Anthropic model - UPDATE ON NEW RELEASE
    ...
)
```

### 6. Revert the URL override once upstream merges

After `router-for-me/models` merges your PR, revert the `modelsURLs` change in
`model_updater.go` and rebuild so we're back on the upstream feed.

## Cross-repo checklist (all places to touch on a new release)

Steps 1–6 above make the proxy serve the model. The places below make it
actually usable/visible everywhere else. Search each repo for
`UPDATE ON NEW RELEASE` — every such marker is a spot to revisit.

| # | Repo / file | What to change |
|---|---|---|
| 1 | `awesome/CLIProxyAPI` `internal/registry/models/models.json` | Add the model block (id, display_name, created, thinking levels), then rebuild + restart (steps 2–4). |
| 2 | `OpenRouterCLIProxyAPI.jl` `src/OpenRouterCLIProxyAPI.jl` → `MODEL_MAP_ANTHROPIC` / `MODEL_MAP_OPENAI` / `MODEL_MAP_GEMINI` | Add `"<native-id>" => "<provider>/<or-id>"`. Without this you get `502: unknown provider for model …`. Move the `# LATEST … UPDATE ON NEW RELEASE` comment to the new flagship. |
| 3 | `OpenRouter.jl` `src/storage.jl` → `MODEL_ALIASES` | If it's the new provider flagship, repoint the short alias (`"claude"`, `"gpt5"`, …). |
| 4 | `OpenRouter.jl` `scripts/export_models_json.jl` | Re-run it (`julia --project=. scripts/export_models_json.jl`) to refresh `frontend/src/assets/models_data.json`. The OpenRouter list must already carry the model. |
| 5 | `todoforai/packages` `shared-fbe/src/thinkingLevels.ts` → `THINKING_LEVELS_BY_MODEL` | Add `'<normalized-id>': [...levels]` (normalized = lowercase, dots→dashes, last path segment). Mirror the registry's `thinking.levels`. Without this the UI shows no thinking badges. |
| 6 | `todoforai/frontend` `src/constants/recommendedModels.ts` → `RECOMMENDED_MODELS` | Add the model if it should appear in the recommended list (place by tier). |

Notes:
- Empty-endpoint models (e.g. OpenRouter `~…-latest` aliases) are dropped by the
  export script and won't ship to the frontend — use the concrete pinned id.
- `MODEL_MAP` keys are the proxy's **native** ids (`claude-fable-5`); values are
  **OpenRouter-style** ids (`anthropic/claude-fable-5`).

## Rollback

If something goes wrong:

```bash
mv ~/cliproxyapi/cli-proxy-api.bak ~/cliproxyapi/cli-proxy-api
systemctl --user restart cliproxyapi.service
```

## Handing this off to an operator

Give them:

1. This document.
2. The built binary (`~/cliproxyapi/cli-proxy-api-new`) — or build instructions above.
3. The deploy target: `~/cliproxyapi/cli-proxy-api` on the server.
4. The restart command: `systemctl --user restart cliproxyapi.service`.
5. The verify command from step 4.
