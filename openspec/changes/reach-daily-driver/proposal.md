# Proposal: Reach Daily-Driver Status

## Table of Contents

- [Why](#why)
- [Current State](#current-state)
- [Target State](#target-state)
- [Phase Overview](#phase-overview)
- [Non-Goals](#non-goals)
- [Success Criteria](#success-criteria)

## Why

`claw_code` is already a working Elixir-first runtime with a local daemon, provider adapters, a minimal TUI, replayable sessions, and an optional Zig fast path. What is still missing is a single canonical plan that answers one practical question:

What work is left before a serious operator can use this instead of the current generation of coding assistants every day?

This change set creates that plan.

## Current State

The repo already has:

- daemon-backed session control
- GLM, Kimi, NVIDIA NIM, and generic OpenAI-compatible provider support
- replayable receipts and explicit session persistence
- a minimal TUI with search, filtering, watch/follow, and targeted cancel
- semantic-release, Ralph loops, and OMX execution docs

The main remaining gap is not "can it run?" It is "can it be trusted as a daily-driver under real repo work, provider variation, tool usage, and long-running operator sessions?"

## Target State

Daily-driver status means:

- one operator can use `claw_code` for daily repo inspection and guided edits
- provider switching is boring and predictable
- session continuity survives long runs and shell boundaries
- tool behavior is explicit, inspectable, and replayable
- the TUI is good enough for repeated daily use
- release gates prove the system rather than hand-waving about it

## Phase Overview

### Phase 0: Freeze The Definition

- Land this OpenSpec change set.
- Make the daily-driver bar explicit.
- Map all remaining work to Ralph loops and agent lanes.

### Phase 1: Workflow Parity And Session Durability

- Audit the original `claw-code` workflows worth preserving.
- Finish the session durability gaps: long-run checkpoints, richer recovery, clearer busy/cancel/resume semantics.
- Make session inspection and replay boring under failure.

### Phase 2: Provider Portability

- Finish live-provider confidence across GLM, Kimi, NIM, and generic endpoints.
- Harden compatibility behavior for weird OpenAI-compatible backends.
- Make provider state obvious inside the CLI and TUI.

### Phase 3: Tool And Adapter Reliability

- Finish the shell/write safety story.
- Harden Python, Lua, and Common Lisp adapter receipts and failure behavior.
- Keep Zig optional, measurable, and easy to disable.

### Phase 4: TUI Daily-Driver UX

- Tighten the active-work loop: monitor, open, resume, cancel, and inspect without ceremony.
- Add just enough operator ergonomics to use the TUI for hours without friction.
- Avoid turning the UI into a second architecture.

### Phase 5: Long-Run Operations

- Prove daemon stability across stale state, provider failure, repeated resume/cancel cycles, and multi-session monitoring.
- Add better operator health surfaces and recovery paths.

### Phase 6: Release Confidence

- Build a live-provider and operator smoke matrix.
- Define the release candidate bar.
- Keep the repo teachable while increasing confidence.

### Phase 7: Post-RC Research Track

- Plugin boundaries
- deeper transport or streaming if it earns complexity
- benchmark-guided Zig or GPU work
- provider-specific power features

These are deliberately not blockers for daily-driver status.

## Non-Goals

- Rebuilding the whole product around Zig
- Turning OMX into a shipped dependency
- Adding speculative WebGPU or streaming work before the operator loop is solid
- Chasing perfect feature parity with every other coding assistant

## Success Criteria

This change is successful when:

1. the repo has one canonical daily-driver roadmap
2. each remaining slice is assigned to a lane and Ralph loop
3. the acceptance bar for "daily-driver ready" is explicit enough to validate
4. future parallel agent work can execute against this plan without planning drift
