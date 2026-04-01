# Design: Daily-Driver Roadmap

## Table of Contents

- [Guiding Principle](#guiding-principle)
- [Execution Topology](#execution-topology)
- [Phase Design](#phase-design)
- [Parallel Agent Split](#parallel-agent-split)
- [Exit Bar](#exit-bar)

## Guiding Principle

The correct end state is not "a clone of other coding assistants in Elixir." The correct end state is a smaller, more explicit runtime that does the important things better:

- clearer persistence
- cleaner provider boundaries
- safer tool execution
- simpler local operations
- less hidden state

## Execution Topology

Keep one canonical mapping:

- OpenSpec defines the scope and exit criteria.
- `.omx/board.md` defines the active lanes.
- `scripts/ralph-*.sh` run the persistent loops.
- `progress.md` records evidence as the slices land.

This keeps planning, execution, and evidence separate.

## Phase Design

### Phase 0: Freeze The Definition

Owner lanes:

- `architect`
- `qa`

Primary output:

- OpenSpec project context
- daily-driver proposal, design, tasks, and spec delta
- links from README, board, and execution docs

Exit criteria:

- all operators can find the roadmap in one hop
- remaining work is grouped into lanes, not scattered notes

### Phase 1: Workflow Parity And Session Durability

Owner lanes:

- `core`
- `qa`

Questions to answer:

- Which original `claw-code` workflows are essential enough to preserve?
- Which session semantics still feel brittle under repeated daily use?

Required outputs:

- original-repo parity reference for essential operator flows
- stronger long-run checkpoint and replay semantics
- clearer session/run-state inspection for active and recently failed sessions
- explicit stale-session and stale-daemon recovery evidence

Suggested Ralph loop:

- `scripts/ralph-core.sh`

Exit criteria:

- resume/cancel/replay behavior is predictable across repeated runs
- operator can recover from interruption without guessing which state is authoritative

### Phase 2: Provider Portability

Owner lanes:

- `providers`
- `qa`

Required outputs:

- live smoke evidence for GLM, Kimi, NIM, and one generic endpoint
- provider profile docs for auth, defaults, and weird compatibility behavior
- stronger fallback behavior for endpoints that partially implement OpenAI compatibility
- provider-agnostic multimodal image input with replayable local-path persistence and explicit validation
- an optional split vision backbone so image understanding can come from one provider/model while reasoning stays on another
- multimodal preflight and capability visibility through `doctor`, `providers`, `probe`, and the TUI header
- clearer provider identity and capability display in CLI and TUI

Suggested Ralph loop:

- `scripts/ralph-provider.sh`

Exit criteria:

- switching providers does not require code edits
- probe, doctor, chat, and TUI flows behave predictably across the supported matrix

### Phase 3: Tool And Adapter Reliability

Owner lanes:

- `adapters`
- `native`
- `qa`

Required outputs:

- hardened shell/write policy receipts
- explicit subprocess failure and timeout evidence for Python, Lua, and Common Lisp
- runtime adapter receipts that preserve engine, invocation, exit status, and merged output under both failure and timeout
- one structured Common Lisp-backed tool path that justifies keeping the adapter beyond raw eval
- native ranker build, disable, and fallback proof
- one documented policy for when Zig is worth adding to a feature

Suggested Ralph loops:

- `scripts/ralph-adapters.sh`
- `scripts/ralph-native.sh`

Exit criteria:

- adapter behavior is boring under success and failure
- native acceleration never becomes a dependency for correctness

### Phase 4: TUI Daily-Driver UX

Owner lanes:

- `core`
- `qa`

Required outputs:

- active-run shortcuts that reduce command ceremony
- tighter provider/model/tool-policy visibility
- multimodal `chat` and `resume` forwarding that stays inside the thin-client daemon/runtime path
- session and transcript navigation that stays fast as the session root grows
- a small set of keyboard-friendly or alias-friendly workflows that cover most daily use

Suggested Ralph loop:

- `scripts/ralph-daemon.sh`

Exit criteria:

- an operator can spend a few hours in `./claw_code tui` without constantly dropping to raw commands
- the TUI remains a thin client instead of accumulating runtime logic

### Phase 5: Long-Run Operations

Owner lanes:

- `core`
- `providers`
- `qa`

Required outputs:

- daemon health and recovery surface for stale state, busy sessions, provider failures, and partial writes
- better inspection of currently running and recently failed work
- evidence that repeated background session use does not silently corrupt session continuity

Suggested Ralph loops:

- `scripts/ralph-daemon.sh`
- `scripts/ralph-provider.sh`

Exit criteria:

- long-running local use feels stable, not lucky

### Phase 6: Release Confidence

Owner lanes:

- `qa`
- `architect`

Required outputs:

- a release candidate checklist for daily-driver readiness
- a live smoke matrix covering core operator flows
- docs that make setup, troubleshooting, and supported modes obvious
- semantic-release remains green without contaminating runtime architecture

Suggested Ralph loop:

- `scripts/ralph-release.sh`

Exit criteria:

- the repo can cut a believable "daily-driver beta" without hand-curated tribal knowledge

### Phase 7: Post-RC Research Track

Owner lanes:

- `architect`
- `providers`
- `native`

Scope:

- plugin surface
- direct daemon protocol if the JSON CLI boundary becomes too coarse
- benchmark-guided native or GPU offload work
- provider-specific advanced features

Exit criteria:

- none of this blocks daily-driver status

## Parallel Agent Split

Use this default split when running OMX `$team` or comparable parallel agents:

1. `architect`
   - maintain OpenSpec and phase boundaries
   - keep `.omx/board.md`, `docs/execution-plan.md`, and `progress.md` aligned
2. `core`
   - own session semantics, CLI, daemon, and TUI thin-client behavior
3. `providers`
   - own provider compatibility, profiles, and live smoke evidence
4. `adapters`
   - own Python, Lua, and Common Lisp adapter behavior
5. `native`
   - own Zig build, fallback, and benchmark evidence
6. `qa`
   - own release gates, matrix validation, and regression review

## Exit Bar

Call the repo "daily-driver ready" only when all of these are true:

1. the operator can run real chats against at least one preferred provider and one generic provider every day
2. session persistence, replay, cancel, and resume are stable across repeated shell invocations
3. the TUI covers the normal inspect, continue, monitor, and intervene loop
4. tool execution is explicit, gated, and evidenced
5. native acceleration is optional and observable
6. release and smoke gates prove the above instead of assuming it
