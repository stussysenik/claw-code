# OMX Team

## Table of Contents

- [Role Split](#role-split)
- [Handoff Rules](#handoff-rules)

## Role Split

### architect

- Owns `docs/execution-plan.md`, mission scope, issue decomposition, and phase sequencing.
- Decides when a change is architectural versus incremental.

### core

- Owns sessions, replay, routing, CLI behavior, and requirements-ledger work.
- Primary missions: Mission 01 and the reliability edge of Mission 04.

### native

- Owns Zig helpers, build flow, and fallback behavior.
- Primary mission: Mission 03 for the native fast path.

### adapters

- Owns Python, Lua, Common Lisp, and local tool subprocess boundaries.
- Shares Mission 03 with `native`.

### providers

- Owns GLM/NIM adapters, OpenAI-compatible provider behavior, and tool-calling loop work.
- Primary mission: Mission 02.

### qa

- Owns validation scripts, smoke commands, review gates, and release-readiness evidence.
- Maintains `scripts/qa.sh`, `scripts/validate-repo.sh`, and the release checklist.
- Primary mission: Mission 04.

## Handoff Rules

1. `architect` opens or updates the mission.
2. The lane owner runs the matching Ralph loop.
3. `qa` confirms tests, smoke commands, and evidence.
4. The issue is updated with what changed, what was verified, and what remains.
