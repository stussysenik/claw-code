# TUI Boundary

## Table of Contents

- [Goal](#goal)
- [Correct Layering](#correct-layering)
- [Minimal Client Contract](#minimal-client-contract)
- [First UI Shape](#first-ui-shape)
- [Non-Goals](#non-goals)

## Goal

Make the terminal UI a thin client over the Elixir runtime and daemon, not a second runtime with duplicated state, provider logic, or tool execution.

## Correct Layering

- Elixir owns session state, replay, provider routing, tool execution, and daemon control.
- Zig stays a narrow optional optimization boundary.
- The TUI reads and writes through stable operator commands first, then can speak the daemon protocol directly later if that earns its complexity.

## Current Slice

The repo now includes a first terminal client:

```bash
./claw_code tui
```

It stays intentionally small:

- recent session list
- selected transcript and receipts
- daemon-backed `chat` and `resume`
- in-client `provider`, `model`, and `base-url` switching, including reset-to-default
- in-client `probe` for the active provider configuration
- `next` and `prev` session navigation
- session filtering, substring `find`, and list limits inside the client
- `open latest`, `open latest-completed`, `open running`, `open completed`, and `open failed`
- targeted `resume latest ...` and `resume completed ...`
- explicit `tools auto|on|off`
- `open`, `cancel`, `refresh`, `help`, and `quit`

## Minimal Client Contract

The stable contract under the TUI is still JSON over the existing CLI:

- `./claw_code doctor --json`
- `./claw_code probe --json`
- `./claw_code daemon start --json`
- `./claw_code daemon status --json`
- `./claw_code chat --daemon --json ...`
- `./claw_code resume-session <id|latest|running|latest-running|completed|latest-completed|failed|latest-failed|N> --daemon --json ...`
- `./claw_code cancel-session <id|latest|running|latest-running|completed|latest-completed|failed|latest-failed|N> --daemon --json`
- `./claw_code sessions --json`
- `./claw_code load-session <id|latest|running|latest-running|completed|latest-completed|failed|latest-failed|N> --json`

This keeps the UI replaceable while the daemon/runtime semantics harden.

## First UI Shape

- left pane: recent sessions
- center pane: transcript
- right drawer: receipts, run state, and provider details
- footer: prompt composer plus provider/model badges

The current in-repo TUI uses the same local control-plane boundaries and keeps the interaction model simple. Streaming and richer panes can come later.

## Non-Goals

- Do not move provider logic into the UI.
- Do not make Bubble Tea or any TUI framework the architectural center.
- Do not add remote transport, voice, or streaming complexity before the local JSON boundary is solid.
