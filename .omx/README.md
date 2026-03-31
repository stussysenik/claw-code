# OMX Operator Layer

This repo uses OMX as an execution layer, not as a shipped runtime dependency.

## Table of Contents

- [Directory Layout](#directory-layout)
- [Recommended Flow](#recommended-flow)
- [Command Map](#command-map)

## Directory Layout

- `board.md` tracks the active workstreams and issue map.
- `missions/` contains the four canonical mission files for agent kickoff.
- `checklists/` contains review and release gates.
- `../openspec/` contains the canonical daily-driver planning artifacts.
- `progress.md` at the repo root records the UTC workflow ledger.

Runtime artifacts such as logs, temporary state, or loop output should live in ignored directories under `.omx/` created by the loop scripts.

## Recommended Flow

1. Open `board.md` and pick one active mission.
2. Check `../openspec/changes/reach-daily-driver/` for the current phase and exit criteria.
3. Start with the relevant mission file in `missions/`.
4. Use the matching Ralph loop from `scripts/`.
5. Close the loop only after the checklist in `checklists/` is satisfied.
6. Append evidence and next steps to `progress.md`.

## Command Map

- Planning: use OMX `$plan` against `docs/execution-plan.md` and `board.md`
- Parallel execution: use OMX `$team` with the mission file for the selected lane
- Persistent execution: use OMX `$ralph` together with one of the `scripts/ralph-*.sh` loops
- Validation dispatcher: use `scripts/qa.sh` for baseline or lane-specific gates
