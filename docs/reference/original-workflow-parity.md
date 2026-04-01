# Original Workflow Parity

## Table of Contents

- [Purpose](#purpose)
- [Source Of Truth](#source-of-truth)
- [Preserve These Workflows](#preserve-these-workflows)
- [Current Mapping](#current-mapping)
- [Defer Or Drop](#defer-or-drop)

## Purpose

This note captures the original operator workflows worth preserving while `claw_code` moves toward daily-driver status.

It does not aim for feature-count parity. It focuses on the smallest set of workflows that make the product usable every day.

## Source Of Truth

The most reliable local parity references are:

- [`src/main.py`](../../src/main.py)
- [`src/parity_audit.py`](../../src/parity_audit.py)
- [`src/reference_data/commands_snapshot.json`](../../src/reference_data/commands_snapshot.json)
- [`src/reference_data/tools_snapshot.json`](../../src/reference_data/tools_snapshot.json)

Those files preserve the archived Python porting workspace and its mirrored command/tool surfaces.

## Preserve These Workflows

### 1. Preflight Before A Real Run

The original workspace emphasized summary, manifest, setup, command graphs, tool inventories, and parity audit before deeper runtime work.

What must survive:

- a fast summary of the product state
- a fast provider/config health check
- a cheap probe before a longer session
- visibility into available commands and tools

### 2. Searchable Command And Tool Surface

The original workspace preserved mirrored command and tool inventories with queryable indexes.

What must survive:

- searchable command inventory
- searchable tool inventory
- explicit permission and policy context
- route/bootstrap visibility before full execution

### 3. Stateful, Resumable Sessions

The original workspace already treated session persistence as a first-class operator behavior.

What must survive:

- explicit session ids
- session resume by id and by useful aliases
- session inspection without hidden state
- transcript and receipt replay

### 4. Long-Run Control Outside One Shell

The modern Elixir runtime now goes further than the original workspace here, and that is correct.

What must survive:

- start, inspect, stop, resume, and cancel long-running work cleanly
- boring local control-plane behavior
- no guesswork about which process owns a running session

### 5. Thin Interactive Client

The original workspace carried CLI-first interactive/reporting flows. The Elixir rewrite extends that into the TUI.

What must survive:

- inspect recent work quickly
- continue a prior session without typing raw ids
- watch active runs
- intervene on active runs

## Current Mapping

| Original workflow surface | Current `claw_code` path |
| --- | --- |
| `summary`, `manifest` | `./claw_code summary`, `./claw_code manifest` |
| `parity-audit`, `setup-report`, graph-style preflight | `./claw_code doctor`, `./claw_code probe`, `./claw_code bootstrap`, docs in `openspec/` and `docs/` |
| `commands`, `tools`, `route`, `bootstrap` | `./claw_code commands`, `./claw_code tools`, `./claw_code route`, `./claw_code bootstrap` |
| `turn-loop`, `flush-transcript`, `load-session` | `./claw_code chat`, daemon-backed `chat`, `resume-session`, `load-session`, `.claw/sessions/` |
| exact command/tool introspection | `./claw_code show-command`, `./claw_code show-tool`, `./claw_code exec-command`, `./claw_code exec-tool` |
| remote/direct/transport branching experiments | local daemon path plus provider adapters; remote transport remains intentionally deferred |
| parity as a first-class concern | OpenSpec roadmap, `progress.md`, `scripts/qa.sh`, semantic commits, and release evidence |

## Defer Or Drop

These are not blockers for daily-driver status:

- broad command-count or tool-count parity with the archived snapshots
- remote-control transport modes as product requirements
- plugin sprawl before the local runtime is fully boring
- speculative UI complexity that duplicates daemon/runtime state

The daily-driver bar is workflow parity on the important operator loop, not historical surface-area parity.
