# ClawCode Execution Plan

## Table of Contents

- [Objective](#objective)
- [Team Topology](#team-topology)
- [Phase Plan](#phase-plan)
- [Git And Release Discipline](#git-and-release-discipline)
- [Evidence Required Per Slice](#evidence-required-per-slice)

## Objective

Turn `claw_code` into a learning repo and a durable coding runtime: small codebase, explicit boundaries, reproducible behavior, and enough operational scaffolding that multiple agents can work without creating chaos.

## Team Topology

### 1. Runtime Core

- Scope: sessions, routing, CLI, persistence, replay
- Primary issues: `#6`, `#12`
- Exit signal: session and requirement state survive long runs and reload cleanly

### 2. Provider Loop

- Scope: GLM/NIM adapters, tool-calling loop, provider errors
- Primary issues: `#11`, `#5`
- Exit signal: OpenAI-compatible flow works with local function tools and persists failures cleanly

### 3. Native Lane

- Scope: Zig scorer, build pipeline, BEAM fallback
- Primary issues: `#7`, `#8`
- Exit signal: native fast path is optional, observable, and safe to disable

### 4. Research And Release

- Scope: provider/plugin strategy, WebGPU boundary, OMX role in the repo, release documentation
- Primary issues: `#9`, `#10`
- Exit signal: research outcomes become docs or scoped tickets, not runtime sprawl

## Phase Plan

### Phase 0: Repo Operating System

- Commit the engineering standards into `AGENTS.md`.
- Commit the OMX mission files and board.
- Commit Ralph loops for core, native, provider, and release paths.
- Make sure local operators can run the loops without extra ceremony.

### Phase 1: Core Reliability

- Land durable OTP-style session orchestration and requirements ledger work.
- Add replay and persistence evidence around `.claw/sessions`.
- Remove brittle CLI behavior and ambiguous switches.

### Phase 2: Real Agent Loop

- Land GLM/NIM provider adapters through one OpenAI-compatible boundary.
- Keep local tools disciplined: list, read, Python, Lua, Lisp first.
- Add shell receipts before expanding shell capability.

### Phase 3: Native And Adapter Hardening

- Stabilize Zig build/rebuild paths.
- Add BEAM fallback proof when native ranking is unavailable or fails.
- Strengthen subprocess adapter tests and error receipts.

### Phase 4: UX And Research

- Keep CLI sharp and inspectable.
- Delay heavyweight TUI work until runtime and provider surfaces are stable.
- Treat OMX as the development workflow layer, not the shipped product dependency.

## Git And Release Discipline

- Use short-lived branches for each mission slice.
- Land one semantic commit per green mission slice.
- Use conventional commits so semantic-release can generate tags, changelogs, and GitHub Releases later.
- Record the exact evidence in `progress.md` when a slice lands.

## Evidence Required Per Slice

1. The issue or mission links are updated.
2. At least one automated test proves the new behavior.
3. At least one smoke command proves the operator surface.
4. The persistence or failure-mode story is documented if relevant.
