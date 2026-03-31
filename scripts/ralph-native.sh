#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ralph-lib.sh"

loop_init "native"
note "running native Ralph loop"

native_cycle() {
  run mix claw_code.native.build
  run mix test test/claw_code/native_ranker_test.exs test/claw_code/router_test.exs
  run ./claw_code route --native "review MCP tool"
  run ./claw_code symphony --native "review MCP tool"
}

run_cycles "native gate" native_cycle

note "native Ralph loop complete"
note "log file: $LOG_FILE"
