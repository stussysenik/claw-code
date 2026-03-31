#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ralph-lib.sh"

loop_init "core"
note "running core Ralph loop"

core_cycle() {
  run mix format --check-formatted
  run mix test
  run mix escript.build
  run ./claw_code summary
  run ./claw_code doctor
  run ./claw_code symphony --native "review MCP tool"
}

run_cycles "core gate" core_cycle

note "core Ralph loop complete"
note "log file: $LOG_FILE"
