# Quality Gates

## Table of Contents

- [Always Required](#always-required)
- [Change-Specific](#change-specific)
- [Evidence Standard](#evidence-standard)

## Always Required

1. `mix format --check-formatted`
2. `mix test`
3. `mix escript.build`
4. `./claw_code summary`
5. `./claw_code symphony --native "review MCP tool"`
6. `./scripts/validate-repo.sh`

## Change-Specific

- Runtime/provider changes: add one test for missing-config or tool-loop behavior.
- Native changes: prove native ranking and one BEAM fallback path.
- CLI changes: update or add a CLI smoke test.
- Host/tool adapter changes: prove subprocess output and failure handling.

## Evidence Standard

1. One automated test added or strengthened.
2. One smoke command run.
3. One failure mode handled explicitly.
4. One persistence or replay implication checked if sessions or tools are involved.
