# Architecture Reference

## Table of Contents

- [Positioning](#positioning)
- [Core Rule](#core-rule)
- [Runtime Layers](#runtime-layers)
- [Control Plane](#control-plane)
- [Native Boundary](#native-boundary)
- [Provider Boundary](#provider-boundary)
- [Operator Surface](#operator-surface)
- [What To Extend Next](#what-to-extend-next)

## Positioning

`claw_code` is an Elixir-first coding runtime with a small Zig fast path.

The right mental model is not "a Zig app with Elixir around it" and not "a generic polyglot shell." The right model is:

- Elixir owns orchestration, persistence, supervision, replay, and control flow.
- Zig owns narrow, optional native acceleration where the BEAM is not the best fit.
- Everything else sits behind explicit adapters or protocols.

## Core Rule

Elixir is the control plane. Zig is a helper.

If a feature changes session continuity, supervision, cancellation, receipts, replay, provider routing, or CLI semantics, it belongs in Elixir first.

If a feature is a pure compute fast path with a clear fallback, it can live at the Zig boundary.

## Runtime Layers

### 1. CLI And Operator Entry

- [cli.ex](../../lib/claw_code/cli.ex)
- responsibility: commands, flags, explicit local-vs-daemon mode, operator output

### 2. Runtime And Sessions

- [runtime.ex](../../lib/claw_code/runtime.ex)
- [session_server.ex](../../lib/claw_code/session_server.ex)
- [session_store.ex](../../lib/claw_code/session_store.ex)
- responsibility: turn loop, persistence, cancellation, single-flight session ownership, replayable state

### 3. Persistent Control Plane

- [daemon.ex](../../lib/claw_code/daemon.ex)
- responsibility: cross-process session control, local daemon lifecycle, daemon-backed chat and cancellation

### 4. Providers

- [openai_compatible.ex](../../lib/claw_code/providers/openai_compatible.ex)
- responsibility: one provider contract across `generic`, `glm`, `nim`, and `kimi`

### 5. Tools And Adapters

- [builtin.ex](../../lib/claw_code/tools/builtin.ex)
- [external.ex](../../lib/claw_code/adapters/external.ex)
- responsibility: disciplined shell/runtime/tool execution with receipts

### 6. Native Fast Path

- [native_ranker.ex](../../lib/claw_code/native_ranker.ex)
- [token_ranker.zig](../../native/token_ranker.zig)
- responsibility: optional ranking acceleration with a deterministic BEAM fallback

## Control Plane

The control plane has two valid modes:

- direct runtime mode
  - one CLI invocation owns one BEAM instance
  - useful for tests, short runs, and simple scripts
- daemon mode
  - one local daemon owns long-running session state across CLI invocations
  - useful for cancellation, background work, and future multi-client control

The daemon is deliberately local-only. It is not a web service, not a distributed Erlang cluster, and not a hidden product dependency.

## Native Boundary

The Zig boundary should stay:

- optional
- observable
- easy to disable
- easy to replace with a BEAM fallback

Do not move session logic, tool execution, provider behavior, or daemon behavior into Zig. That would make the system faster in the wrong place and less reliable where it matters.

## Provider Boundary

Providers should keep one OpenAI-compatible shape even when the upstream is GLM, Kimi, NIM, or a custom endpoint.

That keeps:

- CLI configuration uniform
- session persistence uniform
- tool-calling behavior uniform
- failure receipts comparable across providers

## Operator Surface

The operator layer should stay explicit:

- `chat` vs `chat --daemon`
- `cancel-session` vs `cancel-session --daemon`
- `--session-root` and `--daemon-root` for isolated roots
- Ralph loops for validation instead of ad hoc shell rituals

If the operator surface becomes implicit, the repo will become harder to reason about and harder to teach from.

## What To Extend Next

The next extensions should still follow the same boundary:

- richer daemon replay and inspection semantics in Elixir
- stale-daemon recovery coverage in Elixir
- provider hardening in the OpenAI-compatible boundary
- only narrow, measurable acceleration work at the Zig edge
