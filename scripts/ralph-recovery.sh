#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ralph-lib.sh"

loop_init "recovery"
note "running recovery Ralph loop"

capture_cmd() {
  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  printf '%s' "$output"
  return "$status"
}

require_text() {
  local output="$1"
  local needle="$2"
  local label="$3"

  if [[ "$output" != *"$needle"* ]]; then
    note "missing expected text for ${label}: ${needle}"
    return 1
  fi
}

cleanup_recovery_cycle() {
  local daemon_root="$1"
  local tmp_root="$2"

  ./claw_code daemon stop --daemon-root "$daemon_root" >/dev/null 2>&1 || true
  rm -rf "$tmp_root"
}

recovery_cycle() {
  local tmp_root daemon_root session_root conflicting_root broken_id
  tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/claw-code-recovery.XXXXXX")"
  daemon_root="$tmp_root/daemon"
  session_root="$tmp_root/sessions"
  conflicting_root="$tmp_root/conflicting-sessions"
  broken_id="broken-recovery-session"

  trap "cleanup_recovery_cycle '$daemon_root' '$tmp_root'" RETURN

  mkdir -p "$daemon_root" "$session_root" "$conflicting_root"

  cat >"$daemon_root/daemon.json" <<EOF
{
  "host": "127.0.0.1",
  "port": 65000,
  "token": "stale-token",
  "pid": "99999",
  "version": "0.1.0",
  "started_at": "2026-04-01T00:00:00Z",
  "session_root": "$session_root"
}
EOF

  cat >"$session_root/session-running.json" <<EOF
{
  "id": "session-running",
  "prompt": "recover me",
  "output": "still running",
  "stop_reason": "running",
  "provider": {
    "provider": "glm",
    "model": "GLM-4.7"
  },
  "run_state": {
    "status": "running",
    "started_at": "2026-04-01T00:01:00Z"
  },
  "messages": [],
  "tool_receipts": []
}
EOF

  printf '{not-json' >"$session_root/$broken_id.json"

  run mix format --check-formatted
  run mix test test/claw_code/daemon_test.exs test/claw_code/cli_test.exs test/claw_code/session_server_test.exs test/claw_code/session_store_test.exs test/claw_code/qa_script_test.exs
  run mix escript.build

  local stale_output
  stale_output="$(capture_cmd ./claw_code daemon status --daemon-root "$daemon_root")"
  note "$stale_output"
  require_text "$stale_output" "- status: stale" "stale daemon status"

  local start_output
  start_output="$(capture_cmd ./claw_code daemon start --daemon-root "$daemon_root" --session-root "$session_root")"
  note "$start_output"
  require_text "$start_output" "- status: running" "daemon start"

  local health_output
  health_output="$(capture_cmd ./claw_code daemon status --daemon-root "$daemon_root")"
  note "$health_output"
  require_text "$health_output" "- latest_recovered: session-running" "recovered session summary"
  require_text "$health_output" "stop=run_interrupted" "recovered session stop reason"

  local mismatch_output
  if mismatch_output="$(capture_cmd ./claw_code chat --daemon --daemon-root "$daemon_root" --session-root "$conflicting_root" --provider generic --base-url http://127.0.0.1:1/v1 --api-key test-key --model smoke-model hello)"; then
    note "expected daemon-backed chat to fail on a conflicting session root"
    return 1
  fi

  note "$mismatch_output"
  require_text "$mismatch_output" "Daemon session root mismatch" "session root mismatch"

  local invalid_output
  if invalid_output="$(capture_cmd ./claw_code load-session "$broken_id" --session-root "$session_root")"; then
    note "expected load-session to fail on corrupted session state"
    return 1
  fi

  note "$invalid_output"
  require_text "$invalid_output" "Session state is invalid for $broken_id" "invalid session message"

  run ./claw_code daemon stop --daemon-root "$daemon_root"
  trap - RETURN
  cleanup_recovery_cycle "$daemon_root" "$tmp_root"
}

run_cycles "recovery gate" recovery_cycle

note "recovery Ralph loop complete"
note "log file: $LOG_FILE"
