# ClawCode Agent Guide

## Table Of Contents

- [North Star](#north-star)
- [Architecture Rules](#architecture-rules)
- [Engineering Standards](#engineering-standards)
- [Required Checks](#required-checks)
- [OMX Workflow](#omx-workflow)
- [Team Roles](#team-roles)
- [Definition Of Done](#definition-of-done)

## North Star

Build `claw_code` as an Elixir-first coding runtime with explicit session state, replayable tool execution, isolated Zig/native helpers, and adapter-based provider/runtime integrations.

## Architecture Rules

1. Elixir is the control plane.
2. Zig stays outside the BEAM behind a narrow executable boundary.
3. Python, Lua, and Common Lisp remain adapter processes, not core runtime dependencies.
4. Provider integrations such as GLM and NVIDIA NIM stay behind one OpenAI-compatible boundary.
5. New shell or write capabilities must be explicitly gated and evidenced in tests.

## Engineering Standards

1. Keep diffs minimal and behavior-focused.
2. Every meaningful behavior change gets one focused automated test.
3. Every meaningful behavior change gets one smoke command.
4. Failures must be explicit: native fallback, provider errors, subprocess failures, and persistence edge cases.
5. If a change touches sessions or tools, verify replayability or receipts directly.

## Required Checks

- `mix format --check-formatted`
- `mix test`
- `mix escript.build`
- `./claw_code summary`
- `./claw_code symphony --native "review MCP tool"`
- `./scripts/validate-repo.sh`

## Change-Specific Gates

- Runtime/provider changes: add a missing-config or tool-loop test.
- Native changes: run native-ranker tests and one fallback-path check with native disabled.
- CLI changes: update or add a CLI smoke test.
- Host/tool adapter changes: prove subprocess exit/output behavior in tests.
- Release-config changes: run `npm run release:dry-run` and keep commit messages conventional.

## OMX Workflow

1. Use `.omx/board.md` as the active execution board.
2. Use `.omx/missions/` for the four canonical mission files only.
3. Use `.omx/checklists/review.md` before merging behavior changes.
4. Use `.omx/checklists/release.md` before cutting a release-quality branch or tag.
5. Use `scripts/ralph-*.sh` as the canonical persistent execution loops.
6. Use `scripts/qa.sh` as the dispatcher for validation and lane-specific gates.
7. Record workflow state in `progress.md` with UTC timestamps and evidence.

## Team Roles

- `architect`: shape phases, boundaries, and exit criteria
- `core`: sessions, replay, routing, CLI behavior
- `native`: Zig helpers, build flow, fallback behavior
- `adapters`: Python, Lua, Common Lisp, local tool execution
- `providers`: GLM, NIM, OpenAI-compatible loop, tool calling
- `qa`: tests, smoke commands, checklists, release gate

## Definition Of Done

1. One user-visible behavior is clearly improved.
2. One automated test was added or strengthened.
3. One failure mode is handled explicitly.
4. One smoke command was run and recorded.
5. Documentation is updated if the operator surface changed.
