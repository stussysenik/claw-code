# claw_code

![Demo](demo.gif)


`claw_code` is an Elixir-first coding runtime with explicit session state, replayable tool execution, isolated Zig helpers, and adapter-based provider/runtime integrations.

## Table of Contents

- [What Lives Here](#what-lives-here)
- [Vision Design Roadmap And Stack](#vision-design-roadmap-and-stack)
- [Architecture Reference](#architecture-reference)
- [Original Workflow Parity](#original-workflow-parity)
- [Canonical Operator Layer](#canonical-operator-layer)
- [OpenSpec Roadmap](#openspec-roadmap)
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

## Vision Design Roadmap And Stack

The fastest top-level orientation is now split cleanly:

- [VISION.md](./VISION.md) explains what the repo is trying to become and what "daily-driver" means.
- [DESIGN.md](./DESIGN.md) defines the system shape and the boundaries that should not drift while we keep building.
- [ROADMAP.md](./ROADMAP.md) turns the current readiness bar plus the competitive feature study into one execution order.
- [TECHSTACK.md](./TECHSTACK.md) records the concrete runtime, provider, adapter, native, and release stack in the repo today.

## Architecture Reference

The right way to think about this repo is: `claw_code` is Elixir-first with a small Zig fast path, not a mixed-language app without a center. The canonical reference for that boundary is [docs/reference/architecture.md](./docs/reference/architecture.md).

## Original Workflow Parity

The preserved operator workflows from the archived workspace are documented in [docs/reference/original-workflow-parity.md](./docs/reference/original-workflow-parity.md). That note defines the parity target in workflow terms instead of chasing raw command-count parity.

## Canonical Operator Layer

- [AGENTS.md](./AGENTS.md)
- [.omx/README.md](./.omx/README.md)
- [.omx/board.md](./.omx/board.md)
- [.omx/team.md](./.omx/team.md)
- [docs/backlog.md](./docs/backlog.md)
- [docs/reference/architecture.md](./docs/reference/architecture.md)
- [docs/reference/release-confidence.md](./docs/reference/release-confidence.md)
- [docs/reference/recovery.md](./docs/reference/recovery.md)
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
- [scripts/ralph-provider-matrix.sh](./scripts/ralph-provider-matrix.sh)
- [scripts/ralph-daemon.sh](./scripts/ralph-daemon.sh)
- [scripts/ralph-recovery.sh](./scripts/ralph-recovery.sh)
- [scripts/ralph-release.sh](./scripts/ralph-release.sh)
- [package.json](./package.json)
- [.releaserc.json](./.releaserc.json)
- [.github/workflows/ci.yml](./.github/workflows/ci.yml)
- [.github/workflows/release.yml](./.github/workflows/release.yml)
- [CHANGELOG.md](./CHANGELOG.md)

## OpenSpec Roadmap

OpenSpec now holds the canonical "what is left until this is a daily driver?" plan.

- [ROADMAP.md](./ROADMAP.md)
- [openspec/README.md](./openspec/README.md)
- [openspec/project.md](./openspec/project.md)
- [openspec/changes/reach-daily-driver/proposal.md](./openspec/changes/reach-daily-driver/proposal.md)
- [openspec/changes/reach-daily-driver/design.md](./openspec/changes/reach-daily-driver/design.md)
- [openspec/changes/reach-daily-driver/tasks.md](./openspec/changes/reach-daily-driver/tasks.md)
- [openspec/changes/reach-daily-driver/specs/daily-driver/spec.md](./openspec/changes/reach-daily-driver/specs/daily-driver/spec.md)

`ROADMAP.md` is the short product-and-priority version. The OpenSpec layer defines the sharper daily-driver bar and the remaining phases. `.omx/board.md` and the Ralph loops remain the execution surface.

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
./scripts/qa.sh provider-matrix
./scripts/qa.sh daemon
./scripts/qa.sh recovery
./scripts/qa.sh release
```

Runtime smoke:

```bash
mix deps.get
mix claw_code.native.build
mix test
mix escript.build
./claw_code summary
./claw_code providers
./claw_code doctor
./claw_code probe
./claw_code symphony --native "review MCP tool"
./claw_code symphony --no-native "review MCP tool"
./claw_code chat --allow-shell --allow-write "inspect the repo and propose a minimal plan"
```

## Session Resume

Sessions live under `.claw/sessions/` and can be resumed by explicit id.

```bash
./claw_code chat --session-id my-session --provider kimi "inspect this repo"
./claw_code chat --session-id my-session --provider kimi --image ./diagram.png "inspect this screenshot"
./claw_code chat --session-id my-session --provider glm --model GLM-5.1 --vision-provider kimi --vision-model kimi-k2.5 --image ./diagram.png "inspect this screenshot"
./claw_code resume-session my-session --provider kimi "continue from the last state"
./claw_code resume-session my-session --provider kimi --image ./diagram.png "compare this new screenshot with the last run"
./claw_code resume-session my-session --provider glm --model GLM-5.1 --vision-provider kimi --vision-model kimi-k2.5 --image ./diagram-2.png "compare this new screenshot with the last run"
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

The inspection surface is intentionally getting denser as the repo moves toward daily-driver status: `sessions` now includes provider and output summaries, while `load-session` shows provider/model plus run timing and stop metadata before the optional message and receipt details. When a session includes multimodal user input, `load-session --show-messages` renders compact image markers like `[image:diagram.png]` instead of dumping raw content-part maps, and split-backbone runs add compact derived markers like `[vision:kimi/kimi-k2.5] ...` instead of hiding that extra context in raw JSON.

If a specific session JSON is corrupted or partial, `load-session`, `resume-session`, `cancel-session`, and `chat --session-id ...` now fail against that session id with an explicit local invalid-session message instead of crashing the runtime or silently replacing the broken file with a fresh session.

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

Once a daemon is running, its session root is authoritative. Later daemon-backed `chat`, `resume-session`, and `cancel-session` calls fail explicitly if they try to override that root, so background work cannot silently fork across multiple session directories.

Daemon startup now also reconciles any abandoned persisted `run=running` sessions in its session root before it reports health, and the recovered state is made explicit as `run_interrupted` instead of pretending the abandoned run is still live.

`./claw_code daemon status` now also derives a compact session-health view from the daemon's session root: busy/failed/partially recovered signals, aggregate running/failed/recovered counts, plus `latest_running`, `latest_failed`, and `latest_recovered` summaries with recent receipt detail for the newest failed run. That keeps break/fix triage on one command instead of forcing immediate `load-session` hops.

The concrete break or fix paths now live in [docs/reference/recovery.md](./docs/reference/recovery.md), and `./scripts/qa.sh recovery` is the canonical smoke lane for stale-daemon replacement, abandoned-run reconciliation, corrupted-session handling, and daemon root mismatch rejection.

The final UX can absolutely include a full terminal UI, and the correct layering stays engine first: the Elixir runtime and daemon remain the product core, and the TUI is a client over that control plane instead of the architectural center.

`./claw_code tui` is the first in-repo slice of that client. It is intentionally minimal: recent sessions, selected transcript, prompt/output summaries, provider/model diagnostics, tool receipts, aggregate run counts, selected-session run metadata, optional `watch` refresh cadence, `follow` targets like `running`, `latest-running`, or `latest-failed`, an `active` alias plus `focus active` preset for monitoring live work, explicit `inspect active` / `inspect failed` shortcuts over the same alias resolver used by `open`, targeted `cancel active` / `cancel running` intervention, in-client provider/model/base-url switching with reset-to-default, session filtering and limits, root-wide substring `find`, explicit `older` / `newer` paging through larger session roots, transcript `find-msg` with `next-hit` / `prev-hit`, alias-driven `open latest-completed` / `open latest-failed`, targeted `resume selected ...` / `resume active ...` / `resume latest-failed ...`, repeated `--image PATH` support on in-client `chat` and `resume`, bounded session-window rendering around the current selection, transcript tail windows with absolute message numbering, provider `probe`, and a command loop for `chat`, `resume`, `inspect`, `open`, `next`, `prev`, `older`, `newer`, `cancel`, and `tools`.

The TUI header/footer now also surfaces compact `provider_health`, `input_modalities`, and `selected_health` summaries so missing config, image-capable providers, failed sessions, and active work are visible without opening more detail panes. If you want split reasoning plus vision in the client, start `./claw_code tui` with the same `--vision-*` flags you would use on `chat` or `resume-session`. The compact operator loop is documented in [docs/reference/tui.md](./docs/reference/tui.md#operator-quickstart).

## Provider Setup

Provider contracts are documented in [docs/providers.md](./docs/providers.md). `claw_code` accepts explicit CLI flags and also autoloads `.env.local` / `.env` at runtime for local development. Those files are git-ignored in this repo.

The checked-in template is [`.env.local.example`](./.env.local.example). Copy it to `.env.local`, uncomment one provider block, and keep secrets local. The runtime load order is explicit: existing shell env wins, then `.env.local`, then `.env`.

`chat` and `resume-session` default to an `auto` tool policy: repo or tool-oriented prompts expose local tools, plain chat prompts do not. Use `--tools` to force tool specs on, `--no-tools` to force a chat-only request, or `CLAW_TOOL_MODE=auto|on|off` to set the default behavior across local and daemon-backed runs.

`./claw_code doctor` now makes the active shell and write access explicit, `chat` results now echo the run permissions snapshot, and `load-session --show-receipts` now includes blocked-policy detail for destructive shell commands instead of only saying the tool was blocked.

The runtime adapters behind `python_eval`, `lua_eval`, and `lisp_eval` now also accept optional `timeout_ms` arguments and persist explicit runtime, engine, invocation, exit-status, and merged stderr/stdout output in their receipts, so adapter failures and timeouts stay inspectable instead of collapsing into opaque tool errors.

There is also now one structured Common Lisp-backed local tool beyond raw eval: `sexp_outline`. It takes s-expression source text and returns a compact top-level outline like `defpackage`, `defun`, and per-form depth summaries, which gives the model a deterministic way to inspect Lisp-like source without falling back to arbitrary `lisp_eval`.

`chat` and `resume-session` also accept repeated `--image PATH` flags. Session state keeps those local image references replayable as provider-agnostic content parts, and the OpenAI-compatible provider boundary translates them into request-time `image_url` parts only when the selected backend call is built.

When the main reasoning model is not the best vision model, `chat` and `resume-session` also accept `--vision-provider`, `--vision-model`, `--vision-base-url`, `--vision-api-key`, and `--vision-api-key-header`, plus the matching `CLAW_VISION_*` env vars. In that split mode, `claw_code` first derives replayable `vision_context` from the configured vision-capable backbone and then sends a text-only augmented request to the primary reasoning model. That keeps combinations like `--provider glm --model GLM-5.1 --vision-provider kimi --vision-model kimi-k2.5` or `--provider glm --model GLM-5.1 --vision-model GLM-4.6V` inside the same session and daemon boundary instead of inventing a second workflow.

`./claw_code probe` is the fastest way to validate a provider before a longer chat. It sends one small chat-completions request and reports the request URL, configuration state, provider portability hints like `auth_mode` / `tool_support` / `input_modalities` / `payload_modes`, the requested input shape, latency, the final `request_mode`, and a short response preview. Generic endpoints now retry once with a minimal `model + messages` payload when they reject extra OpenAI-style fields such as `temperature`, `tools`, or `tool_choice`. Generic endpoints can also override the auth header with `--api-key-header` or `CLAW_API_KEY_HEADER` when they expect something other than `Authorization: Bearer ...`.

When you want to preflight a vision-capable model specifically, pass repeated `--image PATH` flags to `probe` before starting a real session.

Core operator commands now also support `--json`, which is the intended first contract for a future terminal UI client. The boundary is documented in [docs/reference/tui.md](./docs/reference/tui.md).

`./claw_code doctor` now reports whether the active provider is fully configured, which request URL will be used, which input modalities the provider boundary accepts, and whether each field came from an env var, a default, or is still missing.

`./claw_code providers` is the matrix view for the whole supported provider set, including input-modality support, and `./scripts/qa.sh provider-matrix` is the corresponding Ralph loop for pre-RC validation.

## Release Automation

Release automation is driven by semantic-release from conventional commits on `main`.

The daily-driver beta checklist and live smoke matrix now live in [docs/reference/release-confidence.md](./docs/reference/release-confidence.md).

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
- `docs/reference/recovery.md` records the common break or fix playbooks for daemon and session recovery.
- `docs/reference/tui.md` records the client boundary for a future terminal UI.
- `.omx/` contains the operator board, team split, checklists, and mission briefs.
- `scripts/` contains the canonical Ralph loops, QA dispatcher, and validation gate.
- `.claw/sessions/` stores resumable session state with message history and tool receipts.
- `progress.md` is the append-only UTC ledger for workflow progress.

## Progress Ledger

Track operator work in [progress.md](./progress.md). Every entry should use a UTC ISO-8601 timestamp and record the mission, issues, lane, loop, status, evidence, and next step.
