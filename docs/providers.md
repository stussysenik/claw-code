# Provider Setup

## Table of Contents

- [Principles](#principles)
- [Generic Or Custom OpenAI-Compatible](#generic-or-custom-openai-compatible)
- [GLM Coding Plan](#glm-coding-plan)
- [Kimi K2.5](#kimi-k25)
- [NVIDIA NIM](#nvidia-nim)

## Principles

- Configure providers through environment variables or explicit CLI flags.
- Local runtime commands also autoload `.env.local` and `.env` when present.
- Do not rely on committed secret files.
- `claw_code` only needs one OpenAI-compatible contract: base URL, API key, and model.
- `./claw_code doctor` reports the active provider request URL, whether the provider is fully configured, and whether each field is coming from an env var, a default, or is still missing.
- `./scripts/qa.sh provider` is env-driven; use direct `./claw_code doctor` or `./claw_code chat` commands when you want to pass explicit CLI flags.

## Copy-Paste CLI Checks

Kimi:

```bash
./claw_code doctor --provider kimi --api-key "$KIMI_API_KEY"
./claw_code chat --provider kimi --api-key "$KIMI_API_KEY" "say hello and report the configured provider"
```

Custom OpenAI-compatible endpoint:

```bash
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
  "say hello and report the configured provider"
```

## Generic Or Custom OpenAI-Compatible

- Provider: `generic`
- Env vars:
- `CLAW_BASE_URL`
- `CLAW_MODEL`
- optional: `CLAW_API_KEY`
- Use this for self-hosted or custom OpenAI-compatible inference endpoints, including your own GLM-serving stack.
- If the endpoint does not require auth, omit `CLAW_API_KEY` entirely. `claw_code` will skip the `Authorization` header for `generic` when no API key is present.
- Smoke:

```bash
CLAW_PROVIDER=generic \
CLAW_BASE_URL="https://example.com/v1" \
CLAW_MODEL="gpt-4.1-mini" \
./scripts/qa.sh provider "say hello and report the configured provider"
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
- Smoke:

```bash
CLAW_PROVIDER=glm \
GLM_API_KEY="..." \
GLM_MODEL="GLM-4.7" \
./scripts/qa.sh provider "say hello and report the configured provider"
```

## Kimi K2.5

- Provider: `kimi`
- Default base URL: `https://api.moonshot.ai/v1`
- Env vars:
- `KIMI_API_KEY` or `MOONSHOT_API_KEY`
- `KIMI_MODEL` default: `kimi-k2.5`
- Optional overrides: `KIMI_BASE_URL`, `MOONSHOT_BASE_URL`
- Smoke:

```bash
CLAW_PROVIDER=kimi \
KIMI_API_KEY="..." \
KIMI_MODEL="kimi-k2.5" \
./scripts/qa.sh provider "say hello and report the configured provider"
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
```
