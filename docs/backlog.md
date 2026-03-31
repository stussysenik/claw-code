# ClawCode Backlog

## Table of Contents

- [Product Direction](#product-direction)
- [Design Constraints](#design-constraints)
- [Active Epics](#active-epics)
- [Issue Map](#issue-map)
- [Operator Notes](#operator-notes)

## Product Direction

Build `claw_code` as an Elixir-first runtime with explicit session state, replayable tool execution, isolated Zig/native helpers, and adapter-based provider/runtime integrations.

The repo should stay small, teachable, and evidence-driven. OMX belongs in the operator layer, not the shipped runtime.

See also:

- `AGENTS.md` for engineering standards
- `docs/reference/architecture.md` for the canonical Elixir/Zig boundary
- `.omx/board.md` for execution tracking
- `docs/execution-plan.md` for phase sequencing
- `openspec/changes/reach-daily-driver/` for the remaining daily-driver roadmap
- `progress.md` for the UTC workflow ledger

## Design Constraints

- Keep the shipped runtime centered on Elixir plus isolated Zig/native helpers.
- Prefer explicit session and requirement persistence over lossy compaction.
- Delay heavyweight TUI work until the engine, provider loop, and session model are stable.
- Treat GLM and NVIDIA NIM as adapter modules behind one OpenAI-compatible boundary.
- Keep every execution path replayable from persisted session state, local tool receipts, and deterministic routing inputs.

## Active Epics

### 1. OTP Runtime Core

- Title: Build durable session orchestration on OTP
- Outcome: Persist session turns, route work through supervisors, and keep session replay deterministic.

### 2. Native Zig Lane

- Title: Harden the Zig scorer and native build pipeline
- Outcome: Keep the fast path outside the BEAM while adding fixture coverage, crash handling, and repeatable builds.

### 3. Multi-Runtime Adapters

- Title: Expand adapter coverage across Python, Lua, and Common Lisp
- Outcome: Provide stable runtime contracts for evaluation, environment capture, and transcripted subprocess execution.

### 4. UNIX and Tooling Surface

- Title: Add a disciplined shell and tool execution boundary
- Outcome: Make command execution inspectable, timeout-aware, and easy to replay.

### 5. Provider and GPU Research

- Title: Research provider plugins and WebGPU offload boundaries
- Outcome: Keep future LLM-provider and GPU work behind adapters rather than contaminating the core runtime.

### 6. Feedback-Driven Reliability

- Title: Eliminate known coding-assistant failure modes
- Outcome: Avoid plan drift, retain key requirements across long runs, and keep the terminal UX simpler than the current generation of brittle coding TUIs.

### 7. Persistent Control Plane

- Title: Add a local daemon for cross-process session control
- Outcome: Run `claw_code` behind a small Elixir control plane that can manage background sessions, status checks, cancellation, and future multi-client coordination without turning the runtime into a network service.
- Proposal: [docs/proposals/persistent-control-plane.md](./proposals/persistent-control-plane.md)
- Current state: initial daemon lifecycle and daemon-backed session control are implemented; remaining work is hardening and operator evidence.

## Issue Map

1. `#6` Build durable OTP session orchestration for `claw_code`
2. `#12` Add an immutable requirements ledger to prevent compaction loss and plan drift
3. `#11` Add OpenAI-compatible provider adapters for GLM and NVIDIA NIM
4. `#5` Add a disciplined shell adapter with execution receipts and timeouts
5. `#7` Harden the Zig native ranker build and crash-recovery path
6. `#8` Expand runtime adapters across Python, Lua, and Common Lisp
7. `#9` Research provider/plugin boundaries and WebGPU offload strategy
8. `#10` Evaluate oh-my-codex as a development workflow layer, not a product dependency
9. `#13` Add a persistent control-plane daemon for cross-process session control

## Operator Notes

- Use GitHub issues as the tracking source until a Linear connector is available.
- Update `progress.md` with every meaningful workflow milestone.
- Keep the mission set to the four canonical `.omx/missions/*.md` files and retire duplicate variants.
- Keep the daemon slice grounded in release-gated evidence: lifecycle tests, CLI smoke, and stale-daemon recovery.
