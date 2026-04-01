#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ralph-lib.sh"

loop_init "adapters"
note "running adapter Ralph loop"

adapters_cycle() {
  run mix test test/claw_code/host_test.exs test/claw_code/tools_test.exs test/claw_code/runtime_test.exs test/claw_code_test.exs
  run mix run -e 'alias ClawCode.Tools.Builtin; IO.puts(elem(Builtin.execute_with_receipt("sexp_outline", %{"source" => "(defpackage :demo) (defun hello (name) (format t \"Hello, ~A\" name))"}), 1))'
  run mix escript.build
  run ./claw_code summary
  run ./claw_code symphony --no-native "review MCP tool"
}

run_cycles "adapter gate" adapters_cycle

note "adapter Ralph loop complete"
note "log file: $LOG_FILE"
