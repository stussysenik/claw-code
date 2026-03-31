# OpenSpec Project Context

## Table of Contents

- [Product Intent](#product-intent)
- [Canonical Boundaries](#canonical-boundaries)
- [Daily-Driver Standard](#daily-driver-standard)
- [Evidence Rules](#evidence-rules)

## Product Intent

Build `claw_code` as an Elixir-first coding runtime that is small, replayable, inspectable, and suitable for daily terminal use across GLM, Kimi, NVIDIA NIM, and generic OpenAI-compatible inference endpoints.

## Canonical Boundaries

1. Elixir is the control plane.
2. Zig stays behind a narrow executable boundary and must always be optional.
3. Python, Lua, and Common Lisp remain adapter processes, not core runtime dependencies.
4. Provider integrations stay behind one OpenAI-compatible boundary.
5. The TUI is a client over the runtime and daemon, not a second runtime.
6. OMX is the planning and execution layer, not a shipped product dependency.

## Daily-Driver Standard

Daily-driver means one operator can rely on `claw_code` for real repo work without frequent session loss, provider confusion, hidden tool behavior, or TUI friction.

That bar requires:

- durable session and receipt persistence
- safe and portable provider behavior
- explicit tool and shell policy
- active-run monitoring and intervention
- release-gated evidence instead of faith

## Evidence Rules

Every meaningful slice in an OpenSpec change set must carry:

1. one focused automated test
2. one real smoke command
3. one explicit failure-mode check
4. one `progress.md` entry with UTC timestamp and evidence
5. one docs update if the operator surface changes
