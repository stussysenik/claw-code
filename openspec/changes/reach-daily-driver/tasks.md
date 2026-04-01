# Tasks: Reach Daily-Driver Status

## Table of Contents

- [Phase 0: Freeze The Definition](#phase-0-freeze-the-definition)
- [Phase 1: Workflow Parity And Session Durability](#phase-1-workflow-parity-and-session-durability)
- [Phase 2: Provider Portability](#phase-2-provider-portability)
- [Phase 3: Tool And Adapter Reliability](#phase-3-tool-and-adapter-reliability)
- [Phase 4: TUI Daily-Driver UX](#phase-4-tui-daily-driver-ux)
- [Phase 5: Long-Run Operations](#phase-5-long-run-operations)
- [Phase 6: Release Confidence](#phase-6-release-confidence)
- [Phase 7: Post-RC Research Track](#phase-7-post-rc-research-track)

## Phase 0: Freeze The Definition

- [x] Add the OpenSpec planning layer under `openspec/`.
- [x] Define the daily-driver target state and exit bar.
- [x] Link the roadmap from README, OMX, and execution docs.

## Phase 1: Workflow Parity And Session Durability

- [x] Create a parity note for the essential workflows worth preserving from the original `stussysenik/claw-code` repo.
- [x] Add stronger active-run and failed-run inspection for daemon-backed sessions.
- [ ] Prove resume/cancel/replay behavior across repeated shell exits and daemon restarts.
- [ ] Add one explicit stale-session recovery test and one stale-daemon recovery smoke path for the daily-driver checklist.
- [ ] Tighten session-root hygiene so corrupted or partial state fails clearly and locally.

## Phase 2: Provider Portability

- [ ] Record live smoke evidence for GLM, Kimi, NIM, and one generic OpenAI-compatible endpoint.
- [ ] Add provider capability summaries so the operator can see tool support, auth mode, and endpoint identity at a glance.
- [ ] Harden compatibility fallback for partial OpenAI-compatible backends beyond the current `tools` retry.
- [ ] Add one provider-matrix Ralph loop mode or checklist that can be run before calling a release candidate "daily-driver".
- [ ] Document the preferred local setup patterns for `.env.local` without persisting secrets.

## Phase 3: Tool And Adapter Reliability

- [ ] Finish the shell/write safety story with clear receipts, policy display, and destructive-command evidence.
- [ ] Add stronger timeout, exit-status, and output proof for Python, Lua, and Common Lisp adapters.
- [ ] Add one nontrivial Common Lisp-backed tool or evaluation path that proves the adapter is worth keeping.
- [ ] Add native-ranker build and fallback evidence for the release checklist with native explicitly disabled.
- [ ] Document when a new optimization belongs in Elixir first versus Zig.

## Phase 4: TUI Daily-Driver UX

- [ ] Add tighter active-session shortcuts for resume, inspect, and intervention without widening the daemon boundary.
- [ ] Improve at-a-glance provider, model, tool-policy, and health visibility in the TUI header/footer.
- [ ] Add transcript/session views that still feel usable as the session root grows.
- [ ] Add one compact "operator quickstart" flow in the TUI docs for normal daily use.
- [ ] Keep all new TUI behavior behind the thin-client rule and prove it with tests.

## Phase 5: Long-Run Operations

- [ ] Add clearer daemon health reporting for busy, failed, stale, and partially recovered states.
- [ ] Prove that repeated background session use does not silently lose session continuity.
- [ ] Add better inspection for the most recent receipt, provider error, and stop reason of active or failed runs.
- [ ] Add recovery docs and smoke commands for the common break/fix paths.

## Phase 6: Release Confidence

- [ ] Build a daily-driver release checklist that combines core, provider, daemon, native, and TUI evidence.
- [ ] Add a small live smoke matrix document with expected commands and outputs.
- [ ] Run `npm run release:dry-run` as part of the release-quality path after any release-config change.
- [ ] Define the first "daily-driver beta" bar in docs, not just in chat.
- [ ] Record the release candidate decision in `progress.md` with evidence links.

## Phase 7: Post-RC Research Track

- [ ] Evaluate whether the JSON CLI boundary is still sufficient or whether direct daemon polling is worth the complexity.
- [ ] Evaluate plugin and provider-extension boundaries without turning them into runtime sprawl.
- [ ] Benchmark candidate Zig or GPU work before adding any new native surface.
- [ ] Keep speculative work explicitly outside the daily-driver critical path.
