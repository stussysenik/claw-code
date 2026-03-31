# OpenSpec Layer

OpenSpec is the spec and phase-planning layer for `claw_code`.

## Table of Contents

- [Purpose](#purpose)
- [Directory Layout](#directory-layout)
- [Current Change Set](#current-change-set)
- [How It Maps To OMX](#how-it-maps-to-omx)

## Purpose

Use OpenSpec to define what "daily-driver ready" means before parallel agents and Ralph loops start chewing through slices.

OMX remains the execution layer. OpenSpec becomes the canonical planning layer for:

- proposal scope
- design boundaries
- requirement deltas
- executable task lists

## Directory Layout

- `project.md` defines repo-wide OpenSpec constraints and review rules.
- `changes/` contains active change sets.
- `changes/reach-daily-driver/` is the current canonical roadmap from today's repo state to a daily-driver release candidate.

## Current Change Set

The active roadmap is:

- [`changes/reach-daily-driver/proposal.md`](./changes/reach-daily-driver/proposal.md)
- [`changes/reach-daily-driver/design.md`](./changes/reach-daily-driver/design.md)
- [`changes/reach-daily-driver/tasks.md`](./changes/reach-daily-driver/tasks.md)
- [`changes/reach-daily-driver/specs/daily-driver/spec.md`](./changes/reach-daily-driver/specs/daily-driver/spec.md)

## How It Maps To OMX

- OpenSpec defines the phases and exit criteria.
- `.omx/board.md` maps those phases onto active execution lanes.
- `scripts/ralph-*.sh` run the persistent loops for each lane.
- `progress.md` records UTC evidence as slices land.
