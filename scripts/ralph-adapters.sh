#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ralph-lib.sh"

loop_init "adapters"
note "running adapter Ralph loop"

adapters_cycle() {
  run mix test test/claw_code_test.exs test/claw_code/runtime_test.exs
  run ./claw_code summary
  run ./claw_code symphony --no-native "review MCP tool"
}

run_cycles "adapter gate" adapters_cycle

note "adapter Ralph loop complete"
note "log file: $LOG_FILE"
