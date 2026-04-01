# Roadmap

## Table of Contents

- [Status Today](#status-today)
- [Competitive Study](#competitive-study)
- [Adopt Next](#adopt-next)
- [Adopt After Beta](#adopt-after-beta)
- [Do Not Copy](#do-not-copy)
- [Execution Order](#execution-order)
- [Main-Tool Readiness](#main-tool-readiness)

## Status Today

As of 2026-04-01, `claw_code` is not yet ready to be the main tool.

What is already strong:

- explicit, replayable session state under `.claw/sessions/`
- a local daemon with inspect, resume, cancel, and status paths
- a TUI that stays on the thin-client side of the daemon/runtime boundary
- provider capability visibility through `doctor`, `probe`, `providers`, and the TUI
- provider-agnostic multimodal image input persistence and replay
- an optional split vision-backbone path, so a stronger reasoning model can be paired with a different vision-capable model without breaking replayability
- OpenSpec, OMX, Ralph loops, and `progress.md` as a real execution and evidence layer

What still blocks daily-driver use:

- Phase 2 still needs the remaining live smoke evidence for Kimi and one generic OpenAI-compatible endpoint. GLM and NIM are already proven, the current live vision-capable GLM path in this repo is `GLM-4.6V`, and the split path `GLM-5.1` reasoning plus `GLM-4.6V` vision has now also been proven through `chat` and the TUI.
- Phase 6 still needs the final release-candidate decision record, and release-config changes still require explicit `npm run release:dry-run` evidence.

That means the right claim today is: promising daily-driver candidate, not main-tool ready.

## Competitive Study

The goal is not to clone other tools. The goal is to import the features that reinforce Claw Code's architecture.

### Gemini CLI

Primary sources:

- [google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli)
- [Gemini CLI docs](https://geminicli.com/docs/)
- [Checkpointing](https://geminicli.com/docs/cli/checkpointing/)
- [Headless mode](https://geminicli.com/docs/cli/headless/)
- [Trusted folders](https://geminicli.com/docs/cli/trusted-folders/)

Best ideas to borrow:

- automatic local checkpoint and restore before file mutations
- structured headless output with JSON and streaming event modes
- trusted-workspace and safe-mode controls before loading project-local instructions or tools
- first-class project context files instead of relying on ad hoc chat memory
- save and resume ergonomics that are obvious to operators and scripts

### OpenCode

Primary sources:

- [OpenCode docs](https://opencode.ai/docs/)
- [Commands](https://opencode.ai/docs/commands/)
- [Permissions](https://opencode.ai/docs/permissions)
- [Agents](https://opencode.ai/docs/agents/)
- [Plugins](https://opencode.ai/docs/plugins/)
- [Rules](https://opencode.ai/docs/rules)
- [Share](https://opencode.ai/docs/share/)

Best ideas to borrow:

- `/init` style project bootstrap that creates or improves `AGENTS.md`
- plan versus build execution modes with tighter write and shell permissions
- reusable project commands for repetitive tasks
- granular permission rules by command, path, and external directory
- explicit agent and subagent roles for bounded parallel work
- project and global instruction layering with stable precedence

### Google Antigravity

Primary sources:

- [Google blog: Gemini 3 and Antigravity](https://blog.google/products-and-platforms/products/gemini/gemini-3/)
- [Google Codelab: Getting Started with Antigravity](https://codelabs.developers.google.com/getting-started-google-antigravity)

As of 2026-04-01, I have not located a public official Antigravity source repository, so this comparison is based on Google's official blog and codelab instead of a repo audit.

Best ideas to borrow:

- artifact-first review surfaces for plans, diffs, and results
- clearer autonomy presets for terminal execution, review, and browser behavior
- multi-agent orchestration that makes parallel work visible instead of implicit
- browser-assisted validation as a distinct capability instead of overloaded shell work
- status views that make pending approvals and agent outputs obvious

## Adopt Next

These are the best competitive features to bring into Claw Code before calling it a daily-driver beta.

### 1. Finish The Reliability Bar First

- reject daemon client requests that try to override the daemon-owned session root
- reconcile abandoned `run=running` sessions on daemon startup instead of waiting for a manual reopen
- harden crash-path persistence so runtime and session-server terminal states cannot drift
- make corrupt daemon metadata degrade into recoverable stale state instead of blowing up status paths

### 2. Add A Real `claw_code init`

- create or improve `AGENTS.md`
- point operators at `VISION.md`, `DESIGN.md`, `ROADMAP.md`, and `TECHSTACK.md`
- seed project-local instructions for validation commands, architecture rules, and tool policy

### 3. Add Structured Automation Output

- keep the current JSON surface for command responses
- add an event-stream mode for `chat`, `resume-session`, and daemon-backed work
- make tool calls, tool results, provider retries, and terminal outcomes script-visible

### 4. Add Checkpoint Or Restore For Mutating Work

- take a local snapshot before write-capable tool execution
- keep restore local and explicit
- never make checkpointing a hidden correctness dependency

### 5. Tighten Trust And Permission Surfaces

- make trusted roots explicit before loading project-local overrides
- show shell and write policy clearly in CLI, daemon, and TUI surfaces
- add command-pattern and path-based allow or deny rules for destructive flows

### 6. Add Reusable Project Commands

- project-scoped command macros for repetitive flows like test, review, smoke, and release checks
- keep them as thin prompt templates and execution recipes, not a new runtime

## Adopt After Beta

These are valuable, but they should not delay the daily-driver bar.

- browser validation receipts and artifact capture
- richer agent-role presets beyond the current OMX role split
- session export and local share surfaces that default to private or local-only behavior
- a narrow plugin boundary once Phase 7 is active and the runtime surface is stable
- more advanced multimodal ergonomics after live provider proof exists

## Do Not Copy

- do not move core session or provider logic out of Elixir to chase parity with JavaScript-heavy tools
- do not add public or cloud-backed sharing as a default operator path
- do not let plugin or extension loading become a runtime dependency before the core loop is stable
- do not turn provider-specific features into special cases spread across CLI, runtime, daemon, and TUI
- do not introduce hidden browser or remote-service state that makes recovery less inspectable

## Execution Order

### P0: Close The OpenSpec Blockers

1. Capture live provider evidence for GLM, Kimi, NIM, and one generic endpoint.
2. Prove the split-backbone path against a real preferred provider combination, then close the remaining Kimi and generic evidence gaps.
3. Record the first release-candidate decision with current evidence links.
4. Keep `npm run release:dry-run` evidence attached to any future release-config change.

### P1: Daily-Driver Beta

1. Add `claw_code init`.
2. Add structured event output for automation.
3. Add checkpoint and restore for write-capable tool paths.
4. Add trusted-root and permission policy surfaces.
5. Add project command packs for repeated operator flows.

### P2: Competitive Polish

1. Add browser-assisted validation receipts.
2. Add richer local agent orchestration patterns.
3. Add optional plugin or extension hooks behind a narrow boundary.
4. Add session export and collaboration surfaces that stay local-first by default.

## Main-Tool Readiness

Call `claw_code` the main tool only when all of these are true:

1. All remaining Phase 2, Phase 3, Phase 5, and Phase 6 blockers are closed.
2. One preferred provider and one generic endpoint have both been used successfully in real repos for at least a week without silent session forks or continuity loss.
3. The preferred vision-capable GLM path or split-backbone combination has real smoke evidence through `probe`, `chat`, and the TUI.
4. Shell and write capability are explicit enough that a destructive action is visible before it runs and inspectable after it runs.
5. The TUI covers the normal inspect, continue, monitor, and intervene loop for multi-hour work without constant fallback to manual session surgery.
6. The release checklist, live smoke matrix, and recovery playbooks are green and current.

Until then, the correct posture is to keep building toward daily-driver beta, not to pretend the bar has already been met.
