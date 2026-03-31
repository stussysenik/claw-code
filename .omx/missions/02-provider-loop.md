# Mission 02: Provider Loop

## Goal

Make the runtime useful against GLM and NVIDIA NIM today through one OpenAI-compatible adapter and a disciplined local tool loop.

## Linked Issues

- `#11` Add OpenAI-compatible provider adapters for GLM and NVIDIA NIM
- `#5` Add a disciplined shell adapter with execution receipts and timeouts

## Scope

- Provider config defaults
- Local function tools
- Tool-call persistence and failure receipts
- Missing-key and provider-error handling

## Exit Evidence

1. `mix test`
2. `./claw_code doctor`
3. `./scripts/qa.sh provider "say hello and report the configured provider"`
4. One provider failure path is persisted without crashing the runtime
