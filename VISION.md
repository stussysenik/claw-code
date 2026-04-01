# Vision

## Table of Contents

- [Why This Exists](#why-this-exists)
- [Product Thesis](#product-thesis)
- [Daily-Driver Bar](#daily-driver-bar)
- [Principles](#principles)
- [Non-Goals](#non-goals)
- [Canonical References](#canonical-references)

## Why This Exists

Current coding assistants are often fast enough to impress and unreliable enough to waste time. They hide session state, blur tool behavior, make recovery feel lucky, and turn provider changes into operator friction.

`claw_code` exists to take the opposite approach:

- keep state explicit
- keep execution replayable
- keep failures local and inspectable
- keep the architecture small enough to teach and maintain

This file answers why the repo exists. `DESIGN.md` answers how it is built.

## Product Thesis

`claw_code` should become a serious local coding runtime that an operator can use every day without accepting mystery state as the price of power.

The core thesis is simple:

- Elixir should own orchestration, supervision, session continuity, and control flow.
- Providers should feel boring behind one OpenAI-compatible boundary.
- Tools should be explicit, gated, and evidenced with receipts.
- Native acceleration should stay optional and narrow.
- The terminal UI should be a client over the runtime, not a second architecture.

## Daily-Driver Bar

Call this repo a daily driver only when all of these feel true in normal use:

- a real repo session can survive shell exits, daemon restarts, cancels, and resumes without ambiguity
- provider switching between supported backends does not require code edits or tribal knowledge
- tool execution is visible enough to trust and constrained enough to recover from
- the TUI covers the normal inspect, continue, monitor, and intervene loop
- release evidence proves reliability instead of relying on optimistic demos

The goal is not feature maximalism. The goal is dependable daily use.

## Principles

### 1. Elixir Is The Control Plane

Anything that changes session continuity, replay, supervision, cancellation, routing, or operator semantics belongs in Elixir first.

### 2. Replay Beats Vibes

Session state, messages, tool receipts, run status, and requirements should remain explicit enough to reload, inspect, and reason about later.

### 3. Thin Boundaries Matter

Zig stays behind an executable boundary. Python, Lua, and Common Lisp stay adapter processes. Provider variation stays behind one compatible API surface.

### 4. Local-First Operations

The daemon is local-only. The runtime should be usable without inventing a service architecture before it is earned.

### 5. Evidence Before Expansion

New capability only counts when the repo can prove it with tests, smokes, Ralph loops, and a progress entry.

## Non-Goals

The project is not trying to become:

- a remote multi-tenant service
- a mixed-language runtime with no architectural center
- a plugin marketplace before the core operator loop is stable
- a Zig-first rewrite of session and tool logic
- a research sandbox that blocks daily-driver reliability work

## Canonical References

- [DESIGN.md](./DESIGN.md)
- [ROADMAP.md](./ROADMAP.md)
- [README.md](./README.md)
- [docs/reference/architecture.md](./docs/reference/architecture.md)
- [docs/reference/original-workflow-parity.md](./docs/reference/original-workflow-parity.md)
- [openspec/changes/reach-daily-driver/proposal.md](./openspec/changes/reach-daily-driver/proposal.md)
- [openspec/changes/reach-daily-driver/design.md](./openspec/changes/reach-daily-driver/design.md)
- [openspec/changes/reach-daily-driver/tasks.md](./openspec/changes/reach-daily-driver/tasks.md)
- [progress.md](./progress.md)
