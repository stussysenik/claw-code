# Design

## Table of Contents

- [Purpose](#purpose)
- [System Shape](#system-shape)
- [Runtime Layers](#runtime-layers)
- [Session Contract](#session-contract)
- [Execution Modes](#execution-modes)
- [Provider Boundary](#provider-boundary)
- [Tool And Adapter Boundary](#tool-and-adapter-boundary)
- [Native Boundary](#native-boundary)
- [TUI And Thin Clients](#tui-and-thin-clients)
- [Operational Evidence](#operational-evidence)
- [Change Rules](#change-rules)

## Purpose

This file is the repo-level design contract for `claw_code`.

`VISION.md` defines the product intent. This file defines the architectural shape that should stay stable while the repo moves toward daily-driver status.

## System Shape

`claw_code` is an Elixir-first local coding runtime with:

- persisted session documents
- OTP-supervised session ownership
- an optional local daemon for cross-process control
- one OpenAI-compatible provider boundary
- explicit tool and adapter execution receipts
- a narrow optional Zig fast path

The system should stay centered on explicit state and boring recovery, not hidden background magic.

## Runtime Layers

### 1. CLI

Primary files:

- `lib/claw_code/cli.ex`
- `lib/claw_code/manifest.ex`

Responsibilities:

- parse operator commands and flags
- render human and JSON output
- keep local and daemon-backed paths explicit

### 2. Runtime And Sessions

Primary files:

- `lib/claw_code/runtime.ex`
- `lib/claw_code/session_server.ex`
- `lib/claw_code/session_store.ex`

Responsibilities:

- run the turn loop
- persist checkpoints and terminal state
- keep one active run per session owner
- preserve replayable session history

### 3. Local Control Plane

Primary file:

- `lib/claw_code/daemon.ex`

Responsibilities:

- keep cross-process session ownership stable
- expose local-only status, chat, resume, and cancel operations
- make stale or failed daemon state inspectable

### 4. Provider Layer

Primary file:

- `lib/claw_code/providers/openai_compatible.ex`

Responsibilities:

- normalize provider config
- keep GLM, Kimi, NIM, and generic endpoints behind one request shape
- make portability failures explicit instead of special-casing the whole runtime

### 5. Tools And External Adapters

Primary files:

- `lib/claw_code/tools/builtin.ex`
- `lib/claw_code/adapters/external.ex`

Responsibilities:

- gate local tool execution through policy
- capture receipts with output, status, duration, and failure details
- keep Python, Lua, and Common Lisp outside the BEAM core

### 6. Native Fast Path

Primary files:

- `lib/claw_code/native_ranker.ex`
- `native/token_ranker.zig`

Responsibilities:

- provide optional scoring acceleration
- fail clearly
- preserve a deterministic Elixir fallback

## Session Contract

The session document is the runtime truth that must remain inspectable and replayable.

Minimum expectations:

- one JSON document per session under the configured session root
- stable `id`, `created_at`, `updated_at`, and `saved_at`
- prompt, output, messages, tool receipts, and requirements ledger
- explicit `run_state` and `stop_reason`
- writes that favor local atomic replacement over in-place mutation
- corrupted or partial session files fail clearly for that session id instead of poisoning the whole session root

If session state becomes hard to inspect or recover by hand, the design has regressed.

## Execution Modes

There are two valid modes.

### Direct Runtime Mode

- one CLI invocation owns one BEAM lifecycle
- good for tests, simple runs, and local scripting

### Daemon Mode

- one local daemon owns session continuity across CLI invocations
- good for long-running work, monitoring, cancellation, and resume flows

The daemon is deliberately local-only. It is not a web API and not a distributed cluster.

## Provider Boundary

Providers must remain boring to the rest of the runtime.

Rules:

- provider configuration enters through flags or env
- provider identity and capability summaries should stay visible to the operator
- provider-specific quirks belong in the compatibility layer, not in session logic or the TUI
- generic OpenAI-compatible endpoints should degrade gracefully when they reject optional fields

## Tool And Adapter Boundary

Tool use must stay explicit enough to audit later.

Rules:

- shell and write capability must be explicitly enabled
- destructive or risky capability should be visible in policy and receipts
- adapter subprocess behavior should prove exit status, timeout, and output handling
- new host capabilities must come with tests and evidence

## Native Boundary

The Zig path is an optimization boundary, not a correctness boundary.

Rules:

- native behavior must be easy to disable
- failure must fall back clearly
- session logic, provider control flow, and operator semantics must not move into Zig
- only benchmarked, pure compute hotspots with a deterministic BEAM fallback belong at the Zig edge
- if disabling the native path changes correctness, continuity, or inspectability, the feature is in the wrong place

## TUI And Thin Clients

The TUI should remain a thin client over the runtime and daemon surfaces.

That means:

- use the CLI JSON surface and local daemon contract as the boundary
- keep session ownership, persistence, and provider logic in Elixir runtime modules
- improve the active operator loop without creating a second source of truth

## Operational Evidence

The repo already has an execution and evidence model. Use it.

- OpenSpec defines the daily-driver scope and remaining phases
- `.omx/board.md` defines the active lanes
- `scripts/qa.sh` and `scripts/ralph-*.sh` are the canonical validation loops
- `progress.md` records workflow evidence with UTC timestamps

If a design claim cannot be demonstrated through those surfaces, it is still only intent.

## Change Rules

When deciding where a new feature belongs:

- if it changes session continuity, cancellation, replay, routing, or operator semantics, put it in Elixir first
- if it is a pure compute optimization with a benchmarked hotspot and a clear fallback, it may live behind the Zig boundary
- if it needs another runtime, keep it as an adapter process rather than a core dependency
- if it expands the operator surface, document it in the README and the relevant reference docs

Deeper references:

- [VISION.md](./VISION.md)
- [docs/reference/architecture.md](./docs/reference/architecture.md)
- [docs/proposals/persistent-control-plane.md](./docs/proposals/persistent-control-plane.md)
- [docs/reference/tui.md](./docs/reference/tui.md)
- [openspec/changes/reach-daily-driver/design.md](./openspec/changes/reach-daily-driver/design.md)
