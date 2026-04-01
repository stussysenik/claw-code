# OMX Execution Board

## Table of Contents

- [Active Lanes](#active-lanes)
- [Operator Notes](#operator-notes)
- [Role Map](#role-map)

## Active Lanes

| Lane | Mission | Issues | Default Loop | Status |
| --- | --- | --- | --- | --- |
| Runtime Core | `missions/01-runtime-core.md` | `#6`, `#12` | `scripts/ralph-core.sh` | active |
| Provider Loop | `missions/02-provider-loop.md` | `#11`, `#5` | `scripts/ralph-provider.sh` | active |
| Native And Adapters | `missions/03-native-and-adapters.md` | `#7`, `#8` | `scripts/ralph-native.sh`, `scripts/ralph-adapters.sh` | active |
| Release Quality | `missions/04-release-readiness.md` | `#9`, `#10` | `scripts/ralph-release.sh` | active |

## Operator Notes

- Start with one lane at a time unless OMX `$team` is coordinating the split explicitly.
- Use `ROADMAP.md` for the short readiness and competitive-plan view, then use `openspec/changes/reach-daily-driver/` for the sharper phase bar.
- Use `openspec/changes/reach-daily-driver/` as the canonical phase map for the remaining daily-driver work.
- Do not expand shell or write capability without tests and receipts.
- Treat the requirements ledger as a blocking reliability feature, not optional polish.
- Use `scripts/qa.sh` as the canonical dispatcher for validation and lane-specific gates.

## Role Map

- `architect` owns `docs/execution-plan.md`, mission scope, and issue decomposition.
- `core` owns Mission 01 and the requirements ledger.
- `providers` owns Mission 02.
- `native` and `adapters` split Mission 03 by boundary.
- `qa` owns Mission 04, `scripts/qa.sh`, and the release gate.
