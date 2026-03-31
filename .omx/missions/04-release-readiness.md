# Mission 04: Release Readiness

## Goal

Keep the repo teachable and shippable: clean operator docs, explicit standards, and a repeatable release-quality gate.

## Linked Issues

- `#9` Research provider/plugin boundaries and WebGPU offload strategy
- `#10` Evaluate oh-my-codex as a development workflow layer, not a product dependency

## Scope

- Review and release checklists
- Evidence requirements
- Docs accuracy for operator commands and repo layout
- Research writeups that do not bloat the runtime surface

## Exit Evidence

1. `./scripts/qa.sh release`
2. Docs and commands agree with the actual repo
3. Research outcomes are captured as docs or issues, not speculative runtime code
