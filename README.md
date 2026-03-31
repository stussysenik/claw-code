# claw_code

`claw_code` is an Elixir-first coding runtime with explicit session state, replayable tool execution, isolated Zig helpers, and adapter-based provider/runtime integrations.

## Table of Contents

- [What Lives Here](#what-lives-here)
- [Architecture Reference](#architecture-reference)
- [Canonical Operator Layer](#canonical-operator-layer)
- [Working Commands](#working-commands)
- [Session Resume](#session-resume)
- [Persistent Control Plane](#persistent-control-plane)
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

## Architecture Reference

The right way to think about this repo is: `claw_code` is Elixir-first with a small Zig fast path, not a mixed-language app without a center. The canonical reference for that boundary is [docs/reference/architecture.md](./docs/reference/architecture.md).

## Canonical Operator Layer

- [AGENTS.md](./AGENTS.md)
- [.omx/README.md](./.omx/README.md)
- [.omx/board.md](./.omx/board.md)
- [.omx/team.md](./.omx/team.md)
- [docs/backlog.md](./docs/backlog.md)
- [docs/reference/architecture.md](./docs/reference/architecture.md)
- [docs/execution-plan.md](./docs/execution-plan.md)
- [docs/engineering-standards.md](./docs/engineering-standards.md)
- [docs/providers.md](./docs/providers.md)
- [docs/proposals/persistent-control-plane.md](./docs/proposals/persistent-control-plane.md)
- [progress.md](./progress.md)
- [scripts/validate-repo.sh](./scripts/validate-repo.sh)
- [scripts/qa.sh](./scripts/qa.sh)
- [scripts/ralph-core.sh](./scripts/ralph-core.sh)
- [scripts/ralph-native.sh](./scripts/ralph-native.sh)
- [scripts/ralph-adapters.sh](./scripts/ralph-adapters.sh)
- [scripts/ralph-provider.sh](./scripts/ralph-provider.sh)
- [scripts/ralph-daemon.sh](./scripts/ralph-daemon.sh)
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
./scripts/qa.sh daemon
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
./claw_code probe
./claw_code symphony --native "review MCP tool"
./claw_code chat --allow-shell --allow-write "inspect the repo and propose a minimal plan"
```

## Session Resume

Sessions live under `.claw/sessions/` and can be resumed by explicit id.

```bash
./claw_code chat --session-id my-session --provider kimi "inspect this repo"
./claw_code resume-session my-session --provider kimi "continue from the last state"
./claw_code resume-session latest --provider kimi "continue the latest session"
./claw_code sessions --limit 10
./claw_code sessions --limit 10 --query build
./claw_code cancel-session my-session
./claw_code cancel-session latest-completed
./claw_code cancel-session my-session --daemon
./claw_code load-session my-session
./claw_code load-session latest-completed
./claw_code load-session my-session --show-messages --show-receipts
```

`load-session` exposes `created=` and `updated=` timestamps together with message and receipt counts. `sessions` gives a fast index of recent session ids, run states, stop reasons, and receipt counts, and now accepts `--query` for substring search across ids, prompts, outputs, provider names, and message content. The direct runtime path still allows one active run per session id inside the same BEAM and checkpoints tool receipts/messages before the final provider reply lands. If you need cross-process control, use the daemon-backed path explicitly.

## Persistent Control Plane

`claw_code` now has an explicit local daemon path for cross-process session ownership. It stays local-only and narrow: `daemon start`, `daemon status`, `daemon stop`, and daemon-backed `chat`, `resume-session`, and `cancel-session`.

```bash
./claw_code daemon start
./claw_code daemon status
./claw_code chat --daemon --provider kimi "inspect this repo"
./claw_code resume-session my-session --daemon --provider kimi "continue"
./claw_code cancel-session my-session --daemon
./claw_code daemon stop
```

The design goal is not a network service or a distributed node mesh. It is a boring, inspectable local coordinator that can survive a shell exit, keep session ownership stable, and become the foundation for future multi-client control without loosening the current KISS/DRY/SRP boundaries. Use `--session-root PATH` and `--daemon-root PATH` when you want isolated operator roots for testing or parallel work.

The final UX can absolutely include a full terminal UI, and the correct layering stays engine first: the Elixir runtime and daemon remain the product core, and the TUI is a client over that control plane instead of the architectural center.

`./claw_code tui` is the first in-repo slice of that client. It is intentionally minimal: recent sessions, selected transcript, tool receipts, aggregate run counts, selected-session run metadata, optional `watch` refresh cadence, in-client provider/model/base-url switching with reset-to-default, session filtering and limits, substring `find`, transcript `find-msg` with `next-hit` / `prev-hit`, `open latest-completed`, targeted `resume latest ...`, provider `probe`, and a command loop for `chat`, `resume`, `open`, `next`, `prev`, `cancel`, and `tools`.

## Provider Setup

Provider contracts are documented in [docs/providers.md](./docs/providers.md). `claw_code` accepts explicit CLI flags and also autoloads `.env.local` / `.env` at runtime for local development. Those files are git-ignored in this repo.

`chat` and `resume-session` default to an `auto` tool policy: repo or tool-oriented prompts expose local tools, plain chat prompts do not. Use `--tools` to force tool specs on, `--no-tools` to force a chat-only request, or `CLAW_TOOL_MODE=auto|on|off` to set the default behavior across local and daemon-backed runs.

`./claw_code probe` is the fastest way to validate a provider before a longer chat. It sends one small chat-completions request and reports the request URL, configuration state, latency, and a short response preview. When tool exposure is still in `auto`, `chat` now retries once without `tools` / `tool_choice` if a generic endpoint rejects those parameters. Generic endpoints can also override the auth header with `--api-key-header` or `CLAW_API_KEY_HEADER` when they expect something other than `Authorization: Bearer ...`.

Core operator commands now also support `--json`, which is the intended first contract for a future terminal UI client. The boundary is documented in [docs/reference/tui.md](./docs/reference/tui.md).

`./claw_code doctor` now reports whether the active provider is fully configured, which request URL will be used, and whether each field came from an env var, a default, or is still missing.

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
- `docs/reference/tui.md` records the client boundary for a future terminal UI.
- `.omx/` contains the operator board, team split, checklists, and mission briefs.
- `scripts/` contains the canonical Ralph loops, QA dispatcher, and validation gate.
- `.claw/sessions/` stores resumable session state with message history and tool receipts.
- `progress.md` is the append-only UTC ledger for workflow progress.

## Progress Ledger

Track operator work in [progress.md](./progress.md). Every entry should use a UTC ISO-8601 timestamp and record the mission, issues, lane, loop, status, evidence, and next step.
