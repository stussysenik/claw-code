# Release Confidence

## Table of Contents

- [Status Today](#status-today)
- [Daily-Driver Beta Bar](#daily-driver-beta-bar)
- [Checklist](#checklist)
- [Live Smoke Matrix](#live-smoke-matrix)
- [Still Open](#still-open)

## Status Today

As of 2026-04-02, `claw_code` is not yet at the daily-driver beta bar.

What is already green:

- core session, replay, and daemon continuity gates
- native enabled and explicit `--no-native` fallback evidence
- adapter timeout and failure evidence for Python, Lua, and Common Lisp
- one structured Common Lisp-backed tool path beyond raw eval
- recovery playbooks and recovery Ralph loop
- live GLM and NIM operator use in this environment
- one live generic OpenAI-compatible endpoint proof against the BigModel coding URL
- multimodal and split-vision proof through `chat` and the TUI

What is still open:

- live Kimi proof once credentials are available
- the final release-candidate decision recorded in `progress.md`
- `npm run release:dry-run` evidence whenever release-config files change

## Daily-Driver Beta Bar

Call the repo a daily-driver beta only when all of these are true:

1. The OpenSpec Phase 2 and Phase 6 tasks are closed.
2. `./scripts/qa.sh release` is green and current.
3. The preferred provider path and one generic endpoint both have current live smoke evidence.
4. Native-enabled and native-disabled routing both pass through the same release lane.
5. The daemon, recovery, and TUI operator loops have current smoke evidence, not just unit tests.
6. The release decision and evidence links are recorded in `progress.md`.

## Checklist

Use this as the short pre-RC checklist:

1. `./scripts/validate-repo.sh`
2. `./scripts/qa.sh core`
3. `./scripts/qa.sh native`
4. `./scripts/qa.sh adapters`
5. `./scripts/qa.sh provider`
6. `./scripts/qa.sh provider-matrix`
7. `./scripts/qa.sh provider-live` when you are claiming current live provider evidence
8. `./scripts/qa.sh daemon`
9. `./scripts/qa.sh recovery`
10. `./scripts/qa.sh release`
11. `npm run release:dry-run` if the branch changed `.releaserc.json`, `package.json`, or release workflows
12. Record the resulting RC or non-RC decision in `progress.md`

## Live Smoke Matrix

| Surface | Command | Expected Signal | Status |
| --- | --- | --- | --- |
| Core runtime | `./scripts/validate-repo.sh` | `repo validation passed` | green |
| Native enabled | `./claw_code symphony --native "review MCP tool"` | routing summary renders without fallback failure | green |
| Native disabled | `./claw_code symphony --no-native "review MCP tool"` | routing summary still renders with explicit disabled path | green |
| Adapters | `./scripts/qa.sh adapters` | Python, Lua, and Common Lisp receipts stay explicit under failure and timeout | green |
| Provider matrix | `./scripts/qa.sh provider-matrix` | each provider reports either live success or explicit `missing_config` | green |
| Live provider lane | `./scripts/qa.sh provider-live` | selected providers must all pass `doctor -> probe -> chat` live | green |
| Preferred GLM lane | `./claw_code probe --provider glm --model GLM-5.1 "Reply with OK."` | probe succeeds with a live response preview | green |
| NIM lane | `./claw_code probe --provider nim "Reply with OK."` | probe succeeds or reports an explicit upstream failure | green |
| Kimi lane | `./claw_code probe --provider kimi "Reply with OK."` | probe succeeds with live provider output | pending credentials |
| Generic endpoint lane | `./claw_code probe --provider generic --base-url https://open.bigmodel.cn/api/coding/paas/v4 --api-key ... --model GLM-4.7 "Reply with OK."` | probe succeeds against one real OpenAI-compatible endpoint | green |
| Daemon continuity | `./scripts/qa.sh daemon` | daemon-backed session loop stays continuous across CLI invocations | green |
| Recovery | `./scripts/qa.sh recovery` | stale daemon, abandoned runs, invalid sessions, and root mismatch stay explicit | green |
| TUI operator loop | `printf 'open latest-completed\nquit\n' \| ./claw_code tui --provider glm --model GLM-5.1 --no-tools --session-root ... --daemon-root ...` | header renders provider health and the selected session opens without raw session surgery | green |
| Split vision | `printf 'chat --image ... Briefly describe this image.\nquit\n' \| ./claw_code tui --provider glm --model GLM-5.1 --vision-model GLM-4.6V --no-tools --session-root ... --daemon-root ...` | multimodal session persists compact image and vision markers | green |
| Release automation | `./scripts/qa.sh release` | all release lanes complete and release config is validated or dry-run | green |

## Still Open

Do not call the repo daily-driver beta yet.

The remaining blockers are external proof, not architecture ambiguity:

- add Kimi credentials and capture live `probe`, `chat`, and TUI evidence
- record the first explicit release-candidate decision in `progress.md`
