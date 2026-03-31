#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ralph-lib.sh"

loop_init "daemon"
note "running daemon Ralph loop"

daemon_cycle() {
  local tmp_root
  tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/claw-code-daemon.XXXXXX")"
  local daemon_root="$tmp_root/daemon"
  local session_root="$tmp_root/sessions"
  local status=0

  run mix format --check-formatted
  run mix test test/claw_code/daemon_test.exs test/claw_code/cli_test.exs
  run mix escript.build
  run ./claw_code daemon status --daemon-root "$daemon_root"
  run ./claw_code daemon start --daemon-root "$daemon_root" --session-root "$session_root"
  run ./claw_code daemon status --daemon-root "$daemon_root"
  run ./claw_code daemon stop --daemon-root "$daemon_root" || status=$?

  ./claw_code daemon stop --daemon-root "$daemon_root" >/dev/null 2>&1 || true
  rm -rf "$tmp_root"

  return "$status"
}

run_cycles "daemon gate" daemon_cycle

note "daemon Ralph loop complete"
note "log file: $LOG_FILE"
