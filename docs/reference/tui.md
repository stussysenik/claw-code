# TUI Boundary

## Table of Contents

- [Goal](#goal)
- [Correct Layering](#correct-layering)
- [Minimal Client Contract](#minimal-client-contract)
- [Operator Quickstart](#operator-quickstart)
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
- aggregate run counts plus selected-session run and receipt summaries
- selected-session provider/model plus prompt/output summaries for faster failure inspection
- compact `provider_health`, `input_modalities`, and `selected_health` summaries in the header/footer for faster operator triage
- explicit `shell` and `write` access labels in the header so the active safety posture is visible before a run
- optional `watch <seconds|on|off>` auto-refresh cadence for active monitoring
- optional `follow <latest|active|running|latest-running|completed|latest-completed|failed|latest-failed|off>` auto-selection for active monitoring
- `active` alias support plus `focus active` / `focus all` monitoring presets
- targeted `cancel active`, `cancel running`, and `cancel selected` intervention
- daemon-backed `chat` and `resume`
- repeated `--image PATH` support on in-client `chat` and `resume`, forwarded through the same daemon/runtime path
- in-client `provider`, `model`, and `base-url` switching, including reset-to-default
- in-client `probe` for the active provider configuration
- `next` and `prev` session navigation
- session filtering, root-wide substring `find`, and list limits inside the client
- explicit `older` and `newer` paging across larger session roots without widening the daemon/runtime boundary
- a bounded session window around the current selection so large filtered lists stay navigable with `next`, `prev`, and alias targets
- transcript `find-msg`, `clear find-msg`, `next-hit`, and `prev-hit` inside the selected session
- transcript tail rendering with absolute message numbers so excerpts stay intelligible as histories grow
- `inspect selected`, `inspect active`, and `inspect latest-failed` as explicit inspection shortcuts over the same alias resolver used by `open`
- `open latest`, `open active`, `open latest-running`, `open latest-completed`, and `open latest-failed`
- targeted `resume selected ...`, `resume latest ...`, `resume active ...`, `resume latest-running ...`, `resume latest-completed ...`, and `resume latest-failed ...`
- explicit `tools auto|on|off`
- `open`, `cancel`, `refresh`, `help`, and `quit`

## Operator Quickstart

For one stable shell launcher instead of running `./claw_code` from the repo root every time:

```bash
mix escript.build
./claw_code install
pikachu
```

The installed launcher opens a compact chat-first TUI by default with no arguments and still forwards explicit subcommands like `pikachu chat ...` or `pikachu daemon start`. Use `./claw_code install --as snik`, `--bin-dir /custom/path`, or `--force` when you want a different launcher name, location, or replacement behavior.

For the normal local loop without installing a launcher:

```bash
./claw_code tui --provider generic
```

For split reasoning plus vision:

```bash
./claw_code tui --provider glm --model GLM-5.1 --vision-provider kimi --vision-model kimi-k2.5
```

Then use this sequence inside the client:

```text
hi!
/dashboard
/kimi
/model kimi-k2.5
chat --image ./diagram.png inspect this screenshot
resume active --image ./diagram-2.png continue from the last tool result
/tools off
/quit
```

That gives one compact flow for daily use:

- `pikachu` now starts in a compact chat view instead of dumping the full session board on every frame.
- plain text now uses the chat path by default, so typing `hi!` behaves like a prompt instead of an unknown command error.
- `/dashboard` switches back to the full session board when you want the heavier inspection view.
- direct slash aliases like `/kimi`, `/glm`, `/nim`, and `/generic` choose the provider in one token.
- slash control aliases like `/provider ...`, `/model ...`, `/base-url ...`, `/tools ...`, `/probe`, `/help`, and `/quit` still reuse the same thin-client command path when you want terminal-chat style controls.
- `chat --image ...` and `resume ... --image ...` let the TUI drive the same multimodal path as the CLI without inventing a second provider boundary.
- start the client with `--vision-*` flags when the primary reasoning model should stay text-only and a separate vision-capable backbone should handle image understanding.
- `older` and `newer` move the loaded page through larger session roots while keeping the same thin-client state path.
- `resume selected ...`, `resume active ...`, or `resume latest-failed ...` keeps intervention on aliases instead of raw ids.
- `cancel active` stops the currently running daemon-backed session without leaving the client.
- the session list stays windowed around the current selection, and transcript excerpts keep absolute message positions, so a larger root does not force the client to dump every line at once.

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
- footer: prompt composer plus provider/model/tool-policy/health badges

The current in-repo TUI uses the same local control-plane boundaries and keeps the interaction model simple. Streaming and richer panes can come later.

## Non-Goals

- Do not move provider logic into the UI.
- Do not make Bubble Tea or any TUI framework the architectural center.
- Do not add remote transport, voice, or streaming complexity before the local JSON boundary is solid.
