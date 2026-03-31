# Mission 03: Native And Adapters

## Goal

Keep the Zig and subprocess lanes fast, isolated, and easy to reason about.

## Linked Issues

- `#7` Harden the Zig native ranker build and crash-recovery path
- `#8` Expand runtime adapters across Python, Lua, and Common Lisp

## Scope

- Native build stability
- BEAM fallback behavior
- Python/Lua/Common Lisp adapter receipts
- Tests for subprocess output and failure handling

## Exit Evidence

1. `mix claw_code.native.build`
2. `mix test test/claw_code/native_ranker_test.exs`
3. `./scripts/qa.sh native`
4. Native failure or disablement falls back to BEAM routing deterministically
