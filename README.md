# claw_code

`claw_code` is an Elixir-first coding runtime with explicit session state, replayable tool execution, isolated Zig helpers, and adapter-based provider/runtime integrations.

## Table of Contents

- [What Lives Here](#what-lives-here)
- [Canonical Operator Layer](#canonical-operator-layer)
- [Working Commands](#working-commands)
- [Session Resume](#session-resume)
- [Provider Setup](#provider-setup)
- [Release Automation](#release-automation)
- [Repository Layout](#repository-layout)
- [Progress Ledger](#progress-ledger)

## What Lives Here

- Elixir is the control plane.
- Zig stays behind a narrow executable boundary.
- Python, Lua, and Common Lisp stay as adapters, not core dependencies.
- GLM, Kimi, and NVIDIA NIM stay behind one OpenAI-compatible provider boundary.
- OMX is the planning and execution layer, not the shipped runtime.

## Canonical Operator Layer

- [AGENTS.md](./AGENTS.md)
- [.omx/README.md](./.omx/README.md)
- [.omx/board.md](./.omx/board.md)
- [.omx/team.md](./.omx/team.md)
- [docs/backlog.md](./docs/backlog.md)
- [docs/execution-plan.md](./docs/execution-plan.md)
- [docs/engineering-standards.md](./docs/engineering-standards.md)
- [docs/providers.md](./docs/providers.md)
- [progress.md](./progress.md)
- [scripts/validate-repo.sh](./scripts/validate-repo.sh)
- [scripts/qa.sh](./scripts/qa.sh)
- [scripts/ralph-core.sh](./scripts/ralph-core.sh)
- [scripts/ralph-native.sh](./scripts/ralph-native.sh)
- [scripts/ralph-adapters.sh](./scripts/ralph-adapters.sh)
- [scripts/ralph-provider.sh](./scripts/ralph-provider.sh)
- [scripts/ralph-release.sh](./scripts/ralph-release.sh)
- [package.json](./package.json)
- [.releaserc.json](./.releaserc.json)
- [.github/workflows/ci.yml](./.github/workflows/ci.yml)
- [.github/workflows/release.yml](./.github/workflows/release.yml)
- [CHANGELOG.md](./CHANGELOG.md)

## Working Commands

Baseline validation:

```bash
./scripts/validate-repo.sh
```

Canonical QA dispatcher:

```bash
./scripts/qa.sh
./scripts/qa.sh core
./scripts/qa.sh native
./scripts/qa.sh adapters
./scripts/qa.sh provider "say hello and report the configured provider"
./scripts/qa.sh release
```

Runtime smoke:

```bash
mix deps.get
mix claw_code.native.build
mix test
mix escript.build
./claw_code summary
./claw_code doctor
./claw_code symphony --native "review MCP tool"
./claw_code chat --allow-shell --allow-write "inspect the repo and propose a minimal plan"
```

## Session Resume

Sessions live under `.claw/sessions/` and can be resumed by explicit id.

```bash
./claw_code chat --session-id my-session --provider kimi "inspect this repo"
./claw_code resume-session my-session --provider kimi "continue from the last state"
./claw_code load-session my-session
```

`load-session` now exposes `created=` and `updated=` timestamps together with message and receipt counts.

## Provider Setup

Provider contracts are documented in [docs/providers.md](./docs/providers.md). `claw_code` does not need to read secret files; pass provider credentials through environment variables or explicit CLI flags.

## Release Automation

Release automation is driven by semantic-release from conventional commits on `main`.

Local verification:

```bash
npm ci --ignore-scripts
npm run release:dry-run
```

The release lane generates tags, updates `CHANGELOG.md`, and publishes GitHub Releases. It does not publish a Hex or npm package in this phase.

## Repository Layout

- `lib/` contains the OTP application, CLI, session store, routing, and symphony-style orchestration.
- `native/` contains the isolated Zig helper boundary.
- `docs/` contains backlog and execution-plan material.
- `docs/providers.md` records the provider env contract for `generic`, `glm`, `kimi`, and `nim`.
- `.omx/` contains the operator board, team split, checklists, and mission briefs.
- `scripts/` contains the canonical Ralph loops, QA dispatcher, and validation gate.
- `.claw/sessions/` stores resumable session state with message history and tool receipts.
- `progress.md` is the append-only UTC ledger for workflow progress.

## Progress Ledger

Track operator work in [progress.md](./progress.md). Every entry should use a UTC ISO-8601 timestamp and record the mission, issues, lane, loop, status, evidence, and next step.
