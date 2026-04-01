# Persistent Control Plane Proposal

## Table of Contents

- [Problem](#problem)
- [Proposal](#proposal)
- [Phase Plan](#phase-plan)
- [Non-Goals](#non-goals)
- [Evidence Bar](#evidence-bar)
- [Related Docs](#related-docs)

## Problem

`claw_code` already has replayable sessions and a supervised in-process session owner, but the current cancellation and long-running ownership model is still bounded by one BEAM instance. That is enough for single-process use, but it is not enough for the operator flow the repo is moving toward:

- start a run in one shell
- inspect or cancel it from another shell
- keep the session alive across shell exits
- preserve the same session file and receipt trail
- make the future multi-client story boring instead of architectural drift

## Proposal

Add a local Elixir daemon that becomes the persistent control plane for long-running sessions. The daemon should stay deliberately narrow:

- local-only transport
- explicit start/status/stop lifecycle
- daemon-backed chat/resume/cancel commands
- session ownership persisted under `.claw/`
- stale-daemon detection and restart-safe metadata

The daemon is a control plane, not a product rewrite. `claw_code` remains the runtime, Zig remains an isolated native boundary, and the daemon only owns cross-process coordination.

Initial implementation status:

- explicit `daemon start`, `daemon status`, and `daemon stop`
- daemon-backed `chat` and `cancel-session`
- direct module and CLI coverage for lifecycle and cross-process cancellation

Remaining work stays in hardening rather than architecture: richer replay/inspection semantics, background-loop evidence, and more stale-daemon recovery coverage.

Recent hardening status:

- daemon-backed sessions are now covered across full stop/start restart continuity
- daemon shutdown now fails closed when the process does not actually stop in time
- recovered sessions that were previously persisted as `run=running` are reconciled to `run_interrupted`

## Phase Plan

### Phase 0: Contract

- Define the daemon lifecycle and CLI surface before implementation details spread.
- Decide the on-disk metadata format for daemon identity, port, token, and startup state.
- Document the client/server split so direct-runtime and daemon-backed flows remain explicit.

### Phase 1: Local Server

- Implement a small Elixir daemon process that owns the session supervisor boundary.
- Expose `start`, `status`, `stop`, `chat`, `resume-session`, and `cancel-session` through a local client protocol.
- Persist daemon metadata and session ownership state so clients can reconnect safely.

### Phase 2: Cross-Process Session Control

- Move cancellation and run ownership checks behind the daemon boundary.
- Ensure a session can be inspected, resumed, and cancelled from separate CLI invocations.
- Treat stale or missing metadata as a clean `not_running` path.

### Phase 3: Hardening

- Add tests for daemon lifecycle, stale metadata, and cross-process session flow.
- Add explicit timeouts, connection failure handling, and safe shutdown behavior.
- Keep the direct in-process runtime path available for tests and simple scripts.

### Phase 4: Multi-Client Readiness

- Keep the daemon contract simple enough that multiple clients can share it later.
- Prefer additive protocol changes over hidden state.
- Avoid turning the daemon into a web service or distributed node mesh unless a future requirement justifies that complexity.

## Non-Goals

- No HTTP API.
- No distributed Erlang requirement.
- No remote exposure by default.
- No replacement for the runtime session model.
- No TUI rewrite as part of this slice.

## Evidence Bar

The daemon slice should not be considered complete until it has:

- documented lifecycle and usage
- automated coverage for lifecycle and failure paths
- a smoke path for cross-process chat or cancellation
- a clear story for stale daemon recovery

## Related Docs

- [docs/execution-plan.md](../execution-plan.md)
- [docs/backlog.md](../backlog.md)
- [README.md](../../README.md)
