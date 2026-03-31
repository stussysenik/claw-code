# Provider Setup

## Table of Contents

- [Principles](#principles)
- [Generic OpenAI-Compatible](#generic-openai-compatible)
- [GLM Coding Plan](#glm-coding-plan)
- [NVIDIA NIM](#nvidia-nim)

## Principles

- Configure providers through environment variables or explicit CLI flags.
- Do not rely on committed secret files.
- `claw_code` only needs one OpenAI-compatible contract: base URL, API key, and model.

## Generic OpenAI-Compatible

- Provider: `generic`
- Env vars:
- `CLAW_BASE_URL`
- `CLAW_API_KEY`
- `CLAW_MODEL`
- Smoke:

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
