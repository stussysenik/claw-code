# Mission 01: Runtime Core

## Goal

Strengthen the Elixir control plane so sessions, routing, replay, and long-run requirements are durable and inspectable.

## Linked Issues

- `#6` Build durable OTP session orchestration for `claw_code`
- `#12` Add an immutable requirements ledger to prevent compaction loss and plan drift

## Scope

- Session persistence and replay
- Requirements ledger design
- CLI/operator visibility into persisted state
- Tests for missing-config, recovery, and replay behavior

## Exit Evidence

1. `mix test`
2. `./claw_code summary`
3. `./claw_code symphony --native "review MCP tool"`
4. One saved session can be loaded and inspected after the change
