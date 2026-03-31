# Daily-Driver Specification

## ADDED Requirements

### Requirement: Durable Local Session Control

`claw_code` MUST provide predictable local session continuity across shell invocations, daemon-backed runs, and recovery paths.

#### Scenario: Resume a daemon-backed session after the original shell exits

- **GIVEN** a session created through the daemon-backed path
- **AND** the original client shell is gone
- **WHEN** the operator resumes or inspects that session from a new shell
- **THEN** the session id, persisted messages, receipts, and run state remain authoritative

#### Scenario: Cancel a running session without ambiguity

- **GIVEN** a session is actively running
- **WHEN** the operator cancels it by id or alias
- **THEN** the resulting stop reason is explicit
- **AND** the persisted session state reflects the cancellation

### Requirement: Portable Provider Boundary

`claw_code` MUST support daily use across GLM, Kimi, NVIDIA NIM, and generic OpenAI-compatible endpoints without code changes.

#### Scenario: Switch providers through configuration only

- **GIVEN** the operator changes provider, model, base URL, or auth header through supported env vars or flags
- **WHEN** the operator runs `doctor`, `probe`, `chat`, or the TUI
- **THEN** the resolved provider configuration is explicit
- **AND** the runtime does not require code changes to switch inference backends

#### Scenario: Use a partial OpenAI-compatible endpoint

- **GIVEN** a generic endpoint rejects a subset of OpenAI-style parameters
- **WHEN** `claw_code` can safely retry or degrade behavior
- **THEN** it does so explicitly
- **AND** the failure or fallback is inspectable

### Requirement: Inspectable Tool And Adapter Execution

Local tool and adapter execution MUST remain gated, replayable, and explicit under both success and failure.

#### Scenario: Tool execution emits a replayable receipt

- **GIVEN** a local tool, shell command, or adapter process executes
- **WHEN** the run completes or fails
- **THEN** the session persists status, timing, cwd, and output evidence sufficient for replay and inspection

#### Scenario: Adapter failure is not silent

- **GIVEN** Python, Lua, or Common Lisp execution fails or times out
- **WHEN** the operator inspects the session
- **THEN** the failure mode is explicit
- **AND** the surrounding session remains readable and recoverable

### Requirement: Daily TUI Operator Loop

The TUI MUST cover the normal local operator loop without becoming a second runtime.

#### Scenario: Monitor and intervene on active work

- **GIVEN** the operator is using `./claw_code tui`
- **WHEN** sessions are running in the background
- **THEN** the operator can monitor, open, resume, and cancel the relevant work from the client
- **AND** the client continues to rely on the runtime and daemon for authoritative state

#### Scenario: Navigate a busy session root

- **GIVEN** the session root contains multiple running, completed, and failed sessions
- **WHEN** the operator uses filtering, search, aliases, or watch/follow controls
- **THEN** the correct session can be found and acted on without guesswork

### Requirement: Optional Native Acceleration

Native optimization MUST remain optional and never become a correctness dependency.

#### Scenario: Run with native disabled

- **GIVEN** the native helper is unavailable or explicitly disabled
- **WHEN** routing or ranking work is requested
- **THEN** the Elixir fallback path remains correct and observable

### Requirement: Release-Gated Evidence

Daily-driver claims MUST be backed by repeatable validation rather than informal confidence.

#### Scenario: Declare a daily-driver release candidate

- **GIVEN** the repo claims daily-driver readiness
- **WHEN** the operator reviews the release evidence
- **THEN** there is a documented checklist, current validation output, and smoke evidence across the core runtime, providers, adapters, daemon, and TUI
