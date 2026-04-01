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

#### Scenario: Inspect daemon health from persisted session state

- **GIVEN** the daemon is running or stale and the session root includes active, failed, or recovered work
- **WHEN** the operator runs `./claw_code daemon status`
- **THEN** the health surface exposes busy, failed, and partially recovered signals plus compact latest-session summaries
- **AND** recent stop reason, provider-error detail, and last-receipt evidence stay derived from persisted session state instead of duplicated client logic

#### Scenario: Reject a daemon-backed request that tries to switch session roots midstream

- **GIVEN** a local daemon is already running against one session root
- **WHEN** a later daemon-backed `chat`, `resume-session`, or `cancel-session` request tries to use a different session root
- **THEN** the request fails explicitly instead of silently creating or mutating session state in a second root
- **AND** the daemon-owned session root remains authoritative for that control-plane instance

#### Scenario: Reconcile abandoned running sessions when the daemon starts

- **GIVEN** the session root contains a persisted session with `run_state.status=running` from an abandoned earlier process
- **WHEN** the local daemon starts against that session root
- **THEN** the daemon rewrites that session to an explicit recovered state before reporting health
- **AND** `daemon status` reports it as `run_interrupted` instead of live running work

#### Scenario: Common local recovery flows are documented and repeatable

- **GIVEN** the operator hits stale daemon metadata, an abandoned running session, a corrupted session file, or a daemon session-root mismatch
- **WHEN** they follow the documented recovery playbook or run the canonical recovery smoke loop
- **THEN** the inspect and fix commands are explicit
- **AND** the resulting behavior matches the persisted daemon or session contracts instead of relying on ad hoc shell surgery

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

#### Scenario: Send replayable multimodal image input through the portable boundary

- **GIVEN** the operator provides one or more local image paths together with a prompt
- **WHEN** `claw_code` runs `chat` or `resume-session` against a supported OpenAI-compatible backend
- **THEN** local image paths are validated before provider I/O
- **AND** persisted session content remains replayable and provider-agnostic
- **AND** provider-specific wire translation or failure remains inspectable

#### Scenario: Split reasoning and vision providers for one multimodal session

- **GIVEN** the operator wants one provider or model to reason and a different provider or model to interpret image inputs
- **WHEN** they run `chat`, `resume-session`, or daemon-backed flows with `--vision-provider ...` or `CLAW_VISION_*`
- **THEN** the runtime derives replayable visual context through the configured vision lane before the primary reasoning request
- **AND** the persisted user turn keeps the local image references plus a replayable derived `vision_context` part
- **AND** the primary reasoning request can drop raw image inputs for turns that already have derived visual context
- **AND** missing split-vision configuration fails explicitly before a misleading primary-provider result is returned

#### Scenario: Probe a vision-capable model before a longer run

- **GIVEN** the operator wants to validate a provider or model for multimodal use
- **WHEN** they run `./claw_code probe --image <path> ...`
- **THEN** the probe reports request modalities explicitly
- **AND** invalid local image input fails before provider I/O
- **AND** provider-edge success or failure stays inspectable without starting a full session

#### Scenario: Split the reasoning and vision backbones without losing replayability

- **GIVEN** the operator wants one provider or model for reasoning and a different vision-capable backbone for image understanding
- **WHEN** they run `chat` or `resume-session` with local image input plus `--vision-provider ...` or `--vision-model ...`
- **THEN** `claw_code` derives explicit replayable vision context through the configured vision backbone before the main reasoning request
- **AND** persisted session content keeps the original local image references plus the derived vision context inspectable
- **AND** the primary reasoning request can stay text-only instead of forwarding raw image payloads

#### Scenario: Inspect provider readiness across the supported matrix

- **GIVEN** the operator wants to validate provider setup before daily use or a release candidate
- **WHEN** they run `./claw_code providers` or `./scripts/qa.sh provider-matrix`
- **THEN** each supported provider reports configured state, missing fields, request identity, and supported input modalities explicitly
- **AND** one provider's missing config does not hide the state of the others

### Requirement: Inspectable Tool And Adapter Execution

Local tool and adapter execution MUST remain gated, replayable, and explicit under both success and failure.

#### Scenario: Tool execution emits a replayable receipt

- **GIVEN** a local tool, shell command, or adapter process executes
- **WHEN** the run completes or fails
- **THEN** the session persists status, timing, cwd, and output evidence sufficient for replay and inspection

#### Scenario: Shell and write policy stays explicit during destructive or blocked work

- **GIVEN** the operator enables or disables shell or write access for a run
- **WHEN** they inspect `doctor`, a chat result, or a persisted session with receipts
- **THEN** the effective shell or write policy is explicit
- **AND** blocked destructive shell commands include the policy rule that blocked them instead of failing with an opaque error

#### Scenario: Adapter failure is not silent

- **GIVEN** Python, Lua, or Common Lisp execution fails or times out
- **WHEN** the operator inspects the session
- **THEN** the failure mode is explicit
- **AND** timeout state, nonzero exit status, and merged stderr/stdout output remain visible in the persisted receipt
- **AND** the surrounding session remains readable and recoverable

#### Scenario: Common Lisp can provide structured analysis beyond raw eval

- **GIVEN** the operator or model needs structure from s-expression-heavy source text
- **WHEN** `claw_code` runs the `sexp_outline` local tool
- **THEN** the result returns a compact top-level outline instead of requiring arbitrary Common Lisp eval
- **AND** the persisted receipt still exposes the Common Lisp runtime, engine, invocation, and output for replay or inspection

### Requirement: Daily TUI Operator Loop

The TUI MUST cover the normal local operator loop without becoming a second runtime.

#### Scenario: Monitor and intervene on active work

- **GIVEN** the operator is using `./claw_code tui`
- **WHEN** sessions are running in the background
- **THEN** the operator can monitor, open, resume, and cancel the relevant work from the client
- **AND** the client continues to rely on the runtime and daemon for authoritative state
- **AND** alias-driven shortcuts such as `inspect failed`, `resume selected ...`, and `cancel active` keep the operator off raw session ids

#### Scenario: Send multimodal prompts from the TUI without leaving the thin client

- **GIVEN** the operator is using `./claw_code tui`
- **WHEN** they run `chat` or `resume` with one or more `--image PATH` inputs
- **THEN** the client forwards those image inputs through the existing daemon/runtime boundary instead of inventing a second provider path
- **AND** the resulting persisted session remains replayable and inspectable with compact image markers

#### Scenario: Navigate a busy session root

- **GIVEN** the session root contains multiple running, completed, and failed sessions
- **WHEN** the operator uses filtering, search, aliases, older/newer paging, or watch/follow controls
- **THEN** the correct session can be found and acted on without guesswork
- **AND** the session list and transcript excerpt stay bounded around the current target while preserving absolute positions for inspection
- **AND** substring search can still surface an older matching session beyond the current recent-session limit

#### Scenario: See provider and session health at a glance

- **GIVEN** the operator is using `./claw_code tui`
- **WHEN** provider configuration is missing, partially configured, or healthy and the selected session is running, completed, or failed
- **THEN** the header or footer exposes provider/model/tool-policy plus compact provider-health and selected-session-health summaries
- **AND** the UI still relies on runtime-derived state instead of duplicating provider logic

### Requirement: Stable Local Launcher

`claw_code` MUST provide an installable local launcher so the operator can enter the TUI and CLI loop from `PATH` without repo-specific shell glue.

#### Scenario: Install a stable launcher that defaults to the TUI

- **GIVEN** the operator has built the local `claw_code` escript
- **WHEN** they run `./claw_code install`
- **THEN** a stable launcher is created in the selected bin directory
- **AND** invoking that launcher with no arguments opens the TUI
- **AND** invoking that launcher with arguments forwards them to the existing CLI surface
- **AND** PATH guidance is explicit instead of assumed

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
