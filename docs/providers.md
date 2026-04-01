# Provider Setup

## Table of Contents

- [Principles](#principles)
- [Local Env Pattern](#local-env-pattern)
- [Split Reasoning And Vision Backbone](#split-reasoning-and-vision-backbone)
- [Provider Matrix Workflow](#provider-matrix-workflow)
- [Live Provider Evidence](#live-provider-evidence)
- [Generic Or Custom OpenAI-Compatible](#generic-or-custom-openai-compatible)
- [GLM Coding Plan](#glm-coding-plan)
- [Kimi K2.5](#kimi-k25)
- [NVIDIA NIM](#nvidia-nim)

## Principles

- Configure providers through environment variables or explicit CLI flags.
- Local runtime commands also autoload `.env.local` and `.env` when present.
- Do not rely on committed secret files.
- `claw_code` only needs one OpenAI-compatible contract: base URL, API key, and model.
- Provider-specific providers now only inherit provider-specific env vars like `GLM_*`, `KIMI_*`, `MOONSHOT_*`, `NIM_*`, and `NVIDIA_*`; shared `CLAW_*` connection vars are reserved for the `generic` provider and explicit generic live-proof helpers.
- Tool exposure defaults to `auto`: repo-oriented prompts expose tools, plain chat prompts do not. Use `--tools` to force tool specs on, `--no-tools` to force chat-only mode, or `CLAW_TOOL_MODE=auto|on|off` for env-driven defaults.
- `chat` and `resume-session` accept repeated `--image PATH` flags; local image paths are validated before provider I/O, persisted in session state as replayable content parts, and only translated into OpenAI-style `image_url` payload parts at request time.
- `chat` and `resume-session` also accept an optional split vision backbone through `--vision-provider`, `--vision-model`, `--vision-base-url`, `--vision-api-key`, and `--vision-api-key-header`; when enabled, `claw_code` derives replayable `vision_context` first and keeps the primary reasoning request text-only.
- `./claw_code providers` is the matrix view: it shows the configured state, request URL, auth mode, input modalities, aliases, and missing fields for every supported provider in one pass.
- `./claw_code doctor` reports the active provider request URL, whether the provider is fully configured, which input modalities the provider boundary accepts, and whether each field is coming from an env var, a default, or is still missing.
- `./claw_code doctor` also reports provider portability hints at a glance: `auth_mode`, `tool_support`, `payload_modes`, `fallback_modes`, and supported aliases.
- `./claw_code probe` accepts repeated `--image PATH` flags and reports `request_modalities`, which is the fastest local preflight for a vision-capable model or endpoint.
- `./scripts/qa.sh provider` is env-driven; use direct `./claw_code doctor` or `./claw_code chat` commands when you want to pass explicit CLI flags.
- `./scripts/qa.sh provider-matrix` is the pre-RC matrix loop: it walks `generic`, `glm`, `kimi`, and `nim`, validates either the live path or the explicit missing-config path, and records the evidence under `.omx/logs/provider-matrix/`.
- `./scripts/qa.sh provider-live` is the strict live-success loop: every selected provider must pass `doctor -> probe -> chat`, and missing config is treated as a real failure instead of an accepted path.

## Local Env Pattern

Use the checked-in [`.env.local.example`](../.env.local.example) as the starting point.

Recommended workflow:

```bash
cp .env.local.example .env.local
```

Then uncomment exactly one provider block in `.env.local` and fill in only the keys you need for that provider.

Precedence is explicit:

1. existing shell environment wins
2. `.env.local` fills anything still missing
3. `.env` fills anything still missing after that

That means you can keep a stable local default in `.env.local` and still override it per shell with exported vars when you want to test another provider or model.

## Split Reasoning And Vision Backbone

Use this when your preferred reasoning model is not the same as your preferred vision model. The runtime keeps one persisted session, appends a replayable derived `vision_context` part to the image-bearing user turn, and sends text-only visual context to the primary reasoning provider for that turn.

Example: `GLM-5.1` reasoning with `kimi-k2.5` vision.

Env-driven setup:

```bash
export CLAW_PROVIDER=glm
export GLM_API_KEY="..."
export GLM_MODEL="GLM-5.1"
export CLAW_VISION_PROVIDER=kimi
export KIMI_API_KEY="..."
export CLAW_VISION_MODEL="kimi-k2.5"
./claw_code chat --image ./diagram.png "describe this screenshot and suggest the next fix"
```

Explicit CLI flags:

```bash
./claw_code chat \
  --provider glm \
  --api-key "$GLM_API_KEY" \
  --model "GLM-5.1" \
  --vision-provider kimi \
  --vision-api-key "$KIMI_API_KEY" \
  --vision-model "kimi-k2.5" \
  --image ./diagram.png \
  "describe this screenshot and suggest the next fix"
```

Same-provider split is also supported. If the primary connection details already point at the right backend, you can often swap only `CLAW_VISION_MODEL` or `--vision-model`, and the vision lane will reuse the primary provider's base URL and auth details.

## Provider Matrix Workflow

Use the fast local matrix first:

```bash
./claw_code providers
./claw_code providers --json
```

Then run the QA lane:

```bash
./scripts/qa.sh provider-matrix
```

If a provider is configured, the matrix lane will run `doctor -> probe -> chat`. If a provider is not configured, it validates the explicit missing-config path instead of treating that as an opaque failure.

## Live Provider Evidence

Use the live lane when you want current proof instead of a mixed live-or-missing-config matrix:

```bash
./scripts/qa.sh provider-live
```

By default it checks `glm`, `nim`, and `generic`.

Select a narrower set:

```bash
CLAW_PROVIDER_LIVE=glm,generic \
./scripts/qa.sh provider-live
```

The generic leg needs explicit generic endpoint details in shell env through `CLAW_GENERIC_LIVE_*` or the generic `CLAW_*` fallbacks:

```bash
set -a
source .env.local
set +a

CLAW_PROVIDER_LIVE=generic \
CLAW_GENERIC_LIVE_BASE_URL="https://open.bigmodel.cn/api/coding/paas/v4" \
CLAW_GENERIC_LIVE_API_KEY="$GLM_API_KEY" \
CLAW_GENERIC_LIVE_MODEL="GLM-4.7" \
./scripts/qa.sh provider-live
```

That is the recommended path when you want to prove one real generic OpenAI-compatible endpoint without changing your default provider block.

## Copy-Paste CLI Checks

Kimi:

```bash
./claw_code providers
./claw_code probe --provider kimi --api-key "$KIMI_API_KEY"
./claw_code doctor --provider kimi --api-key "$KIMI_API_KEY"
./claw_code chat --provider kimi --api-key "$KIMI_API_KEY" "say hello and report the configured provider"
```

Custom OpenAI-compatible endpoint:

```bash
./claw_code providers
./claw_code probe \
  --provider generic \
  --base-url "https://example.com/v1" \
  --api-key "$CLAW_API_KEY" \
  --api-key-header "authorization" \
  --model "GLM-4.7" \
  --image ./diagram.png \
  "describe this screenshot"

./claw_code doctor \
  --provider generic \
  --base-url "https://example.com/v1" \
  --api-key "$CLAW_API_KEY" \
  --model "GLM-4.7"

./claw_code chat \
  --provider generic \
  --base-url "https://example.com/v1" \
  --api-key "$CLAW_API_KEY" \
  --model "GLM-4.7" \
  --image ./diagram.png \
  --no-tools \
  "describe this screenshot and report the configured provider"
```

Split reasoning plus vision backbone:

```bash
./claw_code chat \
  --provider glm \
  --api-key "$GLM_API_KEY" \
  --model "GLM-5.1" \
  --vision-provider kimi \
  --vision-api-key "$KIMI_API_KEY" \
  --vision-model "kimi-k2.5" \
  --image ./diagram.png \
  --no-tools \
  "inspect this screenshot and explain the visible failure"
```

## Generic Or Custom OpenAI-Compatible

- Provider: `generic`
- Env vars:
- `CLAW_BASE_URL`
- `CLAW_MODEL`
- optional: `CLAW_API_KEY`
- Use this for self-hosted or custom OpenAI-compatible inference endpoints, including your own GLM-serving stack.
- If the endpoint does not require auth, omit `CLAW_API_KEY` entirely. `claw_code` will skip the `Authorization` header for `generic` when no API key is present.
- If the endpoint expects a different auth header, pass `--api-key-header api-key` or export `CLAW_API_KEY_HEADER=api-key`.
- `./claw_code probe` is the recommended first check before a longer session or TUI run.
- `probe` reports `request_modalities`, so a multimodal preflight is explicit instead of inferred from the command line.
- When a generic endpoint rejects extra OpenAI-style request fields, `claw_code` now retries once with a minimal payload containing only `model` and `messages`. `probe` exposes the final `request_mode` so the operator can see whether the endpoint accepted the standard or minimal shape.
- As of 2026-04-01, the repo now has live generic-provider evidence against `https://open.bigmodel.cn/api/coding/paas/v4` with model `GLM-4.7`, which means the generic boundary is proven on one real OpenAI-compatible endpoint instead of only local stubs or missing-config paths.
- Smoke:

```bash
CLAW_PROVIDER=generic \
CLAW_BASE_URL="https://example.com/v1" \
CLAW_MODEL="gpt-4.1-mini" \
./scripts/qa.sh provider "say hello and report the configured provider"

CLAW_PROVIDER_MATRIX=generic \
./scripts/qa.sh provider-matrix

set -a
source .env.local
set +a

CLAW_PROVIDER_LIVE=generic \
CLAW_GENERIC_LIVE_BASE_URL="https://open.bigmodel.cn/api/coding/paas/v4" \
CLAW_GENERIC_LIVE_API_KEY="$GLM_API_KEY" \
CLAW_GENERIC_LIVE_MODEL="GLM-4.7" \
./scripts/qa.sh provider-live
```

Authenticated generic endpoint:

```bash
CLAW_PROVIDER=generic \
CLAW_BASE_URL="https://example.com/v1" \
CLAW_API_KEY="..." \
CLAW_MODEL="gpt-4.1-mini" \
./scripts/qa.sh provider "say hello and report the configured provider"
```

## GLM Coding Plan

- Provider: `glm`
- Default base URL: `https://open.bigmodel.cn/api/coding/paas/v4`
- Env vars:
- `GLM_API_KEY` or `BIGMODEL_API_KEY`
- `GLM_MODEL` default: `GLM-4.7`
- Optional overrides: `GLM_BASE_URL`, `BIGMODEL_BASE_URL`
- As of 2026-04-01, the live multimodal path proven in this repo is `GLM-4.6V` on the coding endpoint. `GLM-4.5V` also passed `probe` with local image input, while `GLM-4.7` returned a 400 on image input and `GLM-5` returned a 429 plan-access error in this environment.
- As of 2026-04-01, BigModel publishes a dedicated `GLM-5.1` coding-plan path, and that makes `GLM-5.1` the current preferred reasoning-side target when you want a stronger reasoning model plus a separate vision-capable backbone.
- As of 2026-04-01, the split path `GLM-5.1` reasoning plus `GLM-4.6V` vision also completed successfully through both `chat` and the TUI in this repo.
- As of 2026-04-01, BigModel's official model overview also lists `GLM-5V-Turbo` as the current multimodal coding model. In this repo, `GLM-4.6V` is still the vision-side path with live smoke evidence, while `GLM-5V-Turbo` is now a documented target for the split-backbone path.
- Smoke:

```bash
CLAW_PROVIDER=glm \
GLM_API_KEY="..." \
GLM_MODEL="GLM-4.7" \
./scripts/qa.sh provider "say hello and report the configured provider"

./claw_code probe --provider glm --model GLM-4.6V --image ./diagram.png
./claw_code chat --provider glm --model GLM-4.6V --no-tools --image ./diagram.png "briefly describe this image"
./claw_code chat --provider glm --model GLM-5.1 --vision-provider glm --vision-model GLM-4.6V --no-tools --image ./diagram.png "inspect this screenshot"

CLAW_PROVIDER_MATRIX=glm \
./scripts/qa.sh provider-matrix
```

## Kimi K2.5

- Provider: `kimi`
- Default base URL: `https://api.moonshot.ai/v1`
- Env vars:
- `KIMI_API_KEY` or `MOONSHOT_API_KEY`
- `KIMI_MODEL` default: `kimi-k2.5`
- Optional overrides: `KIMI_BASE_URL`, `MOONSHOT_BASE_URL`
- As of 2026-04-01, Moonshot's official platform and docs describe `kimi-k2.5` as a multimodal model with visual and text input plus default-on thinking, so it is the preferred Kimi-side choice for a split vision backbone in `claw_code`.
- Smoke:

```bash
CLAW_PROVIDER=kimi \
KIMI_API_KEY="..." \
KIMI_MODEL="kimi-k2.5" \
./scripts/qa.sh provider "say hello and report the configured provider"

CLAW_PROVIDER_MATRIX=kimi \
./scripts/qa.sh provider-matrix
```

Moonshot also publishes an Anthropic-compatible endpoint for upstream Claude Code itself, but `claw_code` uses the OpenAI-compatible Kimi endpoint above.

## NVIDIA NIM

- Provider: `nim`
- Default base URL: `https://integrate.api.nvidia.com/v1`
- Env vars:
- `NIM_API_KEY` or `NVIDIA_API_KEY`
- `NIM_MODEL` default: `meta/llama-3.1-8b-instruct`
- Optional overrides: `NIM_BASE_URL`, `NVIDIA_BASE_URL`
- Smoke:

```bash
CLAW_PROVIDER=nim \
NIM_API_KEY="..." \
NIM_MODEL="meta/llama-3.1-8b-instruct" \
./scripts/qa.sh provider "say hello and report the configured provider"

CLAW_PROVIDER_MATRIX=nim \
./scripts/qa.sh provider-matrix
```
