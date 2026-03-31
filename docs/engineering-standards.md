# Engineering Standards

## Table of Contents

- [Core Principles](#core-principles)
- [Change Checklist](#change-checklist)
- [Quality Gates](#quality-gates)
- [Review Questions](#review-questions)

## Core Principles

- Keep modules small and single-purpose.
- Prefer explicit state and replayable artifacts over hidden mutation.
- Keep failure boundaries outside the BEAM when the work is native or subprocess-heavy.
- Add the smallest test that proves the behavior that matters.
- Land evidence, not vibes.
- Keep workflow records in `progress.md` with UTC timestamps and concrete evidence.

## Change Checklist

1. Is the module boundary still clear?
2. Is the failure mode explicit?
3. Is the behavior replayable from files or logs?
4. Is there a focused automated test?
5. Is the CLI behavior still terminal-friendly?
6. Did the change preserve the canonical OMX mission and Ralph loop layout?

## Quality Gates

- `mix format --check-formatted`
- `mix test`
- `mix escript.build`
- `./claw_code summary`
- `./claw_code symphony --native review MCP tool`
- `./scripts/validate-repo.sh`
- provider smoke when credentials are available
- `npm run release:dry-run` when release tooling or workflow files change

## Review Questions

- Did this change expand scope without adding leverage?
- Did this change mix policy with execution?
- Did this change make provider-specific behavior leak into the core runtime?
- Did this change add native complexity without a clean fallback?
- Did this change improve the learning value of the repo?
