# Tech Stack

## Table of Contents

- [Purpose](#purpose)
- [Core Runtime](#core-runtime)
- [Persistence And Control Plane](#persistence-and-control-plane)
- [Provider Stack](#provider-stack)
- [Tool And Adapter Stack](#tool-and-adapter-stack)
- [Native Stack](#native-stack)
- [Release And Validation Stack](#release-and-validation-stack)
- [Intentionally Absent](#intentionally-absent)

## Purpose

This file is the factual inventory of what `claw_code` is built from today.

Use it when you need to answer "what is actually in the repo?" quickly. Use `VISION.md` for product intent and `DESIGN.md` for the architectural contract.

## Core Runtime

### Primary language and packaging

- Elixir `~> 1.19`
- OTP application started through `ClawCode.Application`
- escript packaging with `ClawCode.CLI` as the entrypoint

### Core dependency

- `jason ~> 1.4` for JSON encoding and decoding

### OTP and standard library building blocks

- `GenServer` for session ownership
- `DynamicSupervisor` for per-session process lifecycle
- `Registry` for session process lookup
- `Task.Supervisor` for async work
- `:gen_tcp` for the local daemon protocol
- `:inets` and `:ssl` for HTTP/provider access
- `Port` for subprocess and native executable boundaries

## Persistence And Control Plane

### Storage model

- filesystem-backed JSON session documents under `.claw/sessions/`
- filesystem-backed daemon metadata under `.claw/`
- no database
- no external queue

### Runtime control modes

- direct CLI/runtime mode
- local daemon mode for cross-process session control

### Session data carried today

- prompts and outputs
- message history
- tool receipts
- run state and stop reason
- requirements ledger
- created and updated timestamps

## Provider Stack

### Provider protocol

- one OpenAI-compatible HTTP+JSON boundary

### Supported provider profiles

- `glm`
- `kimi`
- `nim`
- `generic`

### Configuration model

- CLI flags
- environment variables
- local `.env.local` and `.env` autoloading during runtime startup

## Tool And Adapter Stack

### Built-in runtime/tool surface

- local tool execution is owned by Elixir
- receipts capture command, cwd, env keys, duration, exit status, and output

### External adapter runtimes

- Python via `python3`
- Lua via `luajit`
- Common Lisp via `sbcl`

### Terminal client surface

- CLI built in Elixir
- minimal TUI built in Elixir with no external UI framework

## Native Stack

### Native language

- Zig

### Current native surface

- optional token/ranking fast path under `native/`
- Elixir fallback path for correctness when native is unavailable or disabled

## Release And Validation Stack

### Elixir-side validation

- `mix format --check-formatted`
- `mix test`
- `mix escript.build`

### Repo validation and smoke layer

- `./scripts/qa.sh`
- `./scripts/validate-repo.sh`
- Ralph lane scripts under `scripts/ralph-*.sh`

### Release tooling

- Node.js-based semantic-release flow
- `semantic-release 24.2.7`
- `@semantic-release/changelog`
- `@semantic-release/commit-analyzer`
- `@semantic-release/github`
- `@semantic-release/git`
- `@semantic-release/release-notes-generator`
- GitHub Actions workflows for CI and release

## Intentionally Absent

The repo is deliberately not built around:

- Phoenix
- Ecto
- a frontend bundler or SPA framework
- a database-backed session layer
- a remote daemon or network service architecture
- plugin-first runtime sprawl
