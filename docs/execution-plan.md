# ClawCode Execution Plan

## Table of Contents

- [Objective](#objective)
- [Team Topology](#team-topology)
- [Phase Plan](#phase-plan)
- [Daemon Proposal](#daemon-proposal)
- [Architecture Reference](#architecture-reference)
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

### 5. Persistent Control Plane

- Scope: local daemon lifecycle, cross-process session control, background runs, multi-client coordination
- Primary issues: `#13` plus the runtime/core lane for shared session semantics
- Exit signal: `claw_code` can be started once and controlled from separate CLI invocations without losing session continuity or forcing a web server model

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

### Phase 5: Persistent Control Plane

- Add a local Elixir daemon that owns background session runs and exposes explicit `start`, `status`, `stop`, `chat`, `resume`, and `cancel` operations.
- Keep transport local-only and boring: no distributed Erlang, no HTTP API, no remote exposure by default.
- Persist daemon metadata and session ownership state under `.claw/` so client invocations can reconnect, inspect, and cancel work across processes.
- Introduce a clear client/server split: the CLI can act as a direct runtime client or as a daemon client, but the daemon remains a separate operator surface.
- Add resilient startup, stale-daemon detection, and crash recovery so a dead control plane fails closed instead of silently losing session state.
- Make future multi-client control an extension of the same daemon contract, not a separate subsystem.
- Initial slice status: local daemon lifecycle plus daemon-backed `chat` and `cancel-session` are implemented behind tests; next work is hardening the background path and widening replay/inspection semantics.

## Daemon Proposal

The working proposal is documented in [docs/proposals/persistent-control-plane.md](./proposals/persistent-control-plane.md). It should be treated as the canonical design note for the daemon slice, while this file keeps the repo-level phase ordering.

## Architecture Reference

The canonical repository shape is documented in [docs/reference/architecture.md](./reference/architecture.md). Use that document when deciding whether a new change belongs in Elixir, Zig, provider adapters, or the daemon control plane.

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
