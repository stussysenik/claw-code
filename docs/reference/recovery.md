# Recovery Playbooks

## Table of Contents

- [Goal](#goal)
- [Quick Triage](#quick-triage)
- [Stale Daemon Metadata](#stale-daemon-metadata)
- [Recovered Abandoned Session](#recovered-abandoned-session)
- [Session-Root Mismatch](#session-root-mismatch)
- [Corrupted Session State](#corrupted-session-state)
- [Canonical Smoke](#canonical-smoke)

## Goal

Keep common local break or fix paths explicit and repeatable.

The daemon and session model already fail closed in these cases. This note is the operator companion: which commands to run, what to expect, and how to get back to a clean state without silently forking or overwriting session history.

## Quick Triage

Start here:

```bash
./claw_code daemon status --daemon-root .claw
./claw_code sessions --limit 10
./claw_code load-session latest-failed --show-receipts
```

Use those three commands to answer:

- is the daemon `running`, `stale`, or `stopped`
- which session failed or was recovered most recently
- whether the last receipt or stop reason points at a provider error, interrupted run, or invalid local state

## Stale Daemon Metadata

Symptom:

- `./claw_code daemon status` prints `- status: stale`

Recovery:

```bash
./claw_code daemon status --daemon-root .claw
./claw_code daemon start --daemon-root .claw --session-root .claw/sessions
./claw_code daemon status --daemon-root .claw
```

Expected result:

- the first status call shows `stale`
- `daemon start` replaces the dead metadata and returns `running`
- the follow-up status call shows a live daemon with the authoritative `session_root`

## Recovered Abandoned Session

Symptom:

- the daemon starts cleanly, but `daemon status` reports `partially_recovered`
- `latest_recovered` shows `stop=run_interrupted`

Recovery:

```bash
./claw_code daemon start --daemon-root .claw --session-root .claw/sessions
./claw_code daemon status --daemon-root .claw
./claw_code load-session <session-id> --session-root .claw/sessions --show-receipts
./claw_code resume-session <session-id> --daemon --provider glm "continue from the last stable state"
```

Expected result:

- startup rewrites stale `run_state.status=running` sessions to `run_interrupted`
- `load-session` keeps the messages and receipts readable
- `resume-session` reuses the same session id instead of creating a silent fork

## Session-Root Mismatch

Symptom:

- daemon-backed `chat`, `resume-session`, or `cancel-session` fails with `Daemon session root mismatch`

Recovery:

```bash
./claw_code daemon status --daemon-root .claw
./claw_code chat --daemon --daemon-root .claw --session-root <the-root-from-status> --provider glm "continue"
```

If the daemon is using the wrong root entirely:

```bash
./claw_code daemon stop --daemon-root .claw
./claw_code daemon start --daemon-root .claw --session-root <intended-session-root>
```

Expected result:

- the daemon-owned session root stays authoritative
- recovery is explicit: either use that root or restart the daemon with the intended one

## Corrupted Session State

Symptom:

- `load-session`, `resume-session`, `cancel-session`, or `chat --session-id ...` fails with `Session state is invalid for <id>`

Recovery:

```bash
./claw_code load-session <session-id> --session-root .claw/sessions
mv .claw/sessions/<session-id>.json .claw/sessions/<session-id>.invalid.json
./claw_code sessions --session-root .claw/sessions --limit 20
```

Expected result:

- the bad session fails locally and explicitly
- adjacent sessions remain readable
- moving the broken JSON aside lets you preserve the evidence without forcing the runtime to keep tripping over the same corrupted file

If the session matters, inspect the `.invalid.json` copy manually instead of letting the runtime overwrite it.

## Canonical Smoke

Use the repo loop when you want one repeatable recovery proof instead of ad hoc commands:

```bash
./scripts/qa.sh recovery
```

That loop proves, in order:

- stale daemon metadata is detected
- daemon restart can recover into a live control plane
- abandoned running sessions become `run_interrupted`
- daemon-backed root mismatch fails explicitly
- corrupted session JSON fails locally instead of being silently replaced
